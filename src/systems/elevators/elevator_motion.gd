class_name ElevatorMotion
extends RefCounted

## Elevator cab movement logic.
##
## Knows nothing of nodes or physics: takes the frame time, the player's command and
## whether the cab is occupied, and returns the new vertical coordinate. So it is
## tested without a scene — the same trick as [OttoStateMachine] in M1.
##
## The mechanic's rules and source quotes are in ADR-0004.

## Tolerance within which the cab counts as aligned with a floor, m.
const FLOOR_EPSILON: float = 0.015

## Below this threshold the player's command counts as released.
const COMMAND_THRESHOLD: float = 0.1

## How far the cab floor may be above the floor's floor for one to still jump out on
## the move, in fractions of a floor: 18 px of 48 in the ROM (@36F2).
const STEP_OUT_SHARE: float = 18.0 / 48.0

## Directions are the same as for the escalator and the door: one place for the project.
const UP := Intent.UP
const DOWN := Intent.DOWN

## Stop floors: the cab coordinate at each of them, ascending.
var floors: PackedFloat32Array = PackedFloat32Array()

## Cab speed, m/s.
var speed: float = 1.8

## An empty cab's pause on a floor, s. In the original — one to two seconds.
var floor_pause: float = 1.5

## How close to a floor the cab pulls in by itself when released, m: closer than this it
## stops at the nearest floor even if it is behind, and farther — it travels to the
## next floor ahead. A player's cab does not stop between floors, as in the ROM
## (@5E1E): released, it travels until it lines up with a floor (ADR-0053,
## decision 1). It does not travel farther by itself — that part is ours: in the arcade
## the cab started moving without the player after 2 s.
##
## Without the pull-in one could step out only at the shaft's ends: "aligned with a
## floor" is half a centimetre, and the cab passes it in a fraction of a frame, and
## hitting such a window by hand is impossible. Intermediate floors were unreachable.
var settle_distance: float = 0.36

## Current cab coordinate.
var position: float = 0.0

## Direction of movement: -1 up, +1 down, 0 standing.
var direction: float = 0.0

## Actual speed over the last frame, px/s. Needed for crushing: what matters is not the
## cab's intention but whether it actually moved.
var velocity: float = 0.0

## Response delay to a command, s. During an alarm the cab obeys worse, and this is
## described directly in the original (ADR-0009, point 1).
var response_delay: float = 0.0

## Whether the bottom stop is locked: the cab does not go down to it either with a
## passenger or by itself. That way the shaft into the basement does not go there
## until all documents are collected (M24b; the rule is set by [BasementLock]). The
## lock does not move a cab already standing lower — it only keeps it from going down.
var bottom_locked: bool = false

var _pause_left: float = 0.0
var _held: float = 0.0


## Sets the stops and puts the cab on one of the floors.
func setup(stops: PackedFloat32Array, start_floor: int = 0) -> void:
	floors = stops.duplicate()
	floors.sort()
	direction = 0.0
	velocity = 0.0
	if not floors.is_empty():
		position = floors[clampi(start_floor, 0, floors.size() - 1)]
	# On a floor the cab stands — including the one it starts on.
	_pause_left = floor_pause
	_held = 0.0


## Moves the cab for a frame and returns the new coordinate.
##
## [param command] — the player's intention: -1 up, +1 down, 0 released.
## [param occupied] — whether Otto stands inside. An occupied cab obeys only him, an
## empty one travels by itself from floor to floor (ADR-0004, points 1 and 4).
func update(delta: float, command: float, occupied: bool) -> float:
	if floors.is_empty():
		return position

	var previous := position
	if occupied:
		_drive(delta, command)
	else:
		# An empty cab deliberates nothing: whoever enters starts the countdown anew,
		# otherwise the alarm delay would work only for the first ride.
		_held = 0.0
		_run_on_its_own(delta)
	velocity = (position - previous) / delta if delta > 0.0 else 0.0
	return position


## Whether the cab can still go in this direction: -1 up, +1 down.
##
## Shafts do not run the full height (ADR-0008), and a band has a top and a bottom.
## A cab that reached the end hears the command but stands — and without this question
## the player has no way to know the shaft is the reason, not the game.
func can_go(towards: float) -> bool:
	if floors.is_empty() or is_zero_approx(towards):
		return false
	# By direction, not by magnitude: a cab under a locked stop is below its limit, and
	# "down" toward the limit would take it up.
	return (_shaft_limit(towards) - position) * signf(towards) > FLOOR_EPSILON


## Whether one can step out of the cab onto the floor right now — including on the move.
##
## As in the ROM (@36F2–3712): one jumps out of a moving cab while its floor is above
## the floor below it by no more than [constant STEP_OUT_SHARE] of a floor; below a floor
## — only when level (ADR-0044, decision 5). Before M24h one could step out only from
## a cab aligned with the floor.
func can_step_out() -> bool:
	if floors.is_empty():
		return false
	var step := _floor_step()
	for stop: float in floors:
		# The rules axis points down: the floor under the cab's floor has the larger coordinate.
		var drop := stop - position
		if drop >= -FLOOR_EPSILON and drop <= step * STEP_OUT_SHARE:
			return true
	return false


