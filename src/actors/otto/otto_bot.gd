class_name OttoBot
extends RefCounted

## A bot that plays through the building: goes down from top to bottom, collects the documents,
## leaves through the exit.
##
## It is driven **by state, not by time**: not "hold right for 3.5 seconds" but "hold right until
## you get there". Timed tests in this project broke four times in a row — on shooting scenarios —
## and each time silently captured something other than what they promised. That must not happen
## here: the bot looks at where it is and decides anew.
##
## The bot takes its path from the building graph ([method BuildingRoute.walkable]) rather than
## searching greedily. Up to M18 greed was enough: shafts were laid end to end, and every junction
## had an escalator. Now shafts overlap, escalators run both ways, and a blank wall splits a floor
## in two — and "ride down the nearest shaft" runs into a dead end whose only way out is back and up
## (ADR-0024).
##
## The bot can shoot back and dodge: it crouches under a high bullet and jumps over a low one.
## Without this it would measure itself rather than the game — in the original, crouch and jump are
## the defence against fire (ADR-0006, item 3), and a bot standing under fire would only prove that
## you cannot stand under fire.
##
## Since M24a an agent's bullet is three times faster than in the ROM (ADR-0037, decision 5), and
## the bot, like the player, dodges by the aiming beam rather than by the bullet itself: the beam is
## lit for the whole ROM wind-up, at the height of the future bullet. High — crouch at once; low —
## jump so that the bullet arrives while the feet are above it.
##
## The bot does not walk around an agent who has come up close, it meets him. Since M24d — with a
## takedown (ADR-0040): an agent who is not aiming is caught up with standing and shot point-blank,
## and a point-blank shot is the takedown. An agent with his back to the bot is stalked from afar —
## a takedown from behind is worth more; one facing it only from very close, otherwise his shot
## comes first. An aiming agent the bot, as before, meets with a duel from a crouch.
##
## The bot thinks in rule coordinates — the same as the layout and floors. It converts from the
## scene in one place, [method _at]: the scene counts Y upward, the rules downward, and a bot
## reading the scene directly would walk the building upside down (ADR-0021).

## How close to the target horizontally counts as "arrived", m.
const REACHED: float = 0.18

## From what distance the bot opens fire, m.
##
## Half a frame wide: an agent has no fire range, he shoots while he is in the frame (ADR-0027,
## decision 3a), — and whoever shoots first lives. The bot fires only if the agent is already on its
## line.
const ENGAGE: float = SideCamera.DEFAULT_HALF_HEIGHT * 16.0 / 9.0

## How closely an agent must match Otto in height to count as a target, m. The bullet flies
## horizontally, and an agent a floor below is not a target but a wasted round.
const SAME_LINE: float = 0.72

## From what distance the bot goes to take down an agent standing with his back to it, m. Any
## farther and the agent has time to turn around: he wanders with pauses (ADR-0027, decision 3a).
const TAKEDOWN_SNEAK: float = 5.0

## From what distance the bot rushes to take down an agent facing it, m. Two steps: walking longer
## under the agent's gaze gives him time to wind up.
const TAKEDOWN_RUSH: float = 2.2

## How long the bot is willing to fight without moving, in seconds of game time.
##
## The count runs while anyone at all is nearby and resets only when the line is clear. After that
## the bot pushes through: an agent can also be out of reach — beyond an opening, on a cab, in a
## blind corner — and doors send the next one every three seconds. A bot that stands until it wins
## never leaves the floor.
const DUEL_PATIENCE: float = 2.0

## How many seconds before impact the bot notices a flying bullet.
##
## The former 2.88 m with the ROM bullet at 8.88 m/s is 0.32 s; the bullet is three times faster,
## and it has to be measured in time, not metres (ADR-0037, decision 5). The main sign is now the
## aiming beam, and a bullet in flight is the fallback: the beam may have hit a wall between them,
## and the bot may have missed reacting to it.
const DODGE_SIGHT: float = 0.32

## How many seconds before impact the bot jumps over a low bullet.
##
## Otto's feet rise above a low ROM bullet (0.68 m) 0.1 s after take-off and stay above it until
## 0.85 s (jump 7.9 m/s with gravity 16.6). The bot decides once every two frames under [member
## Engine.time_scale] 4, that is once every 0.13 s, — jumping at 0.55 s before the bullet, it meets
## it with its feet up at any step.
const JUMP_LEAD: float = 0.55

## Half the width of Otto's body, m.
##
## Together with the bullet length ([method Bullet.half_length]) it gives the clearance the bullet
## must leave before standing up. Agents got caught by this — straightening up right under the
## bullet and taking it in the chest — and Otto would get caught the same way.
const BODY_HALF_WIDTH: float = Proportions.BODY_WIDTH * 0.5

