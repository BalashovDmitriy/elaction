class_name TakedownScene
extends Node

## Director of the takedown scene (ADR-0040, since M24i ADR-0050).
##
## Places the agent right next to Otto, turns off control for both (Otto's input and
## the agent's brain) and leads the two through the pose table [Takedown.Scene]. The
## world around is slowed down for the duration of the scene, while the scene runs at its
## own pace: the director counts time divided by the slowdown and speeds up both rigs by
## the same amount. On the key frame the agent dies and Otto gets points.
##
## Since M24i the scene is staged rather than played evenly. The slowdown is uneven: a
## fast approach, toward the blow the world nearly stops, on the blow itself a freeze
## frame for a fraction of a second, then speeding back up. On the blow the camera jolts
## and tilts, a flash at the faces, the music drops out, the blow sounds hollow, the
## agent's hat flies off, and he falls as a ragdoll thrown away from Otto, not into a
## ready pose. Throughout the scene the background is darker and more colorless, and the
## music more muffled. The angle does not change: the view stays from the side.
##
## Otto is vulnerable in the scene (the user's decision): another agent's bullet arriving
## during the slowdown kills him, and the scene is cut short. An agent who did not die
## before the key frame then returns to combat.

## How many times the world slows down toward the blow.
const SLOW: float = 0.3
## The slowdown on the approach is softer than toward the blow: the scene starts fast.
const APPROACH: float = 0.6
## The freeze frame on the blow: how long it lasts, s of real time, and how many times
## the world is slowed down: almost standing, but bullets and lights do not freeze dead.
const FREEZE_TIME: float = 0.14
const FREEZE_SCALE: float = 0.03
## Close-up: how long the camera takes to push in, s (of scene time), and how long it
## holds close after the key frame, before pulling back toward the end of the scene.
const CLOSE_IN: float = 0.25
const CLOSE_HOLD: float = 0.12
## At what height above the floor the close-up's middle is, m: the chest of those
## standing.
const CLOSE_HEIGHT: float = 1.0
## How far Otto's figure moves away from the camera in a scene from behind, m: the bodies
## stand close in one plane, and the agent must be in front, Otto's arms behind him.
const BEHIND_DEPTH: float = 0.14
## At what height the probe looks for a wall in front of the agent's spot, m: at knee
## level, below any opening and above the threshold.
const WALL_PROBE: float = 0.4
## How long the agent takes to get to his spot in front of Otto, s (of his scene time).
const ALIGN_TIME: float = 0.12
## The flash on the blow: it sculpts the two faces. Color, brightness, range, m, how much
## closer to the camera, m, and how long it takes to fade, s of real time.
const FLASH_COLOR := Color(1.0, 0.9, 0.75)
const FLASH_ENERGY: float = 6.0
const FLASH_RANGE: float = 2.4
const FLASH_OUT: float = 0.45
const FLASH_TIME: float = 0.32
## The background during the scene: saturation and brightness of the frame, and how long
## it takes to reach them, s of real time. It goes away at once, on any exit from the
## scene ([method _restore_grade]).
const GRADE_SATURATION: float = 0.35
const GRADE_BRIGHTNESS: float = 0.8
const GRADE_TIME: float = 0.2
## The blow layered over itself a tone lower and louder: hollow.
const BOOM_PITCH: float = 0.55
const BOOM_DB: float = 3.0
## The music drops out on the blow, s.
const DUCK_TIME: float = 0.7
## Reason for muffling the music during the scene ([method Sounds.muffle_music]).
const MUFFLE := "takedown"
## Throwing the corpse away from Otto: the force along Otto's gaze, as fractions of a
## bullet's push ([constant Corpse.HIT_META]).
const HIT_PUSH: float = 1.4
## The hat: mass, kg, push, m/s (away from Otto and up), and spin, rad/s.
const HAT_MASS: float = 0.15
const HAT_PUSH := Vector2(1.6, 2.4)
const HAT_SPIN: float = 9.0

