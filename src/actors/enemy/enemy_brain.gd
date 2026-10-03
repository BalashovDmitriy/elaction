class_name EnemyBrain
extends RefCounted

## Agent decisions: walk, shoot, dodge or stand.
##
## No nodes, no physics — takes the vector to Otto and facts, returns a state.
## So it is checked without a scene, like [OttoStateMachine] and [DoorVisit].
##
## Since M18d the decisions follow the arcade ROM rules ([Arcade], ADR-0027). The agent has his own
## aggression: it drives the wind-up before a shot, the pause after, the shooting pose — standing,
## crouched or lying — and the chance to dodge. He does not chase Otto: he wanders the floor, and
## shoots when facing him; under alarm — without looking, having turned around himself.
##
## In cabs the agent rides as a passenger (ADR-0025, decision 6), but [Enemy] decides that with the
## level, not the brain. Does not jump — neither in the original nor here (ADR-0026, ADR-0027).

enum State { EMERGING, WALK, SHOOT, DEAD }

## Agent stance. Both the height and which bullet will pass by depend on it, and at
## what height his own will leave.
enum Stance { STAND, KNEEL, PRONE }

## The wind-up is no shorter than this, s, at any aggression. In ROM at aggression 10 and up there
## is no wind-up at all, and the bullet leaves on the same frame; with ROM's slow bullet this was
## tolerable, with a three times faster one (ADR-0037, decision 5) it cannot be dodged without the
## aim laser — neither by a human nor by the test bot. A quarter second — for reaction, not for
## rest.
const MIN_TELL: float = 0.25

## How long the agent takes to get out of a door, s: all this time he does not shoot.
var emerge_time: float = 0.6

## How close vertically to count Otto as on the same line, m.
var same_line: float = 0.45

## Agent height in each stance, m. These decide whether a bullet passes by.
var stand_height: float = Proportions.BODY
var kneel_height: float = Proportions.KNEEL
var prone_height: float = Proportions.PRONE

## Agent aggression, 0..[constant Arcade.TOP]. [Enemy] raises it over time.
var anger: int = 0

## Agents' alarm (ADR-0027, decision 5): shoots without looking at Otto.
var alert: bool = false

## An agent from the late ones — third or fourth in the building: he has his own pose table,
## he shoots on the move more often (table_1D95).
var late: bool = false

## Decision generator. Each agent has his own, seeded by the level: otherwise a bot
## run stops repeating.
var rng := RandomNumberGenerator.new()

var state: State = State.EMERGING
var stance: Stance = Stance.STAND
var facing: float = 1.0

var _emerging_left: float = 0.0
var _cooldown_left: float = 0.0
var _fired_now: bool = false
## Action — a shot or a dodge: how long it still lasts and how long until the bullet leaves.
var _action_left: float = 0.0
var _wind_up_left: float = 0.0
var _shot_pending: bool = false
## Whether Otto can be hit now. If not — the wind-up runs up to [constant MIN_TELL]
## and holds there: the laser is lit, and the bullet waits.
var _target_hittable: bool = true
## Whether the agent shoots on the move: ROM's "other" pose — a shot without stopping.
var _on_the_move: bool = false
## Wandering: how much longer to walk and how much longer to stand.
var _stroll_left: float = 0.0
var _pause_left: float = 0.0


## Starts the agent's life: he gets out of the door toward [param towards].
func start(towards: float) -> void:
	state = State.EMERGING
	stance = Stance.STAND
	facing = signf(towards) if not is_zero_approx(towards) else 1.0
	_emerging_left = emerge_time
	_cooldown_left = 0.0
	_fired_now = false
	_action_left = 0.0
	_shot_pending = false
	_on_the_move = false
	_pause_left = 0.0
	_stroll_left = _stroll_time()


func kill() -> void:
	state = State.DEAD
	# The dead do not dodge: the corpse lies as it fell, and stance does not affect it.
	stance = Stance.STAND
	_fired_now = false
	_action_left = 0.0
	_shot_pending = false


func is_dead() -> bool:
	return state == State.DEAD


## Turns the agent around. The node calls it when the floor ahead has ended: a wandering
## agent walks on the other way rather than standing at the edge.
func turn_around() -> void:
	facing = -facing


