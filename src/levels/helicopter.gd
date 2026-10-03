class_name Helicopter
extends Node3D

## Intro helicopter: brings Otto to the roof (ADR-0038, decision 1).
##
## A look, not a body: it has no collisions and takes no part in combat. It flies in
## from the left, hovers, rolls back the sliding door, drops a coil of rope, reels the
## rope in on command, closes the door and leaves — nose down, banking, up and to the
## side (ADR-0052, decision 6) — and removes itself off screen. When to do what is
## decided by [RoofArrival]; the helicopter can only fly, hover, open the door and
## lower the rope. Behind the glazing sits the pilot, who nods on leaving.
##
## Its own model since M24i (ADR-0049, `tools/build_helicopter.py`): a fuselage with
## glazing, skids, a fin, main and tail rotors as separate nodes `MainRotor` and
## `TailRotor`, since M24k the door as a `Door` node, and empties for the lights,
## searchlight, cabin light, winch and pilot seat. The node's origin is under the
## rotor axis at skid level, in the middle of the fuselage depth-wise: so "hover over
## a point" simply means putting the node there.

enum Phase { ARRIVING, HOVERING, LEAVING }

const MODEL := preload("res://assets/models/aircraft/helicopter.glb")
const PILOT_MODEL := preload("res://assets/models/pilot.glb")

## Fuselage length from nose to tail, m. A light helicopter is a little over nine
## metres; the model is brought to it by a single scale.
const LENGTH: float = 8.6

## Paint. The fuselage is dark metallic, catching the neon and city lights; the
## glazing glows from inside with instruments — so the cabin is visible in the dark,
## and the helicopter reads as a machine with people, not a silhouette; the door
## opening glows with warm cabin light.
const HULL_COLOR := Color(0.34, 0.37, 0.44)
const GLASS_COLOR := Color(0.05, 0.07, 0.09)
const GLASS_GLOW := Color(0.3, 0.46, 0.52)
const GLASS_GLOW_ENERGY: float = 0.08
## The glazing is transparent: the pilot is visible behind it (ADR-0052, decision 6).
const GLASS_ALPHA: float = 0.42
const CABIN_GLOW := Color(1.0, 0.72, 0.42)
const ROTOR_COLOR := Color(0.5, 0.5, 0.52)
const CABIN_GLOW_ENERGY: float = 0.25
## Blur disc under the blades: a rotor at speed is not four sticks but a circle the
## blades run around. Opacity share at the tips and at the axis.
const BLUR_ALPHA: float = 0.22
const BLUR_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color;
uniform float blades = 4.0;
void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float streak = 0.55 + 0.45 * cos(atan(p.y, p.x) * blades);
	float ring = smoothstep(0.12, 0.3, r) * (1.0 - smoothstep(0.92, 1.0, r));
	ALBEDO = tint.rgb;
	ALPHA = tint.a * ring * streak * (0.4 + 0.6 * r);
}
"""
## The tail rotor spins faster than the main one, like a real one.
const TAIL_ROTOR_SPEED: float = 48.0
## Rotor speed, rad/s. Not the real one — at that the rotor would strobe still at the
## frame rate — but one at which the blades read as motion.
const ROTOR_SPEED: float = 21.0

## The fuselage stands behind the play plane: the near side with the door is right at
## the plane, and the winch boom carries the rope exactly into it, where Otto hangs.
const DEPTH_Z: float = -1.15

## Flight: where it comes from — this many metres left of and above the hover point —
## and in how many seconds. The travel curve has no jerk at entry: it flies in at
## cruising speed and bleeds it off toward the point ([method _arrival_progress]).
const ARRIVAL_DISTANCE: float = 22.0
const ARRIVAL_RISE: float = 1.8
const ARRIVAL_TIME: float = 2.3

## How the helicopter leaves: acceleration, speed limit and climb per metre of path, m/s².
const LEAVE_ACCELERATION: float = 7.0
const LEAVE_SPEED: float = 17.0
const LEAVE_CLIMB: float = 0.45
## How many metres of path before it removes itself: the frame is 23.5 m wide, and
## the helicopter leaves past its edge with margin from any hover point.
const GONE_AFTER: float = 38.0

## Tilt by acceleration, like a real one: accelerating — nose down, braking — nose up.
## [constant DRAG] is the drag at cruising speed: without it, flying level it would
## not lean at all.
const DRAG: float = 0.35
const TILT_GAIN: float = 0.75
## Tilt limit — 10°, in radians: GDScript does not allow functions in a constant.
## The margin over the roof equipment also depends on it ([method clear_height]): the
## tail of a tilted fuselage drops by 0.9 m, and at 14° the margin would double.
const TILT_MAX: float = 0.1745
const TILT_EASE: float = 5.0

## Margin over the roof equipment, m, and climb steepness to it: the path does not jump
## up over the tower but gains height in advance — a metre per one and a half travelled.
const CLEARANCE: float = 0.4
const CLEAR_SLOPE: float = 0.65

## Fuselage rim: a cold glint along the silhouette's edges. Otherwise at night the tail
## boom vanishes — neither the cabin light nor the searchlight falls on it. A second mesh
## pass, not a light source: no shadows and no light in the frame budget.
const RIM_COLOR := Color(0.5, 0.62, 0.85)
const RIM_POWER: float = 2.2
const RIM_STRENGTH: float = 0.55
const RIM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled;

uniform vec4 rim_color : source_color;
uniform float rim_power = 2.0;
uniform float rim_strength = 0.5;

void fragment() {
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	ALBEDO = rim_color.rgb * edge * rim_strength;
}
"""