var _otto: Otto = null
var _agent: Enemy = null
var _scene: Takedown.Scene = null
var _facing: float = 1.0
var _time: float = 0.0
var _killed: bool = false
## The time scale before the scene: tests run the world sped up, and the scene does
## not reset it but slows down relative to it.
var _time_scale_before: float = 1.0
var _slowed: bool = false
## How many times the world is slowed down right now: by the scene's curve.
var _world: float = APPROACH
## How many times the world was slowed down at the start of this frame, and which frame.
## The engine reads the time scale once per frame: a physics step running in the frame
## after the scene changed the slowdown still arrives with the old one. Divided by the
## new one, the second step of the blow frame would run ten times longer and skip the
## freeze frame entirely, and the scene's outcome would depend on the number of steps in
## a frame (M24i code review).
var _frame_world: float = 1.0
var _frame_number: int = -1
## How much longer the freeze frame lasts, s of real time.
var _freeze_left: float = 0.0
var _from_x: float = 0.0
var _to_x: float = 0.0
var _flash: OmniLight3D = null
var _flash_age: float = 0.0
## The scene's frame and its former saturation and brightness: the scene restores them.
var _environment: Environment = null
var _saturation_before: float = 1.0
var _brightness_before: float = 1.0
var _grade_age: float = 0.0


## Starts scene [param scene] over agent [param agent]. The node enters the tree
## next to Otto and leaves it by itself when the scene has ended or been cut short.
static func play(otto: Otto, agent: Enemy, scene: Takedown.Scene) -> TakedownScene:
	var director := TakedownScene.new()
	director.name = "Takedown"
	director._otto = otto
	director._agent = agent
	director._scene = scene
	director._facing = otto.facing()
	otto.get_parent().add_child(director)
	return director


## Which scene is running. For tests.
func scene() -> Takedown.Scene:
	return _scene


## Whether the agent has already died.
func killed() -> bool:
	return _killed


## Whether the blow's freeze frame is on. For tests.
func is_frozen() -> bool:
	return _freeze_left > 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_otto.takedown = self
	_agent.held_facing = -_facing if _scene.faces_otto else _facing
	_agent.held = true
	_from_x = _agent.global_position.x
	_to_x = _free_spot(_otto.global_position.x + _facing * _scene.offset)
	_otto.died.connect(_abort)
	if _scene.side == Takedown.Side.BACK:
		_otto.figure.position.z = -BEHIND_DEPTH
	# An arm aimed before the scene (the agent was winding up, Otto had just fired)
	# would hang raised over its clips: the view in the scene updates neither one
	# (ADR-0043, decision 16).
	_otto.figure.aim_height = NAN
	_agent.figure.aim_height = NAN
	_grade_in()
	Sounds.muffle_music(MUFFLE, true)
	# The scene starts in the middle of Otto's physics step: until the end of the frame the
	# world still runs without the slowdown.
	_frame_number = Engine.get_process_frames()
	_frame_world = 1.0
	# The whoosh is the scene's start, not the slowdown's: continuing from the pause slows
	# the world again, silently (ADR-0060).
	Sounds.play(Sounds.SLOWMO)
	_slow_down()
	_show(0.0)


## Runs the scene for [param delta] seconds of world time. Exposed for tests.
func advance(delta: float) -> void:
	if _scene == null:
		return
	# The agent or Otto was thrown out in the middle of the scene (went behind a door, the
	# building changed, a test took the scene apart): the scene is removed instead of
	# touching the freed one.
	if not is_instance_valid(_agent) or not is_instance_valid(_otto):
		_abort()
		return
	var frame := Engine.get_process_frames()
	if frame != _frame_number:
		_frame_number = frame
		_frame_world = _world if _slowed else 1.0
	var real := delta / _frame_world
	_flash_age += real
	_grade_age += real
	_fade_effects()
	if _freeze_left > 0.0:
		_freeze_left -= real
		if _freeze_left <= 0.0:
			_apply_world()
		return
	_time += real
	if not _killed:
		var align := clampf(_time / ALIGN_TIME, 0.0, 1.0)
		var at := _agent.global_position
		at.x = lerpf(_from_x, _to_x, smoothstep(0.0, 1.0, align))
		_agent.global_position = at
	_show(_time)
	_frame(_time)
	if not _killed and _time >= _scene.kill_at:
		_kill()
	if _time >= _scene.duration:
		_finish()
		return
	_apply_world()