## Turns the agent to a given side. The node calls it when he must walk not wherever
## his eyes lead but to a standing cab (ADR-0025, decision 6).
func face(towards: float) -> void:
	if not is_zero_approx(towards):
		facing = signf(towards)


## Whether the agent fired exactly on this frame. Asked right after [method update].
func fired() -> bool:
	return _fired_now


## Whether the agent is winding up: the shot is decided, but the bullet has not left yet. All this
## time the aim laser is visible (ADR-0037, decision 5). There is no wind-up shorter than [constant
## MIN_TELL] even at aggression 10 and up, where ROM's is zero (@1BDF): the laser is always there.
func is_winding_up() -> bool:
	return state == State.SHOOT and _shot_pending and _wind_up_left > 0.0


## How long until the bullet leaves, s; zero — no wind-up.
func wind_up_left() -> float:
	return maxf(_wind_up_left, 0.0) if is_winding_up() else 0.0


## Recomputes the decision.
##
## [param to_target] — from the agent to Otto. [param target_alive] — whether there is someone to
## aim at: whether Otto is alive and visible. An invisible one — in shadow or behind a door — the
## brain does not shoot at (ADR-0023, decision 8).
##
## [param incoming_height] — height of the bullet flying at the agent above his feet, m;
## negative — nothing is flying. [param in_range] — whether the shot reaches: in
## ROM there is no range, the original's floor is wholly on screen, and here that is "the agent
## is in frame" (ADR-0027, decision 3a). [param gun_free] — whether his last bullet is not
## in flight: he has only one (@1BAE). [param target_low] — Otto crouched:
## then the agent shoots from a crouch (@1CD8).
##
## [param target_hittable] — whether Otto can be hit now. Not while he
## is coming out of a door, riding an escalator or blinking after returning to play:
## the bullet would pass through him, and the player would see a hit without a death. Aiming
## at such an Otto is allowed, shooting is not: the wind-up holds at [constant MIN_TELL], and
## the bullet leaves a quarter second after Otto becomes vulnerable.
func update(
	delta: float,
	to_target: Vector2,
	target_alive: bool,
	incoming_height: float = -1.0,
	in_range: bool = true,
	gun_free: bool = true,
	target_low: bool = false,
	target_hittable: bool = true
) -> State:
	_fired_now = false
	_target_hittable = target_hittable
	if state == State.DEAD:
		return state

	_cooldown_left = maxf(_cooldown_left - delta, 0.0)

	if state == State.EMERGING:
		_emerging_left -= delta
		if _emerging_left > 0.0:
			return state
		state = State.WALK

	if _action_left > 0.0:
		# Otto hid behind a door or died while the agent was winding up: no shot.
		# The invisible are not shot at (ADR-0023, decision 8), and a wind-up begun on a
		# visible one does not cancel that — otherwise a door would stop hiding.
		if _shot_pending and not target_alive:
			_shot_pending = false
		_act(delta)
		return state

	if _dodges(delta, incoming_height):
		return state

	if target_alive and in_range and gun_free and _cooldown_left <= 0.0:
		if _on_the_same_line(to_target) and _faces(to_target):
			_open_fire(to_target, target_low)
			return state

	state = State.WALK
	_stroll(delta)
	return state


## Whether the agent wants to walk now. Standing still he aims, dodges or
## waits out a wandering pause.
func wants_to_walk() -> bool:
	if state == State.EMERGING:
		return true
	if state == State.SHOOT:
		return _on_the_move
	return stance == Stance.STAND and _action_left <= 0.0 and _pause_left <= 0.0


## Stance against a flying bullet: from a high one — onto a knee, from a low one — lie down (@05F5).
##
## High is one that passes over a crouching one; everything lower is low.
func stance_against(incoming_height: float) -> Stance:
	if incoming_height < 0.0:
		return Stance.STAND
	return Stance.KNEEL if incoming_height > kneel_height else Stance.PRONE


## Height in the current stance. The level sets the collision shape by it.
func height() -> float:
	match stance:
		Stance.KNEEL:
			return kneel_height
		Stance.PRONE:
			return prone_height
		_:
			return stand_height


