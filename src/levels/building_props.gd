class_name BuildingProps
extends Node3D

## Предметы у задней стены, табло над шахтами и трубы под потолком
## (ADR-0029, решение 3).
##
## Всё без тел: предмет — декор, а не укрытие. Где что стоит, решает
## [BuildingDressing]; здесь только коробки. Тона приглушённые, а светится лишь
## то, что и в жизни светится, — вывеска, панель автомата, табло: предмет за
## спиной актёра не должен спорить с его силуэтом (обводка — ADR-0022).

## Насколько предмет отстоит от задней стены, м: вплотную он мерцал бы с ней.
const STANDOFF: float = 0.04

## Габариты предметов, м: ширина, высота, глубина.
const PLANT_POT := Vector3(0.5, 0.45, 0.5)
const PLANT_LEAVES := Vector3(0.75, 0.8, 0.6)
const VENDING := Vector3(0.9, 1.8, 0.62)
const COOLER := Vector3(0.36, 1.05, 0.36)
## Скамья и вывеска уже шага места без пилястры: шире они налезали на
## пилястру у соседнего проёма (авторевью M19).
const BENCH := Vector3(0.9, 0.45, 0.45)
const CABINET := Vector3(0.55, 1.3, 0.5)
const SIGN := Vector3(0.85, 0.3, 0.06)

## На какой высоте над полом висит вывеска, м — выше дверей, под потолком.
const SIGN_RISE: float = 2.35

## Табло этажа над шахтой, м.
const BOARD := Vector3(0.9, 0.22, 0.08)
const BOARD_DROP: float = 0.3

## Труба под потолком: толщина, м. Висит перед пилястрами — они выступают из
## стены на [constant BuildingRibs.PILASTER_DEPTH] — и сразу под полосой, которую
## от наклонённой камеры закрывает кромка перекрытия
## ([method FloorSigns.hidden_band]). До авторевью M19 она шла в 7 см под
## потолком и целиком пряталась за кромкой: в кадре труб не было ни одной.
const PIPE_THICKNESS: float = 0.14
## Зазор трубы от пилястр и от полосы под кромкой, м.
const PIPE_GAP: float = 0.03
## Насколько труба не доходит до вывески и таблички этажа, м: перед ними она
## закрыла бы их верх.
const PIPE_CLEARANCE: float = 0.1
## Короче этого кусок трубы не ставится, м: обрубок у стены читается мусором.
const PIPE_MIN_LENGTH: float = 0.3

