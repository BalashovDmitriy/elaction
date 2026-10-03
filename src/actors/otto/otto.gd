class_name Otto
extends CharacterBody3D

## The player: agent Otto.
##
## Responsible for physics, the collision shape and the look. The decision about what
## state he is in is made by [OttoStateMachine].
##
## Lives in the play plane: Z is locked to [constant WorldSpace.PLAY_Z] and
## returns there after every physics step (ADR-0021, decision 1). Otto will not walk
## into the depth: depth is a property of the picture, not of movement.

## Otto has died: from a bullet, a fall of more than one floor, or under a cab.
signal died

const BULLET_SCENE := preload("res://src/systems/combat/bullet.tscn")

## How long the shot pose holds, s. The shot is instant, but it needs to be seen.
const SHOOT_POSE_TIME: float = 0.18

## How long Otto falls before lying down: death is two poses (ADR-0011, item 12).
const FALLING_TIME: float = 0.3

## How long Otto is invulnerable after returning to the game, s.
##
## He returns to the floor where he died, and the agent who killed him has not gone
## anywhere and stands in his zone of fire: without a breather the second death comes a
## quarter second after the first, and three lives burn out in one spot (ADR-0014,
## item 6).
const RESPAWN_GRACE: float = 1.5

## How often invulnerable Otto blinks, times per second. Blinking is the only way the
## breather shows itself: without it the player does not know it existed at all.
const GRACE_BLINKS: float = 8.0

## How far Otto can move between two of his physics frames, m, and it still is not
## a teleport. He moves by himself only within his own frame; between
## frames he is moved by others (the level, a test, the capture tool), and such a move
## is not a fall: without this, being placed one floor lower would kill him for nothing.
const TELEPORT_GAP: float = 0.5

## How long to stay in the air for a floor contact to be a landing, s.
## A jump lasts about a second, and a frame without support on a cab going down is one.
const LANDING_AIR_TIME: float = 0.15
## Otto's look during a ride ([member ride_look]): hangs on the rope, walks the steps.
const LOOK_ROPE := "rope"
const LOOK_WALK := "walk"
## Goes into a red door into the depth and comes out of it (ADR-0043, decision 4).
const LOOK_DOOR_IN := "door_in"
const LOOK_DOOR_OUT := "door_out"
## In the helicopter doorway and on its threshold: the pose, depth and turn are set by
## the intro ([member ride_pose]).
const LOOK_HELI := "heli"
## How far into the opening Otto goes, m: out of the play plane behind the wall.
const DOOR_WALK_DEPTH: float = 1.2
## Swinging on the rope: amplitude, radians, and frequency, rad/s.
const ROPE_SWAY: float = 0.05
const ROPE_SWAY_RATE: float = 2.2

## Buttons whose press may be spent on skipping the intro ([method ride]).
const PRESS_ACTIONS: Array[StringName] = [&"jump", &"shoot"]

## Walking and the bullet follow the ROM: 2 and 8 px per logic tick (ADR-0027, decision
## 4); the bullet is three times faster than in the ROM ([constant Arcade.BULLET_PACE],
## ADR-0037, decision 5).
@export var walk_speed: float = Arcade.speed(Arcade.WALK_PX)
## The jump per the ROM: feet +25 px (1.88 m) over 14 ticks (0.95 s), table_42E2.
## Jump height = jump_speed squared divided by 2 · gravity: 7.9 and 16.6
## give the same 1.88 m over the same 0.95 s. Before M18d the jump was 2.4 m by physics.
@export var jump_speed: float = 7.9
@export var gravity: float = 16.6
@export var bullet_speed: float = Arcade.bullet_speed(Arcade.OTTO_BULLET_PX)
## Where the bullet comes out, from the feet. Crouching, Otto shoots lower, and his shot
## passes where a standing enemy cannot jump over it.
##
## The numbers are in [Proportions]: the standing one is from a frame of the original;
## it does not reach a lamp under the ceiling even from a jump: Otto hits the ceiling
## with his head first (ADR-0026, decision 5).
@export var shot_height_standing: float = Proportions.SHOT_HIGH
@export var shot_height_crouching: float = Proportions.SHOT_LOW
@export var muzzle_offset: float = Proportions.MUZZLE
@export var max_fall_speed: float = 12.6
## In the original Otto crouches in place. Kept as a switch for tuning.
@export var can_move_while_crouching: bool = false

## Whether Otto stands on a snowy deck: set by the roof snow ([SnowTracks]).
var icy: bool = false