## Floor step of the shaft: the difference between neighbouring stops. A one-stop shaft
## has no step — then one can step out only when level.
func _floor_step() -> float:
	if floors.size() < 2:
		return 0.0
	return floors[1] - floors[0]


## Whether the cab floor is aligned with the floor's floor.
func is_aligned() -> bool:
	return aligned_floor() >= 0


## Index of the floor the cab is aligned with, or -1.
func aligned_floor() -> int:
	for index: int in floors.size():
		if absf(floors[index] - position) <= FLOOR_EPSILON:
			return index
	return -1


## Whether the cab is standing still right now.
func is_stopped() -> bool:
	return is_zero_approx(velocity)


## Forget how long the command has been held: the wait is counted anew.
##
## Needed when [member response_delay] changes on the move — during an alarm. Otto
## holds "down" the whole ride, by then the counter has long exceeded the new delay,
## and a ride started before the siren would finish the old way: the penalty would
## only catch the next press.
func forget_command() -> void:
	_held = 0.0


## An empty cab standing on a floor stays at least [param seconds] longer. The demo
## from the roof holds the cab at the roof this way while the helicopter drops Otto off
## (ADR-0041): otherwise it left downward on schedule, and the bot waited half the demo
## for it. Does not touch a moving cab.
func hold(seconds: float) -> void:
	if is_stopped():
		_pause_left = maxf(_pause_left, seconds)


func _drive(delta: float, command: float) -> void:
	# The cab obeys a passenger without pauses but keeps the counter full: as soon as he
	# steps out, it stays put, like any empty one (ADR-0004, point 4).
	_pause_left = floor_pause

	if absf(command) > COMMAND_THRESHOLD:
		_held += delta
		if _held < response_delay:
			# The cab is still "thinking": it hears the command but does not move.
			return
		direction = signf(command)
		if can_go(direction):
			_move_towards(_shaft_limit(direction), delta)
		return

	# The command is released.
	_held = 0.0
	if is_aligned() or direction == 0.0:
		direction = 0.0
		return

	var nearest := _nearest_floor()
	if absf(nearest - position) <= settle_distance:
		# Stopped almost at a floor — pull in, otherwise one cannot step off.
		if _move_towards(nearest, delta):
			direction = 0.0
		return

	var target := _next_floor(direction)
	if is_nan(target) or _move_towards(target, delta):
		direction = 0.0


func _run_on_its_own(delta: float) -> void:
	if _pause_left > 0.0:
		_pause_left = maxf(_pause_left - delta, 0.0)
		return

	if direction == 0.0:
		direction = DOWN

	var target := _next_floor(direction)
	if is_nan(target):
		# Reached the end of the shaft — turn around.
		direction = -direction
		target = _next_floor(direction)
	if is_nan(target):
		# A one-floor shaft: nowhere to go.
		direction = 0.0
		return

	if _move_towards(target, delta):
		_pause_left = floor_pause


## Moves the cab toward the target and reports whether it arrived in this frame.
##
## Arrival is counted with tolerance [constant FLOOR_EPSILON], not by comparing the
## remainder with the step head-on. Without tolerance a remainder equal to the step up
## to the last bit of the fraction did not count: the cab stopped a micron from the stop
## — "aligned" by the same tolerance — but got no pause and turned around on the next
## frame. In pixels the numbers met at zero and the rule held by luck; with metres and
## float32 stops the luck ran out (M15, found by the bot on the roof of a thirty-storey
## building).
func _move_towards(target: float, delta: float) -> bool:
	var step := speed * delta
	var gap := target - position
	if absf(gap) <= step + FLOOR_EPSILON:
		position = target
		return true
	position += signf(gap) * step
	return false


## Nearest open floor, in either direction.
func _nearest_floor() -> float:
	var best := floors[0]
	for stop: float in _open_floors():
		if absf(stop - position) < absf(best - position):
			best = stop
	return best


## The shaft's far boundary in the direction of movement.
func _shaft_limit(towards: float) -> float:
	var open := _open_floors()
	return open[0] if towards < 0.0 else open[open.size() - 1]


## Stops the cab may go to: all but the locked bottom one. A one-floor shaft has
## nothing to lock — otherwise it would have none left.
func _open_floors() -> PackedFloat32Array:
	if not bottom_locked or floors.size() < 2:
		return floors
	return floors.slice(0, floors.size() - 1)


## Nearest floor strictly ahead in the direction of movement, or NAN if there is nowhere
## farther to go.
func _next_floor(towards: float) -> float:
	var best := NAN
	for stop: float in _open_floors():
		var gap := stop - position
		if towards < 0.0 and gap < -FLOOR_EPSILON:
			if is_nan(best) or stop > best:
				best = stop
		elif towards > 0.0 and gap > FLOOR_EPSILON:
			if is_nan(best) or stop < best:
				best = stop
	return best