## Above this height over the feet a bullet counts as high: you crouch under it. Otto's crouching
## shape is 1.08 m, and a bullet above it passes over the head.
const HIGH_BULLET: float = Proportions.CROUCH

## Where to stand next to a shaft while waiting for the cab, m from its axis.
##
## **Outside the cab's clearance, not at the very edge of the opening.** The cab is 1.8 m wide
## ([constant Proportions.SHAFT], the building's default [member BuildingRules.shaft_width]), that
## is it takes 0.9 m from the axis; Otto is [constant BODY_HALF_WIDTH] = 0.36 wide. So his middle
## must stay farther than 1.26 m from the axis, otherwise his edge enters the cab's clearance.
##
## The bot may stop [constant REACHED] short of the target, and it makes the last step whole: the
## distance covered in two frames under [member Engine.time_scale] 4 is 0.36 m at [member
## Otto.walk_speed] 2.7 m/s (`docs/testing.md`, item 4). So it never stops closer than
## [code]WAIT_ASIDE - REACHED[/code] = 1.47 m — with a 0.21 m margin from the dangerous 1.26. The
## neighbouring spot 1.8 m from the axis is never a shaft (ADR-0026, decision 3), so where the bot
## waits there is always a floor.
##
## The former 0.96 m did not account for this, and Otto's edge ended up 0.54 m from the axis —
## inside the cab. A cab coming up from below caught him with its roof and carried him up, and the
## roof cannot be controlled ([method Otto.is_riding]). On seed 2 this gave an endless loop: up onto
## the roof, fall back to the floor, wait again — the bot did not leave the 21st floor until the end
## of the run.
const WAIT_ASIDE: float = Proportions.SHAFT * 0.5 + BODY_HALF_WIDTH + REACHED + 0.21

## How close the cab must be to count as arrived at the floor, m.
const CAR_ALIGNED: float = 0.12

## Actions Otto reads on the press edge, not on holding.
##
## They cannot be released and pressed again in the same frame: the engine does not see such an
## edge, and the press is lost entirely. The bot did exactly that — and over the whole milestone it
## never fired once and never jumped once, and the measurements showed only crouching. So a single
## action is held for a frame, the next frame rests, and only then is it pressed again.
const TAPS: Array[StringName] = [&"jump", &"shoot"]

## How many seconds before impact the bot in a cab moves it off the line of fire.
const CAR_DODGE_SIGHT: float = 0.6

## Below this height over the feet a bullet in a cab is jumped over: the cab's ceiling does not let
## the jump go higher.
const CAR_LOW_BULLET: float = 0.6

## Tolerance for the beam having reached Otto, m.
const LASER_SLACK: float = 0.1

## Closer than this to a floor a released cab finishes the way by itself ([member
## ElevatorMotion.settle_distance]).
const SETTLE_BY_ITSELF: float = 0.3

## Whether the bot shoots down lamps. A lamp is shot down from a cab, as in the arcade
## (`test_a_lamp_is_out_of_reach_from_the_floor`): the gun of a riding Otto passes its height.
## Before ADR-0053 the bot did not touch lamps, and the run did not check exactly what darkness
## exists for — that from the shadow Otto is seen only up close ([member
## BuildingRules.agent_dark_fire_range]). Turned off for the "no lamps" measurement
## (`tools/playthrough.gd`, flag [code]--no-lamps[/code]).
var shoots_lamps: bool = true
## How many times the bot shot at a lamp: for measurement.
var lamp_shots: int = 0

var _level: GreyboxLevel
var _rules: BuildingRules
var _otto: Otto
var _pressed: Array[StringName] = []
## Whether we are heading into a cab that stands at the floor.
var _boarding: bool = false
## How long the bot has already been fighting without moving, s. Counted in game time, not frames:
## the measurement runs under [member Engine.time_scale], and a frame there is four times longer.
var _duel_time: float = 0.0
## Single actions released in this frame: they can be pressed again only from the next one.
var _resting: Array[StringName] = []
## Floor pieces and the labelled transitions between them — [method BuildingRoute.walkable].
var _graph: Dictionary = {}
## At which level to step out of the cab. While riding — the goal of the ride.
var _ride_to: int = 0
## Where this ride is going. The direction is remembered on entry: stopping is based on it, and it
## must not be recomputed on the way — that would make a seesaw.
var _riding_down: bool = true
## Column of the shaft the ride is planned in. Without it the bot, having decided "I go to the
## neighbouring shaft and ride to floor N", rode in the cab it was standing in — if that cab's span
## also covers floor N. With overlap this happens all the time.
var _ride_shaft_x: float = INF
## What the bot decided at the last evaluation: for the run trace.
var _decision: String = ""
## The decision already written to the run log.
var _logged: String = ""
## How much longer to hold the cab in the direction chosen to escape the bullet, s. The decision
## holds until the bullet has passed: whoever changes course immediately leaves the beam, and
## recomputing at every step would rock the cab back and forth right on the line of fire.
var _car_dodge_left: float = 0.0
var _car_dodge_dir: float = 0.0