## What a step sounds like: the building sets the floor, the hotel carpet, the stone of
## the office and the roof.
var step_sound: String = Sounds.STEP_CONCRETE
## The building's floor step, m: someone falling more than a floor dies (ADR-0037,
## decision 7). Set by the level from its rules; by default, a standard floor.
var floor_height: float = Proportions.FLOOR
## Whether Otto can be hit right now so that he dies. Not behind a door or in its
## doorway, on an escalator, while arriving on the roof: everywhere input is off
## ([constant OttoStateMachine.State.RIDE]), and during the breather after returning to
## the game. Agents hold their fire by this: a bullet through an invulnerable one would
## read as a bug, not as a rule. A property, like [member invulnerable]: this way it is
## next to it and does not multiply the node's methods.
var hittable: bool:
	get:
		return _grace <= 0.0 and not _states.is_world_driven()
## Whether the breather after returning to the game is on: a bullet hits Otto but does
## not wound. By this [Bullet] decides whether to splatter blood. A property, not a
## method: the bullet asks it through [method Object.get] without knowing Otto's class.
var invulnerable: bool:
	get:
		return _grace > 0.0

## The takedown scene Otto is in now (ADR-0040); null means none. While
## it runs, Otto does not obey input and does not move by himself: the director sets his
## poses and place. The director sets and clears it. A property, like [member hittable]:
## the node's methods have hit the linter limit.
var takedown: TakedownScene:
	get:
		return _takedown
	set(director):
		_takedown = director
		velocity = Vector3.ZERO
		_air_speed = 0.0
		_rest_here()
		if director != null:
			_body.face(_facing, true)
## Otto's figure: the scene director sets its poses and tempo.
var figure: FigureRig:
	get:
		return _body
## Takedown scene draw. The level seeds it from the building seed: the scene's length and
## the moment of the agent's death depend on it, and an unseeded draw would make the bot
## run unrepeatable (`docs/testing.md`, a rule from M18b).
var takedown_rng := RandomNumberGenerator.new()
## A jointed body ([Corpse]): built at birth, falls at the moment of death and
## gets up on returning to the game (ADR-0043, decision 12).
var corpse: Corpse = null
## How Otto looks while he is being carried ([method ride]): set by whoever carries him,
## before [code]ride(true)[/code]: the run log writes it at the start of the ride
## (ADR-0043, decisions 1 and 2). On the rope he hangs by his hands, on the escalator he
## walks the steps. Empty means he stands.
var ride_look: String = ""
## Where Otto looks while walking on the escalator: −1 left, +1 right, 0 means where he
## was looking.
var ride_facing: float = 0.0
## How far Otto has gone into the door opening: 0 at the mat, 1 inside. Set by the door
## following the leaf travel.
var ride_progress: float = 0.0
## The building intro (ADR-0052, decision 6), [constant LOOK_HELI]: which pose to
## show, how deep the figure is from the play plane, m (minus is farther from the
## camera), and how much it is turned toward the camera, 0–1.
var ride_pose: String = ""
var ride_depth: float = 0.0
var ride_turn: float = 0.0

var _states := OttoStateMachine.new()
## One input snapshot for the whole lifetime: it is reread, not created anew.
var _snapshot := OttoInput.new()
var _posed_state := OttoStateMachine.State.IDLE
## Horizontal velocity in flight, m/s. Set by the push-off and does not change in the
## air: in the ROM the jump direction is chosen at the start (@43FA), but
## turning to face the other way in flight is allowed (@42A7).
## The precipitation catcher on the body ([Shelter]).
var _shelter: GPUParticlesCollisionBox3D = null
var _air_speed: float = 0.0
## The cab Otto is inside now. On the cab roof it is not set:
## the elevator is not controlled from there (ADR-0004, item 3).
var _car: ElevatorCar = null
## Height difference between the standing and crouching shapes: this much room is needed
## overhead.
var _headroom: float = 0.0
## Where Otto looks: -1 left, +1 right. His bullets fly there too.
var _facing: float = 1.0
## How much Otto is turned with his back to the camera, 0..1: getting into the car, he
## turns toward it instead of stepping sideways into the depth ([method turn_into_depth]).
var _depth_turn: float = 0.0
## Walk phase: the integer part is the frame number out of three.
var _walk_phase: float = 0.0
## How much longer to hold the shot pose and the fall pose, s.
var _shooting: float = 0.0
var _falling_over: float = 0.0
## Crushed by a cab: such a death has its own pose.
var _crushed: bool = false
## On which walk frame the step has already sounded.
var _stepped_on: int = -1
var _gun := Gun.new()
## Height of the last support: the fall depth is counted from it, m of scene.
##
## From the support, not from the top point of the flight: your own jump adds nothing
## to the fall: you can jump one floor down both from a run and from a jump.
var _support_y: float = 0.0
## Whether Otto stood on a support last frame: a landing is a transition.
var _was_grounded: bool = true
## How long Otto has already been in the air, s: only a real flight counts as landing,
## not a frame without support on the roof of a cab going down.
var _air_time: float = 0.0
## Turn and landing pauses (ADR-0039, decision 4).
var _locks := MoveLocks.new()
## How much longer to show the landing, s.
var _landing: float = 0.0
## Whether jump was pressed during recovery: it will fire when recovery ends.
var _jump_waiting: bool = false
var _takedown: TakedownScene = null
## Which scene was the previous one: the same one does not repeat in a row.
var _last_scene: String = ""
## Where Otto ended the previous physics frame: a teleport shows by this.
var _last_position := Vector3.ZERO
## How much longer the breather after returning to the game lasts, s.
var _grace: float = 0.0
## Buttons whose press was spent on skipping the intro ([method ride]):
## while they are held, Otto does not hear them; once released, he hears them again.
var _spent_actions: Array[StringName] = []

