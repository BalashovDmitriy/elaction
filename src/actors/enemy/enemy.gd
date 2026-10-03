class_name Enemy
extends CharacterBody3D

## Enemy agent.
##
## Comes out of an ordinary door, wanders his floor and shoots when Otto
## is on the same line with him (ADR-0027). [EnemyBrain] decides, the node executes.
##
## The agent's body does no harm: in the original only a shot takes a life (ADR-0006,
## point 4), so he has no damage zone — only a weapon.
##
## Like Otto, he lives in the play plane: Z is locked (ADR-0021, decision 1).

## The agent is killed. Passes itself so the door knows whom to release again.
signal died(agent: Enemy)

## The agent reached a door and went into it (ADR-0027, decision 3a). His level removes him.
signal left_building(agent: Enemy)

## Agent sound at his position (ADR-0052, decision 7): how far a step and a shot
## can be heard, m, and how much quieter his step is than Otto's, dB.
const STEP_REACH: float = 14.0
const SHOT_REACH: float = 40.0
const STEP_DB: float = -5.0

const BULLET_SCENE := preload("res://src/systems/combat/bullet.tscn")
## Enemy layer in `project.godot`. The agent leaves it while he stands in the doorway.
const ENEMY_LAYER: int = 3
## The building's agent group: Otto uses it to find whom he reaches point-blank (ADR-0040).
const GROUP := &"agents"

## How long the shooting pose holds, s.
const SHOOT_POSE_TIME: float = 0.25

## How close to the spot by the door the agent counts as arrived, m. More than the path
## over two frames under test speed-up (docs/testing.md), less than the offset from the mat.
const WATCH_REACH: float = 0.12

## Walking is the same as Otto's: in ROM they share one step routine (ADR-0027).
@export var walk_speed: float = Arcade.speed(Arcade.WALK_PX)
@export var gravity: float = 27.0
@export var max_fall_speed: float = 12.6

## Shot height from the feet when standing: hits a standing Otto and passes over a crouching one.
## From a crouch and lying — their own ROM heights ([Proportions]): from a crouch the bullet passes
## over a lying one, lying — it hits a crouching one (ADR-0027, decision 3).
@export var shot_height: float = Proportions.AGENT_SHOT
@export var muzzle_offset: float = Proportions.MUZZLE

## Decision settings that do not depend on the building: how long the agent takes to get out
## of the door and what height spread counts as "on the same line". The node keeps them
## and hands them to [EnemyBrain] — just as a door hands over its [DoorVisit].
##
## Combat numbers — wind-up, pause, pose, dodge, bullet speed — are computed by [Arcade]
## from the agent's aggression and the building skill (ADR-0027).
@export var emerge_time: float = 0.6
@export var same_line: float = 0.45

## Whether the agent stands on a snowy deck: set by the roof snow ([SnowTracks]).
var icy: bool = false

## Aim laser: lit while the agent winds up. The player dodges the shot by it —
## and so does the test bot (ADR-0037, decision 5). The agent sets it himself.
var laser: AimLaser = null

## Where to wait by the door Otto hid behind, and where the door itself is; NAN — not waiting
## ([DoorWatch], ADR-0038, decision 2). The level sets it every frame; as fields, not
## a method — it is an assignment and nothing more, like shadow and darkness.
var watch_at: float = NAN
var watch_door: float = NAN

## Whether the agent can be taken down: alive, out of the door and not already in a scene.
## As properties, not methods: the node's methods hit the linter's limit.
var takedown_ready: bool:
	get:
		return (
			is_inside_tree()
			and not _held
			and not _brain.is_dead()
			and not _brain.is_emerging()
			and not Takedown.rides_a_car(self)
		)