func _init(level: GreyboxLevel) -> void:
	_level = level
	_rules = level.rules
	_otto = level.otto
	# The graph is computed once: the layout does not change during a game, and a decision is made
	# every frame.
	_graph = BuildingRoute.walkable(level.plan(), _rules)


## One decision step. Called every physics frame.
func step() -> void:
	_log_the_decision()
	_release_all()
	if _otto.is_dead():
		_duel_time = 0.0
		return

	var floor_index := _rules.floor_index_near(_at(_otto).y)
	var threat := _threat()
	if threat == null:
		_duel_time = 0.0
	else:
		_duel_time += _otto.get_physics_process_delta_time()

	# Dodging replaces the step, but not the shot: an enemy bullet matters more than the descent, but
	# it does not prevent shooting. A bot that stopped doing everything else while dodging froze in
	# place — doors send agents without a break, and there is almost always a bullet in the air.
	var incoming := _incoming()
	var bullet_height := _dodge_height(incoming)
	# Dodging cancels the duel: what gets pressed is not a direction but crouch or jump. In a cab you
	# cannot crouch, and dodging there is different — move the cab off the line ([method
	# _dodge_in_car]). Before M24a it did not exist at all: the ROM bullet is slow, and the bot managed
	# to shoot first. A three-times-faster bullet against an Otto riding down — that is half of the
	# deaths in the M24a measurement.
	#
	# Crouching in a standing cab was tried on M18: the measurement rejected it — the bot crouched
	# instead of walking, and on one seed did not collect a single document in the whole run.
	var dodging := bullet_height >= 0.0 and not _otto.is_riding()
	var car := _car_of_otto() if _otto.is_riding() else null
	_car_dodge_left = maxf(_car_dodge_left - _otto.get_physics_process_delta_time(), 0.0)
	if car == null:
		_car_dodge_left = 0.0
	var car_dodging := (
		car != null
		and (_car_dodge_left > 0.0 or (incoming.x >= 0.0 and incoming.y <= CAR_DODGE_SIGHT))
	)
	# A takedown matters more than a duel: an agent who is not aiming is caught up with standing.
	var closing := not dodging and not car_dodging and _worth_a_takedown(threat)
	# Whether the gun turns toward the target in this same frame: in a duel the bot presses the
	# direction itself, and there is no need to aim in a separate frame.
	var aiming := not dodging and not car_dodging and not closing and _duelling(threat)
	if dodging:
		_dodge(bullet_height)
	elif car_dodging:
		_dodge_in_car(car, incoming)
	elif closing:
		_close_in(threat)
		return
	elif aiming:
		_hold_the_line(threat)
	else:
		_advance(floor_index)

	# Fire comes on top of the plan, not instead of it. A fight that stops the descent stops it
	# forever: doors send the next one every three seconds, and a bot that first "clears the floor"
	# never leaves it. So on the move the bot shoots only forward: turning around would fight with the
	# step.
	if threat != null and (aiming or is_equal_approx(_otto.facing(), _side_of(threat))):
		_press(&"shoot")
	elif shoots_lamps and _lamp_in_line() != null and _press(&"shoot"):
		lamp_shots += 1
		_decision = "сбиваю лампу"


## The lamp the bullet will hit if fired now, or null: Otto rides in a cab, the gun is at lamp
## height, the lamp is in front of him, within the combat field and not behind a wall. The bot will
## not turn toward a lamp — in a cab turning is a step, and a step while moving leads toward the
## edge; a lamp on the other side is left for the next ride.
##
## While its own bullet is in flight, the bot does not shoot at a lamp: the lamp hangs until the
## bullet arrives, and if it fired every free frame it would put all three bullets into it
## ([constant Gun.MAX_LIVE_BULLETS]) and meet the next agent without ammo.
func _lamp_in_line() -> Lamp:
	if not _otto.is_riding() or Bullet.any_in_flight(_otto.get_tree(), Bullet.FROM_OTTO):
		return null
	var muzzle := _otto.global_position.y + _otto.shot_height_standing
	var reach := Proportions.LAMP.y * 0.5
	var x := _otto.global_position.x
	for lamp in _level.lamps():
		var ahead := (lamp.global_position.x - x) * _otto.facing()
		if ahead <= 0.0 or ahead > ENGAGE:
			continue
		if absf(lamp.global_position.y - muzzle) > reach:
			continue
		# A bullet does not pass through a wall: such a shot is a round into the wall.
		if _level.plan().wall_between(lamp.floor_index, x, lamp.global_position.x):
			continue
		return lamp
	return null