@onready var _standing_shape: CollisionShape3D = $StandingShape
@onready var _crouching_shape: CollisionShape3D = $CrouchingShape
@onready var _body: FigureRig = $Body
@onready var _camera: SideCamera = $Camera


## Body shapes are set by [Proportions], not by the scene: right after the scene is
## assembled, even before the tree. Tests read the shapes from a fresh copy without
## adding it to the tree, and they must see the same numbers as the game.
func _notification(what: int) -> void:
	if what != NOTIFICATION_SCENE_INSTANTIATED:
		return
	var depth := WorldSpace.BODY_DEPTH
	var width := Proportions.BODY_WIDTH
	Proportions.fit_box($StandingShape as CollisionShape3D, Vector3(width, Proportions.BODY, depth))
	Proportions.fit_box(
		$CrouchingShape as CollisionShape3D, Vector3(width, Proportions.CROUCH, depth)
	)


func _ready() -> void:
	# Rain and snow die on the head and shoulders (ADR-0054).
	_shelter = Shelter.over(self, _cover())
	add_to_group(Footing.OTTO_GROUP)
	var standing := _shape_size(_standing_shape)
	var crouching := _shape_size(_crouching_shape)
	_headroom = standing.y - crouching.y
	_rest_here()
	_camera.follow(self)
	_repose()
	corpse = Corpse.new(self, _body)


## Body size under precipitation: full height or crouched.
func _cover() -> Vector3:
	var tall := Proportions.CROUCH if is_crouching() else Proportions.BODY
	return Vector3(Proportions.BODY_WIDTH, tall, WorldSpace.BODY_DEPTH)


func _physics_process(delta: float) -> void:
	# The precipitation catcher follows the pose; it does not hold a dead one: the body lies
	# on the floor.
	if _shelter != null:
		_shelter.visible = not is_dead()
		Shelter.fit(_shelter, _cover())
	if _takedown != null:
		# In a scene Otto stands where he stood: the director controls his coordinate
		# and pose. He is vulnerable: a bullet will find him (ADR-0040, decision 5).
		velocity = Vector3.ZERO
		_rest_here()
		return
	_grace = maxf(_grace - delta, 0.0)
	if global_position.distance_to(_last_position) > TELEPORT_GAP:
		# Moved by the level, a test or a capture: we count from the new point.
		_rest_here()
	_snapshot.read_actions()
	if not _spent_actions.is_empty():
		_forget_spent_presses()
	if _car != null:
		# In a cab "up/down" drive it, and crouching inside is not possible.
		_car.drive(vertical_intent())
		_snapshot.crouch = false

	_locks.tick(delta)
	_landing = maxf(_landing - delta, 0.0)
	_hold_the_feet()

	# The state machine needs velocity in rules coordinates, where Y is down:
	# falling is positive for it, as it was in 2D.
	var state := _states.update(_snapshot, is_on_floor(), -velocity.y, _can_stand_up())

	# While someone else has taken Otto (an escalator carries him or a door hid him),
	# physics is silent: that one controls the coordinate, not physics.
	if state == OttoStateMachine.State.RIDE or state == OttoStateMachine.State.INDOORS:
		velocity = Vector3.ZERO
		# He is carried, not dropped: the fall from this height does not accumulate.
		_rest_here()
		_apply_pose(state)
		_update_look(delta)
		return

	if _snapshot.shoot_pressed and state != OttoStateMachine.State.DEAD:
		# Right next to an agent the fire button does a takedown, from afar it shoots (ADR-0040).
		var target := _reachable_agent(state)
		if target != null:
			_take_down(
				target,
				Takedown.side_of(global_position.x, target.global_position.x, target.facing())
			)
			return
		if _gun.can_fire():
			_fire()

	# The jump impulse is given in the same frame while the body still stands on the floor,
	# so gravity does not eat it in this frame.
	if _states.just_entered(OttoStateMachine.State.JUMP) and is_on_floor():
		velocity.y = jump_speed

	if is_on_floor() or state == OttoStateMachine.State.DEAD:
		var wanted := _horizontal_speed(_snapshot, state)
		# From the velocity the body actually moved with (after the wall and the cab
		# side), not from the intended one: otherwise someone pressed against a wall on snow
		# would keep "braking" into it for a quarter second before moving back.
		_air_speed = Footing.step(velocity.x, wanted, icy and is_on_floor(), delta)
	velocity.x = _within_the_car(_air_speed)
	if not is_on_floor():
		velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)

	move_and_slide()
	_hold_the_plane()

	_track_fall()
	if _takedown != null:
		# Landed on an agent: the director already sets the pose, his own would override it.
		return
	_last_position = global_position
	_apply_pose(_states.state)
	_update_look(delta)