## A takedown scene is running over the agent (ADR-0040): brain and steps stop, the laser
## goes out, the agent at once faces [member held_facing]. Released alive — back in combat,
## dead — lies down. The director sets and clears it.
var held: bool:
	get:
		return _held
	set(value):
		_held = value
		set_physics_process(not value)
		if not value:
			# The scene's corpse falls from the pose the scene released it in: while it
			# ran, turning or falling would have broken the staging (ADR-0043,
			# decision 12).
			if _brain.is_dead():
				set_physics_process(false)
				corpse.fall(Vector3.ZERO)
			return
		velocity = Vector3.ZERO
		_walking = false
		if laser != null:
			laser.put_out()
		_brain.face(held_facing)
		_faced = _brain.facing
		_body.face(held_facing, true)
## Where the agent faces in the scene: −1 left, +1 right. Set before [member held].
var held_facing: float = 1.0
## The agent's jointed body ([Corpse]): assembled from birth, falls at the moment
## of death (ADR-0043, decision 12).
var corpse: Corpse = null
## The agent's figure: the scene director sets its poses and tempo.
var figure: FigureRig:
	get:
		return _body

## What the agent's step sounds like — the level sets it from the building floor.
var step_sound: String = Sounds.STEP_CONCRETE

## Rules of the building the agent came out of. Never empty: without them he
## gets the default values — the same as the default building.
var _rules: BuildingRules = null

## Precipitation catcher on the body ([Shelter]).
var _shelter: GPUParticlesCollisionBox3D = null
var _brain := EnemyBrain.new()
var _target: Otto = null
var _in_the_dark: bool = false
## Whether Otto stands in darkness. This, not the agent's own shadow, decides whether he sees Otto:
## from the shadow the lit one is seen, the lit one does not see into the shadow.
var _target_in_the_dark: bool = false
var _target_behind_a_wall: bool = false
## Where to go to ride: the axis of a standing cab, or NAN if there is nowhere to go.
var _lift_x: float = NAN
## Where to go to leave the building: a door or NAN (@041F).
var _exit_x: float = NAN
## Walk phase, shooting and falling pose, crushed flag — all as with Otto.
var _walk_phase: float = 0.0
## The walk frame on which the step has already sounded; the stance that has already
## sounded (ADR-0052, decision 7).
var _stepped_on: int = -1
var _heard_stance: EnemyBrain.Stance = EnemyBrain.Stance.STAND
var _walking: bool = false
## Turn pause, as with Otto (ADR-0039, decision 6), and the side the agent
## faced last frame: a change of side on the floor is the turn.
var _locks := MoveLocks.new()
var _faced: float = 0.0
var _shooting: float = 0.0
var _crushed: bool = false
## Corpse pose if the agent was taken down by a scene: lies as he fell (ADR-0040).
var _corpse: String = ""
var _held: bool = false
## The aggression the agent came out with and how long he has lived, s: aggression grows
## with age (@5AFC). Building skill — for bullet speed, alarm — the siren.
var _spawn_anger: int = 0
var _age: float = 0.0
var _skill: int = 0
var _alarmed: bool = false
## How much longer the agents' alarm lasts, s (ADR-0027, decision 5).
var _alert_left: float = 0.0
## The last bullet fired: the agent has only one in flight (@1BAE).
var _bullet: Bullet = null

@onready var _body: FigureRig = $Body
@onready var _floor_probe: RayCast3D = $FloorProbe
@onready var _shape: CollisionShape3D = $Shape


## Body shape and floor probe are set by [Proportions], not the scene — as with [Otto].
func _notification(what: int) -> void:
	if what != NOTIFICATION_SCENE_INSTANTIATED:
		return
	var width := Proportions.BODY_WIDTH
	Proportions.fit_box(
		$Shape as CollisionShape3D, Vector3(width, Proportions.BODY, WorldSpace.BODY_DEPTH)
	)
	# The probe looks three quarters of a body ahead and one body down: the foot
	# the agent is about to step with, and the floor under it.
	var probe := $FloorProbe as RayCast3D
	probe.position = Vector3(width * 0.75, width / 3.0, 0.0)
	probe.target_position = Vector3(0.0, -width, 0.0)