## Writes the bot's decision to the run log when it has changed.
func _log_the_decision() -> void:
	if _decision == _logged or not RunLog.is_on():
		return
	_logged = _decision
	RunLog.write("bot", {"decision": _decision, "at": RunLog.at(_otto)})


## Step toward the target: what the bot will use right now.
##
## The decision is made by the building graph, not a greedy descent: since M18 shafts overlap,
## escalators run both ways, and a blank wall splits a floor in two (ADR-0024). "Ride down the
## nearest shaft" in such a building runs into a dead end — the bot reached the middle and pushed
## against the wall until the end of the run.
func _advance(floor_index: int) -> void:
	if _riding_further():
		_decision = "едем к этажу %d %s" % [_ride_to, "вниз" if _riding_down else "вверх"]
		_ride_on()
		return
	if _otto.is_riding() and not _car_aligned_under_otto():
		# The cab is between floors — moved it off the line of fire. Released, it would reach a floor
		# along its direction by itself (ADR-0053, decision 1), but the bot drives it to the nearest one:
		# that one can also be behind.
		var nearest := _rules.floor_surface(floor_index)
		_decision = "довожу кабину до этажа %d" % floor_index
		# Near a floor the cab finishes the way by itself, you only need to release it: holding a
		# direction means rocking it around the floor.
		if absf(_at(_otto).y - nearest) > SETTLE_BY_ITSELF:
			_press(&"move_down" if _at(_otto).y < nearest else &"move_up")
		return

	var goal := _goal()
	var move := BuildingRoute.step_toward(
		_graph, floor_index, _at(_otto).x, int(goal["floor"]), float(goal["x"])
	)
	if move.is_empty():
		# The target is unreachable. The generator does not produce such buildings, and the traversability
		# test catches it; all that is left here is not to charge blindly.
		#
		# The decision is overwritten rather than left as before: the run trace and the idle watchdog read
		# it, and the previous — successful — decision would send the investigation exactly where
		# everything is fine.
		_decision = (
			"хода нет: цель %s на %d"
			% ["документ" if bool(goal["enter"]) else "выход", int(goal["floor"])]
		)
		return

	_decision = (
		"%s к x=%.1f → этаж %d, цель %s на %d"
		% [
			move["kind"],
			float(move["x"]),
			int(move["floor"]),
			"документ" if bool(goal["enter"]) else "выход",
			int(goal["floor"])
		]
	)

	match String(move["kind"]):
		"shaft":
			_ride_to = int(move["floor"])
			_riding_down = _ride_to > floor_index
			_ride_shaft_x = float(move["x"])
			if _ride_to == floor_index:
				_cross_the_shaft(_ride_shaft_x, float(move["to_x"]), floor_index)
			else:
				_take_the_car(_ride_shaft_x, floor_index)
		"escalator":
			_take_the_escalator(float(move["x"]), int(move["floor"]) < floor_index)
		_:
			if _walk_to(float(move["x"])) and bool(goal["enter"]):
				_press(&"move_up")


## Where the bot goes: to the topmost uncollected document, and if all are collected — to the exit.
##
## The topmost, not the nearest: the descent goes from top to bottom, and a document above the
## current floor means it was skipped, — and without all five the exit sends you back.
func _goal() -> Dictionary:
	var best: BuildingPlan.DoorSpot = null
	for spot in _level.plan().doors:
		if not spot.has_document or not _still_pending(spot):
			continue
		if best == null or spot.floor_index < best.floor_index:
			best = spot
	if best != null:
		return {"floor": best.floor_index, "x": best.x, "enter": true}
	return {"floor": _rules.floors - 1, "x": _level.exit_position().x, "enter": false}


## What the bot decided this frame: the target and the move toward it. The run trace needs this —
## from "presses [down]" you cannot see where it was going and why it changed its mind.
func decision() -> String:
	return _decision


## Releases everything it was holding: without this Otto would keep walking after a change of
## decision.
func release() -> void:
	_release_all()


## Where the node stands in the rules plane.
static func _at(node: Node3D) -> Vector2:
	return WorldSpace.to_plane(node.global_position)