## Kills Otto: a bullet, a fall of more than a floor, crushing by a cab.
##
## During the breather after returning to the game it does nothing: the invulnerability
## covers all causes, not only bullets: reviving under a cab is just as
## annoying as under a shot.
##
## [param crushed]: crushed by a cab; such a death has its own pose, in the original
## the crushed one is shown as a separate picture (ADR-0011, item 12).
func kill(crushed: bool = false) -> void:
	if _grace > 0.0:
		return

	if _states.is_dead():
		return
	_crushed = crushed
	if crushed:
		# Only a real death: during the breather the cab calls this every physics
		# step while Otto is under it, and the crush would sound like a volley.
		Sounds.play(Sounds.CRUSH)
		set_meta(&"death_cause", "crushed")
	elif not has_meta(&"shooter"):
		set_meta(&"death_cause", "fall")
	_states.kill()
	corpse.fall(velocity)
	_falling_over = FALLING_TIME
	Sounds.play(Sounds.OTTO_DEATH)
	Sounds.play(Sounds.DEATH_JINGLE)
	_repose()
	died.emit()


func is_dead() -> bool:
	return _states.is_dead()


## Whether Otto stands on his own feet: not in a cab, not on an escalator, not behind a
## door. Until then no more than one agent comes out onto the floor (@59F4).
func is_on_foot() -> bool:
	return _car == null and not _states.is_world_driven()


## Whether Otto is crouching: an agent then shoots from a crouch (@1CD8).
func is_crouching() -> bool:
	return _states.state == OttoStateMachine.State.CROUCH


## Whether Otto has hidden behind a door. He is not outside, and agents cannot see him:
## in the original entering a door means throwing them off the trail (ADR-0023,
## decision 8).
func is_hidden() -> bool:
	return _states.state == OttoStateMachine.State.INDOORS


## Removes from the input snapshot the presses spent on the skip while the button is held.
func _forget_spent_presses() -> void:
	for action: StringName in _spent_actions.duplicate():
		if not Input.is_action_pressed(action):
			_spent_actions.erase(action)
		elif action == &"jump":
			_snapshot.jump_pressed = false
		else:
			_snapshot.shoot_pressed = false


## The turn and the landing hold the legs (ADR-0039, decision 4): the input snapshot
## loses the step while the body turns, and the jump while Otto recovers.
## The facing is taken before that, from what the player pressed.
##
## A dead one does not turn: a corpse lies on the side it fell on; poking
## the arrows would spin the body during the countdown to returning to the game. Input
## does not touch someone being carried or hidden at all. In the air turning to face is
## allowed without a pause (ROM @42A7): the flight velocity does not change from it.
func _hold_the_feet() -> void:
	if _states.is_dead() or _states.is_world_driven():
		return
	if absf(_snapshot.move) > OttoStateMachine.MOVE_THRESHOLD:
		var side := signf(_snapshot.move)
		if side != _facing and is_on_floor():
			_locks.turn()
		_facing = side
	if not _locks.can_walk():
		_snapshot.move = 0.0
	# A jump pressed during recovery is not lost but waits for its end:
	# a 0.15 s pause is shorter than reaction time, and a lost press would read as
	# a button that did not work. Released the button earlier: changed one's mind.
	if not _locks.can_jump():
		_jump_waiting = _jump_waiting or _snapshot.jump_pressed
		_snapshot.jump_pressed = false
	elif _jump_waiting:
		_snapshot.jump_pressed = Input.is_action_pressed(&"jump") or _snapshot.jump_pressed
		_jump_waiting = false


## Returns Otto to the game after death. Putting him in place is the level's job,
## so this is called after the move: the support the fall is counted from
## is taken from here.
##
## Without resetting [member _support_y] someone who fell into a shaft would come back
## with someone else's fall depth behind him and die for nothing.
func revive() -> void:
	_crushed = false
	for key: StringName in [&"death_cause", &"shooter"]:
		if has_meta(key):
			remove_meta(key)
	corpse.rise()
	_states.reset()
	_locks.clear()
	_jump_waiting = false
	_landing = 0.0
	velocity = Vector3.ZERO
	_rest_here()
	_grace = RESPAWN_GRACE
	# The camera arrives at the revived one at once: otherwise for half a second of
	# smoothing the player looks at where he was killed.
	_camera.snap_to(Vector2(global_position.x, global_position.y))
	_repose()