## Hovering is never still: the helicopter bobs slightly up and down.
const BOB_HEIGHT: float = 0.06
const BOB_RATE: float = 1.7

## Rope: thickness, colour and the speed the winch reels it in, m/s. It is not the
## winch that pays it out: the coil is dropped, and the rope unwinds by falling.
const ROPE_RADIUS: float = 0.022
const ROPE_COLOR := Color(0.36, 0.34, 0.3)
const ROPE_SPEED: float = 3.2
## The dropped coil falls with acceleration slightly below free fall — the rope pulls
## it back — and no faster than the limit, m/s², m/s.
const ROPE_DROP_PULL: float = 7.5
const ROPE_DROP_TOP: float = 9.0
## Rope swinging as a pendulum in the play plane: the kick on the drop, rad, and how
## fast it dies out, 1/s; the rotor wash keeps swinging it further — by this much, rad.
const ROPE_KICK: float = 0.16
const ROPE_DAMPING: float = 1.1
const ROPE_DRAFT: float = 0.018
const ROPE_DRAFT_RATE: float = 1.3

## Sliding door: how many seconds it takes to roll back and how far it moves out from
## the side before sliding back, m.
const DOOR_TIME: float = 0.85
const DOOR_POP: float = 0.05
## How much shorter than its length the door rolls back: the edge stays at the opening.
const DOOR_KEEP: float = 0.12

## Leaving (ADR-0052, decision 6): bank in the turn, rad, and how far it moves sideways,
## into the frame's depth, per metre of path to the right; the nose yaws the same way.
const BANK_MAX: float = 0.3
const LEAVE_AWAY: float = 0.28
const LEAVE_YAW: float = 0.32
## How long it hovers with the door closed before leaving, s: the pilot nods.
const NOD_TIME: float = 0.55

## The pilot sits in the seat: how far the feet are below the cushion and ahead of it, m.
const PILOT_FEET := Vector3(0.36, -0.36, 0.0)

## Lights: green navigation light on the near side (the nose faces right, toward the
## camera is the starboard side), red beacon top and bottom, white strobe on the tail.
const NAV_GREEN := Color(0.25, 1.0, 0.45)
const BEACON_RED := Color(1.0, 0.12, 0.08)
const STROBE_WHITE := Color(1.0, 1.0, 1.0)
const LIGHT_SIZE: float = 0.07
## The beacon blinks once a second, the strobe — double, once every second and a half.
const BEACON_PERIOD: float = 1.0
const STROBE_PERIOD: float = 1.5
const FLASH: float = 0.07

## Searchlight under the nose: a spot on the roof while the helicopter hovers. No
## shadows — it burns for a couple of seconds, and a shadow is not worth paying for.
const SEARCH_ENERGY: float = 10.0
const SEARCH_RANGE: float = 11.0
const SEARCH_ANGLE: float = 20.0
const SEARCH_COLOR := Color(0.92, 0.95, 1.0)

## Cabin light from the open door: warm, dim, reaching a couple of metres.
const CABIN_COLOR := Color(1.0, 0.78, 0.5)
const CABIN_ENERGY: float = 1.6
const CABIN_RANGE: float = 3.4

## Sound: the hover loop plays the whole scene, loudest when hovering, quieter in motion;
## the flyby is a second layer, heard in motion and silent when hovering. Both on the
## helicopter itself — positional, heard for [constant ENGINE_REACH] metres.
const ENGINE_REACH: float = 50.0
## Hover loop volume at rest and at full speed, dB; pitch at full speed.
const HOVER_DB: float = 0.0
const HOVER_DB_MOVING: float = -7.0
const HOVER_PITCH_MOVING: float = 1.06
## The speed at which the flyby plays at full strength, m/s, and its volume, dB.
const PASS_FULL_SPEED: float = 9.0
const PASS_DB: float = -2.0
## Below this the layer counts as silent, dB.
const SILENT_DB: float = -60.0
## How fast the volume follows the speed, 1/s: without smoothing, the braking jerk
## would be heard as a click.
const VOLUME_EASE: float = 4.0

## One rim for all helicopters: the shader compiles once per launch, not for every
## building when the helicopter flies into the frame.
static var _rim_material: ShaderMaterial = null
## Rotor blur disc shader, also once per launch ([method _blur_shader]).
static var _blur_code: Shader = null

## In the morning and daytime the searchlight is off (ADR-0052): set before [method fly_in].
var daytime: bool = false

var _phase: Phase = Phase.ARRIVING
var _time: float = 0.0
var _hover := Vector3.ZERO
var _from := Vector3.ZERO
## Speed visible from the motion, m/s: the fuselage leans by it, and the departure
## starts from it — one interrupted mid-arrival does not stop with a jerk.
var _velocity := Vector3.ZERO
var _tilt: float = 0.0
var _left_from := Vector3.ZERO
var _leave_in: float = 0.0
var _leaving_set: bool = false

