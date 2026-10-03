class_name GarageGate
extends Node3D

## Garage gate in the left end wall of the bottom floor (ADR-0038, decision 3): an opening
## in the wall, a roller shutter, a housing under the ceiling, a beacon, stripes at the
## threshold, an EXIT sign and the ramp up beyond the gate.
##
## Its own node, not part of [Garage]: the gate has its own state — how far the shutter is
## raised — and it is moved by finishing the building, not by the layout.
##
## The camera sees the end wall edge-on, and a shutter in its plane is, from the camera, a
## line five centimetres thick. So the shutter has a face: in the opening the
## back face of the opening is visible, the shutter slats are on it, and they roll up together
## with the real shutter, revealing the orange light of the street light over the ramp
## behind them. Everything else that says "gate" faces the camera: the housing, the guide,
## the beacon, the stripes, the sign.
##
## The wall body stays whole — [BuildingShell] builds it invisible, and the visible
## pieces around the opening are placed here. Otto does not go out through the gate; the car
## — looks without a body — drives through.

## How long raising the shutter takes by default, s.
const OPEN_TIME: float = 1.6
## Opening height, m: a car with a 1.2 m roof passes with a margin.
const HEIGHT: float = 2.4
## Shutter housing: projection from the wall and height, m.
const BOX := Vector2(0.38, 0.3)
## Shutter and guides: shutter thickness, guide cross-section, slat pitch and
## bottom bar (depth, height), m.
const SHUTTER_THICKNESS: float = 0.05
const RAIL: float = 0.1
const SLAT_PITCH: float = 0.12
const SHUTTER_BAR := Vector2(0.06, 0.07)
## Ramp beyond the gate: landing by the opening, rise length, m. The rise is one floor.
const RAMP_APRON: float = 3.0
const RAMP_RUN: float = 12.0

const SHUTTER := Color(0.64, 0.66, 0.68)
## Gate beacon — amber — and the street behind the shutter: a sodium light over the ramp.
const BEACON := Color(1.0, 0.55, 0.1)
const OUTSIDE := Color(0.78, 0.5, 0.2)

## EXIT sign above the gate: a green indicator light, like the former exit sign
## (ADR-0019, decision 5; ADR-0023, decision 6) — the exit must read even on a
## dark floor. It hangs on the lintel, facing the camera.
const EXIT_SIGN := Vector3(0.9, 0.24, 0.06)
const EXIT_INK := Color(0.02, 0.12, 0.05)

## Shutter motor ([constant Sounds.GARAGE_GATE]): how far it is heard, m, and how fast
## it fades when the shutter has reached the top, s. The recording is longer than the
## rise — the motor is cut by the shutter rather than playing on for nothing.
const VOICE_REACH: float = 16.0
const VOICE_FADE: float = 0.4

## How open the gate is: 0 — shutter down, 1 — raised into the housing.
var openness: float = 0.0:
	set = set_openness

var _rules: BuildingRules = null
var _surface: float = 0.0
var _top: float = 0.0
## The shutter, its bottom bar and the street behind it: [member openness] moves them.
var _roll: Node3D = null
var _shutter_bar: MeshInstance3D = null
var _outside: MeshInstance3D = null
## Beacon above the gate: lit while the shutter moves.
var _beacon: MeshInstance3D = null
## Shutter motor: a positional source by the opening, started on the first raise.
var _voice: AudioStreamPlayer3D = null
## The exit beyond the gate: it has a street light that is lit while the bottom floor is in
## frame.
var _ramp: GarageRamp = null
## Building seed: the street beyond the exit and its weather go by it.
var _seed: int = 1


## Builds the gate at the left wall of the bottom floor.
func build(rules: BuildingRules, building_seed: int = 1) -> void:
	_rules = rules
	_seed = building_seed
	var bottom := rules.floors - 1
	_surface = rules.floor_surface(bottom)
	_top = rules.story_top(bottom)
	_build_opening()
	_build_shutter()
	_build_frame()
	_build_ramp()
	_hang_the_sign()
	set_openness(openness)


## Raises the shutter over [param duration] seconds to the gate motor sound. Runs in physics
## steps, like everything in finishing a building: the outcome must not depend on frame rate.
## Returns the tween — its [signal Tween.finished] is "the gate is open".
func open(duration: float = OPEN_TIME) -> Tween:
	_start_the_motor()
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(self, "openness", 1.0, duration)
	tween.finished.connect(_stop_the_motor)
	return tween


