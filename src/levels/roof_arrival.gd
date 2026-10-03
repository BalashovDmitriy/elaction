class_name RoofArrival
extends RefCounted

## Building intro: the helicopter brings Otto to the roof (ADR-0038, decision 1;
## staging — ADR-0052, decision 6).
##
## The full one — in the first building of a game, 10–12 s: the helicopter flies in with the door
## closed, hovers and slides it open, Otto looks out of the opening, sits down on
## the threshold, the rope coil is thrown down, he grabs the rope, slips off the threshold and
## quickly slides down hand over hand, braking near the roof — and lands in a crouch. From this
## moment he obeys the player, while the helicopter reels the rope in, slides the door shut, the
## pilot nods, and the helicopter leaves on its own. The short one — in the other buildings, about
## 6 s: from the first frame the helicopter hovers over the spot with the door open.
##
## Jump, fire or pause skip the intro: Otto stands on the roof right away,
## the helicopter leaves from where it was.
##
## While the intro runs, Otto "rides" ([method Otto.ride]): input does nothing,
## physics is silent, he is invulnerable, the intro owns his coordinate — the same trick
## as the escalator. In the play plane he stands under the opening and on the rope; his figure
## goes into the depth of the frame, into the opening ([member Otto.ride_depth]). While the
## helicopter flies, Otto is inside it, that is, not visible.
##
## The camera zooms in without changing angle, like for takedowns ([method SideCamera.close_up]):
## closer on the door, it follows Otto down the rope and after landing pulls back to
## the gameplay frame ([method linger]).
##
## The level only calls [method advance] every physics step while
## [method is_playing] holds, and keeps agents and cabs still for that time.

enum Step { FLY_IN, DOOR, PEEK, SIT, DROP, GRAB, SWING, SLIDE, DONE }

## Height of the skids above the roof when hovering, m: higher than Otto's jump (2.4 m) and such
## that the descent reads as a descent, and the helicopter with its rotor fits in the frame.
const HOVER_HEIGHT: float = 4.2

## How far above the top of the world the intro frame is raised, m.
##
## The frame on the roof stops at the top of the world 4.8 m above the deck — the helicopter with
## its rotor above the rope does not fit there. For the intro the frame rises higher and does not
## move vertically at all: the bounds band is exactly one frame tall. The building bounds
## return when the helicopter has flown away or Otto has left the roof, and the camera glides
## to them with smoothing, without a jerk.
const CAMERA_HEADROOM: float = 4.5

## The intro frame does not rise higher than this, even if the helicopter hovers higher than usual
## over tall equipment: the roof must stay in the frame with room for Otto's height.
const DECK_IN_FRAME: float = 1.6

## How much sky stays in the frame above the top of the helicopter, m.
const SKY_ABOVE: float = 0.4

## Otto's hands on the rope, feet lower by this much, m: height with raised arms.
const REACH: float = Proportions.BODY * 1.15

## How long each step lasts, s: the full intro and the short one. The rope drop and
## the descent last as long as the coil falls and Otto slides.
const DOOR_PAUSE: float = 0.35
const PEEK_TIME: float = 1.5
const PEEK_TIME_SHORT: float = 0.9
const SIT_TIME: float = 1.0
const SIT_TIME_SHORT: float = 0.7
## How long the rope swings before Otto grabs it, s.
const SETTLE_TIME: float = 0.45
const GRAB_TIME: float = 0.5
const SWING_TIME: float = 0.45

## Otto in the opening: how much deeper than the threshold he stands while looking out, and how
## far the threshold is below him when he sits — the feet hang lower, m.
const PEEK_INSET: float = 0.3
const SIT_DROP: float = 0.5
const SIT_OUT: float = 0.05
## Where Otto grabs the rope: hands this much above the threshold, m.
const GRAB_ABOVE_SILL: float = 0.95

## Hand-over-hand rope descent (ADR-0052, decision 6): acceleration, speed limit, m/s,
## and braking near the roof — from what feet height above it, m, with what
## deceleration, m/s², and down to what speed, m/s.
const SLIDE_SPEED: float = 7.0
const SLIDE_ACCELERATION: float = 14.0
const BRAKE_FROM: float = 1.8
const BRAKING: float = 11.0
const TOUCH_SPEED: float = 1.3

## How long the helicopter hovers after landing before reeling the rope in, s.
const LINGER: float = 0.35