## Vertical intent over the last frame. By it the cab, the escalator and the door
## understand where they are asked to go, without reading [Input] themselves.
##
## While Otto is not his own (dead, riding an escalator or sitting behind a door) he
## asks for nothing: otherwise he would keep driving the cab and asking to enter a door
## from where he no longer is. Such a state can be cleared only by whoever set it, not
## by the player. The same in a takedown scene: the input snapshot is not reread in it,
## and a frozen "up" would let Otto into a door in the middle of the scene.
func vertical_intent() -> float:
	return 0.0 if _states.is_world_driven() or _takedown != null else _snapshot.vertical


## How far Otto is below his last support, m. On the support it is zero.
func fall_height() -> float:
	return maxf(_support_y - global_position.y, 0.0)


## How high the jump lifts, m.
func jump_height() -> float:
	return jump_speed * jump_speed / (2.0 * gravity)


## Otto has hidden behind a door or the door has let him out, after 70 ROM ticks,
## you cannot leave earlier (ADR-0038, decision 2). While inside, he is not outside and
## the player's input has no effect; he hides the same way while the car at the exit
## takes him away.
func stay_indoors(inside: bool) -> void:
	if inside:
		_states.go_indoors()
	else:
		_states.come_out()
	_repose()


## Turns Otto with his back to the camera by the fraction [param weight]: 0 is along the
## floor where he looks, 1 is facing into the depth. This is how he gets into the car at
## the exit.
func turn_into_depth(weight: float) -> void:
	_depth_turn = clampf(weight, 0.0, 1.0)


## Otto stepped onto an escalator or off it: while riding, the player's input has no
## effect, and the escalator controls the position. The intro rope uses
## the same: Otto is carried on it too.
##
## [param presses_spent]: on release, do not hear the jump and shot that are
## held right now until they are released. This is how the intro releases when it was
## skipped with a jump or a shot: otherwise the same press would also reach Otto:
## a skip with a shot would shoot, and a skip with a jump would jump. It is the
## press that is muted, not the physics step: the intro sees the button by its own
## "released, pressed" edge, and Otto by [method Input.is_action_just_pressed], and the
## step in which each sees the press does not have to coincide.
func ride(on: bool, presses_spent: bool = false) -> void:
	RunLog.write("ride", {"on": on, "look": ride_look, "at": RunLog.at(self)})
	if on:
		_states.ride()
	else:
		_states.stop_riding()
		# From the rope Otto stands on the roof with the landing clip (ADR-0043, decision 1).
		if ride_look == LOOK_ROPE:
			_landing = FigurePoses.LAND_SHOW
			Sounds.play(Sounds.LAND)
		ride_look = ""
		ride_facing = 0.0
		ride_progress = 0.0
		ride_pose = ""
		ride_depth = 0.0
		ride_turn = 0.0
	if presses_spent:
		for action: StringName in PRESS_ACTIONS:
			if Input.is_action_pressed(action) and not _spent_actions.has(action):
				_spent_actions.append(action)
	_repose()


## Otto entered a cab and now controls it.
func board(car: ElevatorCar) -> void:
	_car = car


## Otto left the cab.
func leave(car: ElevatorCar) -> void:
	if _car == car:
		_car = null


## Whether Otto rides inside a cab. Riding on the roof does not count.
func is_riding() -> bool:
	return _car != null


## The body's current velocity, in rules coordinates.
##
## Together with [method is_grounded] it forms the public interface for observers:
## they depend on Otto's API, not on the fact that inside he is a [CharacterBody3D] and
## that the scene's Y points up.
func motion() -> Vector2:
	return WorldSpace.direction_to_plane(velocity)


## Whether Otto stands on a surface.
func is_grounded() -> bool:
	return is_on_floor()


## What falls into the frame now, in rules coordinates.
##
## The camera follows Otto but rests against the building's edges. So the visible area
## is computed by whoever has the camera, not by whoever needs it: from outside one
## would have to ask for the middle, the frame size and the window size.
##
## [param for_combat]: the frame combat decides by: an agent in it reaches Otto
## (ADR-0027, decision 3a). The same one the player sees, but it depends neither on the
## window nor on camera smoothing; see [method SideCamera.rule_view].
func camera_view(for_combat: bool = false) -> Rect2:
	return _camera.rule_view() if for_combat else _camera.view()


## Where Otto looks: -1 left, +1 right. His next bullet will go there too.
func facing() -> float:
	return _facing


## Camera bounds in rules coordinates. [param snap]: move into place at once;
## without it the camera reaches the new bounds by smoothing (the end of the intro).
func apply_camera_bounds(bounds: Rect2, snap: bool = true) -> void:
	_camera.apply_bounds(bounds, snap)


