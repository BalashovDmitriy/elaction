class_name ExitBoarding
extends RefCounted

## Leaving the building: Otto gets into the car and drives away (ADR-0038, decision 4).
##
## He walks to the car by himself. At the driver's door with all documents control is taken away:
## Otto makes the last step to the door, turns to the car, the door swings open, he steps deeper
## toward the side and disappears behind it — the door slams, the car rocks, — the garage gate
## opens, the starter turns the engine over, the headlights come on, and the car drives away,
## accelerating, up the ramp. The building is cleared when it has left the frame: the next one is
## assembled after the departure, not in the same frame (ADR-0011, item 14).
##
## The car stands behind the play plane, and before, Otto, stepping to the door, simply vanished in
## front of the body. Now boarding is visible: the turn, the door, the step into depth.
##
## From boarding the view widens to the left past the building's end wall ([method exit_frame]): the
## gate and the tunnel behind it are in the frame. The car pulls away, and the view follows it
## ([method _follow_the_car]): through the tunnel, up the ramp — the bottom of the view rises with
## it — and onto the night street ([ExitStreet]), where the car leaves the frame. At first the view
## showed half the ramp and a bare wall above it; now outside the frame shows exactly what the car
## drives along. The next building restores the bounds — it has its own Otto and its own camera.
##
## From the step to the door Otto is unreachable: first he is "carried", as on an escalator, — the
## body shapes are off, — then he is in the car, and outside there is no Otto at all. Agents do not
## shoot at a hidden one ([method Otto.is_hidden]).
##
## As its own class, not in the level: the exit has its own step-by-step state the level has no need
## to know, and the level has hit its line limit. It holds no nodes — the level drives it from its
## own physics step.

## What happened during the step: nothing, the car pulled away, the car left the frame.
enum Event { NONE, STARTED, LEFT }

enum Phase { WAITING, STEPPING_IN, GETTING_IN, SEATING, STARTING, LEAVING, GONE }

## Width of the spot at the driver's door where Otto gets in, m. Wider than the bot's step per frame
## ([constant OttoBot.REACHED] and its last step), but narrower than the car: one gets in at the
## door, not at the boot.
const DOOR_REACH: float = 0.9
## How far the feet may be above or below the basement floor, m: the one who gets in is standing,
## not flying past in a jump.
const FOOTING: float = 0.2
## Boarding by steps, s from its start: Otto turns to the car, the door opens, he steps to the side,
## hides behind the door, and it closes.
const TURN_TIME: float = 0.25
const DOOR_OPEN_TIME: float = 0.35
const STEP_BACK_FROM: float = 0.2
const STEP_BACK_TIME: float = 0.45
const DOOR_CLOSE_TIME: float = 0.2
## How much Otto ducks while diving into the car, m: the body is lower than he is, and without this
## his head would stick out above the roof until the very slam.
const DUCK: float = 0.55
## The whole boarding: from the turn to the door slam.
const GET_IN_TIME: float = STEP_BACK_FROM + STEP_BACK_TIME + DOOR_CLOSE_TIME
## How long Otto sits down, s: from the door slam to the starter.
const SEAT_TIME: float = 0.5
## The middle of the view at the exit — how far right of the building's end wall, m. The view is
## placed by its middle, not its edge, and in a 16:9 view there are 8 m to the left of the end wall:
## the gate, the landing, the tunnel and the start of the climb ([constant GarageGate.RAMP_APRON],
## [constant GarageRamp.TUNNEL]), and on the right — the car at the gate and the garage.
const FRAME_SHIFT: float = 3.5
## View following the car: how far it drives before the view starts moving, m, — the gate and the
## tunnel get to stay in the frame for a while, — and how far the view moves to the left, m. The
## edge of a 16:9 view reaches the street left of the top of the ramp, and the car leaves the frame
## already along it.
const FOLLOW_AFTER: float = 1.5
const FOLLOW_SPAN: float = 20.0
## How many times faster the view moves than the car: it falls back toward the rear edge of the
## frame, and the road ahead, where the headlights shine, stays in the frame until the fade-out
## (ADR-0043, decision 5). When the view moved level with the car, it drove the last metres beyond
## the edge, shining into darkness that could not be seen.
const FOLLOW_LEAD: float = 1.3
## How much of the street under the car the view keeps, m: the bottom of the view rises with the car
## but not up to its wheels — the asphalt the headlights fall on stays in the frame.
const STREET_VIEW: float = 1.5
## How long the engine takes to start, s: starter and revving ([constant Sounds.CAR_START], 2.8 s) —
## the car pulls away during the revving, without waiting for it to end.
const START_TIME: float = 2.0

var phase: Phase = Phase.WAITING

var _car: ExitCar = null
## Basement floor in the rules plane.
var _surface: float = 0.0
var _seat_left: float = 0.0
## The garage whose gate opens in front of the car. The level builds it before the car ([method
## GreyboxLevel._build_garage]); if there is none — the car just drives away.
var _garage: Garage = null
## Camera bounds at the exit; empty — the camera is not touched.
var _frame := Rect2()
## How long boarding has been going on, s.
var _getting_in: float = 0.0
## Where the car stood when it pulled away, in the rules plane: the view follows it from this place.
var _start_x: float = 0.0


func _init(car: ExitCar, surface: float, garage: Garage = null, frame: Rect2 = Rect2()) -> void:
	_car = car
	_surface = surface
	_garage = garage
	_frame = frame