func _ready() -> void:
	add_to_group(GROUP)
	# Rain and snow die on the hat and shoulders (ADR-0054).
	_shelter = Shelter.over(self, _cover())
	_brain.emerge_time = emerge_time
	_brain.same_line = same_line
	# Standing height is taken from the shape itself, not written as a second number:
	# if they drifted apart, they would give an agent dodging with a body not his own.
	_brain.stand_height = (_shape.shape as BoxShape3D).size.y
	_refresh_brain()
	laser = AimLaser.make()
	laser.mask = Bullet.FROM_ENEMY
	add_child(laser)
	corpse = Corpse.new(self, _body)


## Body extent under precipitation: standing, kneeling or lying — lying along the floor.
func _cover() -> Vector3:
	match _brain.stance:
		EnemyBrain.Stance.KNEEL:
			return Vector3(Proportions.BODY_WIDTH, Proportions.KNEEL, WorldSpace.BODY_DEPTH)
		EnemyBrain.Stance.PRONE:
			return Vector3(Proportions.BODY * 0.9, Proportions.PRONE, WorldSpace.BODY_DEPTH)
	return Vector3(Proportions.BODY_WIDTH, Proportions.BODY, WorldSpace.BODY_DEPTH)


func _physics_process(delta: float) -> void:
	# Precipitation catcher follows the pose; a killed one is not held: the body lies separately.
	if _shelter != null:
		_shelter.visible = not is_dead()
		Shelter.fit(_shelter, _cover())
	if _brain.is_dead():
		return

	var alive_target := _target != null and not _target.is_dead()
	# The brain needs the vector to the target in rule coordinates: there Y grows down, and
	# it counts "on the same line" the same way it did in 2D.
	var to_target := Vector2.ZERO
	if alive_target:
		to_target = WorldSpace.direction_to_plane(_target.global_position - global_position)
	# An invisible Otto is not a target for the brain: it does not turn to him and does not
	# shoot, but goes where it was going (ADR-0023, decision 8).
	var sees_target := alive_target and _sees(to_target)
	_age += delta
	_alert_left = maxf(_alert_left - delta, 0.0)
	_brain.anger = Arcade.aggression(_spawn_anger, _age)
	_brain.alert = _alert_left > 0.0
	var state := _brain.update(
		delta,
		to_target,
		sees_target,
		_incoming_height(),
		alive_target and _in_frame() and not _building_rules().agents_hold_fire,
		not is_instance_valid(_bullet),
		alive_target and _target.is_crouching(),
		alive_target and _target.hittable
	)
	_fit_shape()
	if _brain.fired():
		_fire()
	_show_the_aim()

	# The agent steps out of the doorway. EMERGING means "step out", not "stand":
	# before, he stood for that fraction of a second on the mat in front of a closed leaf, and
	# that is exactly what the player called "spawns on top of the door" (ADR-0020).
	var stepping_out := state == EnemyBrain.State.EMERGING
	_shield(stepping_out)

	# Crouching and lying, the agent does not walk: a dodge is freezing, not walking
	# on bent over. Standing, he walks until the brain tells him to stand.
	var walking := _brain.wants_to_walk()
	# One waiting by a door walks to his spot without wandering pauses: he is not wandering but
	# keeping watch. Arrived — stands facing the door.
	var watching := not stepping_out and not is_nan(watch_at)
	if watching:
		walking = _brain.is_standing() and _head_for(watch_at, WATCH_REACH)
		if not walking:
			_brain.face(watch_door - WorldSpace.to_plane(global_position).x)
	# The level offers a cab only when Otto is on another floor (ADR-0025,
	# decision 6) — there is nothing to decide here by "does he see him": [code]sees_target[/code]
	# means "Otto is not in shadow and not behind a wall", and ten floors away it is also
	# true. Gating on it would disable elevators almost always.
	var free_to_go := walking and not watching and not stepping_out
	var to_the_lift := free_to_go and not is_nan(_lift_x)
	if to_the_lift:
		walking = _head_for_the_lift()
	elif free_to_go and not is_nan(_exit_x):
		walking = _head_for(_exit_x)
		if not walking:
			left_building.emit(self)
	if walking and is_on_floor() and _blocked_ahead():
		# No floor ahead or a wall: the agent stays on his floor (ADR-0006,
		# point 6). One coming out and one heading to a cab stop at the edge, a wandering one
		# turns around.
		if to_the_lift or watching:
			# One heading to a cab stops at the doorway and waits: the cab left while he walked,
			# and there is no point stepping into an empty shaft. He must not be turned — he
			# would immediately forget why he came. Same for one heading to a door.
			walking = false
		elif stepping_out:
			walking = false
		else:
			# A wandering agent turns at the floor edge: he does not chase Otto
			# and does not guard the doorway for him (ADR-0027, decision 3a).
			_brain.turn_around()
	walking = _turn_holds(delta, walking)
	var wanted := walk_speed * _brain.facing if walking else 0.0
	velocity.x = Footing.step(velocity.x, wanted, icy and is_on_floor(), delta)
	_apply_gravity(delta)
	move_and_slide()
	_hold_the_plane()
	_walking = walking
	_update_look(delta)