## Returns the body to the play plane.
##
## [method move_and_slide] can push the body out along Z if it has touched an angled face
## even with its edge, and such a shift is not visible in the side frame at all:
## Otto simply stops reaching what he used to reach.
func _hold_the_plane() -> void:
	velocity.z = 0.0
	global_position.z = WorldSpace.PLAY_Z


## Fires a bullet. The flight height is set by the pose: crouching, Otto shoots lower.
func _fire() -> void:
	_shooting = SHOOT_POSE_TIME
	Sounds.play(Sounds.SHOT)
	var crouching := _states.state == OttoStateMachine.State.CROUCH
	var height := shot_height_crouching if crouching else shot_height_standing

	var bullet := BULLET_SCENE.instantiate() as Bullet
	bullet.direction = _facing
	bullet.speed = bullet_speed
	bullet.collision_mask = Bullet.FROM_OTTO
	bullet.hit_target.connect(_on_bullet_hit)
	# The gun itself keeps the count: a bullet ends both on a hit and at the range limit.
	bullet.tree_exited.connect(_gun.bullet_spent)
	get_parent().add_child(bullet)
	var from := global_position + Vector3(0.0, height, 0.0)
	var muzzle := from + Vector3(_facing * muzzle_offset, 0.0, 0.0)
	bullet.global_position = Bullet.spawn_point(get_world_3d(), from, muzzle)
	_gun.fired()


func _on_bullet_hit(target: Node3D) -> void:
	# The bullet does not sort out what it hit; the shooter does.
	var lamp := target as Lamp
	if lamp != null:
		lamp.shoot_down()
		return

	var agent := target as Enemy
	if agent == null or agent.is_dead():
		return
	RunLog.write("hit_agent", {"at": RunLog.at(agent), "otto": RunLog.at(self)})
	agent.take_bullet()
	_award_for(agent, GameState.ENEMY_SHOT_SCORE)


## Awards points for a killed agent: in darkness they are worth more.
func _award_for(agent: Enemy, base: int) -> void:
	var points := GameState.kill_score(base, agent.is_in_the_dark())
	GameState.instance().add_score(points, agent.global_position + GameState.OVER_HEAD)


## The agent Otto reaches at close range (ADR-0040), or null. A takedown is done standing
## on one's own feet (not in a cab, not crouching, not in flight), on a living agent who
## has come out of a door; of several, the nearest.
func _reachable_agent(state: OttoStateMachine.State) -> Enemy:
	if _car != null or not is_on_floor() or Takedown.rides_a_car(self):
		return null
	if state != OttoStateMachine.State.IDLE and state != OttoStateMachine.State.WALK:
		return null
	var me := Vector2(global_position.x, global_position.y)
	var best: Enemy = null
	var best_gap := INF
	for node: Node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var agent := node as Enemy
		if agent == null or not agent.takedown_ready:
			continue
		var at := Vector2(agent.global_position.x, agent.global_position.y)
		if not Takedown.can_reach(me, _facing, at):
			continue
		var gap := absf(at.x - me.x)
		if gap < best_gap:
			best_gap = gap
			best = agent
	return best


## Landed right next to an agent: jumped on him (ADR-0042, decision 9): the scene starts
## by itself, without a button. A landing only after a real flight: a frame without
## support on the roof of a cab going down does not count.
##
## Someone landing in a cab or on its roof does not jump on an agent, for the same reason
## he does not do a takedown with the button ([method _reachable_agent]): the scene
## freezes both, and the cab drives away from under the pair (M24d code review).
func _land_on_a_target() -> bool:
	# Killed in flight, he falls as a body instead of jumping on someone.
	if _states.is_dead() or _air_time < LANDING_AIR_TIME:
		return false
	if _car != null or Takedown.rides_a_car(self):
		return false
	var feet := Vector2(global_position.x, global_position.y)
	var agent: Enemy = null
	var best_gap := INF
	for node: Node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var candidate := node as Enemy
		if candidate == null or not candidate.takedown_ready:
			continue
		var at := Vector2(candidate.global_position.x, candidate.global_position.y)
		if Takedown.lands_on(feet, at) and absf(at.x - feet.x) < best_gap:
			best_gap = absf(at.x - feet.x)
			agent = candidate
	if agent == null:
		return false
	# Facing the agent: the scene places him in front of Otto.
	var towards := agent.global_position.x - global_position.x
	if not is_zero_approx(towards):
		_facing = signf(towards)
	_take_down(agent, Takedown.Side.ABOVE)
	return true


func _take_down(agent: Enemy, side: int) -> void:
	var scene := Takedown.pick(side, _last_scene, takedown_rng)
	_last_scene = scene.name
	TakedownScene.play(self, agent, scene)


## Whether there is room overhead to straighten up from a crouch.
##
## Checked with the crouching shape: if it can rise by the height difference,
## the standing one will fit too. Without this check the full shape would be switched on
## unconditionally and push Otto through the slab (M1 debt).
func _can_stand_up() -> bool:
	if _states.state != OttoStateMachine.State.CROUCH:
		return true
	return not test_move(global_transform, Vector3(0.0, _headroom, 0.0))