var _body: Node3D = null
var _rotor: Node3D = null
var _tail_rotor: Node3D = null
## Model points: lights, searchlight, cabin light, winch — in node coordinates.
var _marks: Dictionary = {}
var _hook := Vector3.ZERO
var _rope: MeshInstance3D = null
var _rope_length: float = 0.0
var _rope_wanted: float = 0.0
## The coil flies down: the rope is paid out by falling, not by the winch.
var _dropping: bool = false
var _drop_speed: float = 0.0
## Rope angle from plumb in the play plane, rad, and its rate.
var _swing: float = 0.0
var _swing_speed: float = 0.0
var _door: Node3D = null
var _door_closed := Vector3.ZERO
var _door_slide: float = 0.0
## Door open fraction, 0–1, and where it is heading.
var _door_share: float = 0.0
var _door_wanted: float = 0.0
var _door_voice: AudioStreamPlayer3D = null
var _winch_voice: AudioStreamPlayer3D = null
var _pilot: FigureRig = null
## Dust under the rotor ([Downwash]).
var _dust: Downwash = null
## How much longer the pilot nods, s.
var _nod: float = 0.0
## Departure steps: reel in the rope, close the door, nod — and only then fly.
var _nodded: bool = false
var _beacons: Array[Node3D] = []
var _strobe: Node3D = null
var _search: SpotLight3D = null
var _cabin: OmniLight3D = null
var _engine: AudioStreamPlayer3D = null
var _pass: AudioStreamPlayer3D = null
var _rope_voice: AudioStreamPlayer3D = null
## Motion fraction for layer volumes, 0 — hovering, 1 — full speed; smoothed.
var _motion: float = 1.0
## Bounds of the fuselage with the winch boom and bounds of the rotor disc in node
## coordinates, at zero tilt; and the same with all tilts up to [constant TILT_MAX].
var _hull_local := AABB()
var _rotor_local := AABB()
var _hull_reach := AABB()
var _rotor_reach := AABB()
## The same on departure — with the turn's bank and yaw (code review M24k).
var _hull_leave := AABB()
var _rotor_leave := AABB()
## Roof equipment to pass over: bounds in scene coordinates.
var _obstacles: Array[AABB] = []


func _init() -> void:
	name = "Helicopter"
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_dress()
	# Rain and snow die on the fuselage, but not on the rotor disc and the rope (ADR-0054).
	var spinning: Array[Node] = [_rotor, _tail_rotor, _rope]
	Shelter.over_meshes(_body, spinning)


## Starts the arrival: the helicopter appears past the left edge and heads to
## [param hover] — the point under the rotor axis at skid level, in scene coordinates.
##
## The point is raised above the roof equipment if that is higher ([method safe_hover]).
##
## [param already_there] — the short intro (ADR-0052, decision 6): from the first frame
## the helicopter hovers over the point with the door open.
func fly_in(hover: Vector3, already_there: bool = false) -> void:
	_hover = safe_hover(hover)
	_from = _hover + Vector3(-ARRIVAL_DISTANCE, ARRIVAL_RISE, 0.0)
	_phase = Phase.ARRIVING
	_time = 0.0
	position = _from
	_velocity = Vector3.ZERO
	_start_engine()
	if already_there:
		position = _hover
		_from = _hover
		_time = ARRIVAL_TIME
		_door_share = 1.0
		_door_wanted = 1.0
		_place_door()
		_motion = 0.0


## Rolls the sliding door back — the cabin lights up in the opening — or closes it,
## [param open] = false.
func set_door_open(open: bool) -> void:
	var wanted := 1.0 if open else 0.0
	if not is_equal_approx(_door_wanted, wanted):
		_door_wanted = wanted
		_door_sound()


## How open the door is, 0–1: 1 — wide open.
func door_share() -> float:
	return _door_share


## Threshold of the door opening in scene coordinates: middle along the opening, on
## the cabin floor, at the near side.
func doorway() -> Vector3:
	return _body.to_global(_marks["Doorway"])


## Drops the rope coil: the rope unwinds by falling for [param length] metres and swings
## as a pendulum until the rotor wash calms it.
func drop_rope(length: float) -> void:
	_rope_wanted = maxf(length, 0.0)
	_dropping = true
	_drop_speed = 0.0
	_swing_speed = ROPE_KICK * 3.0
	# The coil drop sounds at the hook it falls from.
	Sounds.play_at(self, Sounds.ROPE_DROP, hook(), ENGINE_REACH)


## Point on the rope [param along] metres from the hook — with the rope's swing.
func rope_point(along: float) -> Vector3:
	var reach := clampf(along, 0.0, _rope_length)
	return hook() + Vector3(sin(_swing) * reach, -cos(_swing) * reach, 0.0)


