class_name GarageGate
extends Node3D

## Ворота паркинга в левом торце нижнего этажа (ADR-0038, решение 3): проём в
## стене, рулонная штора, короб под потолком, маячок, полосы у порога,
## вывеска EXIT и пандус наверх за воротами.
##
## Своим узлом, а не частью [Garage]: у ворот своё состояние — насколько
## поднята штора, — и его двигает сдача здания, а не раскладка.
##
## Камера видит торцевую стену ребром, и штора в её плоскости с камеры — черта
## толщиной в пять сантиметров. Поэтому у шторы есть лицо: в проёме видна
## задняя грань проёма, на ней — ламели шторы, и они сматываются вверх вместе
## с настоящей шторой, открывая за собой рыжий свет фонаря над пандусом. Остальное, что говорит
## «ворота», обращено к камере: короб, направляющая, маячок, полосы, вывеска.
##
## Тело стены остаётся целым — его строит [BuildingShell] невидимым, а видимые
## куски вокруг проёма ставятся здесь. Otto в ворота не выходит; машина — вид
## без тела — проезжает.

## Сколько уходит на подъём шторы по умолчанию, с.
const OPEN_TIME: float = 1.6
## Высота проёма, м: машина с крышей в 1.2 м проходит с запасом.
const HEIGHT: float = 2.4
## Короб шторы: вынос от стены и высота, м.
const BOX := Vector2(0.38, 0.3)
## Штора и направляющие: толщина шторы, сечение направляющей, шаг ламелей и
## нижняя планка (глубина, высота), м.
const SHUTTER_THICKNESS: float = 0.05
const RAIL: float = 0.1
const SLAT_PITCH: float = 0.12
const SHUTTER_BAR := Vector2(0.06, 0.07)
## Пандус за воротами: площадка у проёма, длина подъёма, м. Подъём — на этаж.
const RAMP_APRON: float = 3.0
const RAMP_RUN: float = 12.0

const SHUTTER := Color(0.64, 0.66, 0.68)
## Маячок ворот — янтарный — и улица за шторой: натриевый фонарь над пандусом.
const BEACON := Color(1.0, 0.55, 0.1)
const OUTSIDE := Color(0.78, 0.5, 0.2)

## Вывеска EXIT над воротами: зелёный огонёк, как у прежней вывески выхода
## (ADR-0019, решение 5; ADR-0023, решение 6) — выход обязан читаться и на
## погашенном этаже. Висит на перемычке, лицом к камере.
const EXIT_SIGN := Vector3(0.9, 0.24, 0.06)
const EXIT_INK := Color(0.02, 0.12, 0.05)

## Насколько открыты ворота: 0 — штора внизу, 1 — поднята в короб.
var openness: float = 0.0:
	set = set_openness

var _rules: BuildingRules = null
var _surface: float = 0.0
var _top: float = 0.0
## Штора, её нижняя планка и улица за ней: их двигает [member openness].
var _roll: Node3D = null
var _shutter_bar: MeshInstance3D = null
var _outside: MeshInstance3D = null
## Маячок над воротами: горит, пока штора ходит.
var _beacon: MeshInstance3D = null


## Собирает ворота у левой стены нижнего этажа.
func build(rules: BuildingRules) -> void:
	_rules = rules
	var bottom := rules.floors - 1
	_surface = rules.floor_surface(bottom)
	_top = rules.story_top(bottom)
	_build_opening()
	_build_shutter()
	_build_frame()
	_build_ramp()
	_hang_the_sign()
	set_openness(openness)


## Поднимает штору за [param duration] секунд. Идёт шагами физики, как всё в
## сдаче здания: исход не должен зависеть от частоты кадров. Возвращает твин —
## его [signal Tween.finished] и есть «ворота открыты».
func open(duration: float = OPEN_TIME) -> Tween:
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(self, "openness", 1.0, duration)
	return tween


## Открыты ли ворота целиком.
func is_open() -> bool:
	return openness >= 1.0