## Where to go to ride: the coordinate of a standing cab, or NAN if there is nowhere
## to go. The level recomputes it every frame — only it knows where Otto is and which
## cab stands level with the floor (ADR-0025, decision 6).
##
## The agent does not call a cab: nobody in the original has a call. He walks to the one
## already standing and rides as a passenger — Otto controls the motion, and an empty cab
## runs on its own schedule.
##
## **The agent keeps the chosen cab as long as he is offered a ride at all.** On a podium
## floor there are up to five shafts, cabs come level and leave each in its turn,
## and the offer jumped from one to another frame by frame: the agent turned
## back and forth and did not budge in half a minute. Only NAN cancels the choice —
## "nowhere to go": then he patrols the floor again.
func set_lift_at(x: float) -> void:
	if is_nan(x):
		_lift_x = NAN
	elif is_nan(_lift_x):
		_lift_x = x


## Shows the agent a door to leave through, or NAN — no reason to leave.
func set_exit_at(x: float) -> void:
	_exit_x = x


## Whether to walk to point [param x] on the floor: closer than [param reach] — arrived.
func _head_for(x: float, reach: float = Proportions.DOOR_MAT * 0.5) -> bool:
	var gap := x - WorldSpace.to_plane(global_position).x
	_brain.face(gap)
	return absf(gap) > reach


## Whether to walk to the cab and whether to move the legs meanwhile. Called only
## when a cab is chosen: without a choice there is nowhere to go and nothing to ask.
##
## Having arrived, the agent freezes and stays turned toward the shaft: a cab is not a place
## for patrolling. Otherwise he would pace from wall to wall inside it and fall out
## on the first floor where the floor ahead appeared again.
func _head_for_the_lift() -> bool:
	var gap := _lift_x - WorldSpace.to_plane(global_position).x
	_brain.face(gap)
	var walking := absf(gap) > _lift_aboard()
	# Boarded a cab — alarm for 90 ticks (@1AED): in the cab the agent shoots without
	# looking at Otto, as in ROM.
	if not walking:
		alert_for(Arcade.seconds(Arcade.ALERT_TICKS))
	return walking


## How close to the cab axis the agent counts himself already inside, m.
##
## Half the cab width minus half the agent's body: closer than this he is entirely within
## the extent, and there is nowhere further to step. The cab width belongs to the building
## rules, not [Proportions]: per the rules the level stretches it ([method
## ElevatorCar.fit_to_story]), and with another shaft the agent would stand half
## outside.
func _lift_aboard() -> float:
	return maxf(_building_rules().shaft_width * 0.5 - _body_half_width(), 0.0)


## Gives the agent the building rules: he takes skill and stance heights from them.
##
## Called before [method Node.add_child] and after — order decides nothing, as
## with [method set_threat]: numbers move into [EnemyBrain] in one [method _refresh_brain].
func apply_rules(rules: BuildingRules) -> void:
	_rules = rules
	_skill = rules.skill
	_refresh_brain()