## Tracks the fall: on a support remembers its height, and after landing decides
## whether he has died (ADR-0037, decision 7).
##
## One rule for the floor, the cab roof and the shaft bottom: all of it is support
## underfoot. In a cab the support rides with Otto: the cab floor is under him every
## frame, and descending in it does not accumulate as a fall, even if the engine loses
## the floor underfoot for a frame.
func _track_fall() -> void:
	var grounded := is_on_floor()
	if grounded and not _was_grounded:
		if ShaftHazards.is_deadly_fall(fall_height(), floor_height):
			kill()
		elif _land_on_a_target():
			pass
		elif _air_time >= LANDING_AIR_TIME:
			_locks.land()
			_landing = FigurePoses.LAND_SHOW
			Sounds.play(Sounds.LAND)
	_air_time = 0.0 if grounded else _air_time + get_physics_process_delta_time()
	_was_grounded = grounded
	if grounded or _car != null:
		_support_y = global_position.y


## Treats the place where Otto is now as support: he was put or carried here.
func _rest_here() -> void:
	_support_y = global_position.y
	_last_position = global_position
	_was_grounded = true
	# A flight before a move or a ride does not count: otherwise a step from an escalator
	# into the air would be appended to an old jump and end in a landing.
	_air_time = 0.0


func _horizontal_speed(input: OttoInput, state: OttoStateMachine.State) -> float:
	if state == OttoStateMachine.State.DEAD:
		return 0.0
	if state == OttoStateMachine.State.CROUCH and not can_move_while_crouching:
		return 0.0
	if absf(input.move) <= OttoStateMachine.MOVE_THRESHOLD:
		return 0.0
	# Movement is arcade-style, discrete: stick tilt does not change the speed.
	return signf(input.move) * walk_speed


## Speed [param speed] in a cab: you can walk in it even while it moves, as in the ROM
## (ADR-0044, decision 4), but you can step out only while a floor is near: otherwise
## the side is a wall.
##
## Both on the ground and in the air: the flight velocity is taken from the ground, and
## a running jump in a moving cab would otherwise carry Otto through the side into the
## shaft (M24h code review).
func _within_the_car(speed: float) -> float:
	if _car == null or is_zero_approx(speed) or _car.can_step_out():
		return speed
	return _up_to_the_car_wall(speed)


## Speed [param speed], trimmed so that this frame's step ends at the
## cab side, not beyond it.
func _up_to_the_car_wall(speed: float) -> float:
	var towards := signf(speed)
	var room := (_car.width() - Proportions.BODY_WIDTH) * 0.5
	var left := room - (global_position.x - _car.global_position.x) * towards
	var step := get_physics_process_delta_time()
	if left <= 0.0 or step <= 0.0:
		return 0.0
	return towards * minf(absf(speed), left / step)


## Rebuilds the pose right now without waiting for the next [method _physics_process].
##
## Needed by those who change Otto's state from outside, in the middle of a frame:
## collision shapes are switched on deferred, and without this Otto would spend the
## first frame after a door bodiless: [method move_and_slide] would find no floor under
## him.
func _repose() -> void:
	_apply_pose(_states.state)


func _apply_pose(state: OttoStateMachine.State) -> void:
	# The pose is a function of state: we rebuild it only on transitions, otherwise
	# every physics frame would drop two deferred calls into the queue.
	if state == _posed_state:
		return
	var was := _posed_state
	_posed_state = state
	_state_sound(was, state)

	var crouching := state == OttoStateMachine.State.CROUCH
	# Behind a door Otto does not exist at all, on an escalator he is in view, but he cannot
	# be hit in either place: "neither kill nor be killed" (ADR-0007, item 7).
	var hidden := state == OttoStateMachine.State.INDOORS
	var untouchable := hidden or state == OttoStateMachine.State.RIDE
	_standing_shape.set_deferred("disabled", untouchable or crouching)
	_crouching_shape.set_deferred("disabled", untouchable or not crouching)
	_body.visible = not hidden


## The pose Otto is playing right now.
##
## It is chosen by [ActorPose], the same one that chose the sprite, and performed by
## [FigureRig] on the skeleton: it interpolates between poses itself (ADR-0022,
## decision 2).
func _pose() -> String:
	if _states.state == OttoStateMachine.State.RIDE:
		if ride_look == LOOK_ROPE:
			return ActorPose.ROPE
		if ride_look == LOOK_HELI:
			return ride_pose if not ride_pose.is_empty() else "idle"
		if ride_look in [LOOK_WALK, LOOK_DOOR_IN, LOOK_DOOR_OUT]:
			return ActorPose.walk_frame(_walk_phase)
	return ActorPose.of_otto(
		_states.state, _crushed, _falling_over > 0.0, _shooting > 0.0, _walk_phase, _landing > 0.0
	)