## What on the roof obstructs flight: bounds in scene coordinates. The arrival path,
## hover and departure pass over them with margin [constant CLEARANCE]. [param deck] —
## height of the roof itself, scene: the rotor wash blows dust onto it ([Downwash]),
## in snow — snow dust with brightness [param snow]; below zero — no snow.
func avoid(obstacles: Array[AABB], deck: float = NAN, snow: float = -1.0) -> void:
	_obstacles = obstacles
	if is_nan(deck):
		return
	if _dust == null:
		_dust = Downwash.new()
		add_child(_dust)
	_dust.deck = deck
	if snow >= 0.0:
		_dust.lift_snow(snow)


## Hover point over [param hover], raised above the roof equipment if needed.
func safe_hover(hover: Vector3) -> Vector3:
	return Vector3(hover.x, maxf(hover.y, clear_height(hover.x)), DEPTH_Z)


## The height below which the skids must not drop when the rotor axis is over
## [param x] — over all roof equipment, at any fuselage tilt and with margin.
## Over neighbours the height falls off along the slope [constant CLEAR_SLOPE]: the
## path gains it in advance. Nothing in the way — minus infinity.
##
## [param leaving] — on departure: the fuselage is banked and yawed, and the node has
## moved into depth by [param depth] (along scene Z).
func clear_height(x: float, leaving: bool = false, depth: float = DEPTH_Z) -> float:
	var lowest := -INF
	var reaches: Array[AABB] = [_hull_reach, _rotor_reach]
	if leaving:
		reaches = [_hull_leave, _rotor_leave]
	for obstacle: AABB in _obstacles:
		for reach: AABB in reaches:
			var near := depth + reach.position.z - CLEARANCE
			var far := depth + reach.end.z + CLEARANCE
			if obstacle.end.z < near or obstacle.position.z > far:
				continue
			var left := x + reach.position.x - CLEARANCE
			var right := x + reach.end.x + CLEARANCE
			var gap := maxf(maxf(obstacle.position.x - right, left - obstacle.end.x), 0.0)
			var needed := obstacle.end.y + CLEARANCE - reach.position.y - gap * CLEAR_SLOPE
			lowest = maxf(lowest, needed)
	return lowest


## How far the top of the helicopter with the rotor is above the skids at any tilt, m.
func top_above_skids() -> float:
	return maxf(_hull_reach.end.y, _rotor_reach.end.y)


## Bounds of the fuselage with the winch boom now, in scene coordinates.
func hull_box() -> AABB:
	return _body.global_transform * _hull_local


## Bounds of the rotor disc now, in scene coordinates: the rotor spins, and the bounds
## are taken over the whole disc, not the blades at this instant.
func rotor_box() -> AABB:
	return _body.global_transform * _rotor_local


## Whether it hovers over the point — arrived and not yet left.
func is_hovering() -> bool:
	return _phase == Phase.HOVERING and not _leaving_set


## Whether it has left — is flying away or has already decided to.
func is_leaving() -> bool:
	return _phase == Phase.LEAVING or _leaving_set


## Where the rope leaves the winch, in scene coordinates: the boom carries it into the
## play plane.
func hook() -> Vector3:
	return _body.to_global(_hook)


## Where the hook would hang over the hover point: the level places Otto by it in
## advance, while the helicopter is still flying.
func hook_at_hover(hover: Vector3) -> Vector3:
	return Vector3(hover.x, hover.y, DEPTH_Z) + _hook


## How much rope is paid out now, m.
func rope_length() -> float:
	return _rope_length


## All of the rope is paid out.
func rope_is_down() -> bool:
	return _rope_wanted > 0.0 and is_equal_approx(_rope_length, _rope_wanted)


## Reels in the rope, closes the door, the pilot nods — and the helicopter leaves right,
## up and to the side, after [param delay] seconds of hovering. Also called mid-arrival:
## the helicopter does not finish a skipped intro, but leaves from the place and at
## the speed it had.
func leave(delay: float = 0.0) -> void:
	_rope_wanted = 0.0
	_dropping = false
	_leave_in = delay
	_leaving_set = true
	if _rope_length > 0.01:
		_winch(true)
	if _search != null:
		_search.visible = false


func _physics_process(delta: float) -> void:
	_time += delta
	var before := position
	match _phase:
		Phase.ARRIVING:
			_arrive()
		Phase.HOVERING:
			_hang()
		Phase.LEAVING:
			_fly_off(delta)
			if position.distance_to(_left_from) > GONE_AFTER:
				queue_free()
				return

	var seen := (position - before) / maxf(delta, 0.0001)
	var acceleration := (seen - _velocity) / maxf(delta, 0.0001)
	_velocity = seen
	_lean(acceleration, delta)
	_wind_rope(delta)
	_slide_door(delta)
	_pose_pilot(delta)
	_raise_dust()
	_blink()
	_mix_engine(delta)


func _process(delta: float) -> void:
	if _rotor != null:
		_rotor.rotate_object_local(Vector3.UP, ROTOR_SPEED * delta)
	if _tail_rotor != null:
		_tail_rotor.rotate_object_local(Vector3.BACK, TAIL_ROTOR_SPEED * delta)


## Arrival along the [method _arrival_progress] curve: cruising speed at entry, dying
## to nothing at the point.
func _arrive() -> void:
	var u := clampf(_time / ARRIVAL_TIME, 0.0, 1.0)
	position = _from.lerp(_hover, _arrival_progress(u))
	position.y = maxf(position.y, clear_height(position.x))
	if u >= 1.0:
		_phase = Phase.HOVERING
		_time = 0.0
		if not _leaving_set:
			_show_hover_lights(true)
	elif _leaving_set:
		_start_leaving()