## Releases the agent from a door: he comes out toward [param towards].
func setup(target: Otto, towards: float) -> void:
	_target = target
	_brain.start(towards)
	# The shield is set here, not on the first physics frame: otherwise between placing
	# him in the doorway and the first [method _physics_process] there is a step on which
	# the agent is an ordinary target, and a bullet or a kick take points for him without
	# killing anything (ADR-0020, decision 3).
	_shield(true)


## Tells the agent it is dark under him. Only the price of his death depends on this:
## a kill in darkness is worth more (ADR-0010, point 6). Darkness under the agent no longer
## changes combat decisions — Otto's shadow decides them (ADR-0023, decision 8) — so here
## it is an assignment and nothing more: it is called every frame on every living one.
func set_in_the_dark(value: bool) -> void:
	_in_the_dark = value


## Tells the agent that Otto stands in darkness. Such an Otto he notices only up close —
## [member BuildingRules.agent_dark_fire_range] — and further away does not see at all.
func set_target_in_the_dark(value: bool) -> void:
	_target_in_the_dark = value


## Tells the agent that a solid inner wall stands between him and Otto.
##
## Neither a bullet nor a gaze passes through it: there is no point shooting at the wall, and the
## agent walks his half of the floor until Otto goes around it through another level
## (ADR-0024, decision 5). This is handled the same way as darkness: not seen —
## not a target (ADR-0023, decision 8).
func set_target_behind_a_wall(value: bool) -> void:
	_target_behind_a_wall = value


## Where the agent faces: -1 left, +1 right.
func facing() -> float:
	return _brain.facing


## What aggression the agent comes out with, which building skill he is from and whether the
## siren sounds. Aggression on exit is the building difficulty at that moment (@5AA4); after that
## it grows with the agent's age by itself.
func set_threat(spawn_anger: int, skill: int, alarmed: bool) -> void:
	_spawn_anger = clampi(spawn_anger, 0, Arcade.TOP)
	_skill = maxi(skill, 0)
	_alarmed = alarmed
	_brain.anger = Arcade.aggression(_spawn_anger, _age)


## Siren switched on or not: the agent's bullet is a step faster (@463D).
func set_alarmed(value: bool) -> void:
	_alarmed = value


## Agents' alarm for [param seconds]: Otto's shot in frame or boarding
## a cab (ADR-0027, decision 5). Does not shorten one already running.
func alert_for(seconds: float) -> void:
	_alert_left = maxf(_alert_left, seconds)


## Third or fourth agent of the building: its own pose table (table_1D95).
func set_late(value: bool) -> void:
	_brain.late = value


## Seeds the agent's decisions. Called by the level: each has its own generator, but from the
## building seed, and a bot run repeats down to the step.
func seed_decisions(value: int) -> void:
	_brain.rng.seed = value


## The agent's current aggression.
func anger() -> int:
	return _brain.anger


## Whether the agent stands in darkness. The kill bonus is computed from this flag.
func is_in_the_dark() -> bool:
	return _in_the_dark


## Which stance he is in. From outside it is also visible by the collision shape, but deriving
## the stance from box height means repeating the height table in everyone who
## needs it.
func stance() -> EnemyBrain.Stance:
	return _brain.stance


## Bullet hit. Whoever shot gets the points — he decides that himself.
func take_bullet() -> void:
	kill()


## Kills the agent: by bullet, takedown, falling lamp or cab.
## [param crushed] — crushed from above: the body is struck downward.
## [param corpse_pose] — corpse pose from the takedown scene: the body goes into physics
## not here, but when the scene releases it ([member held]).
func kill(crushed: bool = false, corpse_pose: String = "") -> void:
	if _brain.is_dead() or _brain.is_emerging():
		return
	_crushed = crushed
	_corpse = corpse_pose
	_brain.kill()
	# The corpse lies until the end of the building (ADR-0037, decision 6) as a jointed body:
	# the agent himself leaves all layers, bullets fly through him. The takedown scene
	# drops the body itself when it releases it ([member held]).
	collision_layer = 0
	collision_mask = 0
	_shape.set_deferred("disabled", true)
	if laser != null:
		laser.put_out()
	if not _held:
		set_physics_process(false)
		# A lamp crushes — the body is struck from above.
		corpse.fall(velocity + (Vector3.DOWN * 3.0 if crushed else Vector3.ZERO))
	velocity = Vector3.ZERO
	Sounds.play(Sounds.AGENT_DEATH)
	died.emit(self)


