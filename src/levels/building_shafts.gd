class_name BuildingShafts
extends Node3D

## Одежда шахт здания: направляющие, створки этажей, упоры и машинное отделение.
##
## Своим узлом, а не прямыми детьми уровня. Частей выходит за полсотни на здание,
## а по детям уровня ходят и агенты, и кабины, и половина тестов — каждый такой
## обход перебирал бы ещё и стойки со створками. Ровно по этой причине из уровня
## в своё время вынесли задний план.
##
## Тел здесь нет ни у чего: по направляющим не ходят, они только видны. Ездит
## кабина, а проём в перекрытии режет само перекрытие.

## Ширина направляющей шахты, м. Стойка идёт по краю проёма во всю его высоту.
const RAIL_WIDTH: float = 0.18

## Высота створок шахты, м.
const DOOR_HEIGHT: float = 1.02

## Высота упора в конце полосы шахты, м.
const BUFFER_HEIGHT: float = 0.24

## Надстройка машинного отделения на крыше, м.
const MACHINE_ROOM_SIZE := Vector2(2.16, 1.32)

## Глубина стоек и упоров и куда они утоплены: за кабину, но перед стеной.
## Кабина идёт в плоскости игры и закрывает их собой, проходя мимо.
const RAIL_DEPTH: float = 0.3
const RAIL_Z: float = -0.45

## Толщина створок шахты и машинного отделения. Створки висят на задней стене,
## как и двери этажей; домик стоит на крыше у той же стены.
##
## Домик не доходит до плоскости игры: его передняя грань кончается за спиной
## Otto (тело толщиной [constant WorldSpace.BODY_DEPTH] вокруг нуля), иначе он
## проходил бы сквозь стену домика, а не перед ней (авторевью M15).
const PANEL_THICKNESS: float = 0.08
const MACHINE_ROOM_DEPTH: float = 0.7

## Столб света в шахте: радиус, яркость, цвет и вынос перед направляющими, м.
##
## Долг с M12 ([ADR-0017](../../../docs/adr/0017-spectrum-palette-and-shafts.md),
## решение 3), закрытый в M18b
## ([ADR-0025](../../../docs/adr/0025-shafts-escalators-and-riders.md), решение 3).
## Источник настоящий, а не свечение материала: свет обязан лечь на направляющие,
## створки и пол перед проёмом, иначе на погашенном этаже шахта висит светящейся
## полосой в черноте и «здесь путь вниз» читается хуже, чем сбитой лампой.
##
## Холодный против тёплых ламп (ADR-0023, решение 3): шахта — металл, и свет
## в ней не домашний. Теней не кладёт — их в шахте некуда ронять, а стоят они
## дороже всего остального.
## Радиус — чуть шире самой шахты (1.2 м), и это не скупость. На 4.2 м столбы
## пяти шахт стилобата заливали этаж целиком, и погашенный этаж переставал быть
## погашенным: темнота M17 отменялась светом, который к ней отношения не имеет.
## Столб обязан светить в шахте, а не вместо ламп.
const GLOW_RANGE: float = 1.8
const GLOW_ENERGY: float = 1.1
const GLOW_COLOR := Color(0.74, 0.84, 1.0)
const GLOW_Z: float = -0.35

var _rules: BuildingRules
var _plan: BuildingPlan
## Источники столба: этаж → те, что на нём стоят. Гаснут вне кадра, как лампы.
var _glow: Dictionary = {}


## Одевает все шахты здания разом.
func dress(rules: BuildingRules, plan: BuildingPlan) -> void:
	_rules = rules
	_plan = plan
	for shaft in plan.shafts:
		_dress_shaft(shaft)
	_spawn_machine_room()


## Зажигает столбы света на видимых этажах и гасит остальные.
##
## Тем же правилом, что и лампы (ADR-0010, пункт 8): в здании до дюжины шахт и
## по источнику на каждый их этаж, а в кадр влезает два с половиной этажа.
## Гаснет источник, но не сам столб: погашенный этаж от невидимого отличается
## тем, что его видно.
func light_span(span: Vector2i) -> void:
	for index: int in _glow:
		var lit := VisibleFloors.covers(span, index)
		for light: OmniLight3D in _glow[index]:
			light.visible = lit


## Верх шахты: докуда идут её стойки и упор.
##
## У шахты, доходящей до крыши, потолка нет — над ней небо, и [method
## BuildingRules.story_top] отдаёт верх мира. Стойка и упор ушли бы в открытое
## небо над крышей; кончается такая шахта внутри машинного отделения, оно и
## есть её верх.
func top_of(shaft: BuildingPlan.ShaftSpot) -> float:
	if shaft.top > BuildingRules.ROOF:
		return _rules.story_top(shaft.top)
	return _rules.floor_surface(BuildingRules.ROOF) - MACHINE_ROOM_SIZE.y * 0.5