func set_openness(value: float) -> void:
	openness = clampf(value, 0.0, 1.0)
	if _roll == null:
		return
	# Штора сматывается вверх, в короб: узел шторы висит верхом у перемычки,
	# и высота уходит снизу.
	var hanging := 1.0 - openness
	_roll.visible = hanging > 0.005
	_roll.scale.y = maxf(hanging, 0.001)
	_shutter_bar.position.y = WorldSpace.height_to_scene(
		_surface - HEIGHT * openness - SHUTTER_BAR.y * 0.5 - 0.002
	)
	var moving := openness > 0.0 and openness < 1.0
	_beacon.material_override = (
		GreyboxLook.light(BEACON) if moving else GreyboxLook.surface(BEACON.darkened(0.6))
	)
	_outside.visible = openness > 0.0


## Проём: перемычка над ним во всю глубину и стена зала за ним — кладка, как у
## наружных стен ([BuildingShell]); за шторой — свет фонаря над пандусом.
func _build_opening() -> void:
	var masonry := GreyboxLook.surface(
		GreyboxLook.WALL.lerp(_rules.palette.masonry, BuildingShell.PALETTE_SHARE)
	)
	var wall := BuildingShell.WALL_WIDTH
	var full := WorldSpace.CORRIDOR_DEPTH + WorldSpace.ROOM_DEPTH
	var gate_top := _surface - HEIGHT
	var x := Garage.gate_x(_rules)
	_box(
		Vector3(wall, gate_top - _top, full),
		masonry,
		_at(x, (_top + gate_top) * 0.5, WorldSpace.CORRIDOR_DEPTH * 0.5 - full * 0.5)
	)
	# Стена за проёмом — до пола, не в толщу плиты: грани плиты и стены
	# легли бы в одну плоскость.
	var behind := full - WorldSpace.CORRIDOR_DEPTH
	_box(
		Vector3(wall, HEIGHT, behind),
		masonry,
		_at(x, gate_top + HEIGHT * 0.5, WorldSpace.BACK_WALL_Z - behind * 0.5)
	)
	_outside = _box(
		Vector3(wall, HEIGHT, 0.006),
		GreyboxLook.marker(OUTSIDE),
		_at(x, gate_top + HEIGHT * 0.5, WorldSpace.BACK_WALL_Z + 0.004),
		false
	)


## Штора — узел, висящий верхом у перемычки: сматывая её, [member openness]
## сжимает его по высоте. Нижняя планка ходит отдельно — она не сжимается.
func _build_shutter() -> void:
	var wall := BuildingShell.WALL_WIDTH
	var x := Garage.gate_x(_rules)
	var slat := GreyboxLook.metal(SHUTTER)
	var groove := GreyboxLook.metal(SHUTTER.darkened(0.45))
	_roll = Node3D.new()
	_roll.name = "Shutter"
	_roll.position = _at(x, _surface - HEIGHT, 0.0)
	add_child(_roll)
	var lane := _lane()
	_box(
		Vector3(SHUTTER_THICKNESS, HEIGHT, lane - RAIL * 2.0),
		slat,
		Vector3(0.0, -HEIGHT * 0.5, 0.0),
		false,
		_roll
	)
	var face_z := WorldSpace.BACK_WALL_Z + 0.015
	_box(
		Vector3(wall - 0.04, HEIGHT, 0.01), slat, Vector3(0.0, -HEIGHT * 0.5, face_z), false, _roll
	)
	var rise := SLAT_PITCH
	while rise < HEIGHT - 0.02:
		_box(
			Vector3(wall - 0.06, 0.014, 0.004),
			groove,
			Vector3(0.0, -rise, face_z + 0.007),
			false,
			_roll
		)
		rise += SLAT_PITCH
	_shutter_bar = _box(
		Vector3(wall - 0.02, SHUTTER_BAR.y, SHUTTER_BAR.x),
		GreyboxLook.metal(SHUTTER.darkened(0.25)),
		_at(x, _surface - SHUTTER_BAR.y * 0.5, WorldSpace.BACK_WALL_Z + 0.05),
		false
	)