func is_dead() -> bool:
	return _brain.is_dead()


## Whether the agent has come out of the doorway. Until he has, he is invulnerable.
func is_emerging() -> bool:
	return _brain.is_emerging()


## Takes the agent off the enemy layer while he is in the doorway.
##
## Not "armour" but the absence of a target: the bullet passes through, does not die and brings
## no points. That way invulnerability is visible to the eye — the shot simply flies past — and
## it need not be explained by a rule (ADR-0020, decision 3).
func _shield(value: bool) -> void:
	# Called every frame, while it changes twice in the agent's life: a needless
	# assignment is a call to the physics server for every living one.
	var on_layer := not value
	if get_collision_layer_value(ENEMY_LAYER) == on_layer:
		return
	set_collision_layer_value(ENEMY_LAYER, on_layer)


## Whether the agent sees Otto. Behind a door he is not there; in darkness he is noticeable only
## closer than [member BuildingRules.agent_dark_fire_range]; a lit one is seen as usual.
##
## Measured horizontally: otherwise an agent one floor below would count as blind where
## one standing on the same line sees.
func _sees(to_target: Vector2) -> bool:
	if _target.is_hidden() or _target_behind_a_wall:
		return false
	if not _target_in_the_dark:
		return true
	return absf(to_target.x) <= _building_rules().agent_dark_fire_range


## Returns the body to the play plane — for the same reason as with [Otto].
func _hold_the_plane() -> void:
	velocity.z = 0.0
	global_position.z = WorldSpace.PLAY_Z


## Height of the nearest bullet flying at the agent above his feet, m, or -1 if
## nothing is flying.
##
## Searched by the bullet group, not by the level's children: there are about three hundred
## children and at most four bullets on screen. The agent ignores his own bullets — he has
## no reason to dodge them, and their mask is the same for all agents.
func _incoming_height() -> float:
	var best := -1.0
	# Beyond 20 ROM px the agent does not notice a bullet (@05F5); the bullet is three times faster
	# than ROM, and the range grows with it — the time to dodge is the same (ADR-0037, decision 5).
	var nearest := Arcade.dodge_reach()
	for node in get_tree().get_nodes_in_group(Bullet.GROUP):
		var bullet := node as Bullet
		if bullet == null or bullet.collision_mask != Bullet.FROM_OTTO:
			continue
		# In rule coordinates, so that the whole measure below stays exactly as it
		# was tuned in 2D: there a bullet's y above the feet is negative.
		var to_bullet := WorldSpace.direction_to_plane(bullet.global_position - global_position)
		# Whether it flies at us — and whether it has already passed behind.
		#
		# The measure is not "from which side" but "how far it still has to us": a bullet
		# past the middle but not out of the extent is the most dangerous. While
		# it was counted by side, the agent straightened up at that very moment and caught it
		# with his own chest — the dodge ended in death by the same bullet.
		#
		# The extent is half the body width plus the whole bullet length: it passes the middle tail
		# first, and while the tail overlaps the chest, standing up is still not allowed.
		var closing := -to_bullet.x * bullet.direction
		if closing < -(_body_half_width() + bullet.half_length()):
			continue
		var reach := absf(to_bullet.x)
		if reach > nearest:
			continue
		# The agent dodges only a bullet in the ROM band above the floor (@05F5):
		# above and below it misses anyway.
		var over_floor := -to_bullet.y / Proportions.PX
		if over_floor < Arcade.DODGE_BAND_PX.x or over_floor > Arcade.DODGE_BAND_PX.y:
			continue
		nearest = reach
		# The agent's feet are zero, up is positive: a bullet's y is negative.
		best = -to_bullet.y
	return best


## Half the body width, m. Together with the bullet length ([method Bullet.half_length])
## gives the extent the bullet must leave before the agent straightens up.
func _body_half_width() -> float:
	return (_shape.shape as BoxShape3D).size.x * 0.5