const POT := Color(0.16, 0.16, 0.17)
const LEAVES := Color(0.10, 0.20, 0.12)
const MACHINE := Color(0.30, 0.10, 0.10)
const MACHINE_PANEL := Color(0.55, 0.75, 0.95)
const PLASTIC := Color(0.55, 0.56, 0.58)
const WATER := Color(0.30, 0.55, 0.95)
const WOOD := Color(0.20, 0.14, 0.10)
const STEEL := Color(0.26, 0.27, 0.29)
const PIPE := Color(0.22, 0.22, 0.24)
const GARAGE_STRIPE := Color(0.75, 0.75, 0.7)
const GARAGE_STOP := Color(0.6, 0.5, 0.15)
## Цифры табло — холодный светодиод. Не красные: красный огонёк на высоте
## вывески двери — знак двери с документом, и на тёмном этаже табло над
## каждой шахтой читалось бы ложной целью (авторевью M19).
const BOARD_DIGITS := Color(0.55, 0.82, 1.0)
## Неон вывесок. Не цвета огоньков игры (ADR-0023, решение 6): тёплый — табло
## обычной двери, красный — двери с документом, зелёный — выхода. Янтарная
## вывеска на высоте табло читалась бы на погашенном этаже дверью, которой нет
## (авторевью M19).
const NEON: Array[Color] = [Color(1.0, 0.25, 0.75), Color(0.25, 0.9, 1.0), Color(0.62, 0.35, 1.0)]

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
## (ходит кабина), проём эскалатора с этажа выше (сквозь потолок идёт полотно),
## вывеска обстановки и табличка номера этажа. Статический: раскладку труб
## проверяют без сцены.
static func pipe_spans(
	rules: BuildingRules, plan: BuildingPlan, dressing: BuildingDressing, floor_index: int
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
	var sign_reach := SIGN.x * 0.5 + PIPE_CLEARANCE
	for prop in dressing.props:
		if prop.floor_index == floor_index and prop.kind == BuildingDressing.Kind.SIGN:
			cuts.append(Vector2(prop.x - sign_reach, prop.x + sign_reach))
	var plate := FloorSigns.centre_on(rules, floor_index).x
	var plate_reach := Proportions.FLOOR_SIGN.x * 0.5 + PIPE_CLEARANCE
	cuts.append(Vector2(plate - plate_reach, plate + plate_reach))

	var spans: Array[Vector2] = []
	for span in BuildingPlan.spans_between(cuts, inner):
		if span.y - span.x >= PIPE_MIN_LENGTH:
			spans.append(span)
	return spans


## Ставит обстановку по раскладке и табло над шахтами по плану.
func build(rules: BuildingRules, plan: BuildingPlan, dressing: BuildingDressing) -> void:
	_rules = rules
	for prop in dressing.props:
		_place(prop)
	for index: int in dressing.pipes:
		_lay_pipe(plan, dressing, index)
	for shaft in plan.shafts:
		for index in range(maxi(shaft.top, 0), shaft.bottom + 1):
			_hang_board(shaft.x, index)
	_mark_garage(plan)


## Разметка гаража — этажа выхода (ADR-0031, решение 4): белые полосы между
## местами и колёсные упоры у стены, в обход шахт и выхода.
func _mark_garage(plan: BuildingPlan) -> void:
	var index := _rules.floors - 1
	var surface := _rules.floor_surface(index)
	var stripe := GreyboxLook.surface(GARAGE_STRIPE)
	var stop := GreyboxLook.surface(GARAGE_STOP)
	var step := _rules.slot_x(1) - _rules.slot_x(0)
	var clear := plan.safe_spots(_rules, index)
	var depth := WorldSpace.CORRIDOR_DEPTH * 0.8
	for x: float in clear:
		if absf(x - plan.exit_x) < step:
			continue
		var line := GreyboxLook.box(Vector3(0.08, 0.01, depth), stripe)
		line.position = WorldSpace.to_scene(Vector2(x - step * 0.5, surface - 0.005))
		add_child(line)
		var block := GreyboxLook.box(Vector3(step * 0.45, 0.08, 0.14), stop)
		block.position = WorldSpace.to_scene(Vector2(x, surface - 0.04))
		block.position.z = WorldSpace.BACK_WALL_Z + STANDOFF + 0.2
		add_child(block)


func _place(prop: BuildingDressing.PropSpot) -> void:
	var surface := _rules.floor_surface(prop.floor_index)
	match prop.kind:
		BuildingDressing.Kind.PLANT:
			_stand(prop.x, surface, PLANT_POT, GreyboxLook.surface(POT))
			_stand(prop.x, surface - PLANT_POT.y, PLANT_LEAVES, GreyboxLook.surface(LEAVES))
		BuildingDressing.Kind.VENDING:
			_stand(prop.x, surface, VENDING, GreyboxLook.metal(MACHINE))
			var panel := Vector3(VENDING.x * 0.7, VENDING.y * 0.55, 0.02)
			_stand(
				prop.x,
				surface - VENDING.y * 0.35,
				panel,
				GreyboxLook.marker(MACHINE_PANEL),
				VENDING.z
			)
		BuildingDressing.Kind.COOLER:
			_stand(prop.x, surface, COOLER, GreyboxLook.surface(PLASTIC))
			var bottle := Vector3(COOLER.x * 0.8, 0.35, COOLER.z * 0.8)
			_stand(prop.x, surface - COOLER.y, bottle, GreyboxLook.marker(WATER))
		BuildingDressing.Kind.BENCH:
			_stand(prop.x, surface, BENCH, GreyboxLook.surface(WOOD))
		BuildingDressing.Kind.CABINET:
			_stand(prop.x, surface, CABINET, GreyboxLook.metal(STEEL))
		BuildingDressing.Kind.SIGN:
			var neon := NEON[posmod(prop.floor_index + int(prop.x), NEON.size())]
			_stand(prop.x, surface - SIGN_RISE, SIGN, GreyboxLook.light(neon))


## Коробка [param size], стоящая низом на [param bottom] у задней стены.
## [param offset] — насколько она выдвинута от стены сверх собственной глубины:
## панель автомата лежит на его передней грани.
func _stand(
	x: float, bottom: float, size: Vector3, material: StandardMaterial3D, offset: float = 0.0
) -> void:
	var part := GreyboxLook.box(size, material)
	part.position = WorldSpace.to_scene(Vector2(x, bottom - size.y * 0.5))
	part.position.z = WorldSpace.BACK_WALL_Z + STANDOFF + offset + size.z * 0.5
	add_child(part)


## Табло над шахтой: тёмная коробка и красная полоса цифр, как над лифтами на
## референсе. Полоса — огонёк: табло видно и на погашенном этаже.
func _hang_board(x: float, floor_index: int) -> void:
	var top := _rules.story_top(floor_index) + BOARD_DROP
	var frame := GreyboxLook.box(BOARD, GreyboxLook.metal(STEEL))
	frame.position = WorldSpace.to_scene(Vector2(x, top + BOARD.y * 0.5))
	frame.position.z = WorldSpace.BACK_WALL_Z + STANDOFF + BOARD.z * 0.5
	add_child(frame)
	var digits := GreyboxLook.box(
		Vector3(BOARD.x * 0.6, BOARD.y * 0.45, 0.02), GreyboxLook.light(BOARD_DIGITS)
	)
	digits.position = frame.position
	digits.position.z += BOARD.z * 0.5 + 0.01
	add_child(digits)


## Труба под потолком вдоль задней стены, кусками [method pipe_spans].
func _lay_pipe(plan: BuildingPlan, dressing: BuildingDressing, floor_index: int) -> void:
	var y := pipe_top(_rules, floor_index) + PIPE_THICKNESS * 0.5
	for span in pipe_spans(_rules, plan, dressing, floor_index):
		var pipe := GreyboxLook.box(
			Vector3(span.y - span.x, PIPE_THICKNESS, PIPE_THICKNESS), GreyboxLook.metal(PIPE)
		)
		pipe.position = WorldSpace.to_scene(Vector2((span.x + span.y) * 0.5, y))
		pipe.position.z = pipe_z()
		add_child(pipe)
