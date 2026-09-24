class_name BuildingProps
extends Node3D

## Обстановка этажей, таблички у дверей и трубы под потолком
## (ADR-0029, решение 3; с M21b — модели паков, ADR-0033, решение 3).
##
## Всё без тел: предмет — декор, а не укрытие. Где что стоит, решает
## [BuildingDressing], чем он выглядит — [PropCatalog]. Светится лишь то, что и
## в жизни светится, — табло, лампа на комоде: предмет за спиной актёра не
## должен спорить с его силуэтом (обводка — ADR-0022).

## Насколько предмет на стене отстоит от неё, м: вплотную он мерцал бы с ней.
const STANDOFF: float = 0.04

## Табличка у двери: размер, на какой высоте середина, м, и насколько она
## правее края двери.
const PLATE := Vector3(0.16, 0.1, 0.015)
const PLATE_RISE: float = 1.5
const PLATE_GAP: float = 0.14
## Таблички: латунь с тёмными цифрами в отеле, сталь в офисе.
const PLATE_HOTEL := Color(0.62, 0.48, 0.22)
const PLATE_OFFICE := Color(0.55, 0.57, 0.6)
const PLATE_INK := Color(0.08, 0.07, 0.06)
const PLATE_FONT := preload("res://assets/fonts/Pixellari.ttf")

## Труба под потолком: толщина, м. Висит перед пилястрами — они выступают из
## стены на [constant BuildingRibs.PILASTER_DEPTH] — и сразу под полосой, которую
## от наклонённой камеры закрывает кромка перекрытия
## ([method FloorSigns.hidden_band]). До авторевью M19 она шла в 7 см под
## потолком и целиком пряталась за кромкой: в кадре труб не было ни одной.
const PIPE_THICKNESS: float = 0.14
## Зазор трубы от пилястр и от полосы под кромкой, м.
const PIPE_GAP: float = 0.03
## Насколько труба не доходит до таблички этажа, м: перед ней она закрыла бы
## её верх.
const PIPE_CLEARANCE: float = 0.1
## Короче этого кусок трубы не ставится, м: обрубок у стены читается мусором.
const PIPE_MIN_LENGTH: float = 0.3

const PIPE := Color(0.22, 0.22, 0.24)
const GARAGE_STRIPE := Color(0.75, 0.75, 0.7)
const GARAGE_STOP := Color(0.6, 0.5, 0.15)

var _rules: BuildingRules = null


## Середина трубы по глубине: перед пилястрами, с зазором.
static func pipe_z() -> float:
	return WorldSpace.BACK_WALL_Z + BuildingRibs.PILASTER_DEPTH + PIPE_GAP + PIPE_THICKNESS * 0.5


## Верх трубы на этаже, в координатах правил: сразу под полосой, которую на
## глубине её передней грани закрывает кромка перекрытия.
static func pipe_top(rules: BuildingRules, floor_index: int) -> float:
	var front := pipe_z() + PIPE_THICKNESS * 0.5
	return rules.story_top(floor_index) + FloorSigns.hidden_band(front) + PIPE_GAP


## Куски трубы этажа: пары «левый край, правый край».
##
## Разрывы — там, где труба прошла бы сквозь что-то или закрыла бы его: шахта
## (ходит кабина), проём эскалатора с этажа выше (сквозь потолок идёт полотно)
## и табличка номера этажа. Статический: раскладку труб
## проверяют без сцены.
static func pipe_spans(
	rules: BuildingRules, plan: BuildingPlan, floor_index: int
) -> Array[Vector2]:
	var bounds := rules.floor_span(floor_index)
	var inner := Vector2(bounds.x + BuildingShell.WALL_WIDTH, bounds.y - BuildingShell.WALL_WIDTH)
	var cuts: Array[Vector2] = []
	var half := rules.shaft_width * 0.5
	for shaft in plan.shafts:
		if shaft.top <= floor_index and floor_index <= shaft.bottom:
			cuts.append(Vector2(shaft.x - half, shaft.x + half))
	for escalator in plan.escalators:
		if escalator.floor_index + 1 == floor_index:
			cuts.append(escalator.gap(rules))
	var plate := FloorSigns.centre_on(rules, floor_index).x
	var plate_reach := Proportions.FLOOR_SIGN.x * 0.5 + PIPE_CLEARANCE
	cuts.append(Vector2(plate - plate_reach, plate + plate_reach))

	var spans: Array[Vector2] = []
	for span in BuildingPlan.spans_between(cuts, inner):
		if span.y - span.x >= PIPE_MIN_LENGTH:
			spans.append(span)
	return spans


## Ставит обстановку по раскладке и таблички у дверей.
func build(
	rules: BuildingRules,
	plan: BuildingPlan,
	dressing: BuildingDressing,
	identity: BuildingIdentity = BuildingIdentity.new()
) -> void:
	_rules = rules
	for prop in dressing.props:
		_stand(prop)
	for item in dressing.decor:
		_hang(item)
	_plate_the_doors(plan, identity)
	for index: int in dressing.pipes:
		_lay_pipe(plan, index)
	_mark_garage(plan)


