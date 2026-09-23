class_name RoofKit
extends Node3D

## Всё, что стоит на крыше, кроме скатов: техника, мачта с огнём и неоновая
## вывеска (ADR-0031, решение 2).
##
## За плоскостью игры и без тел — Otto ходит по настилу, как ходил. Техника
## стоит на ступенях скатов ([method BuildingRoof.steps]): там, где у настоящей
## крыши уровни кровли. Сторона бака и кондиционеров — по месту: бак на ту
## сторону от машинного отделения, где скат длиннее.

## Насколько техника отстоит от задней линии коридора вглубь, м.
const DEPTH_Z: float = WorldSpace.BACK_WALL_Z - 1.8

## Водяной бак: радиус, высота, высота опор.
const TANK_RADIUS: float = 0.75
const TANK_HEIGHT: float = 1.4
const TANK_LEGS: float = 1.0

## Блок кондиционера и сколько их.
const UNIT := Vector3(1.0, 0.7, 0.8)
const UNITS: int = 2

## Вентиляционная труба: радиус и высота; колпак шире.
const VENT_RADIUS: float = 0.1
const VENT_HEIGHT: float = 0.8

## Мачта над машинным отделением: высота и толщина; огонь на верхушке и как
## часто мигает, с.
const MAST_HEIGHT: float = 5.0
const MAST_THICKNESS: float = 0.08
const BEACON: float = 0.16
const BEACON_PERIOD: float = 1.4
const BEACON_ON: float = 0.35

## Неоновая вывеска на каркасе за крышей: размер щита, на какой высоте над
## настилом его низ, насколько он позади коридора; надпись и её цвет.
const SIGN := Vector2(5.0, 1.2)
## Верх щита в кадре крыши: на 2.6 м надпись уходила за верх кадра.
const SIGN_RISE: float = 1.6
const SIGN_Z: float = WorldSpace.BACK_WALL_Z - 6.5
const SIGN_TEXT := "HOTEL"
const NEON := Color(1.0, 0.25, 0.55)
## Отсвет вывески — единственный источник крыши сверх лампы над ней.
const GLOW_ENERGY: float = 1.6
const GLOW_RANGE: float = 9.0

const STEEL := Color(0.3, 0.31, 0.33)
const STEEL_LIGHT := Color(0.52, 0.53, 0.55)
const TANK := Color(0.36, 0.3, 0.26)
const BEACON_RED := Color(1.0, 0.12, 0.08)

var _beacon: MeshInstance3D = null
var _clock: float = 0.0


## Ставит технику, мачту и вывеску по правилам и плану.
func build(rules: BuildingRules, plan: BuildingPlan) -> void:
	var shaft := plan.roof_shaft()
	if shaft == null:
		return
	var steps := BuildingRoof.steps(rules, plan)
	var surface := rules.floor_surface(BuildingRules.ROOF)
	var bounds := rules.floor_span(BuildingRules.ROOF)
	var half_room := BuildingShafts.MACHINE_ROOM_SIZE.x * 0.5
	var left := Vector2(bounds.x + BuildingShell.WALL_WIDTH, shaft.x - half_room)
	var right := Vector2(shaft.x + half_room, bounds.y - BuildingShell.WALL_WIDTH)
	var long := left if left.y - left.x >= right.y - right.x else right
	var short := right if long == left else left

	_tank(
		Vector2(
			long.x + (long.y - long.x) * 0.6,
			_top_at(steps, surface, long.x + (long.y - long.x) * 0.6)
		)
	)
	for index in UNITS:
		var x := long.x + (long.y - long.x) * (0.15 + 0.2 * float(index))
		_unit(Vector2(x, _top_at(steps, surface, x)))
	if short.y - short.x > 1.0:
		var x := (short.x + short.y) * 0.5
		_vent(Vector2(x, _top_at(steps, surface, x)))
	_vent(Vector2(long.x + 0.4, _top_at(steps, surface, long.x + 0.4)))
	_ladder(shaft.x - half_room - 0.2, surface)
	_mast(shaft.x, surface - BuildingShafts.MACHINE_ROOM_SIZE.y)
	_neon((bounds.x + bounds.y) * 0.5, surface)


