class_name CarModel
extends RefCounted

## Машина у выхода — модель Cars Pack Quaternius (ADR-0032, решение 7).
##
## В каждом здании своя: какая машина и какого цвета — жребий по сиду здания.
## Первое здание партии — красная спортивная, как в 1983 году. Такси и полиции в
## жребии нет: шпион, уезжающий на патрульной машине, странен.
##
## Модели собирает `tools/build_actors.py cars`: капот в +X, нуль — между
## колёсами на земле, длина — [constant Proportions.CAR_LENGTH], глубина —
## сколько влезает между задней стеной и телом Otto. Кузов у каждой — материал
## `Paint` (у двухцветной ещё `PaintShade`), его и перекрашивает жребий. Фары и
## стоп-сигналы светятся эмиссией — источников машина не добавляет. С M24i у
## каждой — проём водительской двери, дверь `DriverDoor` на петле, салон
## `CarInterior`, точка плафона `DomeLight` и поворотники (ADR-0046, решение 1).

## Снег на кузове в снегопад ([method snow_on]).
const SNOW_CAP := preload("res://src/levels/snow_cap.gdshader")
## Длина по бамперам, м — та же, по которой [ExitCar] ставит машину у выхода.
const LENGTH: float = Proportions.CAR_LENGTH

## Модели в жребии. Первая — спортивная, её берёт первое здание.
const MODELS: Array[PackedScene] = [
	preload("res://assets/models/cars/sports_car_2.glb"),
	preload("res://assets/models/cars/sports_car_1.glb"),
	preload("res://assets/models/cars/car_1.glb"),
	preload("res://assets/models/cars/car_2.glb"),
	preload("res://assets/models/cars/suv.glb"),
]

## Краски кузова. Первая — красная первого здания. Тона глубокие, но не чёрные:
## машина стоит в гараже под одной лампой, и тёмная пропала бы в кадре.
const PAINTS: Array[Color] = [
	Color(0.62, 0.08, 0.07),
	Color(0.08, 0.2, 0.45),
	Color(0.85, 0.82, 0.74),
	Color(0.12, 0.35, 0.2),
	# Не жёлтая: жёлтая машина любой модели читается такси, а такси в жребии нет.
	Color(0.55, 0.62, 0.7),
	Color(0.45, 0.46, 0.5),
	Color(0.35, 0.12, 0.4),
	Color(0.05, 0.05, 0.06),
]

## Насколько темнее вторая краска двухцветного кузова.
const SHADE: float = 0.55

const HEADLIGHT := Color(1.0, 0.95, 0.8)
const TAILLIGHT := Color(1.0, 0.1, 0.08)
const INDICATOR_GLASS := Color(0.55, 0.3, 0.05)

## Соль жребия машины: своя, чтобы машина не ходила в ногу с раскладкой.
const SALT: int = 0x0CA2_5EED


## Жребий здания: какая модель и какая краска. [param building] — номер здания в
## партии, [param building_seed] — его сид.
class Choice:
	extends RefCounted

	var model: int = 0
	var paint: int = 0


## Что стоит у выхода здания.
static func choose(building: int, building_seed: int) -> Choice:
	var choice := Choice.new()
	if building <= 1:
		return choice
	var rng := RandomNumberGenerator.new()
	# Номер здания — в жребий вместе с сидом: без соли партии сид и есть номер,
	# а инструменты снимают разные здания на одном сиде.
	rng.seed = hash([building_seed, building, SALT])
	choice.model = rng.randi_range(0, MODELS.size() - 1)
	choice.paint = rng.randi_range(0, PAINTS.size() - 1)
	return choice


## Собирает машину узлом без тел.
static func build(choice: Choice = Choice.new()) -> Node3D:
	var car := (MODELS[choice.model] as PackedScene).instantiate() as Node3D
	car.name = "Car"
	var paint := PAINTS[choice.paint]
	for node in car.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.mesh.surface_get_material(surface)
			var wanted := _material_for(material.resource_name if material else "", paint)
			if wanted != null:
				mesh_instance.set_surface_override_material(surface, wanted)
	# Дождь и снег гаснут о кузов, а не идут сквозь машину (ADR-0054).
	Shelter.over_meshes(car)
	return car


## Снег на кузове ([code]snow_cap.gdshader[/code]) — накладным материалом на
## его части, поверх своей краски (ADR-0054). [param amount] — сколько
## снега: 1 — шапка, меньше — налёт. Колёса и салон — без снега: катящееся
## колесо несло бы белую полосу по верху шины, а сиденья под стеклом белели бы
## сугробом в салоне.
static func snow_on(car: Node3D, amount: float = 1.0) -> void:
	var cap := ShaderMaterial.new()
	cap.shader = SNOW_CAP
	cap.set_shader_parameter("amount", amount)
	for node in car.find_children("*", "MeshInstance3D", true, false):
		if node.name.begins_with("Wheel") or node.name.begins_with("CarInterior"):
			continue
		(node as MeshInstance3D).material_overlay = cap


## Колёса машины: узлы, которые крутятся, когда она едет.
static func wheels(car: Node3D) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node in car.find_children("Wheel*", "Node3D", true, false):
		found.append(node as Node3D)
	return found


## Середина каждого колеса [param wheels] в его собственных координатах: вокруг
## неё оно и крутится. Начало узла колеса у пака не на оси, а в нуле машины, и
## поворот вокруг начала носил бы колёса кругом по кузову (авторевью M21).
static func hubs(wheels: Array[Node3D]) -> PackedVector3Array:
	var found := PackedVector3Array()
	for wheel: Node3D in wheels:
		var mesh := wheel as MeshInstance3D
		found.append(mesh.mesh.get_aabb().get_center() if mesh != null else Vector3.ZERO)
	return found


## Радиус колеса по габариту его сетки, м; [param fallback] — если сеток нет.
static func wheel_radius(wheels: Array[Node3D], fallback: float) -> float:
	var radius := fallback
	for wheel: Node3D in wheels:
		var mesh := wheel as MeshInstance3D
		if mesh != null:
			radius = maxf(mesh.mesh.get_aabb().size.y * 0.5, 0.05)
	return radius


## Катит колёса [param wheels] вокруг осей [param hubs] на путь [param travel], м:
## угол — путь, делённый на радиус [param radius]. Капот в +X, и колесо,
## катящееся вперёд, идёт по часовой, если смотреть с +Z, — это минус вокруг +Z.
## Модель, развёрнутая назад, катит их в своей системе вперёд, поэтому знак один.
static func roll(
	wheels: Array[Node3D], hubs_of: PackedVector3Array, travel: float, radius: float
) -> void:
	var spin := Basis(Vector3.BACK, -travel / radius)
	for index: int in wheels.size():
		var hub := hubs_of[index]
		wheels[index].transform *= Transform3D(spin, hub - spin * hub)


## Замена материала пака на игровой: краска, свет. Остальное — как у пака.
static func _material_for(name: String, paint: Color) -> StandardMaterial3D:
	match name:
		"Paint":
			return GreyboxLook.polished(paint)
		"PaintShade":
			return GreyboxLook.polished(paint.darkened(SHADE))
		"Headlights":
			return GreyboxLook.light(HEADLIGHT)
		"TailLights":
			return GreyboxLook.light(TAILLIGHT)
		# Поворотники без огня — янтарный пластик; мигает только правый у машины
		# Otto, своим материалом ([ExitCar]).
		"IndicatorLeft", "IndicatorRight":
			return GreyboxLook.polished(INDICATOR_GLASS)
	return null
