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
const BENCH := Vector3(1.3, 0.45, 0.45)
const CABINET := Vector3(0.55, 1.3, 0.5)
const SIGN := Vector3(0.95, 0.3, 0.06)

## На какой высоте над полом висит вывеска, м — выше дверей, под потолком.
const SIGN_RISE: float = 2.35

## Табло этажа над шахтой, м.
const BOARD := Vector3(0.9, 0.22, 0.08)
const BOARD_DROP: float = 0.3

## Труба под потолком: толщина и отступ от потолка и стены, м.
const PIPE_THICKNESS: float = 0.14
const PIPE_DROP: float = 0.14

const POT := Color(0.16, 0.16, 0.17)
const LEAVES := Color(0.10, 0.20, 0.12)
const MACHINE := Color(0.30, 0.10, 0.10)
const MACHINE_PANEL := Color(0.55, 0.75, 0.95)
const PLASTIC := Color(0.55, 0.56, 0.58)
const WATER := Color(0.30, 0.55, 0.95)
const WOOD := Color(0.20, 0.14, 0.10)
const STEEL := Color(0.26, 0.27, 0.29)
const PIPE := Color(0.22, 0.22, 0.24)
const NEON: Array[Color] = [Color(1.0, 0.25, 0.75), Color(0.25, 0.9, 1.0), Color(1.0, 0.7, 0.25)]

var _rules: BuildingRules = null


## Ставит обстановку по раскладке и табло над шахтами по плану.
func build(rules: BuildingRules, plan: BuildingPlan, dressing: BuildingDressing) -> void:
	_rules = rules
	for prop in dressing.props:
		_place(prop)
	for index: int in dressing.pipes:
		_lay_pipe(plan, index)
	for shaft in plan.shafts:
		for index in range(maxi(shaft.top, 0), shaft.bottom + 1):
			_hang_board(shaft.x, index)


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
		Vector3(BOARD.x * 0.6, BOARD.y * 0.45, 0.02), GreyboxLook.light(GreyboxLook.INDICATOR)
	)
	digits.position = frame.position
	digits.position.z += BOARD.z * 0.5 + 0.01
	add_child(digits)


## Труба под потолком вдоль задней стены, с разрывами у шахт: там ходит кабина.
func _lay_pipe(plan: BuildingPlan, floor_index: int) -> void:
	var bounds := _rules.floor_span(floor_index)
	var inner := Vector2(bounds.x + BuildingShell.WALL_WIDTH, bounds.y - BuildingShell.WALL_WIDTH)
	var cuts: Array[Vector2] = []
	var half := _rules.shaft_width * 0.5
	for shaft in plan.shafts:
		if shaft.top <= floor_index and floor_index <= shaft.bottom:
			cuts.append(Vector2(shaft.x - half, shaft.x + half))
	var y := _rules.story_top(floor_index) + PIPE_DROP
	for span in BuildingPlan.spans_between(cuts, inner):
		var length := span.y - span.x
		if length <= 0.0:
			continue
		var pipe := GreyboxLook.box(
			Vector3(length, PIPE_THICKNESS, PIPE_THICKNESS), GreyboxLook.metal(PIPE)
		)
		pipe.position = WorldSpace.to_scene(Vector2((span.x + span.y) * 0.5, y))
		pipe.position.z = WorldSpace.BACK_WALL_Z + STANDOFF + PIPE_THICKNESS
		add_child(pipe)