## Мигает огнём мачты. Картинка, а не правило: по настенным часам.
func _process(delta: float) -> void:
	if _beacon == null:
		return
	_clock = fmod(_clock + delta, BEACON_PERIOD)
	_beacon.visible = _clock < BEACON_PERIOD * BEACON_ON


## Верх кровли в точке [param x]: верх самой высокой ступени над ней или настил.
static func _top_at(steps: Array[Rect2], surface: float, x: float) -> float:
	var top := surface
	for rect in steps:
		if x >= rect.position.x and x <= rect.end.x:
			top = minf(top, rect.position.y)
	return top


func _box(size: Vector3, at: Vector2, z: float, material: StandardMaterial3D) -> MeshInstance3D:
	var part := GreyboxLook.box(size, material)
	part.position = WorldSpace.to_scene(at)
	part.position.z = z
	add_child(part)
	return part


func _cylinder(
	radius: float, height: float, bottom: Vector2, z: float, material: StandardMaterial3D
) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = WorldSpace.to_scene(bottom - Vector2(0.0, height * 0.5))
	part.position.z = z
	add_child(part)


## Бак на четырёх опорах с обручами.
func _tank(foot: Vector2) -> void:
	var steel := GreyboxLook.metal(STEEL)
	for dx: float in [-TANK_RADIUS * 0.7, TANK_RADIUS * 0.7]:
		for dz: float in [-TANK_RADIUS * 0.6, TANK_RADIUS * 0.6]:
			_box(
				Vector3(0.08, TANK_LEGS, 0.08),
				Vector2(foot.x + dx, foot.y - TANK_LEGS * 0.5),
				DEPTH_Z + dz,
				steel
			)
	var base := Vector2(foot.x, foot.y - TANK_LEGS)
	_cylinder(TANK_RADIUS, TANK_HEIGHT, base, DEPTH_Z, GreyboxLook.surface(TANK))
	for ring: float in [0.25, 0.75]:
		_cylinder(
			TANK_RADIUS + 0.03,
			0.06,
			Vector2(foot.x, base.y - TANK_HEIGHT * ring + 0.03),
			DEPTH_Z,
			steel
		)
	# Коническая крышка.
	var cap := CylinderMesh.new()
	cap.top_radius = 0.05
	cap.bottom_radius = TANK_RADIUS
	cap.height = 0.4
	var lid := MeshInstance3D.new()
	lid.mesh = cap
	lid.material_override = steel
	lid.position = WorldSpace.to_scene(Vector2(foot.x, base.y - TANK_HEIGHT - 0.2))
	lid.position.z = DEPTH_Z
	add_child(lid)


## Блок кондиционера с решёткой вентилятора сверху.
func _unit(foot: Vector2) -> void:
	_box(
		UNIT, Vector2(foot.x, foot.y - UNIT.y * 0.5), DEPTH_Z + 0.6, GreyboxLook.metal(STEEL_LIGHT)
	)
	_cylinder(
		UNIT.z * 0.35,
		0.04,
		Vector2(foot.x, foot.y - UNIT.y),
		DEPTH_Z + 0.6,
		GreyboxLook.metal(STEEL)
	)
	for slat in 4:
		_box(
			Vector3(UNIT.x * 0.9, 0.03, 0.02),
			Vector2(foot.x, foot.y - UNIT.y * (0.2 + 0.15 * float(slat))),
			DEPTH_Z + 0.6 + UNIT.z * 0.5 + 0.01,
			GreyboxLook.metal(STEEL)
		)