## Body opacity: invulnerable Otto blinks, in the other frames he is solid.
func _grace_alpha() -> float:
	if _grace <= 0.0:
		return 1.0
	var phase := fmod(_grace * GRACE_BLINKS, 1.0)
	return 1.0 if phase < 0.5 else 0.25


## What changes every frame rather than on transitions: walk progress, pose timers and
## the breather blinking.
func _update_look(delta: float) -> void:
	_shooting = maxf(_shooting - delta, 0.0)
	_falling_over = maxf(_falling_over - delta, 0.0)
	var riding := _states.state == OttoStateMachine.State.RIDE
	if _states.state == OttoStateMachine.State.WALK:
		_walk_phase = ActorPose.advance(_walk_phase, delta)
		_step_sound()
	elif riding and ride_look in [LOOK_WALK, LOOK_DOOR_IN, LOOK_DOOR_OUT]:
		_walk_phase = ActorPose.advance(_walk_phase, delta)
	else:
		_walk_phase = 0.0
		_stepped_on = -1

	if riding and ride_facing != 0.0:
		_facing = ride_facing
	# The muzzle is where the bullet comes out from (ADR-0043, decision 16).
	var crouching := _states.state == OttoStateMachine.State.CROUCH
	var aim := shot_height_crouching if crouching else shot_height_standing
	_body.aim_height = aim if _shooting > 0.0 else NAN
	_body.aim_reach = muzzle_offset
	_body.show_pose(_pose())
	_body.set_walk_phase(_walk_phase)
	_body.face(_facing)
	# On the rope Otto swings slightly like a pendulum in the play plane.
	var sway := 0.0
	if riding and ride_look == LOOK_ROPE:
		sway = sin(Time.get_ticks_msec() * 0.001 * ROPE_SWAY_RATE) * ROPE_SWAY
	_body.rotation.z = sway
	_walk_the_doorway(riding)
	if riding and ride_look == LOOK_HELI:
		_body.position.z = ride_depth
		_body.rotation.y = lerp_angle(_body.rotation.y, 0.0, clampf(ride_turn, 0.0, 1.0))
	if _depth_turn > 0.0:
		_body.rotation.y = lerp_angle(_body.rotation.y, PI, _depth_turn)
	_body.set_transparency(1.0 - _grace_alpha())


## Entering a door and coming out (ADR-0043, decision 4): Otto turns toward the door and
## goes into the depth of the opening while the leaf opens; comes out toward the camera
## while it closes, and at the end turns along the floor. The figure moves, not the
## body: in the play plane Otto stands on the mat.
func _walk_the_doorway(riding: bool) -> void:
	var depth := 0.0
	if riding and ride_look == LOOK_DOOR_IN:
		depth = ride_progress
		_body.rotation.y = lerp_angle(_body.rotation.y, PI, clampf(ride_progress * 2.0, 0.0, 1.0))
	elif riding and ride_look == LOOK_DOOR_OUT:
		depth = ride_progress
		# Facing the camera while in the opening, along the floor once out.
		_body.rotation.y = lerp_angle(_body.rotation.y, 0.0, clampf(ride_progress * 2.0, 0.0, 1.0))
	_body.position.z = -DOOR_WALK_DEPTH * depth


## A step sounds on the extreme walk frames, the ones where a foot is planted. On every
## frame of the cycle there would be twice as many steps as Otto takes.
func _step_sound() -> void:
	var frame := int(_walk_phase)
	# A frame is marked as passed only together with the sound: one marked in the air
	# would lose the step for good: the foot is planted, but nothing is heard.
	if frame == _stepped_on or frame == 1 or not is_on_floor():
		return
	_stepped_on = frame
	# On a snowy deck, the crunch of snow (ADR-0054).
	var sound := Sounds.STEP_SNOW if icy else step_sound
	Sounds.play(Sounds.STEP_METAL if _on_metal() else sound)


## Whether Otto stands on metal, in a cab or on its roof: the step rings there
## (ADR-0052, decision 7).
func _on_metal() -> bool:
	if _car != null:
		return true
	for index: int in get_slide_collision_count():
		if get_slide_collision(index).get_collider() is ElevatorCar:
			return true
	return false


## The sound of a transition between states: jump and crouch (ADR-0052, decision 7).
## Landing does not sound here but where the fall decides it ([method _track_fall]).
func _state_sound(was: OttoStateMachine.State, now: OttoStateMachine.State) -> void:
	if now == OttoStateMachine.State.JUMP:
		Sounds.play(Sounds.JUMP)
	elif now == OttoStateMachine.State.CROUCH and was != OttoStateMachine.State.CROUCH:
		Sounds.play(Sounds.CROUCH)


static func _shape_size(shape: CollisionShape3D) -> Vector3:
	return (shape.shape as BoxShape3D).size
