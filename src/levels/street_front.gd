class_name StreetFront
extends Node3D

## Вход в здание со стороны улицы выезда по типу (ADR-0058, решения 5 и 6).
##
## Камера смотрит на торец здания ребром, и плоское на его стене не видно:
## вход читается тем, что выступает над тротуаром. У отеля — козырёк с
## бегущими лампочками и латунными стойками, ковёр до бордюра и парковщик в
## ливрее у своей стойки; у офиса — стеклянный тамбур со светом внутри и
## вращающейся дверью; у жилого дома — крыльцо со ступенями, перилами и
## мусорными баками у бордюра.
##
## Вид, без тел и без новых источников света: машина выезжает под тротуаром, по
## тоннелю, и вход ей не мешает. Тротуар — от плоскости игры до мостовой
## ([constant ExitStreet.NEAR_Z]).

## Насколько вход выступает от торца над тротуаром, м.
const REACH: float = 3.2
## Глубина тротуара, занятая входом: от переднего края до мостовой, по z.
const NEAR: float = 0.8
const FAR: float = ExitStreet.NEAR_Z + 0.25

const BURGUNDY := Color(0.4, 0.07, 0.09)
const BRASS := Color(0.78, 0.6, 0.3)
const CARPET := Color(0.5, 0.06, 0.08)
const BULB := Color(1.0, 0.85, 0.6)
const LIVERY := Color(0.38, 0.06, 0.08)

const GLASS := Color(0.55, 0.7, 0.78, 0.18)
const FRAME := Color(0.62, 0.64, 0.68)
const LOBBY_GLOW := Color(0.85, 0.92, 1.0)
const LOBBY_HEIGHT: float = 3.2

const STOOP := Color(0.45, 0.43, 0.4)
const RAIL := Color(0.12, 0.12, 0.12)
const CAN := Color(0.3, 0.32, 0.3)
const STEPS: int = 4
const STEP := Vector2(0.32, 0.17)

## Парковщик отеля; null у других типов. Тестам и кадрам.
var valet: Node3D = null

## Скелет парковщика: дышит, только пока выезд в кадре ([method set_active]).
var _valet_player: AnimationPlayer = null
var _left: float = 0.0
var _floor: float = 0.0
var _lit: bool = true


## Ставит вход здания типа [member BuildingRules.kind] у торца [param left] на
## тротуаре [param sidewalk] (плоскость правил).
func build(
	rules: BuildingRules, left: float, sidewalk: float, building_seed: int, weather: Weather.Kind
) -> void:
	name = "StreetFront"
	_left = left
	_floor = sidewalk
	_lit = TimeOfDay.sign_lit(rules.time_of_day)
	match rules.kind:
		BuildingIdentity.Kind.OFFICE:
			_lobby()
		BuildingIdentity.Kind.RESIDENTIAL:
			_stoop()
		_:
			_canopy()
			_valet(building_seed, weather, rules.time_of_day)


## Отель: козырёк на кронштейнах с лампочками по кромке, латунные стойки у
## края тротуара и ковёр под ним.
func _canopy() -> void:
	var height := 3.0
	var middle := _left - REACH * 0.5
	var depth := NEAR - FAR
	var z := (NEAR + FAR) * 0.5
	_box(GreyboxLook.surface(BURGUNDY), Vector3(REACH, 0.32, depth), middle, height, z)
	_box(
		GreyboxLook.metal(BRASS),
		Vector3(REACH + 0.04, 0.05, depth + 0.04),
		middle - 0.02,
		height - 0.02,
		z
	)
	for corner: float in [NEAR - 0.15, FAR + 0.15]:
		_box(
			GreyboxLook.metal(BRASS), Vector3(0.06, height, 0.06), _left - REACH + 0.1, 0.0, corner
		)
	var bulb := GreyboxLook.light(BULB) if _lit else GreyboxLook.surface(BULB.darkened(0.5))
	for step: int in int(REACH / 0.22):
		var x := _left - REACH + 0.11 + step * 0.22
		var ball := SphereMesh.new()
		ball.radius = 0.035
		ball.height = 0.07
		_mesh(ball, bulb, x, height - 0.05, NEAR + 0.02)
	_box(GreyboxLook.surface(CARPET), Vector3(REACH - 0.2, 0.02, 1.2), middle + 0.1, 0.006, z)
	var word := Garage.label("HOTEL", 800, 0.18, Color(0.95, 0.9, 0.8))
	word.position = _at(middle, height + 0.16, NEAR + 0.01)
	add_child(word)


## Парковщик отеля у своей стойки на краю козырька: модель прохожего в
## бордовой ливрее, стоит и ждёт машину.
func _valet(building_seed: int, weather: Weather.Kind, time: TimeOfDay.Kind) -> void:
	var stand_x := _left - REACH + 0.55
	_box(GreyboxLook.surface(BURGUNDY.darkened(0.2)), Vector3(0.45, 1.05, 0.4), stand_x, 0.0, -1.2)
	_box(GreyboxLook.metal(BRASS), Vector3(0.5, 0.04, 0.45), stand_x, 1.05, -1.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, 0x7A1E])
	var person := Passerby.make(rng, StreetPeople.HEIGHT, Passerby.dress_for(weather, time))
	person.name = "Valet"
	for node: Node in person.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if String(mesh.name).ends_with("Body"):
			# Поверхностями, как красит [Passerby]: общий material_override на
			# модели со скелетом ронял рендер на пустом материале.
			for surface: int in mesh.mesh.get_surface_count():
				mesh.set_surface_override_material(surface, GreyboxLook.surface(LIVERY))
	person.position = _at(stand_x + 0.6, 0.0, -0.9)
	add_child(person)
	var player := person.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null and player.has_animation(&"Idle"):
		player.get_animation(&"Idle").loop_mode = Animation.LOOP_LINEAR
		player.play(&"Idle")
		_valet_player = player
	valet = person