## Разметка гаража — этажа выхода (ADR-0031, решение 4): белые полосы между
## местами и колёсные упоры у стены, в обход шахт и выхода — их места
## [method BuildingPlan.safe_spots] и так не отдаёт.
func _mark_garage(plan: BuildingPlan) -> void:
	var index := _rules.floors - 1
	var surface := _rules.floor_surface(index)
	var stripe := GreyboxLook.surface(GARAGE_STRIPE)
	var stop := GreyboxLook.surface(GARAGE_STOP)
	var step := _rules.slot_x(1) - _rules.slot_x(0)
	var depth := WorldSpace.CORRIDOR_DEPTH * 0.8
	for x: float in plan.safe_spots(_rules, index):
		var line := GreyboxLook.box(Vector3(0.08, 0.01, depth), stripe)
		line.position = WorldSpace.to_scene(Vector2(x - step * 0.5, surface - 0.005))
		add_child(line)
		var block := GreyboxLook.box(Vector3(step * 0.45, 0.08, 0.14), stop)
		block.position = WorldSpace.to_scene(Vector2(x, surface - 0.04))
		block.position.z = WorldSpace.BACK_WALL_Z + STANDOFF + 0.2
		add_child(block)


## Мебель у стены: перед пилястрами, на полу этажа.
func _stand(prop: BuildingDressing.PropSpot) -> void:
	var item := PropCatalog.make(prop.name)
	if item == null:
		return
	item.position = WorldSpace.to_scene(Vector2(prop.x, _rules.floor_surface(prop.floor_index)))
	item.position.z = WorldSpace.BACK_WALL_Z + PropCatalog.FLOOR_OFFSET
	add_child(item)


## Предмет на стене: серединой на высоте из каталога.
func _hang(prop: BuildingDressing.PropSpot) -> void:
	var item := PropCatalog.make(prop.name)
	if item == null:
		return
	var entry := PropCatalog.entry(prop.name)
	var height := PropCatalog.footprint(prop.name).y
	var bottom := _rules.floor_surface(prop.floor_index) - entry.centre + height * 0.5
	item.position = WorldSpace.to_scene(Vector2(prop.x, bottom))
	item.position.z = WorldSpace.BACK_WALL_Z + STANDOFF
	add_child(item)


## Таблички у дверей: номер комнаты — этаж и порядковый номер двери слева
## направо, как в гостинице: 2904 — четвёртая дверь двадцать девятого этажа.
func _plate_the_doors(plan: BuildingPlan, identity: BuildingIdentity) -> void:
	var counted := {}
	var metal := GreyboxLook.metal(PLATE_HOTEL if identity.is_hotel() else PLATE_OFFICE)
	var doors := plan.doors.duplicate()
	doors.sort_custom(
		func(a: BuildingPlan.DoorSpot, b: BuildingPlan.DoorSpot) -> bool: return a.x < b.x
	)
	for door: BuildingPlan.DoorSpot in doors:
		var number := FloorSigns.number_of(_rules, door.floor_index)
		counted[door.floor_index] = int(counted.get(door.floor_index, 0)) + 1
		var x := door.x + Door.LEAF_SIZE.x * 0.5 + PLATE_GAP
		var y := _rules.floor_surface(door.floor_index) - PLATE_RISE
		var plate := GreyboxLook.box(PLATE, metal)
		plate.position = WorldSpace.to_scene(Vector2(x, y))
		plate.position.z = WorldSpace.BACK_WALL_Z + STANDOFF + PLATE.z * 0.5
		add_child(plate)
		var label := Label3D.new()
		label.text = "%d%02d" % [number, counted[door.floor_index]]
		label.font = PLATE_FONT
		label.font_size = 32
		label.pixel_size = 0.0022
		label.modulate = PLATE_INK
		label.outline_size = 0
		label.shaded = true
		label.position = plate.position + Vector3(0.0, 0.0, PLATE.z * 0.5 + 0.002)
		add_child(label)


## Труба под потолком вдоль задней стены, кусками [method pipe_spans].
func _lay_pipe(plan: BuildingPlan, floor_index: int) -> void:
	var y := pipe_top(_rules, floor_index) + PIPE_THICKNESS * 0.5
	for span in pipe_spans(_rules, plan, floor_index):
		var pipe := GreyboxLook.box(
			Vector3(span.y - span.x, PIPE_THICKNESS, PIPE_THICKNESS), GreyboxLook.metal(PIPE)
		)
		pipe.position = WorldSpace.to_scene(Vector2((span.x + span.y) * 0.5, y))
		pipe.position.z = pipe_z()
		add_child(pipe)