## The shutter motor sounds from the opening: it is heard near the gate, not throughout the
## building.
func _start_the_motor() -> void:
	if _voice == null:
		var host := Node3D.new()
		host.name = "Voice"
		host.position = _at(Garage.gate_x(_rules), _surface - HEIGHT * 0.5, 0.0)
		add_child(host)
		_voice = Sounds.source(host, Sounds.GARAGE_GATE, VOICE_REACH)
	_voice.volume_db = 0.0
	_voice.play()


func _stop_the_motor() -> void:
	if _voice == null or not _voice.playing:
		return
	var fade := create_tween()
	fade.tween_property(_voice, "volume_db", -60.0, VOICE_FADE)
	fade.tween_callback(_voice.stop)


## Whether the gate is fully open.
func is_open() -> bool:
	return openness >= 1.0


func set_openness(value: float) -> void:
	openness = clampf(value, 0.0, 1.0)
	if _roll == null:
		return
	# The shutter rolls up into the housing: the shutter node hangs by its top at the lintel,
	# and the height goes away from below.
	var hanging := 1.0 - openness
	_roll.visible = hanging > 0.005
	_roll.scale.y = maxf(hanging, 0.001)
	_shutter_bar.position.y = WorldSpace.height_to_scene(
		_surface - HEIGHT * openness - SHUTTER_BAR.y * 0.5 - 0.002
	)
	var moving := openness > 0.0 and openness < 1.0
	_beacon.material_override = (
		GreyboxLook.light(BEACON) if moving else GreyboxLook.surface(BEACON.darkened(0.6))
	)
	_outside.visible = openness > 0.0


## Opening: the lintel above it through the full depth and the hall wall behind it — masonry,
## like the outer walls ([BuildingShell]); behind the shutter — the street light over the ramp.
func _build_opening() -> void:
	var masonry := GreyboxLook.surface(
		GreyboxLook.WALL.lerp(_rules.palette.masonry, BuildingShell.PALETTE_SHARE)
	)
	var wall := BuildingShell.WALL_WIDTH
	var full := WorldSpace.CORRIDOR_DEPTH + WorldSpace.ROOM_DEPTH
	var gate_top := _surface - HEIGHT
	var x := Garage.gate_x(_rules)
	_box(
		Vector3(wall, gate_top - _top, full),
		masonry,
		_at(x, (_top + gate_top) * 0.5, WorldSpace.CORRIDOR_DEPTH * 0.5 - full * 0.5)
	)
	# The wall behind the opening goes down to the floor, not into the slab: the slab and wall
	# faces would lie in one plane.
	var behind := full - WorldSpace.CORRIDOR_DEPTH
	_box(
		Vector3(wall, HEIGHT, behind),
		masonry,
		_at(x, gate_top + HEIGHT * 0.5, WorldSpace.BACK_WALL_Z - behind * 0.5)
	)
	_outside = _box(
		Vector3(wall, HEIGHT, 0.006),
		GreyboxLook.marker(OUTSIDE),
		_at(x, gate_top + HEIGHT * 0.5, WorldSpace.BACK_WALL_Z + 0.004),
		false
	)


## The shutter is a node hanging by its top at the lintel: rolling it up, [member openness]
## squeezes it in height. The bottom bar moves separately — it is not squeezed.
func _build_shutter() -> void:
	var wall := BuildingShell.WALL_WIDTH
	var x := Garage.gate_x(_rules)
	var slat := GreyboxLook.metal(SHUTTER)
	var groove := GreyboxLook.metal(SHUTTER.darkened(0.45))
	_roll = Node3D.new()
	_roll.name = "Shutter"
	_roll.position = _at(x, _surface - HEIGHT, 0.0)
	add_child(_roll)
	var lane := _lane()
	_box(
		Vector3(SHUTTER_THICKNESS, HEIGHT, lane - RAIL * 2.0),
		slat,
		Vector3(0.0, -HEIGHT * 0.5, 0.0),
		false,
		_roll
	)
	var face_z := WorldSpace.BACK_WALL_Z + 0.015
	_box(
		Vector3(wall - 0.04, HEIGHT, 0.01), slat, Vector3(0.0, -HEIGHT * 0.5, face_z), false, _roll
	)
	var rise := SLAT_PITCH
	while rise < HEIGHT - 0.02:
		_box(
			Vector3(wall - 0.06, 0.014, 0.004),
			groove,
			Vector3(0.0, -rise, face_z + 0.007),
			false,
			_roll
		)
		rise += SLAT_PITCH
	_shutter_bar = _box(
		Vector3(wall - 0.02, SHUTTER_BAR.y, SHUTTER_BAR.x),
		GreyboxLook.metal(SHUTTER.darkened(0.25)),
		_at(x, _surface - SHUTTER_BAR.y * 0.5, WorldSpace.BACK_WALL_Z + 0.05),
		false
	)