## Camera zoom: close-up fraction at the door and on the rope, how fast the frame moves
## to the needed zoom, 1/s, and in how many seconds it pulls back after landing.
const CLOSE_AT_DOOR: float = 0.5
const CLOSE_ON_ROPE: float = 0.32
const CLOSE_EASE: float = 2.6
const CLOSE_RELEASE: float = 0.9
## How much sky above the rotor and roof under the rope stays in the frame at the door, m, for
## both edges together.
const DOOR_FRAME_MARGIN: float = 1.6
## Below this fraction the zoom is not used in computing the point: at zero the point would go to
## infinity, and the frame is almost the regular one anyway.
const MIN_CLOSE: float = 0.05
## The middle of the frame on the rope is this much above Otto's feet, m.
const ROPE_FRAME_RISE: float = 1.0

## Actions that skip the intro. Pause too, but [Main] catches it: it owns
## the pause button, and it must not open the menu in the same second.
const SKIP_ACTIONS: Array[StringName] = [&"jump", &"shoot"]

var _otto: Otto = null
var _helicopter: Helicopter = null
var _host: Node3D = null
var _landing := Vector2.ZERO
var _bounds := Rect2()
var _step: Step = Step.DONE
var _wait: float = 0.0
var _speed: float = 0.0
## Full intro or short one.
var _full: bool = true
## How much rope is between the hook and Otto's hands, m.
var _along: float = 0.0
## Where the intro put Otto in the previous step. If he stands elsewhere, someone else moved
## him (a test, a capture tool), and the intro ends on its own without
## touching him: that is how it was with the rope before M24b.
var _placed := Vector3.ZERO
## Which actions were pressed in the previous step: skipping is by press, not by
## hold, otherwise a jump held down from the previous building would eat the intro.
var _held: Dictionary = {}
## The frame is still held by the intro: the building bounds have not been returned.
var _camera_held: bool = false
## Current camera zoom and its middle in scene coordinates.
var _close: float = 0.0
var _close_point := Vector2.ZERO
## How much longer the camera pulls back after landing, s.
var _release_left: float = 0.0


## Starts the intro: the helicopter appears in [param host], Otto inside it.
## [param landing] — the spot on the roof in the rules plane, [param bounds] — the camera's
## building bounds that return after landing. [param full] — the full
## intro of the first building of a game, otherwise the short one; [param daytime] — morning
## or day: the searchlight is off.
func begin(
	host: Node3D,
	otto: Otto,
	landing: Vector2,
	bounds: Rect2,
	full: bool = false,
	daytime: bool = false,
	snow: float = -1.0
) -> void:
	_host = host
	_otto = otto
	_landing = landing
	_bounds = bounds
	_full = full
	var deck := WorldSpace.to_scene(landing).y
	var obstacles := roof_obstacles(host, deck, [otto] as Array[Node])
	_helicopter = Helicopter.new()
	host.add_child(_helicopter)
	# The helicopter is outside: in daytime the sun is on it (ADR-0051).
	Outdoors.mark(_helicopter)
	_helicopter.daytime = daytime
	# Above the roof equipment — with margin; the rotor downwash blows dust onto the roof itself.
	_helicopter.avoid(obstacles, deck, snow)
	# Above tall equipment — a tower, an antenna — the helicopter hovers higher than usual.
	var hover := _helicopter.safe_hover(WorldSpace.to_scene(landing - Vector2(0.0, HOVER_HEIGHT)))
	_helicopter.fly_in(hover, not full)

	var hook := _helicopter.hook_at_hover(hover)
	_otto.ride_look = Otto.LOOK_HELI
	_otto.ride(true)
	_otto.visible = not full
	_place(Vector3(hook.x, hook.y - REACH, WorldSpace.PLAY_Z))
	# The frame is set right away, as a snap: the building's first frame is already an intro frame.
	# If the helicopter hovers higher than usual — the frame is higher too, while the roof stays in it.
	var top := WorldSpace.to_plane(hover).y - _helicopter.top_above_skids() - SKY_ABOVE
	var headroom := clampf(
		bounds.position.y - top,
		CAMERA_HEADROOM,
		bounds.position.y + Proportions.FIELD - landing.y - DECK_IN_FRAME
	)
	var framed := Rect2(
		bounds.position.x, bounds.position.y - headroom, bounds.size.x, Proportions.FIELD
	)
	_otto.apply_camera_bounds(framed)
	_camera_held = true
	for action: StringName in SKIP_ACTIONS:
		_held[action] = Input.is_action_pressed(action)
	_close = 0.0
	_close_point = Vector2(hover.x, hover.y)
	if full:
		_step = Step.FLY_IN
	else:
		_enter(Step.PEEK)


