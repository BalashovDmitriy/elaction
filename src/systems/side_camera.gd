class_name SideCamera
extends Camera3D

## Orthographic side camera, tilted slightly from above.
##
## Holds only what must be in a node: reads the window size, moves
## the transform, calls the rule. The rule itself is [CameraBounds], and it has no scene.
##
## The tilt is a property of the camera, not the world (ADR-0023, decision 1). The play plane,
## hits and the visible floors band are computed as before: the camera only stands
## above the target so that its axis passes through a point of the play plane, and sees
## a bit more vertically. Strictly from the side the top of a slab is a strip of zero
## thickness, and there would never be any reflections in the floor.

## Half of the frame height, m.
##
## The frame shows 3.67 floors — as much as the original's building field: 176 px
## at a floor pitch of 48 (ADR-0026, decision 4). Before M18c it was 10.8 m and exactly three
## floors. In width at 16:9 this is 23.5 m — 7.8 clearances against 6.4 in the original:
## the arcade field is narrower than the screen, and both axes cannot match.
##
## The orthocamera is tilted, and on the play plane the frame is taller than its size by 1/cos(tilt)
## ([method _read_frame]). So the size is smaller than the field by that cosine: without
## the correction 3.72 floors fit in the frame instead of 3.67 (code review M18c). The number is
## cos(10°): GDScript does not allow functions in a constant.
const DEFAULT_HALF_HEIGHT: float = Proportions.FIELD * 0.5 * 0.98480775

## How far the camera is moved back from the play plane along its axis, m.
##
## For an orthocamera distance does not matter for scale, but it does for clipping: everything
## closer than [member near] is not drawn, and the corridor and actors stand at Z = 0.
const DISTANCE: float = 20.0

## Tilt from above, degrees. Ten reveal the corridor floor as a strip a third of a metre wide —
## reflections and lamp spots fall into it — while floors stay parallel
## strips of the frame. Perspective was rejected: the top and bottom of its frame are at different
## scales, and the rule "a floor is a frame strip" would have to be recomputed.
const TILT_DEGREES: float = 10.0

## How many times narrower the frame is on a takedown scene close-up (ADR-0040).
const CLOSE_UP_SIZE: float = 0.38
## Camera light on figures: cold, like moonlight, and weak — a silhouette, not
## a lit figure.
const ACTOR_FILL_COLOR := Color(0.62, 0.7, 0.95)
const ACTOR_FILL_ENERGY: float = 0.35

## Camera kick on the takedown hit (ADR-0050): frame shift, m, roll, rad, and
## extra zoom — a fraction of the frame size — at a full-strength kick; in how many
## seconds of real time it fades and how often it shakes, Hz. Time is not the world's:
## the world almost stands still on the hit, but the kick must pass.
const KICK_SHIFT: float = 0.09
const KICK_ROLL: float = 0.04
const KICK_ZOOM: float = 0.12
const KICK_FADE: float = 0.45
const KICK_RATE: float = 19.0

## Smoothing speed. The same number that [Camera2D] had in the 2D scene.
@export var smoothing_speed: float = 8.0

