class_name OttoStateMachine
extends RefCounted

## Otto's state transition logic.
##
## Knows nothing about nodes or engine physics: takes an input snapshot and facts
## about the body, returns the new state. So it is tested without a scene.

enum State { IDLE, WALK, CROUCH, JUMP, FALL, RIDE, INDOORS, DEAD }

## Below this threshold a stick tilt counts as rest.
const MOVE_THRESHOLD: float = 0.1

## State names are gathered once: [method state_name] is called every frame.
static var _state_names: PackedStringArray = PackedStringArray(State.keys())

var state: State = State.IDLE
var previous_state: State = State.IDLE


## State name for debug output.
static func state_name(value: State) -> String:
	return _state_names[value]


func reset() -> void:
	state = State.IDLE
	previous_state = State.IDLE


## Hands Otto over to the escalator: until it lets him go, player input has no effect.
##
## The escalator does not pick up a dead Otto: only [method reset] leads out of
## [constant State.DEAD], otherwise a ride would resurrect Otto.
func ride() -> void:
	if state == State.DEAD:
		return
	previous_state = state
	state = State.RIDE


## Returns control to the player.
func stop_riding() -> void:
	if state != State.RIDE:
		return
	previous_state = state
	state = State.IDLE


## Otto went into a door: he is not outside, player input has no effect.
##
## A dead Otto does not go into a door — for the same reason he does not board an escalator.
func go_indoors() -> void:
	if state == State.DEAD:
		return
	previous_state = state
	state = State.INDOORS


## Otto came out of a door: his time behind it is up (ADR-0038, decision 2).
func come_out() -> void:
	if state != State.INDOORS:
		return
	previous_state = state
	state = State.IDLE


## Puts Otto into the terminal state. Only [method reset] can lead out of it.
func kill() -> void:
	previous_state = state
	state = State.DEAD


func is_dead() -> bool:
	return state == State.DEAD


## Whether the state is controlled by the world rather than the player.
##
## Death, an escalator ride and the room behind a door are cleared only from outside:
## [method kill], [method stop_riding], [method come_out]. While Otto is in one of
## them, input is not processed at all.
func is_world_driven() -> bool:
	return state == State.DEAD or state == State.RIDE or state == State.INDOORS


## Whether we entered the state exactly in the last [method update].
func just_entered(value: State) -> bool:
	return state == value and previous_state != value


## Recomputes the state from the input snapshot and facts about the body.
##
## [param can_stand] — whether there is room above the head to straighten up. Without it
## Otto stays crouched: otherwise the full collision shape would switch on in a low
## opening and push him through the geometry.
func update(
	input: OttoInput, on_floor: bool, vertical_velocity: float, can_stand: bool = true
) -> State:
	previous_state = state
	if not is_world_driven():
		state = _resolve(input, on_floor, vertical_velocity, can_stand)
	return state


func _resolve(input: OttoInput, on_floor: bool, vertical_velocity: float, can_stand: bool) -> State:
	if not on_floor:
		return State.JUMP if vertical_velocity < 0.0 else State.FALL
	# One cannot get up from a crouch while there is no room above the head: neither by a step
	# nor by a jump.
	if previous_state == State.CROUCH and not can_stand:
		return State.CROUCH
	# Crouching, Otto does not jump — as in the original.
	if input.jump_pressed and not input.crouch:
		return State.JUMP
	if input.crouch:
		return State.CROUCH
	if absf(input.move) > MOVE_THRESHOLD:
		return State.WALK
	return State.IDLE
