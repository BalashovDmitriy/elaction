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
## стоп-сигналы светятся эмиссией — источников машина не добавляет.

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
	return car


## Колёса машины: узлы, которые крутятся, когда она едет.
static func wheels(car: Node3D) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node in car.find_children("Wheel*", "Node3D", true, false):
		found.append(node as Node3D)
	return found


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
	return null