## What stands on the roof above the deck [param deck] (height in scene coordinates):
## the level's visible meshes — equipment, the machine room with the antenna, roofing,
## the sign. Without cabs (the machine room covers them), without the city (it is in
## its own [SubViewport] and its own world), without rain (its streaks and halos are not
## objects) and without [param skip] — Otto and the like.
static func roof_obstacles(host: Node, deck: float, skip: Array[Node]) -> Array[AABB]:
	var found: Array[AABB] = []
	for node: Node in host.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree() or _skipped(mesh, host, skip):
			continue
		var box := mesh.global_transform * mesh.mesh.get_aabb()
		if box.end.y > deck + 0.05 and box.position.y < deck + 20.0:
			found.append(box)
	return found


static func _skipped(node: Node, host: Node, skip: Array[Node]) -> bool:
	var at := node.get_parent()
	while at != null and at != host:
		if at is SubViewport or at is RoofRain or at is Helicopter or skip.has(at):
			return true
		# The cab is inside the shaft, and its ropes stretch up to the machine room
		# ceiling and are cut by a shader: their bounds are higher than what is visible.
		if at is ElevatorCar:
			return true
		at = at.get_parent()
	return false


## Whether the intro is running: Otto is not on the roof yet.
func is_playing() -> bool:
	return _step != Step.DONE


## Whether the intro is full.
func is_full() -> bool:
	return _full


## Which step is running — for tests and shots.
func step() -> Step:
	return _step


## The intro helicopter; null once it has flown away and been removed.
func helicopter() -> Helicopter:
	return _helicopter if is_instance_valid(_helicopter) else null


## Skips the intro: Otto is on the roof right away. Returns whether there was anything to skip.
func skip() -> bool:
	if not is_playing():
		return false
	_land()
	_release_camera(true)
	return true


## The step after the intro: the camera pulls back to the gameplay frame and bounds return when
## the helicopter has flown away or Otto has left the roof — rode down by cab, jumped off. Called
## every physics step and almost always does nothing.
func linger(delta: float = 1.0 / 60.0) -> void:
	if _release_left > 0.0:
		_release_left = maxf(_release_left - delta, 0.0)
		var share := _release_left / CLOSE_RELEASE
		_frame(_close * smoothstep(0.0, 1.0, share), _close_point)
		if _release_left <= 0.0:
			_close = 0.0
	if not _camera_held or is_playing():
		return
	var off_the_roof := WorldSpace.to_plane(_otto.global_position).y > _landing.y + 0.5
	if helicopter() == null or off_the_roof:
		_restore_camera()


## Intro step. [param delta] — physics step, s.
func advance(delta: float) -> void:
	if not is_playing():
		return
	if _otto.global_position.distance_to(_placed) > 0.01:
		# Moved — the intro no longer owns him.
		_let_go()
		return
	if _skip_pressed():
		# The press was spent on the skip: Otto, released in this same step,
		# will not get it — neither a shot nor a jump from the landing spot.
		_land(true)
		_release_camera(true)
		return

	_wait -= delta
	match _step:
		Step.FLY_IN:
			_hold_in_the_cabin()
			if _helicopter.is_hovering():
				_helicopter.set_door_open(true)
				_enter(Step.DOOR)
		Step.DOOR:
			_hold_in_the_cabin()
			if _helicopter.door_share() >= 1.0 and _wait <= 0.0:
				_enter(Step.PEEK)
		Step.PEEK:
			_peek()
			if _wait <= 0.0:
				_enter(Step.SIT)
		Step.SIT:
			_sit_down()
			if _wait <= 0.0:
				_helicopter.drop_rope(_hook_height() - _deck_height())
				_enter(Step.DROP)
		Step.DROP:
			_sit_down()
			if _helicopter.rope_is_down() and _wait <= 0.0:
				_enter(Step.GRAB)
			elif not _helicopter.rope_is_down():
				_wait = SETTLE_TIME
		Step.GRAB:
			_sit_down()
			if _wait <= 0.0:
				_enter(Step.SWING)
		Step.SWING:
			_swing_out()
			if _wait <= 0.0:
				_enter(Step.SLIDE)
		Step.SLIDE:
			_slide(delta)
	_follow(delta)


