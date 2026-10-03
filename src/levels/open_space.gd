class_name OpenSpace
extends Node3D

## The office open space behind the corridor's glass wall (ADR-0056, decision 4).
##
## Instead of a back wall the office has glass partitions, and behind them a hall through
## the full depth of the slab is visible: rows of cubicles with partitions at seated
## height, desks, monitors with glowing screens, chairs, filing cabinets, and at the far
## wall — ribbon windows onto the city: dark at night, glowing with the sky by day. The
## office has no separate room behind the door: the door opens into this hall.
##
## Looks only: no bodies, no shadows — the set for the whole building is multimeshes,
## one per detail, and it does not take part in the lamp shadow pass (frame budget at
## the bottom of the building, ADR-0042, decision 2). Screens glow by emission only on
## lit floors: on a dark one, per the ROM, the office is dark entirely.
##
## The hall does not go where there is no slab — into shafts — or past solid inner
## walls; desks stand farther than the door leaf swings.

## Cubicle rows: depth of the row's middle from the corridor's back wall, m. The first is
## behind the door leaf ([constant Door.LEAF_SIZE] in depth), the second at the windows.
const ROWS: Array[float] = [2.3, 4.7]
## Cubicle step along the row and their bounds, m.
const CUBICLE_STEP: float = 2.0
const DESK := Vector3(1.5, 0.05, 0.75)
const DESK_HEIGHT: float = 0.74
const PARTITION := Vector3(1.9, 1.2, 0.05)
const MONITOR := Vector3(0.5, 0.36, 0.06)
const CHAIR := Vector3(0.5, 0.9, 0.5)
const CABINET := Vector3(0.5, 1.3, 0.6)
## Windows at the far wall: ribbon height, its bottom above the floor, mullion step, m.
const WINDOW_BAND := Vector2(1.5, 0.9)
const MULLION_STEP: float = 1.2
## A cubicle is not placed closer than this to the span's edge, m.
const EDGE: float = 0.6

## Colours: desk, cubicle partitions (fabric), monitor body, screen, chair, cabinet,
## windows at night and mullions.
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


## Builds the hall on all office floors except the roof, the garage and special floors —
## those have their own hall ([FloorHall], ADR-0057, decision 3).
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


## A cubicle row at depth [param z]: a partition at the back, a desk, a monitor facing
## the corridor, a chair at the desk; every other one has a filing cabinet at the end.
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


## Ribbon windows at the hall's far wall: glass by time of day
## ([method TimeOfDay.window_look]) and mullions.
func _windows(span: Vector2, surface: float, far: float) -> void:
	OpenSpace.ribbon_windows(_batch, _night, _frame, span, surface, far)


## Ribbon of windows at the hall's far wall on span [param span]: special-floor halls
## place it too ([FloorHall]).
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