## Вентиляционная труба с колпаком.
func _vent(foot: Vector2) -> void:
	var steel := GreyboxLook.metal(STEEL_LIGHT)
	_cylinder(VENT_RADIUS, VENT_HEIGHT, foot, DEPTH_Z + 1.0, steel)
	_cylinder(
		VENT_RADIUS * 2.2, 0.06, Vector2(foot.x, foot.y - VENT_HEIGHT - 0.12), DEPTH_Z + 1.0, steel
	)


## Лестница на машинное отделение: две тетивы и перекладины.
func _ladder(x: float, surface: float) -> void:
	var steel := GreyboxLook.metal(STEEL_LIGHT)
	var height := BuildingShafts.MACHINE_ROOM_SIZE.y + 0.4
	var z := WorldSpace.BACK_WALL_Z + BuildingShafts.MACHINE_ROOM_DEPTH * 0.5
	for dx: float in [-0.18, 0.18]:
		_box(Vector3(0.04, height, 0.04), Vector2(x + dx, surface - height * 0.5), z, steel)
	var rungs := int(height / 0.3)
	for rung in rungs:
		_box(Vector3(0.36, 0.03, 0.03), Vector2(x, surface - 0.25 - float(rung) * 0.3), z, steel)


## Мачта над машинным отделением с поперечинами и мигающим огнём.
func _mast(x: float, base: float) -> void:
	var steel := GreyboxLook.metal(STEEL)
	var z := WorldSpace.BACK_WALL_Z - 0.2
	_box(
		Vector3(MAST_THICKNESS, MAST_HEIGHT, MAST_THICKNESS),
		Vector2(x, base - MAST_HEIGHT * 0.5),
		z,
		steel
	)
	for bar: float in [0.35, 0.6, 0.85]:
		_box(Vector3(0.9 - bar * 0.5, 0.04, 0.04), Vector2(x, base - MAST_HEIGHT * bar), z, steel)
	_beacon = _box(
		Vector3(BEACON, BEACON, BEACON),
		Vector2(x, base - MAST_HEIGHT - BEACON * 0.5),
		z,
		GreyboxLook.light(BEACON_RED)
	)


## Неоновая вывеска на решётчатом каркасе за крышей, с цветным отсветом.
func _neon(x: float, surface: float) -> void:
	var steel := GreyboxLook.metal(STEEL)
	var bottom := surface - SIGN_RISE
	for dx: float in [-SIGN.x * 0.4, 0.0, SIGN.x * 0.4]:
		_box(
			Vector3(0.1, SIGN_RISE, 0.1), Vector2(x + dx, surface - SIGN_RISE * 0.5), SIGN_Z, steel
		)
	for dy: float in [0.3, 0.7]:
		_box(Vector3(SIGN.x, 0.06, 0.06), Vector2(x, surface - SIGN_RISE * dy), SIGN_Z, steel)
	_box(
		Vector3(SIGN.x, SIGN.y, 0.08),
		Vector2(x, bottom - SIGN.y * 0.5),
		SIGN_Z - 0.06,
		GreyboxLook.metal(Color(0.08, 0.08, 0.1))
	)

	var text := Label3D.new()
	text.text = SIGN_TEXT
	text.font_size = 128
	text.pixel_size = 0.01
	text.modulate = NEON
	text.shaded = false
	text.outline_size = 0
	text.position = WorldSpace.to_scene(Vector2(x, bottom - SIGN.y * 0.5))
	text.position.z = SIGN_Z + 0.01
	add_child(text)

	var glow := OmniLight3D.new()
	glow.name = "NeonGlow"
	glow.light_color = NEON
	glow.light_energy = GLOW_ENERGY
	glow.omni_range = GLOW_RANGE
	glow.shadow_enabled = false
	glow.position = WorldSpace.to_scene(Vector2(x, bottom - SIGN.y * 0.5))
	glow.position.z = SIGN_Z + 1.2
	add_child(glow)