var _bounds := CameraBounds.new()
## The frame by combat rules: 16:9 and without smoothing, see [method rule_view].
var _rule_bounds := CameraBounds.new()
## Whom the camera follows. Empty — the camera stays where it was put.
var _target: Node3D = null
var _centre := Vector2.ZERO
## Positional sound listener. It stands in the play plane, not at the camera: the camera
## is moved back by [constant DISTANCE], and without it every source — cab hum,
## "ding", door leaf — would be farther than its `max_distance` and silent.
## In 2D the listener was the centre of the frame, and the ranges were tuned for it.
##
## Created in [method Node._ready], not at declaration: a node created by a field and
## not added to the tree is freed by nobody — an Otto scene spawned by a test for
## the shape size and immediately thrown away would leave it orphaned.
var _listener: AudioListener3D = null
## Close-up: how far zoomed in, 0–1, and on what. The scene director drives it.
var _close: float = 0.0
var _close_point := Vector2.ZERO
## Kick strength, 0–1, and how long it has been going, s of real time.
var _kick: float = 0.0
var _kick_age: float = 0.0


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	# The camera looks along -Z, standing in front of the play plane; a negative rotation
	# around X lowers the gaze.
	rotation = Vector3(-_tilt(), 0.0, 0.0)
	size = DEFAULT_HALF_HEIGHT * 2.0
	near = 0.05
	far = DISTANCE * 2.0
	_read_frame()
	get_viewport().size_changed.connect(_read_frame)

	add_child(actor_fill())

	_listener = AudioListener3D.new()
	# Along the camera axis to the play plane: with the tilt this is farther than [constant DISTANCE].
	_listener.position = Vector3(0.0, 0.0, -DISTANCE / cos(_tilt()))
	add_child(_listener)
	_listener.make_current()


func _process(delta: float) -> void:
	if _target == null:
		return
	var wanted := _bounds.clamp_centre(_target_point().lerp(_close_point, _close))
	# On a close-up the director sets the motion with a smooth curve, and the world around is slowed:
	# smoothing by the slowed clock would drag the frame behind the pair.
	if _close > 0.0:
		_centre = wanted
	else:
		_centre = CameraBounds.smoothed(_centre, wanted, smoothing_speed, delta)
	global_position = _perch(_centre)
	_shake(delta)


## Kicks the frame: shift, roll and extra zoom, fading over [constant
## KICK_FADE] of real time. [param strength] — 0–1.
func kick(strength: float) -> void:
	_kick = clampf(strength, 0.0, 1.0)
	_kick_age = 0.0


## Whether a kick is running. For tests.
func is_kicked() -> bool:
	return _kick > 0.0


## Real kick time is the frame step without world slowdown, not the clock: under
## a test run with `--fixed-fps` the clock and the frames diverge (run_tests.py).
func _shake(delta: float) -> void:
	if _kick <= 0.0:
		return
	_kick_age += delta / maxf(Engine.time_scale, 0.001)
	var age := _kick_age
	var left := 1.0 - age / KICK_FADE
	if left <= 0.0:
		_kick = 0.0
		rotation = Vector3(-_tilt(), 0.0, 0.0)
		close_up(_close, _close_point)
		return
	var force := _kick * left * left
	var wave := age * KICK_RATE * TAU
	global_position += (
		Vector3(sin(wave) * KICK_SHIFT, cos(wave * 1.3) * KICK_SHIFT * 0.6, 0.0) * force
	)
	rotation = Vector3(-_tilt(), 0.0, sin(wave * 0.7) * KICK_ROLL * force)
	size = DEFAULT_HALF_HEIGHT * 2.0 * lerpf(1.0, CLOSE_UP_SIZE, _close) * (1.0 - KICK_ZOOM * force)


## Camera light on figures: weak, along the view axis, only on the figure layer
## ([constant FigureRig.RENDER_LAYER]). It, not an outline, makes Otto and agents
## readable on a darkened floor (ADR-0042, decision 7): the surroundings are not
## affected by it, and the floor's darkness stays darkness. No shadow and bypassing fog.
static func actor_fill() -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = "ActorFill"
	light.light_color = ACTOR_FILL_COLOR
	light.light_energy = ACTOR_FILL_ENERGY
	light.light_cull_mask = FigureRig.RENDER_LAYER
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = 0.0
	light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	return light


## Whom to follow. Usually Otto.
func follow(target: Node3D) -> void:
	_target = target
	if target != null:
		snap_to(_target_point())