## Fits the collision shape to the stance.
##
## The bottom of the shape stays on the floor, so both size and offset change:
## [CollisionShape3D] has its origin in the middle, and changing only the size would sink
## a crouching agent into the slab.
func _fit_shape() -> void:
	var box := _shape.shape as BoxShape3D
	var height := _brain.height()
	if is_equal_approx(box.size.y, height):
		return
	# The shape comes from the scene shared by all agents: editing it in place, we
	# would bend down everyone who shares it at once.
	var own := box.duplicate() as BoxShape3D
	own.size = Vector3(box.size.x, height, box.size.z)
	_shape.shape = own
	_shape.position.y = height * 0.5


## Whether there is nowhere to step: ahead is an opening or a wall the agent already hit.
##
## The wall is taken from the last [method CharacterBody3D.move_and_slide] step:
## having turned, the agent walks away from it, and on the next frame it no longer counts,
## so he does not jitter at the wall.
func _blocked_ahead() -> bool:
	return not _floor_ahead() or is_on_wall()


## Whether there is floor where the agent is about to step.
##
## Without this check he would walk off his own floor into a shaft or
## escalator opening: his mask is only for geometry, and a hole in the slab
## is no different to him from more floor.
func _floor_ahead() -> bool:
	_floor_probe.position.x = absf(_floor_probe.position.x) * signf(_brain.facing)
	# The ray updates at the start of the frame, and we have just moved it.
	_floor_probe.force_raycast_update()
	return _floor_probe.is_colliding()


## Moves stance heights from the building rules into [EnemyBrain]. Computed in one
## place so that the call order of [method _ready] and [method apply_rules] decides
## nothing — otherwise an agent configured before [method Node.add_child] would lose the numbers.
func _refresh_brain() -> void:
	var rules := _building_rules()
	_brain.kneel_height = rules.agent_kneel_height
	_brain.prone_height = rules.agent_prone_height


## The rules the agent lives by. One released by the level was given them, while
## one placed by hand — in a test or in the editor — gets the default
## values, the same as the default building.
func _building_rules() -> BuildingRules:
	if _rules == null:
		_rules = BuildingRules.new()
	return _rules


## Whether the agent is in frame: ROM has no fire range, the whole floor is on screen, and here
## the one the player sees can hit (ADR-0027, decision 3a). The frame of the rules, not of the
## camera: that one moves by wall-clock time and is wider on a wide window.
func _in_frame() -> bool:
	return _target.camera_view(true).has_point(WorldSpace.to_plane(global_position))


## Bullet launch height by stance: standing, crouching and lying — the ROM table.
func _shot_height() -> float:
	match _brain.stance:
		EnemyBrain.Stance.KNEEL:
			return Proportions.SHOT_LOW
		EnemyBrain.Stance.PRONE:
			return Proportions.SHOT_PRONE
		_:
			return shot_height


## How far the barrel is ahead of the feet, m: further for a lying one (ADR-0043, decision 16).
func _muzzle_reach() -> float:
	return Proportions.MUZZLE_PRONE if _brain.stance == EnemyBrain.Stance.PRONE else muzzle_offset


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)


## A turn on the floor holds the agent's feet, as it holds Otto's: the body turns
## over [constant MoveLocks.TURN_TIME], and all that time the agent stands.
func _turn_holds(delta: float, walking: bool) -> bool:
	_locks.tick(delta)
	if _brain.facing != _faced:
		if is_on_floor() and _faced != 0.0:
			_locks.turn()
		_faced = _brain.facing
	return walking and _locks.can_walk()