## Fraction of the path to the hover point: a cubic with an initial speed of one and a
## half paths per arrival time, no acceleration at entry and zero speed at the end.
static func _arrival_progress(u: float) -> float:
	return 1.5 * u - 0.5 * u * u * u


func _hang() -> void:
	position = _hover + Vector3(0.0, sin(_time * BOB_RATE * TAU) * BOB_HEIGHT, 0.0)
	if not _leaving_set:
		return
	_leave_in -= get_physics_process_delta_time()
	# Leaves with the rope reeled in and the door closed: a dangling end on departure
	# looks like a breakage, and an open door — like a forgotten one.
	if _leave_in > 0.0 or _rope_length > 0.0:
		return
	if _door_share > 0.0:
		set_door_open(false)
		return
	if not _nodded:
		_nodded = true
		_nod = NOD_TIME
		_leave_in = NOD_TIME
		return
	_start_leaving()


func _start_leaving() -> void:
	_phase = Phase.LEAVING
	_left_from = position
	_time = 0.0


func _fly_off(delta: float) -> void:
	var speed := minf(maxf(_velocity.x, 0.0) + LEAVE_ACCELERATION * delta, LEAVE_SPEED)
	position += Vector3(speed, speed * LEAVE_CLIMB, -speed * LEAVE_AWAY) * delta
	position.y = maxf(position.y, clear_height(position.x, true, position.z))
	# Bank and yaw in the turn sideways — by the speed gained.
	var turn := clampf(speed / LEAVE_SPEED, 0.0, 1.0)
	_body.rotation.x = -BANK_MAX * turn
	_body.rotation.y = LEAVE_YAW * turn


## Leans the fuselage by acceleration and drag — nose down when accelerating and at
## full speed, nose up when braking.
func _lean(acceleration: Vector3, delta: float) -> void:
	var push := acceleration.x + DRAG * _velocity.x
	var wanted := clampf(atan2(push, 9.8) * TILT_GAIN, -TILT_MAX, TILT_MAX)
	_tilt = lerpf(_tilt, wanted, 1.0 - exp(-TILT_EASE * delta))
	# Clockwise rotation around Z — the nose, facing +X, goes down.
	_body.rotation.z = -_tilt


func _wind_rope(delta: float) -> void:
	if _dropping and _rope_length < _rope_wanted:
		_drop_speed = minf(_drop_speed + ROPE_DROP_PULL * delta, ROPE_DROP_TOP)
		_rope_length = minf(_rope_length + _drop_speed * delta, _rope_wanted)
	else:
		var was := _rope_length
		_rope_length = move_toward(_rope_length, _rope_wanted, ROPE_SPEED * delta)
		if was > 0.0 and _rope_length <= 0.0:
			_winch(false)
	_swing_rope(delta)
	_rope.visible = _rope_length > 0.01
	# The rope hangs from the hook however the fuselage leans: it is on a hook, not a
	# stick, and swings as a pendulum in the play plane.
	var top := hook()
	var tilt := Basis(Vector3.BACK, _swing)
	_rope.global_basis = tilt * Basis.from_scale(Vector3(1.0, maxf(_rope_length, 0.01), 1.0))
	_rope.global_position = top + tilt * Vector3(0.0, -_rope_length * 0.5, 0.0)


## Rope pendulum: frequency from the length, damping of its own, and the rotor wash
## pushes it with a slow wave.
func _swing_rope(delta: float) -> void:
	if _rope_length <= 0.05:
		_swing = 0.0
		_swing_speed = 0.0
		return
	var rate := 9.8 / maxf(_rope_length, 0.5)
	var draft := sin(_time * ROPE_DRAFT_RATE * TAU) * ROPE_DRAFT
	_swing_speed += (-rate * (_swing - draft) - ROPE_DAMPING * _swing_speed) * delta
	_swing += _swing_speed * delta


## The door moves toward open or closed: first it moves out from the side, then rolls
## back along the rails.
func _slide_door(delta: float) -> void:
	if is_equal_approx(_door_share, _door_wanted):
		return
	_door_share = move_toward(_door_share, _door_wanted, delta / DOOR_TIME)
	_place_door()


func _place_door() -> void:
	if _door != null:
		var pop := clampf(_door_share * 5.0, 0.0, 1.0)
		var slide := smoothstep(0.15, 1.0, _door_share)
		_door.position = _door_closed + Vector3(-_door_slide * slide, 0.0, DOOR_POP * pop)
	# The cabin is lit while the door is open.
	if _cabin != null:
		_cabin.visible = _door_share > 0.05


## Dust rises under the rotor while the helicopter hovers low over the roof, and
## settles when it leaves.
func _raise_dust() -> void:
	if _dust != null:
		_dust.follow(position.x, position.y, _phase != Phase.LEAVING)


## The pilot sits, and nods on departure.
func _pose_pilot(delta: float) -> void:
	if _pilot == null:
		return
	_nod = maxf(_nod - delta, 0.0)
	_pilot.show_pose("pilot_nod" if _nod > NOD_TIME * 0.45 else "pilot_sit")


