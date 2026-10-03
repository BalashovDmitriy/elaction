class_name OpenSpace
extends Node3D

## Open space офиса за стеклянной стеной коридора (ADR-0056, решение 4).
##
## У офиса вместо задней стены — стеклянные перегородки, и за ними виден зал на
## всю глубину плиты: ряды кубиклов с перегородками в рост сидящего, столы,
## мониторы со светящимися экранами, кресла, шкафы-картотеки, а у дальней стены
## — ленточные окна на город: ночью тёмные, днём светятся небом. Отдельной
## комнаты за дверью у офиса нет: дверь открывается в этот зал.
##
## Только вид: тел нет, теней нет — набор на всё здание мультимешами по одному
## на деталь, и в проходе теней ламп он не участвует (бюджет кадра внизу
## здания, ADR-0042, решение 2). Экраны светятся эмиссией только на светлых
## этажах: на тёмном по ROM офис погашен целиком.
##
## Зал не заходит туда, где плиты нет — в шахты, — и за глухие внутренние
## стены; столы стоят дальше, чем ходит створка двери.

## Ряды кубиклов: глубина середины ряда от задней стены коридора, м. Первый —
## за створкой двери ([constant Door.LEAF_SIZE] в глубину), второй — у окон.
const ROWS: Array[float] = [2.3, 4.7]
## Шаг кубиклов вдоль ряда и их габарит, м.
const CUBICLE_STEP: float = 2.0
const DESK := Vector3(1.5, 0.05, 0.75)
const DESK_HEIGHT: float = 0.74
const PARTITION := Vector3(1.9, 1.2, 0.05)
const MONITOR := Vector3(0.5, 0.36, 0.06)
const CHAIR := Vector3(0.5, 0.9, 0.5)
const CABINET := Vector3(0.5, 1.3, 0.6)
## Окна у дальней стены: высота ленты, её низ над полом, шаг переплёта, м.
const WINDOW_BAND := Vector2(1.5, 0.9)
const MULLION_STEP: float = 1.2
## Ближе этого к краю пролёта кубикл не ставится, м.
const EDGE: float = 0.6

## Цвета: стол, перегородки кубиклов (ткань), корпус монитора, экран, кресло,
## шкаф, окна ночью и переплёт.
const DESK_COLOUR := Color(0.52, 0.47, 0.4)
const FABRIC := Color(0.36, 0.4, 0.46)
const CASE := Color(0.12, 0.12, 0.13)
const SCREEN := Color(0.45, 0.75, 0.95)
const CHAIR_COLOUR := Color(0.1, 0.11, 0.13)
const CABINET_COLOUR := Color(0.55, 0.57, 0.6)
const NIGHT_GLASS := Color(0.06, 0.09, 0.15)
const FRAME := Color(0.3, 0.32, 0.36)

var _batch := MeshBatch.new()
var _desk := GreyboxLook.surface(DESK_COLOUR)
var _fabric := GreyboxLook.surface(FABRIC)
var _case := GreyboxLook.surface(CASE)
var _screen := GreyboxLook.light(SCREEN)
var _screen_off := GreyboxLook.surface(CASE.lightened(0.1))
var _chair := GreyboxLook.surface(CHAIR_COLOUR)
var _cabinet := GreyboxLook.metal(CABINET_COLOUR)
var _frame := GreyboxLook.metal(FRAME)
var _night: StandardMaterial3D = null


## Собирает зал на всех этажах офиса, кроме крыши, паркинга и особых этажей —
## там свой зал ([FloorHall], ADR-0057, решение 3).
func build(rules: BuildingRules, plan: BuildingPlan) -> void:
	name = "OpenSpace"
	_night = TimeOfDay.window_look(rules.time_of_day, NIGHT_GLASS)
	var back := WorldSpace.BACK_WALL_Z
	var far := back - WorldSpace.ROOM_DEPTH
	for index: int in range(0, rules.floors - 1):
		if FloorRole.hall_at(rules, index):
			continue
		var surface := rules.floor_surface(index)
		var bounds := rules.floor_span(index)
		var inner := Vector2(
			bounds.x + BuildingShell.WALL_WIDTH, bounds.y - BuildingShell.WALL_WIDTH
		)
		var lit := not rules.is_unlit(index)
		for span: Vector2 in BuildingPlan.spans_between(plan.blocks_on(rules, index), inner):
			_windows(span, surface, far)
			for row: float in ROWS:
				_row(span, surface, back - row, lit)
	_batch.commit(self)


## Ряд кубиклов на глубине [param z]: перегородка сзади, стол, монитор лицом к
## коридору, кресло за столом; через один — шкаф-картотека в торце.
func _row(span: Vector2, surface: float, z: float, lit: bool) -> void:
	var length := span.y - span.x - EDGE * 2.0
	var count := int(length / CUBICLE_STEP)
	if count <= 0:
		return
	var start := (span.x + span.y) * 0.5 - (count - 1) * CUBICLE_STEP * 0.5
	for cubicle: int in count:
		var x := start + cubicle * CUBICLE_STEP
		_batch.box(
			_fabric, PARTITION, Vector3(x, surface - PARTITION.y * 0.5, z - DESK.z * 0.5 - 0.75)
		)
		_batch.box(_desk, DESK, Vector3(x, surface - DESK_HEIGHT, z))
		var screen_y := surface - DESK_HEIGHT - MONITOR.y * 0.5 - 0.08
		var screen_z := z - DESK.z * 0.25
		_batch.box(_case, MONITOR, Vector3(x - 0.2, screen_y, screen_z))
		var face := Vector3(MONITOR.x * 0.86, MONITOR.y * 0.8, 0.01)
		var lit_face := _screen if lit and (cubicle + int(z)) % 3 != 0 else _screen_off
		_batch.box(lit_face, face, Vector3(x - 0.2, screen_y, screen_z + MONITOR.z * 0.5 + 0.005))
		_batch.box(_chair, CHAIR, Vector3(x + 0.1, surface - CHAIR.y * 0.5, z - DESK.z * 0.5 - 0.3))
		if cubicle % 2 == 1:
			_batch.box(
				_cabinet,
				CABINET,
				Vector3(x + CUBICLE_STEP * 0.5, surface - CABINET.y * 0.5, z - DESK.z * 0.2)
			)


## Ленточные окна у дальней стены зала: стекло по времени суток
## ([method TimeOfDay.window_look]) и переплёт.
func _windows(span: Vector2, surface: float, far: float) -> void:
	OpenSpace.ribbon_windows(_batch, _night, _frame, span, surface, far)


## Лента окон у дальней стены зала на пролёте [param span]: её же ставят залы
## особых этажей ([FloorHall]).
static func ribbon_windows(
	batch: MeshBatch, glass: Material, frame: Material, span: Vector2, surface: float, far: float
) -> void:
	var length := span.y - span.x
	var middle := (span.x + span.y) * 0.5
	var y := surface - WINDOW_BAND.y - WINDOW_BAND.x * 0.5
	var z := far + 0.06
	batch.box(glass, Vector3(length, WINDOW_BAND.x, 0.02), Vector3(middle, y, z))
	for edge: float in [-1.0, 1.0]:
		batch.box(
			frame,
			Vector3(length, 0.06, 0.04),
			Vector3(middle, y + edge * WINDOW_BAND.x * 0.5, z + 0.02)
		)
	for step: int in int(length / MULLION_STEP) + 1:
		var x := span.x + step * MULLION_STEP
		batch.box(frame, Vector3(0.05, WINDOW_BAND.x, 0.04), Vector3(x, y, z + 0.02))