## Короб шторы на внутренней грани стены под потолком, направляющие по краям
## проезда, маячок и полосы у порога — это и видно с камеры.
func _build_frame() -> void:
	var steel := GreyboxLook.metal(SHUTTER)
	var yellow := GreyboxLook.surface(Garage.PAINT_YELLOW)
	var black := GreyboxLook.surface(Garage.PAINT_BLACK)
	var inner_x := Garage.inner_span(_rules).x
	# Короб — сразу над проёмом, вывеска EXIT — над коробом.
	var box_top := _surface - HEIGHT - BOX.y
	var lane := _lane()
	_box(Vector3(BOX.x, BOX.y, lane), steel, _at(inner_x + BOX.x * 0.5, box_top + BOX.y * 0.5, 0.0))
	for index in 3:
		_box(
			Vector3(BOX.x - 0.04, 0.06, 0.006),
			yellow if index % 2 == 0 else black,
			_at(inner_x + BOX.x * 0.5, box_top + BOX.y - 0.05 - 0.06 * index, lane * 0.5 + 0.004),
			false
		)
	var rail_height := _surface - (box_top + BOX.y)
	for z: float in [lane * 0.5 - RAIL * 0.5, -lane * 0.5 + RAIL * 0.5]:
		_box(
			Vector3(RAIL, rail_height, RAIL),
			steel,
			_at(inner_x + RAIL * 0.5 + 0.02, _surface - rail_height * 0.5, z)
		)
	_beacon = _box(
		Vector3(0.12, 0.12, 0.12),
		GreyboxLook.surface(BEACON),
		_at(inner_x + BOX.x + 0.1, box_top + 0.08, lane * 0.5 - 0.1),
		false
	)
	# Полосы у порога: жёлтые и чёрные вдоль проезда, поперёк ворот. Полосы
	# поперёк проезда с наклонённой камеры слились бы: пол виден полосой. Концы —
	# не вровень с направляющими.
	for index in 6:
		_box(
			Vector3(0.12, 0.005, lane - 0.04),
			yellow if index % 2 == 0 else black,
			_at(inner_x + 0.08 + 0.12 * index, _surface - 0.0045, 0.0),
			false
		)


## Пандус за воротами: площадка у проёма и подъём влево на этаж — за краем
## кадра, камера здания туда не заходит. По нему уезжает машина.
func _build_ramp() -> void:
	var ramp := Node3D.new()
	ramp.name = "Ramp"
	add_child(ramp)
	var concrete := BuildingFinish.shaft_concrete(Garage.CONCRETE)
	var left := _rules.floor_span(_rules.floors - 1).x
	var width := WorldSpace.CORRIDOR_DEPTH + 0.4
	var thickness := _rules.slab_height
	_box(
		Vector3(RAMP_APRON, thickness, width),
		concrete,
		_at(left - RAMP_APRON * 0.5, _surface + thickness * 0.5, 0.0),
		true,
		ramp
	)
	var rise := _rules.floor_height
	var slope := Vector2(RAMP_RUN, rise).length()
	var incline := _box(Vector3(slope, thickness, width), concrete, Vector3.ZERO, true, ramp)
	incline.rotation.z = -atan2(rise, RAMP_RUN)
	incline.position = _at(
		left - RAMP_APRON - RAMP_RUN * 0.5, _surface - rise * 0.5 + thickness * 0.5, 0.0
	)


## Вывеска EXIT на перемычке над воротами, лицом к камере.
func _hang_the_sign() -> void:
	var left := _rules.floor_span(_rules.floors - 1).x
	var sign_z := WorldSpace.CORRIDOR_DEPTH * 0.5 + EXIT_SIGN.z * 0.5 + 0.004
	# Не `sign`: так зовут встроенную функцию, и местная переменная её заслонила бы.
	var board := GreyboxLook.box(EXIT_SIGN, GreyboxLook.light(GreyboxLook.SIGN_GREEN))
	board.name = "ExitSign"
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	board.position = _at(left + EXIT_SIGN.x * 0.5 + 0.02, _top + 0.03 + EXIT_SIGN.y * 0.5, sign_z)
	add_child(board)
	var words := Garage.label("◀ EXIT", 800, 0.16, EXIT_INK)
	words.shaded = false
	words.position = Vector3(0.0, 0.0, EXIT_SIGN.z * 0.5 + 0.004)
	board.add_child(words)


## Проезд под короб: глубина коридора с зазором от его граней.
static func _lane() -> float:
	return WorldSpace.CORRIDOR_DEPTH - 0.1


static func _at(x: float, y: float, z: float) -> Vector3:
	return Garage.scene_point(x, y, z)


func _box(
	size: Vector3,
	material: StandardMaterial3D,
	centre: Vector3,
	shadow: bool = true,
	parent: Node = null
) -> MeshInstance3D:
	var part := GreyboxLook.box(size, material)
	part.position = centre
	if not shadow:
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else self).add_child(part)
	return part