func _blink() -> void:
	var beacon := fmod(_time, BEACON_PERIOD) < FLASH * 1.6
	for light: Node3D in _beacons:
		light.visible = beacon
	var strobe := fmod(_time + 0.4, STROBE_PERIOD)
	_strobe.visible = strobe < FLASH or (strobe > FLASH * 2.5 and strobe < FLASH * 3.5)


## Door clang at its place.
func _door_sound() -> void:
	if _door_voice != null:
		_door_voice.global_position = doorway()
		_door_voice.play()


## The winch reels in the rope — hums while it runs.
func _winch(on: bool) -> void:
	if _winch_voice == null:
		return
	if on:
		_winch_voice.global_position = hook()
		_winch_voice.play()
	else:
		_winch_voice.stop()


## Sound of Otto sliding down the rope — at the hook the rope runs from. [param on] —
## start; false — cut off, if Otto is already down or the scene was skipped.
func rope_slide(on: bool) -> void:
	if _rope_voice == null:
		return
	if on:
		_rope_voice.global_position = hook()
		_rope_voice.play()
	else:
		_rope_voice.stop()


## Starts the hover loop and the flyby layer: both play from arrival to departure, and
## [method _mix_engine] splits the volume between them.
func _start_engine() -> void:
	if _engine != null:
		return
	_engine = Sounds.source(self, Sounds.HELICOPTER, ENGINE_REACH)
	_engine.volume_db = HOVER_DB_MOVING
	_engine.play()
	_pass = Sounds.source(self, Sounds.HELICOPTER_PASS, ENGINE_REACH)
	_pass.volume_db = PASS_DB
	_pass.play()
	_rope_voice = Sounds.source(self, Sounds.ROPE_SLIDE, ENGINE_REACH)
	_rope_voice.top_level = true
	_door_voice = Sounds.source(self, Sounds.HELI_DOOR, ENGINE_REACH)
	_door_voice.top_level = true
	_winch_voice = Sounds.source(self, Sounds.WINCH, ENGINE_REACH)
	_winch_voice.top_level = true


## Volume by motion: the faster it flies, the quieter the hover and the louder the flyby.
func _mix_engine(delta: float) -> void:
	if _engine == null:
		return
	var wanted := clampf(absf(_velocity.x) / PASS_FULL_SPEED, 0.0, 1.0)
	_motion = lerpf(_motion, wanted, 1.0 - exp(-VOLUME_EASE * delta))
	_engine.volume_db = lerpf(HOVER_DB, HOVER_DB_MOVING, _motion)
	_engine.pitch_scale = lerpf(1.0, HOVER_PITCH_MOVING, _motion)
	_pass.volume_db = maxf(PASS_DB + linear_to_db(maxf(_motion, 0.0001)), SILENT_DB)


## Assembles the look: the model with a repainted fuselage, rotors with blur discs,
## the winch with the rope, lights and searchlight at the model's points.
func _dress() -> void:
	var model := MODEL.instantiate() as Node3D
	_body.add_child(model)
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		_repaint(node as MeshInstance3D)
	_rotor = model.find_child("MainRotor", true, false) as Node3D
	_tail_rotor = model.find_child("TailRotor", true, false) as Node3D
	# Length by the fuselage: the model is built in metres, but if re-exported with a
	# different length it will not diverge from the game.
	var hull := _parts_box(model, ["Hull", "Skids"])
	var fit := LENGTH / maxf(hull.size.x, 0.001)
	model.scale = Vector3.ONE * fit
	hull = _parts_box(model, ["Hull", "Skids"])
	for mark: String in [
		"NavGreen",
		"BeaconTop",
		"BeaconBelly",
		"Strobe",
		"Searchlight",
		"CabinLight",
		"Winch",
		"PilotSeat",
	]:
		var anchor := model.find_child(mark, true, false) as Node3D
		_marks[mark] = _chain(_body, anchor).origin if anchor != null else hull.get_center()
	_fit_door(model)
	_seat_pilot()
	_blur(_rotor, 4.0, false)
	_blur(_tail_rotor, 2.0, true)
	_hang_winch(hull)
	_hang_lights()
	_measure(hull, model)


## The model's door: closed, at its origin; rolls back by its own length minus the
## edge at the opening. The opening's threshold is the bottom of the door at the near side.
func _fit_door(model: Node3D) -> void:
	_door = model.find_child("Door", true, false) as Node3D
	var door_mesh := _door as MeshInstance3D
	if door_mesh == null:
		_marks["Doorway"] = _marks["CabinLight"]
		return
	_door_closed = _door.position
	var box := door_mesh.mesh.get_aabb()
	_door_slide = maxf(box.size.x - DOOR_KEEP, 0.0)
	var placed := _chain(_body, door_mesh) * box
	_marks["Doorway"] = Vector3(placed.get_center().x, placed.position.y, placed.position.z)