## Takedown scene close-up (ADR-0040): [param amount] 0 — the regular frame,
## 1 — [constant CLOSE_UP_SIZE] times narrower and centred at [param point]
## (scene coordinates). The close-up does not touch the combat frame ([method rule_view]):
## it decides who sees whom, and a camera zoom must not change combat.
func close_up(amount: float, point: Vector2) -> void:
	_close = clampf(amount, 0.0, 1.0)
	_close_point = point
	size = DEFAULT_HALF_HEIGHT * 2.0 * lerpf(1.0, CLOSE_UP_SIZE, _close)
	_read_frame()


## Puts the camera in place without smoothing.
##
## Needed at level start and when returning to play: otherwise the camera arrives
## at the resurrected Otto half a second later, and for that half second the player looks at
## where he was killed.
func snap_to(point: Vector2) -> void:
	_centre = _bounds.clamp_centre(point)
	global_position = _perch(_centre)


## Bounds the camera must not go beyond. They come in rules coordinates
## (Y down) and are converted here: the outside must not know about the Y flip.
##
## Bounds come with the level's placement, when the target already stands in
## place. So the camera snaps to it rather than to the former middle: that one was left
## by [method follow], called from Otto's [method Node._ready] when he still
## stood at the origin — and from it the camera would ride sideways for half a second across
## the empty building. [Camera2D] did not do this: it snapped into place on the first frame.
##
## [param snap] = false lets the camera ride to the new bounds with smoothing: this way
## the intro frame, set above the top of the world, comes down to the building (ADR-0038).
func apply_bounds(rect: Rect2, snap: bool = true) -> void:
	# The bottom of the rules is the top of the scene, and vice versa.
	var lowest := WorldSpace.height_to_scene(rect.end.y)
	var highest := WorldSpace.height_to_scene(rect.position.y)
	_bounds.limits = Rect2(rect.position.x, lowest, rect.size.x, highest - lowest)
	_rule_bounds.limits = _bounds.limits
	if snap:
		snap_to(_target_point() if _target != null else _centre)


## What is in the frame now, in rules coordinates.
func view() -> Rect2:
	return _to_plane(_bounds.view_at(_centre))


## The frame combat decides by, in rules coordinates: the same as the player's,
## but at 16:9 and without smoothing — it snaps to the target at once.
##
## The player's frame moves in [method Node._process] by the wall clock and is wider on a
## wide window. The outcome of a game must come from physics (`docs/testing.md`, a rule
## from M18b): by the player's frame an agent would shoot or not depending on the machine
## and window size, and the bot run would stop repeating (ADR-0027, decision 3a).
func rule_view() -> Rect2:
	var centre := _centre if _target == null else _rule_bounds.clamp_centre(_target_point())
	return _to_plane(_rule_bounds.view_at(centre))


## Scene frame — into rules coordinates: Y grows downward there.
static func _to_plane(scene_view: Rect2) -> Rect2:
	var top := WorldSpace.height_to_plane(scene_view.end.y)
	return Rect2(scene_view.position.x, top, scene_view.size.x, scene_view.size.y)


## Where the target is now, in scene coordinates. Z is dropped: the frame is flat.
func _target_point() -> Vector2:
	return Vector2(_target.global_position.x, _target.global_position.y)


## Where the camera stands so that its axis passes through [param centre] in the play plane:
## higher by "distance × tan(tilt)", otherwise the tilt would look at the target's feet.
func _perch(centre: Vector2) -> Vector3:
	return Vector3(centre.x, centre.y + DISTANCE * tan(_tilt()), DISTANCE)


func _tilt() -> float:
	return deg_to_rad(TILT_DEGREES)


## Recomputes the frame halves by window size: the frame width depends on
## the aspect ratio, and on another window it is different.
##
## Vertically a tilted camera covers a bit more than its size in the play plane
## — by 1/cos(tilt): the frame cuts the plane at an angle.
func _read_frame() -> void:
	var window := get_viewport().get_visible_rect().size
	var aspect := window.x / maxf(window.y, 1.0)
	_bounds.half_height = size * 0.5 / cos(_tilt())
	_bounds.half_width = size * 0.5 * aspect