## Скелет парковщика — работа на каждый кадр, а улицу видно только у выезда:
## он дышит, пока выезд в кадре, как идут прохожие ([method
## StreetPeople.set_active]). Зовёт пандус каждый кадр.
func set_active(on: bool) -> void:
	if _valet_player != null and _valet_player.active != on:
		_valet_player.active = on


## Офис: стеклянный тамбур на всю глубину тротуара, переплёт, свет изнутри и
## барабан вращающейся двери.
func _lobby() -> void:
	var middle := _left - REACH * 0.5
	var depth := NEAR - FAR
	var z := (NEAR + FAR) * 0.5
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = GLASS
	glass.roughness = 0.05
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_box(glass, Vector3(REACH, LOBBY_HEIGHT, depth), middle, 0.0, z)
	var frame := GreyboxLook.metal(FRAME)
	_box(frame, Vector3(REACH + 0.1, 0.12, depth + 0.1), middle - 0.05, LOBBY_HEIGHT, z)
	for step: int in 4:
		# Стойки — внутри выноса: крайняя не входит в стену торца.
		var x := _left - REACH + 0.03 + (REACH - 0.06) * step / 3.0
		_box(frame, Vector3(0.05, LOBBY_HEIGHT, 0.05), x, 0.0, NEAR + 0.03)
	var glow := GreyboxLook.light(LOBBY_GLOW) if _lit else GreyboxLook.surface(FRAME)
	_box(glow, Vector3(REACH - 0.3, 0.06, depth - 0.3), middle, LOBBY_HEIGHT - 0.12, z)
	var drum := CylinderMesh.new()
	drum.top_radius = 0.75
	drum.bottom_radius = 0.75
	drum.height = 2.3
	drum.radial_segments = 16
	# Барабан и створка — на волосок выше пола тамбура: низы не в одной плоскости.
	_mesh(drum, glass, middle, 1.157, z)
	_box(frame, Vector3(0.04, 2.3, 1.4), middle, 0.007, z)


## Жилой дом: крыльцо ступенями к двери в торце, перила и баки у бордюра.
func _stoop() -> void:
	var stone := GreyboxLook.surface(STOOP)
	var z := (NEAR + FAR) * 0.5
	for step: int in STEPS:
		var width := STEP.x * (STEPS - step)
		_box(
			stone,
			Vector3(width, STEP.y, 1.6 - step * 0.01),
			_left - width * 0.5 - 0.01 * step,
			STEP.y * step,
			z - 0.3
		)
	var rail := GreyboxLook.metal(RAIL)
	var top := STEP.y * STEPS
	for side: float in [z - 1.05, z + 0.45]:
		var run := Vector2(STEP.x * STEPS, top).length()
		var bar := GreyboxLook.box(Vector3(run, 0.04, 0.04), rail)
		# Крыльцо поднимается к двери в торце, вправо: туда же и перила, и их
		# нижний конец ложится на стойку у тротуара.
		bar.rotation.z = atan2(top, STEP.x * STEPS)
		bar.position = _at(_left - STEP.x * STEPS * 0.5 - 0.06, top * 0.5 + 0.9, side)
		_add(bar)
		_box(rail, Vector3(0.04, 0.9, 0.04), _left - STEP.x * STEPS - 0.06, 0.004, side)
	var lamp := GreyboxLook.light(BULB) if _lit else GreyboxLook.surface(BULB.darkened(0.5))
	var ball := SphereMesh.new()
	ball.radius = 0.12
	ball.height = 0.24
	_mesh(ball, lamp, _left - 0.2, 2.6, z - 0.3)
	for index: int in 2:
		var can := CylinderMesh.new()
		can.top_radius = 0.28
		can.bottom_radius = 0.24
		can.height = 0.8
		can.radial_segments = 12
		_mesh(can, GreyboxLook.metal(CAN), _left - REACH + 0.4 + index * 0.62, 0.4, FAR + 0.4)


func _box(material: Material, size: Vector3, x: float, rise: float, z: float) -> void:
	var part := GreyboxLook.box(size, material as StandardMaterial3D)
	part.position = _at(x, rise + size.y * 0.5, z)
	_add(part)


func _mesh(mesh: PrimitiveMesh, material: Material, x: float, rise: float, z: float) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = _at(x, rise, z)
	_add(part)


## Точка над тротуаром: всё стоит на 3 мм выше его, чтобы низ не лёг в одну
## плоскость с плитами тротуара.
func _at(x: float, rise: float, z: float) -> Vector3:
	return Garage.scene_point(x, _floor - rise - 0.003, z)


func _add(part: MeshInstance3D) -> void:
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