## The pilot in the seat, facing the nose. The rig puts the pose on the floor by the
## feet — its origin is under the feet, ahead of and below the seat cushion.
func _seat_pilot() -> void:
	_pilot = FigureRig.new()
	_pilot.name = "Pilot"
	_pilot.model = PILOT_MODEL
	_pilot.position = _marks["PilotSeat"] + PILOT_FEET
	_body.add_child(_pilot)
	_pilot.face(1.0, true)


## Bounds of the model's [param names] parts in node coordinates.
func _parts_box(model: Node3D, names: Array[String]) -> AABB:
	var box := AABB()
	var first := true
	for part_name: String in names:
		var part := model.find_child(part_name, true, false) as MeshInstance3D
		if part == null:
			continue
		var placed := _chain(_body, part) * part.mesh.get_aabb()
		box = placed if first else box.merge(placed)
		first = false
	return box


## Bounds for passing over the roof: the fuselage with the winch boom up to the play
## plane, and the rotor disc — a circle with the blade-tip radius.
func _measure(hull: AABB, model: Node3D) -> void:
	var near := maxf(hull.end.z, -DEPTH_Z)
	_hull_local = AABB(hull.position, Vector3(hull.size.x, hull.size.y, near - hull.position.z))
	var disc := _parts_box(model, ["MainRotor"])
	var centre := _chain(_body, _rotor).origin if _rotor != null else disc.get_center()
	var radius := maxf(disc.size.x, disc.size.z) * 0.5
	_rotor_local = AABB(
		Vector3(centre.x - radius, disc.position.y, centre.z - radius),
		Vector3(radius * 2.0, disc.size.y, radius * 2.0)
	)
	_hull_reach = _tilted(_hull_local)
	_rotor_reach = _tilted(_rotor_local)
	_hull_leave = _banked(_hull_local)
	_rotor_leave = _banked(_rotor_local)


## Repaints the model's parts by material name: fuselage, glass, cabin opening.
static func _repaint(mesh: MeshInstance3D) -> void:
	for index: int in mesh.mesh.get_surface_count():
		var source := mesh.mesh.surface_get_material(index)
		var wanted := _paint(source.resource_name if source != null else "")
		if wanted != null:
			mesh.set_surface_override_material(index, wanted)


## Blur disc under the blades of rotor [param rotor]: a circle in the plane of
## rotation, spinning with the rotor. [param upright] — the plane is vertical, along
## the fuselage (tail rotor), otherwise horizontal (main). The plane is given
## explicitly, not guessed from the bounds: for a two-blade tail rotor the thinnest
## axis of the bounds is the blade chord, not the rotation axis, and the disc lay
## flat and tumbled around the axis (code review M24i).
func _blur(rotor: Node3D, blades: float, upright: bool) -> void:
	var mesh := rotor as MeshInstance3D
	if mesh == null:
		return
	var box := mesh.mesh.get_aabb()
	var radius := maxf(maxf(box.size.x, box.size.z), box.size.y) * 0.5
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * radius * 2.0
	var look := ShaderMaterial.new()
	look.shader = _blur_shader()
	look.set_shader_parameter(&"tint", Color(ROTOR_COLOR, BLUR_ALPHA))
	look.set_shader_parameter(&"blades", blades)
	quad.material = look
	var disc := MeshInstance3D.new()
	disc.name = "Blur"
	disc.mesh = quad
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The mesh's plane is XZ; the tail rotor needs it in XY, facing along +Z.
	if upright:
		disc.rotation.x = PI * 0.5
	rotor.add_child(disc)


## Blur disc shader — one for all helicopters, like the rim ([method _rim]): the
## helicopter arrives at every building, and a new shader would be built for each.
static func _blur_shader() -> Shader:
	if _blur_code != null:
		return _blur_code
	_blur_code = Shader.new()
	_blur_code.code = BLUR_SHADER
	return _blur_code


## Bounds of [param box] at all tilts up to [constant TILT_MAX]: at small angles the
## extreme points are at the ends of the range and at zero.
static func _tilted(box: AABB) -> AABB:
	var reach := box
	for angle: float in [-TILT_MAX, TILT_MAX]:
		reach = reach.merge(Transform3D(Basis(Vector3.BACK, angle), Vector3.ZERO) * box)
	return reach


## Bounds of [param box] on departure: nose tilts, bank up to [constant BANK_MAX] and
## yaw up to [constant LEAVE_YAW] — in the order the departure applies them.
static func _banked(box: AABB) -> AABB:
	var reach := box
	for pitch: float in [-TILT_MAX, 0.0, TILT_MAX]:
		for bank: float in [-BANK_MAX, 0.0]:
			for yaw: float in [0.0, LEAVE_YAW]:
				var turn := Basis.from_euler(Vector3(bank, yaw, -pitch))
				reach = reach.merge(Transform3D(turn, Vector3.ZERO) * box)
	return reach