## Camera bounds at the exit, in the rules plane: vertically — the building, horizontally — a narrow
## strip around a point [constant FRAME_SHIFT] to the right of the end wall. The strip is narrower
## than any view, and the camera centres on it ([method CameraBounds.clamp_centre]).
static func exit_frame(rules: BuildingRules) -> Rect2:
	var centre := rules.floor_span(rules.floors - 1).x + FRAME_SHIFT
	return Rect2(centre - 0.5, 0.0, 1.0, rules.total_height())


## Where Otto gets into the car, in the rules plane: at the driver's door, at mid-height above the
## basement floor.
func door_point() -> Vector2:
	return Vector2(_car.door_x(), _surface - GreyboxLevel.EXIT_HEIGHT * 0.5)


## Whether point [param feet] stands at the driver's door, on the basement floor.
func at_the_door(feet: Vector2) -> bool:
	return absf(feet.x - _car.door_x()) <= DOOR_REACH * 0.5 and absf(feet.y - _surface) <= FOOTING


## Whether Otto got in: from this moment the car is in charge of him.
func is_boarded() -> bool:
	return phase != Phase.WAITING


## Exit step. [param documents_done] — whether all documents are collected: without them the car
## does not wait. [param view] — the rules view the car drives out of.
func step(delta: float, otto: Otto, documents_done: bool, view: Rect2) -> Event:
	match phase:
		Phase.WAITING:
			var feet := WorldSpace.to_plane(otto.global_position)
			if documents_done and otto.is_on_foot() and otto.is_grounded() and at_the_door(feet):
				# Control is taken: the last step to the door is now made by the game.
				otto.ride(true)
				if _frame.has_area():
					otto.apply_camera_bounds(_frame, false)
				phase = Phase.STEPPING_IN
		Phase.STEPPING_IN:
			if _step_to_the_door(otto, delta):
				_getting_in = 0.0
				phase = Phase.GETTING_IN
		Phase.GETTING_IN:
			_getting_in += delta
			if _get_in(otto):
				_car.set_door(0.0)
				_car.take_the_driver()
				_open_the_gate()
				_seat_left = SEAT_TIME
				phase = Phase.SEATING
		Phase.SEATING:
			_car.settle(delta)
			_seat_left -= delta
			if _seat_left <= 0.0:
				_car.start_engine()
				_seat_left = START_TIME
				phase = Phase.STARTING
		Phase.STARTING:
			_car.settle(delta)
			_seat_left -= delta
			if _seat_left <= 0.0:
				_car.drive_away()
				_start_x = _car.position.x
				phase = Phase.LEAVING
				return Event.STARTED
		Phase.LEAVING:
			_car.settle(delta)
			if _car.advance(delta, view):
				phase = Phase.GONE
				return Event.LEFT
			_follow_the_car(otto)
	return Event.NONE


## The exit view following the car: to the left while it has driven no more than [constant
## FOLLOW_AFTER] + [constant FOLLOW_SPAN], and up — exactly as much as it has climbed the ramp. The
## bottom of the view strip rises, and the camera target — Otto in the car — is below, at the
## basement floor, so the camera settles on this bottom.
func _follow_the_car(otto: Otto) -> void:
	if not _frame.has_area():
		return
	var moved := clampf((_start_x - _car.position.x - FOLLOW_AFTER) * FOLLOW_LEAD, 0.0, FOLLOW_SPAN)
	var rise := maxf(_surface - WorldSpace.to_plane(_car.position).y - STREET_VIEW, 0.0)
	var frame := Rect2(
		_frame.position.x - moved, _frame.position.y, _frame.size.x, maxf(_frame.size.y - rise, 1.0)
	)
	otto.apply_camera_bounds(frame, false)


## Walks Otto to the door; true — arrived.
func _step_to_the_door(otto: Otto, delta: float) -> bool:
	var at := WorldSpace.to_plane(otto.global_position)
	var gap := _car.door_x() - at.x
	var stride := otto.walk_speed * delta
	if absf(gap) <= stride:
		at.x = _car.door_x()
		otto.global_position = WorldSpace.to_scene(at)
		return true
	at.x += signf(gap) * stride
	otto.global_position = WorldSpace.to_scene(at)
	return false


## Boarding over the time [member _getting_in]: turn to the car, the door, a step deeper toward the
## side, the door closes behind the hidden Otto. true — the door is closed.
func _get_in(otto: Otto) -> bool:
	var t := _getting_in
	otto.turn_into_depth(clampf(t / TURN_TIME, 0.0, 1.0))
	var step := clampf((t - STEP_BACK_FROM) / STEP_BACK_TIME, 0.0, 1.0)
	otto.global_position.z = lerpf(WorldSpace.PLAY_Z, _car.seat_z(), ease(step, -1.6))
	var duck := clampf(step * 2.0 - 1.0, 0.0, 1.0)
	otto.global_position.y = WorldSpace.height_to_scene(_surface) - DUCK * duck
	var closing := t - STEP_BACK_FROM - STEP_BACK_TIME
	if closing < 0.0:
		_car.set_door(t / DOOR_OPEN_TIME)
		return false
	if not otto.is_hidden():
		# Behind the door he can no longer be seen: from here on he is in the car, outside there is no
		# Otto.
		otto.stay_indoors(true)
	_car.set_door(1.0 - closing / DOOR_CLOSE_TIME)
	return closing >= DOOR_CLOSE_TIME


## Opens the garage gate, if there is one.
func _open_the_gate() -> void:
	if _garage != null and is_instance_valid(_garage):
		_garage.open_gate()