## Whether the agent is on his feet.
func is_standing() -> bool:
	return stance == Stance.STAND


## Whether the agent is still coming out of the doorway.
##
## While coming out he is invulnerable: otherwise the leaf's telegraph turns a door into a shooting
## gallery, and the player picks off each one on the way out (ADR-0020, decision 3).
func is_emerging() -> bool:
	return state == State.EMERGING


## An action is running: wind-up, shot, pose hold. Finished — the agent stands up.
##
## While Otto cannot be hit, wind-up time runs only up to [constant MIN_TELL], and
## the action stands still with it: the gap between wind-up and the end of the action is the same
## as in ROM — the bullet just leaves later.
func _act(delta: float) -> void:
	if _shot_pending and not _target_hittable:
		delta = clampf(_wind_up_left - MIN_TELL, 0.0, delta)
	_action_left -= delta
	if _shot_pending:
		_wind_up_left -= delta
		if _wind_up_left <= 0.0:
			_shot_pending = false
			_fired_now = true
			_cooldown_left = Arcade.cooldown(anger)
	if _action_left <= 0.0:
		_action_left = 0.0
		stance = Stance.STAND
		_on_the_move = false
		state = State.WALK


## Dodge: Otto's bullet is close, and aggression gave a chance — the agent crouches or lies down
## for the duration of the action. ROM's chance is per tick, here it is converted per frame.
func _dodges(delta: float, incoming_height: float) -> bool:
	if incoming_height < 0.0:
		return false
	var per_tick := Arcade.dodge_chance(anger)
	if per_tick <= 0.0:
		return false
	var per_frame := 1.0 - pow(1.0 - minf(per_tick, 1.0), delta / Arcade.TICK)
	if rng.randf() >= per_frame:
		return false
	stance = stance_against(incoming_height)
	state = State.WALK
	_action_left = Arcade.action_time(anger)
	return true


## Starts a shot: pose by aggression, turn to Otto, wind-up.
func _open_fire(to_target: Vector2, target_low: bool) -> void:
	face(to_target.x)
	var pose := Arcade.fire_pose(anger, rng.randi_range(0, 255), late)
	if pose == Arcade.Pose.STAND and target_low and anger > 0:
		pose = Arcade.Pose.CROUCH
	_on_the_move = pose == Arcade.Pose.ON_THE_MOVE
	match pose:
		Arcade.Pose.CROUCH:
			stance = Stance.KNEEL
		Arcade.Pose.PRONE:
			stance = Stance.PRONE
		_:
			stance = Stance.STAND
	state = State.SHOOT
	_wind_up_left = tell_time(anger)
	# A ROM action is always longer than the wind-up by two ticks or more (@1C7A): the bullet
	# leaves within it.
	_action_left = Arcade.action_time(anger)
	_shot_pending = true
	# A zero wind-up does not happen ([constant MIN_TELL]), but the step is called at once: that way
	# the wind-up starts on this same frame, not the next.
	_act(0.0)


## Wind-up before a shot at aggression [param level], s: by ROM, but no shorter than
## [constant MIN_TELL].
static func tell_time(level: int) -> float:
	return maxf(MIN_TELL, Arcade.wind_up(level))


## Wandering the floor: walks, stands, walks again — in a random direction (@5D13).
func _stroll(delta: float) -> void:
	if _pause_left > 0.0:
		_pause_left -= delta
		if _pause_left <= 0.0:
			_pause_left = 0.0
			facing = -1.0 if rng.randf() < 0.5 else 1.0
			_stroll_left = _stroll_time()
		return
	_stroll_left -= delta
	if _stroll_left <= 0.0:
		# A pause of 7 ticks plus a random addition, as between ROM decisions (@04E6).
		_pause_left = Arcade.seconds(7.0 + float(rng.randi_range(0, 7)))


func _stroll_time() -> float:
	return rng.randf_range(0.6, 2.4)


## Whether the agent faces Otto. Not needed under alarm: he will turn around himself (@0568).
func _faces(to_target: Vector2) -> bool:
	return alert or is_zero_approx(to_target.x) or signf(to_target.x) == facing


func _on_the_same_line(to_target: Vector2) -> bool:
	return absf(to_target.y) <= same_line