## Winch boom over the door: from the near side into the play plane. The rope hangs
## from its end, and Otto on it is in the play plane, as everywhere.
func _hang_winch(hull: AABB) -> void:
	var winch: Vector3 = _marks["Winch"]
	var near_side := minf(winch.z, hull.end.z)
	var reach := -DEPTH_Z - near_side
	var arm := GreyboxLook.box(
		Vector3(0.08, 0.08, reach + 0.1), GreyboxLook.metal(Color(0.3, 0.31, 0.33))
	)
	arm.name = "WinchArm"
	arm.position = Vector3(winch.x, winch.y, near_side + reach * 0.5)
	_body.add_child(arm)
	_hook = Vector3(winch.x, winch.y - 0.06, -DEPTH_Z)

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = ROPE_RADIUS
	cylinder.bottom_radius = ROPE_RADIUS
	cylinder.height = 1.0
	cylinder.radial_segments = 6
	cylinder.rings = 1
	cylinder.material = GreyboxLook.surface(ROPE_COLOR)
	_rope = MeshInstance3D.new()
	_rope.name = "Rope"
	_rope.mesh = cylinder
	_rope.visible = false
	_rope.top_level = true
	add_child(_rope)


func _hang_lights() -> void:
	var green := _light(NAV_GREEN, _marks["NavGreen"])
	green.name = "NavGreen"
	var top := _light(BEACON_RED, _marks["BeaconTop"])
	top.name = "BeaconTop"
	var belly := _light(BEACON_RED, _marks["BeaconBelly"])
	belly.name = "BeaconBelly"
	_beacons = [top, belly]
	_strobe = _light(STROBE_WHITE, _marks["Strobe"])
	_strobe.name = "Strobe"

	_search = SpotLight3D.new()
	_search.name = "Searchlight"
	_search.light_color = SEARCH_COLOR
	_search.light_energy = SEARCH_ENERGY
	_search.spot_range = SEARCH_RANGE
	_search.spot_angle = SEARCH_ANGLE
	_search.shadow_enabled = false
	# The cone is visible in the haze over the roof ([RoofRain]), where there is haze.
	_search.light_volumetric_fog_energy = Graphics.light_in_fog() * 2.0
	_search.position = _marks["Searchlight"]
	# Points down and slightly forward: the spot falls where Otto descends.
	_search.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	_search.rotate_z(deg_to_rad(12.0))
	_body.add_child(_search)

	# Cabin light from the open door: falls on Otto while he steps onto the rope, and
	# on the side by the door — without it the fuselage is only a silhouette at night.
	_cabin = OmniLight3D.new()
	_cabin.name = "CabinLight"
	_cabin.light_color = CABIN_COLOR
	_cabin.light_energy = CABIN_ENERGY
	_cabin.omni_range = CABIN_RANGE
	_cabin.shadow_enabled = false
	_cabin.position = _marks["CabinLight"]
	_body.add_child(_cabin)
	_show_hover_lights(false)


## The searchlight and cabin light are on only while the helicopter hovers with the
## door open: an extra light in the frame for a couple of seconds, not the whole flight.
func _show_hover_lights(on: bool) -> void:
	if _search != null:
		_search.visible = on and not daytime
	if _cabin != null:
		_cabin.visible = on and _door_share > 0.05


func _light(color: Color, at: Vector3) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = LIGHT_SIZE
	sphere.height = LIGHT_SIZE * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.material = GreyboxLook.light(color)
	var light := MeshInstance3D.new()
	light.mesh = sphere
	light.position = at
	light.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(light)
	return light


## Transform from the space of mesh [param leaf] to the space of [param root]: the
## nodes are not in the tree yet and have no global coordinates.
static func _chain(root: Node3D, leaf: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var node: Node = leaf
	while node != null and node != root:
		var spatial := node as Node3D
		if spatial != null:
			xf = spatial.transform * xf
		node = node.get_parent()
	return xf


## A part's material by the model's material name: fuselage, glazing, cabin opening
## and rotor get their own, the rest stays as in the model.
static func _paint(material_name: String) -> Material:
	match material_name:
		"Hull":
			var hull := StandardMaterial3D.new()
			hull.albedo_color = HULL_COLOR
			hull.metallic = 0.55
			hull.roughness = 0.32
			hull.next_pass = _rim()
			return hull
		"Glass":
			var glass := StandardMaterial3D.new()
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.albedo_color = Color(GLASS_COLOR, GLASS_ALPHA)
			glass.metallic = 0.2
			glass.roughness = 0.08
			glass.emission_enabled = true
			glass.emission = GLASS_GLOW
			glass.emission_energy_multiplier = GLASS_GLOW_ENERGY
			return glass
		"Cabin":
			var cabin := StandardMaterial3D.new()
			cabin.albedo_color = CABIN_GLOW.darkened(0.5)
			cabin.emission_enabled = true
			cabin.emission = CABIN_GLOW
			cabin.emission_energy_multiplier = CABIN_GLOW_ENERGY
			return cabin
		"Rotor":
			return GreyboxLook.metal(ROTOR_COLOR)
	return null


## Second fuselage pass — a cold rim along the silhouette's edges.
static func _rim() -> ShaderMaterial:
	if _rim_material != null:
		return _rim_material
	var shader := Shader.new()
	shader.code = RIM_SHADER
	_rim_material = ShaderMaterial.new()
	_rim_material.shader = shader
	_rim_material.set_shader_parameter(&"rim_color", RIM_COLOR)
	_rim_material.set_shader_parameter(&"rim_power", RIM_POWER)
	_rim_material.set_shader_parameter(&"rim_strength", RIM_STRENGTH)
	return _rim_material