## Одевает шахту: направляющие во всю её высоту и створки на каждом её этаже.
##
## До M12 шахта была дырой в перекрытии — в кадре её почти не было, хотя спуск
## по зданию и есть игра (ADR-0017, решение 3). Направляющие дают ей края,
## створки — отметку этажа: по ним видно, где кабина встаёт.
func _dress_shaft(shaft: BuildingPlan.ShaftSpot) -> void:
	_mark_shaft_ends(shaft)
	var top := top_of(shaft)
	var bottom := _rules.floor_surface(shaft.bottom)
	var half := _rules.shaft_width * 0.5
	# Шахта — металл (ADR-0023, решение 5): направляющие ловят блик ламп.
	var rail := GreyboxLook.metal(GreyboxLook.SHAFT)

	for side: float in [-1.0, 1.0]:
		var x := shaft.x + half * side
		var left := x if side < 0.0 else x - RAIL_WIDTH
		_add_part(Rect2(left, top, RAIL_WIDTH, bottom - top), rail, RAIL_Z, RAIL_DEPTH)

	var panel := GreyboxLook.surface(GreyboxLook.WALL)
	var panel_z := WorldSpace.BACK_WALL_Z + PANEL_THICKNESS * 0.5 + 0.01
	for index: int in range(shaft.top, shaft.bottom + 1):
		var surface := _rules.floor_surface(index)
		var door := Rect2(shaft.x - half, surface - DOOR_HEIGHT, _rules.shaft_width, DOOR_HEIGHT)
		_add_part(door, panel, panel_z, PANEL_THICKNESS)
		_light_the_shaft(shaft.x, index, surface)


## Источник столба на одном этаже шахты: посреди пролёта, перед направляющими.
##
## По источнику на этаж, а не один на всю шахту: полоса бывает в четырнадцать
## этажей, и один источник с таким радиусом освещал бы её середину и оставлял
## тёмными оба конца — а кабина ходит по всей полосе.
func _light_the_shaft(x: float, index: int, surface: float) -> void:
	var light := OmniLight3D.new()
	light.omni_range = GLOW_RANGE
	light.light_energy = GLOW_ENERGY
	light.light_color = GLOW_COLOR
	light.shadow_enabled = false
	light.position = WorldSpace.to_scene(Vector2(x, surface - _rules.floor_height * 0.5))
	light.position.z = GLOW_Z
	add_child(light)

	if not _glow.has(index):
		_glow[index] = [] as Array[OmniLight3D]
	(_glow[index] as Array[OmniLight3D]).append(light)


## Упоры в концах полосы: дальше кабина не идёт, и это видно.
##
## Отзыв после игры: «лифт не слушается команд и стоит, а сошёл — уехал». Это
## и был конец полосы — кабина слышала команду, но идти дальше ей некуда, а
## пустая она тут же уезжала по своему расписанию. Упор объясняет предел без
## единого слова; второй указатель — стрелки в самой кабине.
##
## Нижний упор лежит на дне шахты, то есть над полом нижнего её этажа, а не
## в толще плиты, где его не видно вовсе.
func _mark_shaft_ends(shaft: BuildingPlan.ShaftSpot) -> void:
	var half := _rules.shaft_width * 0.5
	var top := top_of(shaft)
	var bottom := _rules.floor_surface(shaft.bottom) - BUFFER_HEIGHT
	var buffer := GreyboxLook.marker(GreyboxLook.DOOR)

	_add_part(
		Rect2(shaft.x - half, top, _rules.shaft_width, BUFFER_HEIGHT), buffer, RAIL_Z, RAIL_DEPTH
	)
	_add_part(
		Rect2(shaft.x - half, bottom, _rules.shaft_width, BUFFER_HEIGHT), buffer, RAIL_Z, RAIL_DEPTH
	)


## Кусок одежды шахты: коробка без тела на месте прямоугольника правил.
func _add_part(rect: Rect2, material: StandardMaterial3D, z: float, depth: float) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var part := GreyboxLook.box(Vector3(rect.size.x, rect.size.y, depth), material)
	part.position = WorldSpace.to_scene(rect.get_center())
	part.position.z = z
	add_child(part)


## Надстройка машинного отделения над верхней шахтой.
##
## Тела у неё нет намеренно: под ней проём той самой шахты, с которой начинается
## спуск, и сплошная надстройка заперла бы Otto на крыше. Стоит она у задней
## стены, и он проходит перед ней.
func _spawn_machine_room() -> void:
	var shaft := _plan.roof_shaft()
	if shaft == null:
		return

	var surface := _rules.floor_surface(BuildingRules.ROOF)
	var rect := Rect2(
		Vector2(shaft.x - MACHINE_ROOM_SIZE.x * 0.5, surface - MACHINE_ROOM_SIZE.y),
		MACHINE_ROOM_SIZE
	)
	var z := WorldSpace.BACK_WALL_Z + MACHINE_ROOM_DEPTH * 0.5
	_add_part(rect, GreyboxLook.surface(GreyboxLook.WALL), z, MACHINE_ROOM_DEPTH)