## Shutter housing on the inner face of the wall under the ceiling, guides at the edges of
## the driveway, the beacon and the threshold stripes — this is what the camera sees.
func _build_frame() -> void:
	var steel := GreyboxLook.metal(SHUTTER)
	var yellow := GreyboxLook.surface(Garage.PAINT_YELLOW)
	var black := GreyboxLook.surface(Garage.PAINT_BLACK)
	var inner_x := Garage.inner_span(_rules).x
	# Housing — right above the opening, the EXIT sign — above the housing.
	var box_top := _surface - HEIGHT - BOX.y
	var lane := _lane()
	_box(Vector3(BOX.x, BOX.y, lane), steel, _at(inner_x + BOX.x * 0.5, box_top + BOX.y * 0.5, 0.0))
	for index in 3:
		_box(
			Vector3(BOX.x - 0.04, 0.06, 0.006),
			yellow if index % 2 == 0 else black,
			_at(inner_x + BOX.x * 0.5, box_top + BOX.y - 0.05 - 0.06 * index, lane * 0.5 + 0.004),
			false
		)
	var rail_height := _surface - (box_top + BOX.y)
	for z: float in [lane * 0.5 - RAIL * 0.5, -lane * 0.5 + RAIL * 0.5]:
		_box(
			Vector3(RAIL, rail_height, RAIL),
			steel,
			_at(inner_x + RAIL * 0.5 + 0.02, _surface - rail_height * 0.5, z)
		)
	_beacon = _box(
		Vector3(0.12, 0.12, 0.12),
		GreyboxLook.surface(BEACON),
		_at(inner_x + BOX.x + 0.1, box_top + 0.08, lane * 0.5 - 0.1),
		false
	)
	# Threshold stripes: yellow and black along the driveway, across the gate. Stripes
	# across the driveway would merge from the tilted camera: the floor is seen as a strip.
	# The ends are not flush with the guides.
	for index in 6:
		_box(
			Vector3(0.12, 0.005, lane - 0.04),
			yellow if index % 2 == 0 else black,
			_at(inner_x + 0.08 + 0.12 * index, _surface - 0.0045, 0.0),
			false
		)


## The ramp beyond the gate and the exit around it — its own node ([GarageRamp]): from
## the exit it is in frame, and it is built as a cross-section, like the building. The car
## leaves along the ramp.
func _build_ramp() -> void:
	_ramp = GarageRamp.new()
	add_child(_ramp)
	_ramp.build(_rules, _seed)


## Exit light — the street light over the ramp and the neon glow — is lit while the exit is
## in frame: the camera is past the building's end wall, and the bottom floors are in frame.
## Called by the level.
func show_street(in_view: bool) -> void:
	if _ramp != null:
		_ramp.show_light(in_view)


## The exit beyond the gate: tunnel, ramp and street.
func ramp() -> GarageRamp:
	return _ramp


## EXIT sign on the lintel above the gate, facing the camera.
func _hang_the_sign() -> void:
	var left := _rules.floor_span(_rules.floors - 1).x
	var sign_z := WorldSpace.CORRIDOR_DEPTH * 0.5 + EXIT_SIGN.z * 0.5 + 0.004
	# Not `sign`: that is the name of a built-in function, and a local variable would shadow it.
	var board := GreyboxLook.box(EXIT_SIGN, GreyboxLook.light(GreyboxLook.SIGN_GREEN))
	board.name = "ExitSign"
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	board.position = _at(left + EXIT_SIGN.x * 0.5 + 0.02, _top + 0.03 + EXIT_SIGN.y * 0.5, sign_z)
	add_child(board)
	var words := Garage.label("◀ EXIT", 800, 0.16, EXIT_INK)
	words.shaded = false
	words.position = Vector3(0.0, 0.0, EXIT_SIGN.z * 0.5 + 0.004)
	board.add_child(words)


## Driveway under the housing: the corridor depth with a clearance from its faces.
static func _lane() -> float:
	return WorldSpace.CORRIDOR_DEPTH - 0.1


static func _at(x: float, y: float, z: float) -> Vector3:
	return Garage.scene_point(x, y, z)


func _box(
	size: Vector3,
	material: StandardMaterial3D,
	centre: Vector3,
	shadow: bool = true,
	parent: Node = null
) -> MeshInstance3D:
	return Garage.put_box(parent if parent != null else self, size, material, centre, shadow)