## The nearest living agent on the line of fire, or null.
func _threat() -> Enemy:
	var here := _at(_otto)
	var closest: Enemy = null
	var nearest := ENGAGE
	for agent in _level.agents():
		if agent.is_dead():
			continue
		var to_agent := _at(agent) - here
		if absf(to_agent.y) > SAME_LINE:
			continue
		if absf(to_agent.x) > nearest:
			continue
		nearest = absf(to_agent.x)
		closest = agent
	return closest


## The nearest threat: the height of a future or flying bullet over Otto's feet, m, and in how many
## seconds it will arrive. Nothing to fly — height −1.
##
## The aiming beam is checked first: the bullet is three times faster than in the ROM and is seen
## too late, while the beam is lit for the whole wind-up (ADR-0037, decision 5) — and at anger 10
## and above it is no shorter than [constant EnemyBrain.MIN_TELL]. A bullet in flight is the
## fallback sign: for the case when the bot missed the beam.
func _incoming() -> Vector2:
	var best := Vector2(-1.0, INF)
	for agent in _level.agents():
		if agent.is_dead():
			continue
		var threat := _laser_threat(agent)
		if threat.x >= 0.0 and threat.y < best.y:
			best = threat
	for node in _otto.get_tree().get_nodes_in_group(Bullet.GROUP):
		var bullet := node as Bullet
		if bullet == null or bullet.collision_mask != Bullet.FROM_ENEMY:
			continue
		var to_bullet := WorldSpace.direction_to_plane(
			bullet.global_position - _otto.global_position
		)
		# Whether it is flying at us — and whether it has already gone behind us. The measure is not "from
		# which side" but "how far it still has to us": a bullet that has passed the middle but not yet
		# left the clearance with its tail still hits.
		if -to_bullet.x * bullet.direction < -(BODY_HALF_WIDTH + bullet.half_length()):
			continue
		var time := absf(to_bullet.x) / maxf(bullet.speed, 0.01)
		if time > DODGE_SIGHT or time >= best.y:
			continue
		best = Vector2(-to_bullet.y, time)
	return best


## An agent's aiming beam if it looks at Otto: the height of the future bullet over Otto's feet, m,
## and seconds until impact — wind-up and flight. Otherwise height −1.
##
## A beam at Otto is a beam that reached him: one that hit a wall between them does not count. One
## who crouched under a high beam no longer blocks it, and the beam goes farther, — so the length is
## measured, not what it hit: otherwise the bot would stand up right into the shot.
func _laser_threat(agent: Enemy) -> Vector2:
	var laser := agent.laser
	if laser == null or not laser.is_on():
		return Vector2(-1.0, INF)
	var to_otto := _otto.global_position - laser.global_position
	if signf(to_otto.x) != laser.direction:
		return Vector2(-1.0, INF)
	var gap := absf(to_otto.x)
	# A beam that hits Otto himself ends exactly at the edge of his body, and a comparison without
	# tolerance rejected it every other time — due to floating point error.
	if laser.length() < gap - BODY_HALF_WIDTH - LASER_SLACK:
		return Vector2(-1.0, INF)
	var height := -to_otto.y
	var time := laser.time_to(gap)
	# In a cab Otto himself rides onto the line or off it: the height is measured for the moment the
	# bullet arrives. The current one is returned — [method _dodge_in_car] decides by it.
	var car := _car_of_otto() if _otto.is_riding() else null
	var arriving := height + (car.speed_now() * time if car != null else 0.0)
	var slack := 0.1 if car != null else 0.0
	if arriving < -slack or arriving > Proportions.BODY + slack:
		return Vector2(-1.0, INF)
	return Vector2(height, time)


## The height to dodge this frame, or −1.
##
## Under a high bullet you can crouch at once: the crouch is instant, and sitting under the beam is
## safe for the whole wind-up. A low one is jumped over in time: earlier than [constant JUMP_LEAD]
## the bot would land right on it.
func _dodge_height(incoming: Vector2) -> float:
	if incoming.x < 0.0:
		return -1.0
	if incoming.x > HIGH_BULLET or incoming.y <= JUMP_LEAD:
		return incoming.x
	return -1.0


## Leaves the line of fire: crouches under a high bullet, jumps over a low one.
##
## A jump is possible only from the floor: in the air the press is wasted, and the bot meets the
## bullet standing. If it did not work from the floor — crouch, that is at least something.
##
## "Did not work" also covers the rest frame: the jump is a single action, and on such a frame
## [method _press] does not press it. An empty frame under a bullet costs more than an imperfect
## dodge, so the result is checked, not assumed.
func _dodge(bullet_height: float) -> void:
	if bullet_height > HIGH_BULLET:
		_press(&"move_down")
		return
	if _otto.is_grounded() and _press(&"jump"):
		return
	_press(&"move_down")