## The look for this frame: pose, side and walk progress. Arranged the same as Otto's —
## the only difference is the pose set: the agent does not crouch or jump, but he lies down.
func _update_look(delta: float) -> void:
	_shooting = maxf(_shooting - delta, 0.0)
	if _walking:
		_walk_phase = ActorPose.advance(_walk_phase, delta)
		_step_sound()
	else:
		_walk_phase = 0.0
		_stepped_on = -1
	_stance_sound()

	# The muzzle is where the bullet will leave from: both in the wind-up and in the shot
	# (ADR-0043, decision 16).
	var aiming := not _brain.is_dead() and (_shooting > 0.0 or _brain.is_winding_up())
	_body.aim_height = _shot_height() if aiming else NAN
	_body.aim_reach = _muzzle_reach()
	_body.show_pose(_pose())
	_body.set_walk_phase(_walk_phase)
	_body.face(_brain.facing)


## The agent's step — at his position and quieter than Otto's: you hear who walks nearby.
func _step_sound() -> void:
	var frame := int(_walk_phase)
	if frame == _stepped_on or frame == 1 or not is_on_floor():
		return
	_stepped_on = frame
	var sound := Sounds.STEP_SNOW if icy else step_sound
	Sounds.play_at(get_parent(), sound, global_position, STEP_REACH, STEP_DB)


## The agent crouches or lies down from a bullet — a rustle of clothes.
func _stance_sound() -> void:
	var now := _brain.stance
	if now == _heard_stance:
		return
	_heard_stance = now
	if now != EnemyBrain.Stance.STAND and not _brain.is_dead():
		Sounds.play_at(get_parent(), Sounds.CROUCH, global_position, STEP_REACH)


func _pose() -> String:
	if _brain.is_dead() and not _corpse.is_empty():
		return _corpse
	# Wind-up is the shooting pose: the pistol is raised while the laser is lit (ADR-0037,
	# decision 5). The agent has no falling pose: a ragdoll drops the killed one
	# ([Corpse], ADR-0043, decision 12).
	return ActorPose.of_agent(
		_brain.is_dead(),
		_walking,
		_crushed,
		false,
		_shooting > 0.0 or _brain.is_winding_up(),
		_walk_phase,
		_brain.stance
	)


## Aim laser: lit while the agent winds up, from the barrel at the height of the future
## bullet up to whatever it will hit.
func _show_the_aim() -> void:
	if not _brain.is_winding_up():
		laser.put_out()
		return
	laser.position = Vector3(_brain.facing * _muzzle_reach(), _shot_height(), 0.0)
	laser.reach = Bullet.RANGE
	laser.shot_in = _brain.wind_up_left()
	laser.shot_speed = _shot_speed()
	laser.aim(_brain.facing)


## This agent's bullet speed, m/s: by building skill, a step faster in alarm
## (@463D), three times faster than ROM (ADR-0037, decision 5).
func _shot_speed() -> float:
	return Arcade.agent_shot_speed(_skill, _alarmed)


func _fire() -> void:
	_shooting = SHOOT_POSE_TIME
	# His own shot, at the agent's position: by ear it is clear who fired (ADR-0052).
	Sounds.play_at(get_parent(), Sounds.ENEMY_SHOT, global_position, SHOT_REACH)
	var bullet := BULLET_SCENE.instantiate() as Bullet
	bullet.direction = _brain.facing
	bullet.speed = _shot_speed()
	bullet.collision_mask = Bullet.FROM_ENEMY
	bullet.hit_target.connect(_on_bullet_hit)
	get_parent().add_child(bullet)
	var from := global_position + Vector3(0.0, _shot_height(), 0.0)
	var muzzle := from + Vector3(_brain.facing * _muzzle_reach(), 0.0, 0.0)
	bullet.global_position = Bullet.spawn_point(get_world_3d(), from, muzzle)
	bullet.strike_point_blank()
	_bullet = bullet


## Hit by his own bullet. Nobody gets points for Otto — he simply dies.
func _on_bullet_hit(target: Node3D) -> void:
	var victim := target as Otto
	if victim == null:
		return
	if not victim.is_dead() and not victim.invulnerable:
		# Who fired and from where — for the run log.
		victim.set_meta(&"shooter", RunLog.at(self))
		victim.set_meta(&"death_cause", "bullet")
		RunLog.write(
			"hit_otto",
			{"shooter": RunLog.at(self), "otto": RunLog.at(victim), "stance": _brain.stance}
		)
	victim.kill()