## Transition to step [param next]: its length, pose and sound.
func _enter(next: Step) -> void:
	_step = next
	match next:
		Step.DOOR:
			_wait = DOOR_PAUSE
		Step.PEEK:
			_wait = PEEK_TIME if _full else PEEK_TIME_SHORT
			_otto.visible = true
			_otto.ride_pose = ActorPose.PEEK
			_otto.ride_turn = 1.0
			# Into the opening right away: shown under the hook, for a frame he would hang in the air
			# outside the helicopter.
			_peek()
		Step.SIT:
			_wait = SIT_TIME if _full else SIT_TIME_SHORT
			_otto.ride_pose = ActorPose.SIT_EDGE
		Step.DROP:
			_wait = SETTLE_TIME
		Step.GRAB:
			_wait = GRAB_TIME
			_otto.ride_pose = ActorPose.SIT_GRAB
		Step.SWING:
			_wait = SWING_TIME
			_along = maxf(_hook_height() - _sill().y - GRAB_ABOVE_SILL, 0.2)
			_otto.ride_pose = ActorPose.ROPE
		Step.SLIDE:
			_otto.ride_look = Otto.LOOK_ROPE
			_otto.ride_depth = 0.0
			_otto.ride_turn = 0.0
			_speed = 0.0
			_helicopter.rope_slide(true)


## While the helicopter flies and opens the door, Otto is in the cabin: invisible and standing under
## the hook, where the frame is looking.
func _hold_in_the_cabin() -> void:
	var hook := _helicopter.hook()
	_place(Vector3(hook.x, hook.y - REACH, WorldSpace.PLAY_Z))


## Looks out: stands on the cabin floor deep in the opening, facing the camera.
func _peek() -> void:
	var sill := _sill()
	_place(Vector3(sill.x, sill.y, WorldSpace.PLAY_Z))
	_otto.ride_depth = sill.z - WorldSpace.PLAY_Z - PEEK_INSET


## Sits down on the threshold: lowers and moves to the edge over the step, then
## sits with legs hanging — both while the coil falls and while he grabs the rope.
func _sit_down() -> void:
	var sill := _sill()
	var share := 1.0
	if _step == Step.SIT:
		var total := SIT_TIME if _full else SIT_TIME_SHORT
		share = smoothstep(0.0, 1.0, 1.0 - _wait / total)
	var drop := SIT_DROP * share
	_place(Vector3(sill.x, sill.y - drop, WorldSpace.PLAY_Z))
	_otto.ride_depth = (sill.z - WorldSpace.PLAY_Z + lerpf(-PEEK_INSET, SIT_OUT, share))


## Slips off the threshold onto the rope: from sitting to hanging, into the play plane, and
## turns along the floor.
func _swing_out() -> void:
	var share := smoothstep(0.0, 1.0, 1.0 - _wait / SWING_TIME)
	var sill := _sill()
	var seated := Vector3(sill.x, sill.y - SIT_DROP, WorldSpace.PLAY_Z)
	var hanging := _on_rope()
	_place(seated.lerp(hanging, share))
	_otto.ride_depth = lerpf(sill.z - WorldSpace.PLAY_Z + SIT_OUT, 0.0, share)
	_otto.ride_turn = 1.0 - share


## Slides down hand over hand: acceleration to the limit and braking near the roof.
func _slide(delta: float) -> void:
	var feet := _on_rope().y
	var left := feet - _deck_height()
	# Speed limit: full travel, and near the roof — the one from which it can still brake in time.
	# Accelerate in the braking zone too: otherwise a descent started from zero right at the roof
	# would just stay in place.
	var top := SLIDE_SPEED
	if left < BRAKE_FROM:
		top = minf(top, maxf(sqrt(2.0 * BRAKING * maxf(left, 0.0)), TOUCH_SPEED))
	_speed = minf(_speed + SLIDE_ACCELERATION * delta, top)
	_along += _speed * delta
	var at := _on_rope()
	if at.y <= _deck_height() + 0.001:
		# He was put in place by himself: the intro put him there — otherwise the release would take
		# the arrival for a move and cut the rope sound.
		_place(WorldSpace.to_scene(_landing))
		_land()
		_release_camera(false)
		return
	_place(at)


## Where Otto stands holding the rope [member _along] metres from the hook: feet
## lower than hands by his height with raised arms, in the play plane.
func _on_rope() -> Vector3:
	var hands := _helicopter.rope_point(_along)
	return Vector3(hands.x, hands.y - REACH, WorldSpace.PLAY_Z)