## Whether to go and take down [param threat] (ADR-0040): standing on its own feet, not in a cab,
## the agent is ready for a takedown and not aiming — and close: back turned — up to [constant
## TAKEDOWN_SNEAK], facing — up to [constant TAKEDOWN_RUSH].
##
## And only on its own floor piece. The bot catches up in a straight line, bypassing the graph, and
## between it and the agent there may be a shaft opening or a blank wall: one who steps into an
## empty shaft dies, one who runs into a wall stands until the end of the run (M24e code review).
func _worth_a_takedown(threat: Enemy) -> bool:
	if threat == null or not threat.takedown_ready:
		return false
	if _otto.is_riding() or not _otto.is_grounded() or _otto.takedown != null:
		return false
	if threat.laser != null and threat.laser.is_on():
		return false
	var here := _at(_otto)
	var there := _at(threat)
	if not _same_piece(_rules.floor_index_near(here.y), here.x, there.x):
		return false
	var side := Takedown.side_of(_otto.global_position.x, threat.global_position.x, threat.facing())
	var reach := TAKEDOWN_SNEAK if side == Takedown.Side.BACK else TAKEDOWN_RUSH
	return absf(there.x - here.x) <= reach


## Catches up with the agent standing and fires point-blank: close up the shot is the takedown.
## While not close, the bot walks and does not shoot — a bullet would take the agent cheaper.
func _close_in(threat: Enemy) -> void:
	var side := _side_of(threat)
	var gap := absf(threat.global_position.x - _otto.global_position.x)
	var facing_it := is_equal_approx(_otto.facing(), side) or is_zero_approx(side)
	if facing_it and gap <= Takedown.REACH * 0.85:
		_decision = "добиваю"
		_press(&"shoot")
		return
	_decision = "иду добивать"
	_press(&"move_right" if side > 0.0 else &"move_left")


## Whether points [param a] and [param b] are on the same piece of floor [param floor_index]: you
## can walk from one to the other on foot, without a cab or escalator.
func _same_piece(floor_index: int, a: float, b: float) -> bool:
	var pieces: Dictionary = _graph["pieces"]
	for piece: Vector2 in pieces.get(floor_index, []):
		if a >= piece.x and a <= piece.y:
			return b >= piece.x and b <= piece.y
	return false


## On which side of Otto the agent stands: -1 left, +1 right.
func _side_of(agent: Enemy) -> float:
	return signf(_at(agent).x - _at(_otto).x)


## Whether it is time to fight rather than move on.
##
## You cannot walk past an agent who has you in his sights: at a few centimetres the exchange is
## instant, and dodging no longer decides anything there — this is exactly how all the measurements
## of the milestone ended (ADR-0016, "How the milestone ended").
func _duelling(threat: Enemy) -> bool:
	if threat == null:
		return false
	# A duel means crouching and turning, and in a cab you can do neither: crouch is disabled there
	# (ADR-0004, item 3), and a side step on the way leads into an empty shaft. Until the cab stops at
	# a floor, the bot just rides.
	var riding := _otto.is_riding()
	if riding and not _car_aligned():
		return false
	if _duel_time > DUEL_PATIENCE:
		return false
	return absf(_at(threat).x - _at(_otto).x) <= _duel_reach()


## Closer than what distance the bot does not walk past an agent but fights, m.
##
## The same measure as for fire: it is worth fighting exactly those who can hit, and since M18d
## anyone in the frame can hit (ADR-0027, decision 3a).
func _duel_reach() -> float:
	return ENGAGE


## Duel: crouch, turn to the agent and keep him under fire.
##
## Crouching here is not a retreat but the best position of all: the agent's bullet flies 1.4 m
## above the floor and passes over a crouching figure (its shape is 1.08 m), while Otto himself
## shoots lower from a crouch — and hits both a standing agent and one who has dropped to a knee.
## You cannot walk crouched, but in a duel you do not need to.
##
## The direction is pressed in this same frame, and the shot goes that way: Otto takes the fire
## direction from the same press he turns with.
func _hold_the_line(threat: Enemy) -> void:
	if not _otto.is_riding():
		_press(&"move_down")
	_press(&"move_right" if _side_of(threat) > 0.0 else &"move_left")