## In physics steps, not frames: the agent's death, the points and the end of the scene
## decide the game's outcome, and by the wall clock the bot run would stop repeating
## (`docs/testing.md`, a rule from M18b).
func _physics_process(delta: float) -> void:
	advance(delta)


func _notification(what: int) -> void:
	# The slowdown is world time, and the pause menu lives on the same engine: on pause
	# it would run three times slower. The pause lifts the slowdown, continuing
	# restores it.
	match what:
		NOTIFICATION_PAUSED:
			_speed_up()
		NOTIFICATION_UNPAUSED:
			if _scene != null:
				_slow_down()
		NOTIFICATION_EXIT_TREE:
			# The building was thrown away in the middle of the scene: the world must not stay slow,
			# nor the frame colorless.
			_speed_up()
			_restore_grade()
			Sounds.muffle_music(MUFFLE, false)


## Poses by time. A killed agent is already a ragdoll: physics drives him, not the table.
func _show(time: float) -> void:
	_otto.figure.show_pose(Takedown.Scene.pose_at(_scene.otto, time))
	if not _killed:
		_agent.figure.show_pose(Takedown.Scene.pose_at(_scene.agent, time))


## Where the agent should stand in front of Otto: at [param wanted] if there is no wall
## before it, or right at the wall. The director places the agent by hand, bypassing
## physics, and without the check an agent pressed against a wall would go a quarter
## meter into it (M24d code review).
func _free_spot(wanted: float) -> float:
	var space := _otto.get_world_3d().direct_space_state
	var height := Vector3(0.0, WALL_PROBE, 0.0)
	var from := _otto.global_position + height
	var to := Vector3(wanted, from.y, from.z)
	var reach := to + Vector3(signf(wanted - from.x) * Proportions.BODY_WIDTH * 0.5, 0.0, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, reach, 1)
	query.exclude = [_otto.get_rid(), _agent.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return wanted
	var wall: Vector3 = hit["position"]
	return wall.x - signf(wanted - from.x) * Proportions.BODY_WIDTH * 0.5


## The close-up over the course of the scene: push in, close until the key frame, pull
## back.
func _frame(time: float) -> void:
	var camera := _camera()
	if camera == null:
		return
	var closing := smoothstep(0.0, CLOSE_IN, time)
	var leaving := 1.0 - smoothstep(_scene.kill_at + CLOSE_HOLD, _scene.duration, time)
	var middle := (_otto.global_position + _agent.global_position) * 0.5
	camera.close_up(minf(closing, leaving), Vector2(middle.x, middle.y + CLOSE_HEIGHT))


func _camera() -> SideCamera:
	var viewport := get_viewport()
	return viewport.get_camera_3d() as SideCamera if viewport != null else null


## The blow: the agent dies and falls as a ragdoll away from Otto, the world stops in a
## freeze frame, the camera jolts, a flash, the music drops out, a hollow blow, the hat
## flies off.
func _kill() -> void:
	_killed = true
	_freeze_left = FREEZE_TIME
	var camera := _camera()
	if camera != null:
		camera.kick(1.0)
	_flash_at_the_faces()
	Sounds.duck_music(DUCK_TIME)
	# The agent was already killed in the middle of the scene, by a lamp or a cab: the
	# points for him were taken there. His body also falls on the blow: the scene no longer
	# sets poses for him, and holding it would mean leaving him standing frozen until the
	# end of the scene.
	if _agent.is_dead():
		_agent.held = false
		return
	var score := Takedown.score(_scene.side, _agent.is_in_the_dark())
	_knock_the_hat()
	# The throw goes away from Otto, in the direction he is looking, and into the head: the
	# body topples instead of slumping in place.
	_agent.set_meta(Corpse.HIT_META, _facing * HIT_PUSH)
	_agent.set_meta(Corpse.HIT_POINT, _head_of(_agent))
	_agent.kill(false, _scene.corpse)
	_agent.held = false
	GameState.instance().add_score(score, _agent.global_position + GameState.OVER_HEAD)
	Sounds.play(Sounds.BLOW)
	Sounds.play_tuned(Sounds.BLOW, BOOM_PITCH, BOOM_DB)
	_apply_world()


## Where the actor's head is, scene coordinates: at the head bone, and without it, at
## the actor's height.
static func _head_of(actor: Node3D) -> Vector3:
	var figure := actor.get(&"figure") as FigureRig
	var skeleton := figure.skeleton() if figure != null else null
	if skeleton != null:
		var bone := skeleton.find_bone(FigureRig.HEAD)
		if bone >= 0:
			return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
	return actor.global_position + Vector3(0.0, Proportions.BODY * 0.9, 0.0)


## A flash at the two faces: warm, closer to the camera, fading over [constant
## FLASH_TIME] of real time.
func _flash_at_the_faces() -> void:
	if _flash == null:
		_flash = OmniLight3D.new()
		_flash.name = "TakedownFlash"
		_flash.light_color = FLASH_COLOR
		_flash.omni_range = FLASH_RANGE
		_flash.shadow_enabled = false
		_otto.get_parent().add_child(_flash)
	var middle := (_head_of(_otto) + _head_of(_agent)) * 0.5
	_flash.global_position = middle + Vector3(0.0, 0.0, FLASH_OUT)
	_flash.light_energy = FLASH_ENERGY
	_flash_age = 0.0


## The hat flies off the agent: it is hidden on him, and its copy flies off as a body
## (away from Otto, up and spinning) and stays lying, like a corpse.
func _knock_the_hat() -> void:
	var figure := _agent.figure
	var hat := figure.find_child("hat", true, false) as MeshInstance3D
	var skeleton := figure.skeleton()
	if hat == null or not hat.visible or skeleton == null:
		return
	var bone := skeleton.find_bone(FigureRig.HEAD)
	if bone < 0:
		return
	hat.visible = false
	# The hat mesh is in the skeleton's rest pose: it is put onto the head by the head pose
	# relative to its rest.
	var placed := (
		skeleton.global_transform
		* skeleton.get_bone_global_pose(bone)
		* skeleton.get_bone_global_rest(bone).affine_inverse()
	)
	var box := hat.mesh.get_aabb()
	var body := FallenHat.new()
	body.name = "Hat"
	body.mass = HAT_MASS
	body.collision_layer = 0
	body.collision_mask = 1
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = box.get_center()
	var copy := MeshInstance3D.new()
	copy.mesh = hat.mesh
	copy.layers = hat.layers
	for index: int in hat.get_surface_override_material_count():
		copy.set_surface_override_material(index, hat.get_surface_override_material(index))
	body.add_child(copy)
	var shape := CollisionShape3D.new()
	var cube := BoxShape3D.new()
	cube.size = box.size * 0.8
	shape.shape = cube
	shape.position = box.get_center()
	body.add_child(shape)
	_agent.get_parent().add_child(body)
	body.global_transform = placed
	body.apply_central_impulse(Vector3(_facing * HAT_PUSH.x, HAT_PUSH.y, 0.0) * HAT_MASS)
	body.angular_velocity = Vector3(0.0, 0.0, -_facing * HAT_SPIN)


## The flash and the frame color fade by real time: on the blow the world nearly stops.
## Real time is counted in scene steps without the world slowdown, not by the clock:
## under a test run with `--fixed-fps` the clock and the frames diverge (run_tests.py).
func _fade_effects() -> void:
	if _flash != null:
		_flash.light_energy = FLASH_ENERGY * maxf(1.0 - _flash_age / FLASH_TIME, 0.0)
	_grade_step()


## The background darkens and loses color: the frame's saturation and brightness move
## toward the scene's.
func _grade_in() -> void:
	var viewport := get_viewport()
	var world := viewport.find_world_3d() if viewport != null else null
	_environment = world.environment if world != null else null
	if _environment == null:
		return
	_saturation_before = _environment.adjustment_saturation
	_brightness_before = _environment.adjustment_brightness
	_grade_age = 0.0
	_grade_step()


func _grade_step() -> void:
	if _environment == null:
		return
	var share := clampf(_grade_age / GRADE_TIME, 0.0, 1.0)
	_environment.adjustment_enabled = true
	_environment.adjustment_saturation = lerpf(_saturation_before, GRADE_SATURATION, share)
	_environment.adjustment_brightness = lerpf(_brightness_before, GRADE_BRIGHTNESS, share)


## The frame as before the scene: both at the end and on being cut short.
func _restore_grade() -> void:
	if _environment == null:
		return
	_environment.adjustment_saturation = _saturation_before
	_environment.adjustment_brightness = _brightness_before
	_environment = null


func _finish() -> void:
	var otto := _otto
	var agent := _agent
	_release()
	otto.takedown = null
	if is_instance_valid(agent):
		agent.held = false
	queue_free()


## Otto died in the middle of the scene: the agent, still alive, returns to combat.
func _abort() -> void:
	var agent := _agent
	var otto := _otto
	_release()
	if is_instance_valid(otto):
		otto.takedown = null
	if is_instance_valid(agent):
		agent.held = false
	queue_free()


func _release() -> void:
	_freeze_left = 0.0
	_speed_up()
	_restore_grade()
	Sounds.muffle_music(MUFFLE, false)
	if _flash != null and is_instance_valid(_flash):
		_flash.queue_free()
	_flash = null
	if is_instance_valid(_otto):
		_otto.figure.position.z = 0.0
	var camera := _camera()
	if camera != null:
		camera.close_up(0.0, Vector2.ZERO)
	if is_instance_valid(_otto) and _otto.died.is_connected(_abort):
		_otto.died.disconnect(_abort)
	_scene = null


## Slowdown by the scene's curve: a fast approach at [constant APPROACH], toward the
## blow [constant SLOW], on the blow a freeze frame, after it speeding up to normal.
func _world_now() -> float:
	if _freeze_left > 0.0:
		return FREEZE_SCALE
	if _scene == null:
		return 1.0
	if not _killed:
		return lerpf(APPROACH, SLOW, smoothstep(0.0, _scene.kill_at, _time))
	return lerpf(SLOW, 1.0, smoothstep(_scene.kill_at, _scene.duration, _time))


## Sets the world and the rigs to the speed from the curve. In a freeze frame the rigs
## stand still.
func _apply_world() -> void:
	if not _slowed:
		return
	_world = _world_now()
	Engine.time_scale = _time_scale_before * _world
	_set_rig_speed(0.0 if _freeze_left > 0.0 else 1.0 / _world)


func _slow_down() -> void:
	if _slowed:
		return
	_time_scale_before = Engine.time_scale
	_slowed = true
	_apply_world()


func _speed_up() -> void:
	if not _slowed:
		return
	Engine.time_scale = _time_scale_before
	_slowed = false
	_world = 1.0
	_set_rig_speed(1.0)


func _set_rig_speed(speed: float) -> void:
	if is_instance_valid(_otto):
		_otto.figure.speed = speed
	if is_instance_valid(_agent) and not _agent.is_dead():
		_agent.figure.speed = speed


## The knocked-off hat lies like a corpse (ADR-0060): once it has lain still for
## [constant Ragdoll.FREEZE_AFTER] it freezes and leaves the simulation, below
## [member Ragdoll.abyss] it disappears instead of falling forever. On a cab floor it does
## not freeze, or the cab would drive out from under it.
class FallenHat:
	extends RigidBody3D

	## How far below its middle the hat looks for a cab floor, m.
	const REACH: float = 0.3

	## How long the hat has been lying still, s.
	var still: float = 0.0

	func _physics_process(delta: float) -> void:
		if global_position.y < Ragdoll.abyss:
			queue_free()
			return
		var resting := linear_velocity.length() <= Ragdoll.RESTING_SPEED and not _on_a_car()
		still = still + delta if resting else 0.0
		if still >= Ragdoll.FREEZE_AFTER:
			freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			freeze = true
			set_physics_process(false)

	func _on_a_car() -> bool:
		var from := global_transform * center_of_mass
		var query := PhysicsRayQueryParameters3D.create(
			from, from + Vector3.DOWN * REACH, collision_mask, [get_rid()]
		)
		return get_world_3d().direct_space_state.intersect_ray(query).get("collider") is ElevatorCar