## End of the intro by arrival or skip: Otto stands at the landing spot and
## obeys, the helicopter leaves, and the intro frame is held until it has flown away
## ([method linger]).
##
## [param presses_spent] — the intro was skipped by a press, and Otto does not hear it
## ([method Otto.ride]).
func _land(presses_spent: bool = false) -> void:
	_otto.global_position = WorldSpace.to_scene(_landing)
	# Landing in a crouch — with the rope clip, not the stance from the opening.
	_otto.ride_look = Otto.LOOK_ROPE
	_release(presses_spent)


## Releases Otto where he was put — a test, a capture, a return after
## death. The frame catches up with him right away, as a snap: the intro does not own it.
func _let_go() -> void:
	_otto.ride_look = ""
	_release()
	_release_camera(true)
	_otto.apply_camera_bounds(_bounds)
	_camera_held = false


func _release(presses_spent: bool = false) -> void:
	var sliding := _step == Step.SLIDE
	_step = Step.DONE
	_otto.visible = true
	_otto.ride(false, presses_spent)
	if is_instance_valid(_helicopter):
		# Arrived — the rope sound plays out on its own, it is shorter than the descent; torn off
		# mid-descent — it is cut.
		if not sliding or _otto.global_position.distance_to(_placed) > 0.01:
			_helicopter.rope_slide(false)
		_helicopter.leave(LINGER)


## The frame moves to the step's zoom: at the door — on the opening, on the rope — after Otto.
func _follow(delta: float) -> void:
	if not is_playing():
		return
	var wanted := 0.0
	var point := _close_point
	match _step:
		Step.DOOR, Step.PEEK, Step.SIT, Step.DROP, Step.GRAB:
			# Close, but so that both the rotor and the roof under the rope fit in the frame.
			var top := _helicopter.global_position.y + _helicopter.top_above_skids()
			var deck := _deck_height()
			var needed := (top - deck + DOOR_FRAME_MARGIN) / Proportions.FIELD
			var room := (1.0 - needed) / (1.0 - SideCamera.CLOSE_UP_SIZE)
			wanted = clampf(room, 0.0, CLOSE_AT_DOOR)
			point = Vector2(_sill().x, (top + deck) * 0.5)
		Step.SWING, Step.SLIDE:
			wanted = CLOSE_ON_ROPE
			point = Vector2(_otto.global_position.x, _otto.global_position.y + ROPE_FRAME_RISE)
	var ease := 1.0 - exp(-CLOSE_EASE * delta)
	_close = lerpf(_close, wanted, ease)
	_close_point = _close_point.lerp(point, ease)
	_frame(_close, _close_point)


## Pull back to the gameplay frame: after landing — smoothly, on a skip — at once.
func _release_camera(at_once: bool) -> void:
	if at_once:
		_close = 0.0
		_release_left = 0.0
		_frame(0.0, _close_point)
	else:
		_release_left = CLOSE_RELEASE


## Zoom to [param amount] with the frame middle at [param centre]. The camera puts
## the middle between the target — Otto — and the zoom point at the zoom fraction
## ([method SideCamera.close_up]); the point is computed backwards so that the middle
## lands where the intro needs it.
func _frame(amount: float, centre: Vector2) -> void:
	var camera := _camera()
	if camera == null:
		return
	var otto := Vector2(_otto.global_position.x, _otto.global_position.y)
	var point := otto + (centre - otto) / maxf(amount, MIN_CLOSE)
	camera.close_up(amount, point)


func _camera() -> SideCamera:
	if _host == null or not is_instance_valid(_host) or not _host.is_inside_tree():
		return null
	var viewport := _host.get_viewport()
	return viewport.get_camera_3d() as SideCamera if viewport != null else null


## Returns the building bounds to the camera — without a snap, with smoothing.
func _restore_camera() -> void:
	_camera_held = false
	_otto.apply_camera_bounds(_bounds, false)


func _place(at: Vector3) -> void:
	_otto.global_position = at
	_placed = at


## The opening threshold in scene coordinates.
func _sill() -> Vector3:
	return _helicopter.doorway()


func _hook_height() -> float:
	return _helicopter.hook().y


func _deck_height() -> float:
	return WorldSpace.to_scene(_landing).y


func _skip_pressed() -> bool:
	var pressed := false
	for action: StringName in SKIP_ACTIONS:
		var down := Input.is_action_pressed(action)
		if down and not bool(_held.get(action, false)):
			pressed = true
		_held[action] = down
	return pressed