## Whether the cab the bot rides in stands at a floor.
##
## While it is moving, a side step is a step into an empty shaft, and falling into it is deadly. At
## a floor you can step out: there is a floor underfoot.
func _car_aligned() -> bool:
	var here := _at(_otto)
	for child in _level.get_children():
		var car := child as ElevatorCar
		if car == null:
			continue
		var at := _at(car)
		# The horizontal measure is narrow on purpose, even though Otto rides where he stood, not on the
		# axis: across the full width of the cab the duel would almost always switch on in it, and the bot
		# would step sideways out of it onto the floor — and never reach the bottom of the building
		# (ADR-0016).
		if absf(at.x - here.x) > CAR_ALIGNED:
			continue
		if absf(at.y - here.y) > CAR_ALIGNED:
			continue
		return car.is_aligned()
	return false


## Whether the cab carries on, or it is time to step out and go on foot.
##
## The comparison is with the floor itself, not the floor number: the number changes halfway, and
## the bot stopped riding while hanging mid-span, where you cannot step out.
##
## And a cab standing at a floor the bot walks straight through on the way to an escalator, and that
## must not count as a ride: otherwise it turned around and walked back and forth.
func _riding_further() -> bool:
	if not _otto.is_riding():
		return false

	# The cab we stand in may not reach the goal of the ride: shafts overlap, and a transfer happens in
	# a cab standing at its bottom. Such a cab has to be left, not pressed "down" in until the end of
	# the run.
	# Whether this is the right cab: you can stand in one and plan to ride in another.
	var shaft := _shaft_under_otto()
	if shaft == null or not is_equal_approx(shaft.x, _ride_shaft_x):
		return false
	if _ride_to < shaft.top or _ride_to > shaft.bottom:
		return false

	# The stop is one-sided: "until it matches the floor" does not work, because in one frame the cab
	# moves more than the alignment tolerance and overshoots the target. The bot then presses up and
	# down alternately and rocks around the floor until the end of the run.
	var surface := _rules.floor_surface(_ride_to)
	var y := _at(_otto).y
	return y < surface - CAR_ALIGNED if _riding_down else y > surface + CAR_ALIGNED


## The shaft in whose column Otto stands. [code]null[/code] — he is not in a shaft.
##
## The column is not enough: two shafts can stand in the same place at different heights. So the
## level is checked too — on one level the shafts have different columns.
func _shaft_under_otto() -> BuildingPlan.ShaftSpot:
	var here := _at(_otto)
	var index := _rules.floor_index_near(here.y)
	for shaft in _level.plan().shafts:
		if shaft.top > index or shaft.bottom < index:
			continue
		if absf(shaft.x - here.x) <= _rules.shaft_width * 0.5:
			return shaft
	return null


## Drives the cab to the level where it was decided to step out. Upward too: since M18 the way down
## sometimes goes through a floor above where the floor is not cut (ADR-0024).
func _ride_on() -> void:
	_press(&"move_down" if _riding_down else &"move_up")


## Enters the cab, having waited for it at the very edge of the opening.
##
## Enters only on the cab's arrival and only when standing next to it. Entering at any moment of the
## stop can catch its end: the cab leaves while the bot makes the last steps, and he steps into an
## empty shaft — and falling into it is deadly. Missing an arrival is not a problem: the cab will
## come back, the frames are budgeted for it.
func _take_the_car(shaft_x: float, floor_index: int) -> void:
	var surface := _rules.floor_surface(floor_index)
	var here := _car_waits_at(shaft_x, surface)
	var x := _at(_otto).x
	var aside := absf(x - shaft_x) <= WAIT_ASIDE + REACHED

	# Boards as soon as the cab is here and he is next to it — without waiting for it to arrive.
	# Waiting specifically for the arrival the bot could do since M2, and it was cheap while there was
	# one cab per strip. With overlap it waits at shafts all the time — and crossing an opening goes
	# exactly to a standing cab that is not going to arrive anymore. Every such wait is standing under
	# fire: all deaths in the measurement happened there.
	#
	# It is safe because it moves toward the column only while the cab is in place: once it leaves,
	# [code]_boarding[/code] is cleared in the same frame.
	if here and aside:
		_boarding = true
	if not here:
		_boarding = false

	if _boarding:
		_walk_to(shaft_x)
		return

	var side := -1.0 if x < shaft_x else 1.0
	_walk_to(shaft_x + side * WAIT_ASIDE)


## Crosses a shaft opening straight through: via a standing cab.
##
## A shaft cuts the floor with its opening, and the halves connect only this way — as in the
## original, where the cab covers the opening with itself. While there is no cab, the opening must
## not be approached: one who steps into an empty shaft dies, — so the bot first waits for it in the
## same place where it waits for a ride.
func _cross_the_shaft(shaft_x: float, to_x: float, floor_index: int) -> void:
	if not _car_waits_at(shaft_x, _rules.floor_surface(floor_index)):
		_take_the_car(shaft_x, floor_index)
		return
	_walk_to(to_x)


## Steps onto the escalator landing and sets off. Upward too: the belt runs both ways, and sometimes
## this is the only way around a cut floor.
func _take_the_escalator(pad_x: float, upward: bool) -> void:
	if not _walk_to(pad_x):
		return
	_press(&"move_up" if upward else &"move_down")


## Walks to a point. Returns true when already there.
func _walk_to(x: float) -> bool:
	var gap := x - _at(_otto).x
	if absf(gap) <= REACHED:
		return true
	_press(&"move_right" if gap > 0.0 else &"move_left")
	return false


## Whether a cab one can step into stands at the floor.
##
## Being close is not enough: the cab must **match the floor with its own floor**, not merely pass
## by within the [constant CAR_ALIGNED] tolerance. That tolerance is 0.12 m, and the cab goes 1.8
## m/s and passes through it in four frames; stepping into such a cab, Otto lands not inside but on
## the roof — its ceiling passes right through the floor level while the cab approaches from below.
##
## A cab cannot be controlled from the roof (as in the original, [method Otto.is_riding] states this
## explicitly), and there is nowhere to get off between floors. On M18a this is exactly what
## happened: on seed 2 the bot stood on the roof for 21356 decisions until the end of the run. So
## boarding goes only by [method ElevatorCar.is_aligned] — that is, by the stop.
func _car_waits_at(x: float, surface: float) -> bool:
	for child in _level.get_children():
		var car := child as ElevatorCar
		if car == null:
			continue
		var at := _at(car)
		if absf(at.x - x) > CAR_ALIGNED:
			continue
		if absf(at.y - surface) <= CAR_ALIGNED:
			return car.is_aligned()
	return false


## The door is still red: a collected one stops being red, and there is no need to go into it a
## second time.
##
## The floor is checked too: places are shared between floors, and a red door above standing in the
## same column would pass an already collected door off as uncollected — the bot would walk to it
## forever.
func _still_pending(spot: BuildingPlan.DoorSpot) -> bool:
	for door in _level.doors():
		if not door.is_pending():
			continue
		var mat := door.mat_position()
		if absf(mat.x - spot.x) <= REACHED and _rules.floor_index_near(mat.y) == spot.floor_index:
			return true
	return false


## Presses an action. Returns whether it got pressed: a single action released in this same frame
## cannot be pressed — there would be no edge, the frame is skipped, and the press goes out on the
## next one.
func _press(action: StringName) -> bool:
	if _resting.has(action):
		return false
	Input.action_press(action)
	_pressed.append(action)
	return true


func _release_all() -> void:
	_resting.clear()
	for action in _pressed:
		Input.action_release(action)
		if TAPS.has(action):
			_resting.append(action)
	_pressed.clear()


## The cab Otto rides in, or null.
func _car_of_otto() -> ElevatorCar:
	var here := _at(_otto)
	for child in _level.get_children():
		var car := child as ElevatorCar
		if car == null or not car.has_rider():
			continue
		var at := _at(car)
		if absf(at.x - here.x) > car.width() * 0.5 or absf(at.y - here.y) > 0.6:
			continue
		return car
	return null


## Whether Otto's cab stands at a floor.
func _car_aligned_under_otto() -> bool:
	var car := _car_of_otto()
	return car == null or car.is_aligned()


## Dodging a shot in a cab: you cannot crouch there, but you can move the cab.
##
## The cab moves at a steady speed without acceleration, and in the time left before the bullet it
## shifts Otto by [code]speed · time[/code]. Down — the bullet passes over the head, up — under the
## feet, into the floor. The side with the larger margin is chosen; a low bullet in a standing cab
## is easier to jump over.
func _dodge_in_car(car: ElevatorCar, incoming: Vector2) -> void:
	if _car_dodge_left > 0.0:
		if car.can_go(_car_dodge_dir):
			_press(&"move_down" if _car_dodge_dir > 0.0 else &"move_up")
		return
	var height := incoming.x
	if (
		height <= CAR_LOW_BULLET
		and car.is_aligned()
		and _otto.is_grounded()
		and incoming.y <= JUMP_LEAD
		and _press(&"jump")
	):
		return
	var shift := car.speed * incoming.y
	var over_head := height + shift - Proportions.BODY
	var under_feet := shift - height
	var down := over_head if car.can_go(1.0) else -INF
	var up := under_feet if car.can_go(-1.0) else -INF
	if is_inf(down) and is_inf(up):
		return
	_car_dodge_dir = 1.0 if down >= up else -1.0
	_car_dodge_left = incoming.y + 0.1
	_press(&"move_down" if _car_dodge_dir > 0.0 else &"move_up")
