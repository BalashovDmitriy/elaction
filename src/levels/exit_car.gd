class_name ExitCar
extends Node3D

## The car at the exit: the original ends a building with it (ADR-0011, point 14).
##
## Stands next to the exit opening on the bottom floor's floor, behind the play plane: it is
## outside the building, and Otto cannot step on it — it is a view, not a body. Drives off,
## taking Otto away; the next building is assembled after it leaves, not in the same frame.
##
## Its own node since M18d: the level outgrew its line limit, and the car has its own state —
## where it stands and whether it is driving — which the level has no need to know.

## Exit onto the street with traffic (ADR-0044, decisions 1–2): climbed the ramp,
## stopped at the kerb, waited for a gap, merged and drives with the traffic.
enum Stage { CLIMB, WAIT, MERGE, CRUISE }

## Car length, m: by it the car is placed at a gap from the opening and counted as gone
## from the frame. [CarModel] scales any drawn car to it (ADR-0032, decision 7).
const LENGTH: float = CarModel.LENGTH
const GAP: float = 0.36
## Departure: pulls away and accelerates to [constant SPEED], m/s and m/s².
## From standstill, not at full speed at once: the car drives away rather than vanishes.
const SPEED: float = 9.6
const START_SPEED: float = 1.2
const ACCELERATION: float = 7.2
## At the kerb the car brakes, m/s², and stops with its middle this far
## left of the ramp top, m: entirely on the street, nose toward the lane.
const BRAKING: float = 8.0
const STOP_PAST_RAMP: float = LENGTH * 0.5 + 0.4
## Merging into the lane: over how many metres of travel the car moves from the kerb to
## the middle of the near lane.
const MERGE_RUN: float = 7.0
## How long the car waits for a gap before the traffic arranges one is decided by the traffic
## itself for its situation ([method StreetTraffic.wait_limit]): the exit must not
## drag on longer than it holds interest.
##
## How many metres before the kerb the car looks whether the lane is free: if
## yes — it does not stop but merges on the move (ADR-0046, decision 3). From the same spot
## the turn signal blinks.
const ROLL_IN: float = 3.0
const SIGNAL_AHEAD: float = 6.0
## How the car rocked taking the driver in: tilt, rad, and how long it lasts, s.
const ROCK_ANGLE: float = 0.025
const ROCK_TIME: float = 0.5
## Headlights and brake lights: how bright they glow with the engine off and running.
const LIGHTS_OFF: float = 0.15
const LIGHTS_ON: float = 5.0
## Headlight height above the ground, m, and their beams (ADR-0043, decision 5): range, m, angle,
## degrees, and how far the beam is tilted down to the road, degrees. The beams shine far ahead
## and fall on the ramp and the street right up to the darkening; two headlights, one per side.
const BEAM_HEIGHT: float = 0.5
const BEAM_RANGE: float = 22.0
const BEAM_ANGLE: float = 20.0
const BEAM_DIP: float = 7.0
const BEAM_ENERGY: float = 12.0
## How far apart the headlights are across the sides, m.
const BEAM_SPREAD: float = 0.62
## Halo at the headlight itself: a soft spot of light around the glass, radius, m, and brightness.
## There is no beam cone in the air: as geometry it read as a triangle. The beam is visible in
## the air only where there is volumetric fog — by itself, like a real one.
const HALO_SIZE: float = 0.55
const HALO_ALPHA: float = 0.55
const HAZE_FOG: float = 2.0
const HALO_SHADER := preload("res://src/levels/headlight_halo.gdshader")
## How far the car can be heard, m: the door, starter and departure sound at the car.
const SOUND_REACH: float = 24.0
## The car stands outside the building: behind the play plane but in front of the wall, so that
## Otto passes in front of it, not through it.
const Z: float = -0.6
## The driver's door is the model part `DriverDoor`: the body is cut along its
## opening, and in the opening is the interior `CarInterior` (ADR-0046, decision 1). The part's
## origin is on the hinge at the front pillar; how wide the open door swings, degrees.
const DOOR_SWING: float = 62.0
## The interior dome light is under the roof inside, at the model's `DomeLight` point: it comes on
## with the door open, as in any car, and lights the interior and the one getting in. No
## shadow; brightness and range, m. Weak and close: it lights the interior, not the suit.
const DOME := Color(1.0, 0.82, 0.6)
const DOME_ENERGY: float = 0.9
const DOME_RANGE: float = 1.6
## Right turn signal (ADR-0046, decision 2): the car merges into the street's near lane
## — away from the camera, which is to the right in its travel. Blinks while it waits for a gap
## and merges, with half-period [constant BLINK_HALF], s. Only the lamps on the far side
## glow: the amber flashes they used to throw onto the asphalt looked out of place in front
## of the car and were removed at the user's request.
const INDICATOR := Color(1.0, 0.55, 0.08)
const BLINK_HALF: float = 0.36
const BLINK_GLOW: float = 6.0

## Where the car drives off: -1 left, +1 right. Since M24b always left — into the gate.
var towards: float = 1.0
## The street traffic the car merges into. Without it, it drives off as before M24h,
## along the empty street without stopping.
var traffic: StreetTraffic = null
var stage: Stage = Stage.CLIMB
## How long the car has been waiting for a gap, s.
var waited: float = 0.0

var _leaving: bool = false
## Departure speed right now, m/s.
var _speed: float = 0.0
## How much longer the car that took the driver keeps rocking, s.
var _rocking: float = 0.0
## Own copies of the headlight and brake light materials: the shared ones from the [GreyboxLook]
## cache are the same for cars of all buildings, and a started car would light the next one's too.
var _lamps: Array[StandardMaterial3D] = []
var _lamp_glow: Array[float] = []
var _beam: Node3D = null
var _wheels: Array[Node3D] = []
## The middle of each wheel in its own coordinates: it spins around it. The pack's
## wheel node origin is not on the axle but at the car's zero, and rotating
## around the origin would carry the wheels in a circle over the body (M21 code review).
var _hubs := PackedVector3Array()
## Wheel radius, m: by it the wheels spin in step with motion instead of skidding.
var _wheel_radius: float = 0.3
## The ramp past the gate ([GarageGate]): where the climb starts, in the rule plane,
## its length and height, m. The car drives up it, not through the ground.
var _ramp_start: float = 0.0
var _ramp_run: float = 0.0
var _ramp_rise: float = 0.0
## The floor the car stands on, in the rule plane.
var _floor_y: float = 0.0
## The model's driver door and how far it is open: 0 — closed.
var _door: Node3D = null
var _door_open: float = 0.0
## Middle of the door from the middle of the car toward the bonnet, m: Otto gets in at it.
var _door_offset: float = LENGTH * 0.08
var _dome: OmniLight3D = null
## Right turn signal: its own lamp material, whether it is lit now and blink progress, s.
var _indicator: StandardMaterial3D = null
var _indicator_on: bool = false
var _blink: float = 0.0
## The body side nearest the camera, Z in the car's frame: Otto steps to it when boarding.
var _near_side: float = 0.0


## Places the car at the garage gate: [param exit_x] is the middle of the exit, [param
## floor_y] is the bottom floor's floor in rule coordinates.
##
## The spot is at the gate in the left end wall ([method spot]), bonnet toward it: Otto's car in
## ROM is always on the left, and it drives off into the gate (ADR-0038, decision 3).
##
## [param choice] — which car and what colour ([method CarModel.choose]).
func park(
	exit_x: float,
	floor_y: float,
	rules: BuildingRules,
	plan: BuildingPlan,
	choice: CarModel.Choice = CarModel.Choice.new()
) -> void:
	name = "ExitCar"
	var x := spot(exit_x, rules, plan)
	towards = -1.0
	_floor_y = floor_y
	_ramp_start = rules.floor_span(rules.floors - 1).x - GarageGate.RAMP_APRON
	_ramp_run = GarageGate.RAMP_RUN
	_ramp_rise = rules.floor_height
	position = WorldSpace.to_scene(Vector2(x, floor_y))
	position.z = Z
	# The model stands with its wheels at its zero, bonnet toward +X; for the other direction it
	# is turned around whole.
	var model := CarModel.build(choice)
	if towards < 0.0:
		model.rotation.y = PI
	add_child(model)
	_fit_the_cabin(model)
	_wheels = CarModel.wheels(model)
	_hubs = CarModel.hubs(_wheels)
	_wheel_radius = CarModel.wheel_radius(_wheels, _wheel_radius)


## Where the car stands at the gate: a "left edge, right edge" pair by the bumpers.
##
## Right against the left end wall of the bottom floor, with a [constant GAP] gap from the wall:
## the garage gate is in the end wall, and the car drives off into it (ADR-0038, decision 3). By
## this band the layout keeps the basement shaft away from the car
## ([method clears_shaft]) and places the exit — Otto's spot at the driver's door.
static func parked_span(rules: BuildingRules) -> Vector2:
	var bounds := rules.floor_span(rules.floors - 1)
	var left := bounds.x + BuildingShell.WALL_WIDTH + GAP
	return Vector2(left, left + LENGTH)


## Whether the shaft at [param shaft_x] clears the car at the gate — by its portal, with a gap of
## [constant GAP].
##
## The layout asks before a shaft reaches the basement: the car always stands at the
## end wall, and it is the shaft that must give way, not the car.
static func clears_shaft(rules: BuildingRules, shaft_x: float) -> bool:
	var half_shaft := rules.shaft_width * 0.5 + BuildingShafts.PORTAL_JAMB
	return shaft_x - half_shaft >= parked_span(rules).y + GAP - 0.001


## Where the car should stand: at the gate in the left end wall ([method parked_span]) if it is
## free there — the layout promises that. Otherwise — the leftmost spot where along its whole length
## with a [constant GAP] gap it touches neither a shaft, nor the inner wall, nor an escalator
## run, and does not go beyond the walls. If there is no room at all — right at the exit
## [param exit_x].
##
## The exit opening no longer gets in the way: the exit is the car itself, Otto gets into it.
static func spot(exit_x: float, rules: BuildingRules, plan: BuildingPlan) -> float:
	var bottom := rules.floors - 1
	var bounds := rules.floor_span(bottom)
	var busy: Array[Vector2] = []
	var half_shaft := rules.shaft_width * 0.5 + BuildingShafts.PORTAL_JAMB
	for shaft in plan.shafts:
		if shaft.top <= bottom and bottom <= shaft.bottom:
			busy.append(Vector2(shaft.x - half_shaft, shaft.x + half_shaft))
	# The wall is solid through the full depth of the corridor and the room, and an escalator from
	# the floor above comes down here with a run from the opening to the landing: the car would pass
	# through them.
	for wall in plan.walls:
		if wall.floor_index == bottom:
			busy.append(wall.band(rules))
	for escalator in plan.escalators:
		if escalator.floor_index == bottom - 1:
			var landing := escalator.landing(rules)
			var gap := escalator.gap(rules)
			busy.append(Vector2(minf(gap.x, landing), maxf(gap.y, landing)))
	var half := LENGTH * 0.5 + GAP
	# Candidates are at the gate and right against the right edge of each occupied slot:
	# a free spot cannot be further left.
	var parked := parked_span(rules)
	var candidates: Array[float] = [(parked.x + parked.y) * 0.5]
	for zone in busy:
		candidates.append(zone.y + half)
	candidates.sort()
	for x: float in candidates:
		if x - half < bounds.x + BuildingShell.WALL_WIDTH - 0.001:
			continue
		if x + half > bounds.y - BuildingShell.WALL_WIDTH + 0.001:
			continue
		var clear := true
		for zone in busy:
			if x + half > zone.x + 0.001 and x - half < zone.y - 0.001:
				clear = false
				break
		if clear:
			return x
	return exit_x


## Where the driver's door is, horizontally in the rule plane: Otto gets in there.
func door_x() -> float:
	return position.x + towards * _door_offset


## Opens the driver's door: 0 — closed, 1 — wide open.
func set_door(openness: float) -> void:
	var was := _door_open
	_door_open = clampf(openness, 0.0, 1.0)
	# The door is opened — a click of the handle and lock (ADR-0052, decision 7).
	if was <= 0.0 and _door_open > 0.0 and is_inside_tree():
		_say(Sounds.CAR_DOOR_OPEN)
	var eased := ease(_door_open, -2.0)
	if _door != null:
		# The door lies from the hinge toward the boot (-X of the model) at the model's -Z side and
		# swings outward: rotation about +Y with a minus takes its edge into -Z.
		_door.rotation.y = -deg_to_rad(DOOR_SWING) * eased
	if _dome != null:
		_dome.visible = _door_open > 0.0
		_dome.light_energy = DOME_ENERGY * eased


## How far the driver's door is open.
func door_openness() -> float:
	return _door_open


## Where the one getting in stands in depth, scene Z: at the near side, in the door opening.
func seat_z() -> float:
	return global_position.z + _near_side - 0.18


## Otto got in: the car rocked under him and slammed the door.
func take_the_driver() -> void:
	_rocking = ROCK_TIME
	_say(Sounds.CAR_DOOR)


## The starter cranks the engine, and the headlights come on.
func start_engine() -> void:
	set_lights(true)
	_say(Sounds.CAR_START)


## Whether the headlights are on: a car with the engine off stands with them dark, a started one
## lights them and shines two beams ahead. The beams cast no shadow, and only on departure.
func set_lights(on: bool) -> void:
	if _lamps.is_empty():
		_own_the_lamps()
	for index in _lamps.size():
		var glow := LIGHTS_ON if on else LIGHTS_OFF
		_lamps[index].emission_energy_multiplier = _lamp_glow[index] * glow
	if on and _beam == null:
		_beam = Node3D.new()
		_beam.name = "Beam"
		# Beams along the bonnet, slightly toward the road: the spotlight shines along its -Z, the
		# bonnet faces towards.
		_beam.position = Vector3(towards * LENGTH * 0.5, BEAM_HEIGHT, 0.0)
		_beam.rotation.y = PI * 0.5 if towards < 0.0 else -PI * 0.5
		add_child(_beam)
		for side: float in [-1.0, 1.0]:
			_beam.add_child(_headlight(side))
	if _beam != null:
		_beam.visible = on


## One headlight: a shadowless spotlight tilted to the road, and a halo at the glass.
func _headlight(side: float) -> Node3D:
	var lamp := Node3D.new()
	lamp.position = Vector3(side * BEAM_SPREAD * 0.5, 0.0, 0.0)
	lamp.rotation.x = -deg_to_rad(BEAM_DIP)
	var spot := SpotLight3D.new()
	spot.light_color = CarModel.HEADLIGHT
	spot.light_energy = BEAM_ENERGY
	spot.spot_range = BEAM_RANGE
	spot.spot_angle = BEAM_ANGLE
	# The beam edge is soft: the spot on the road blurs rather than being cut by a cone.
	spot.spot_attenuation = 1.2
	spot.spot_angle_attenuation = 0.4
	spot.shadow_enabled = false
	spot.light_volumetric_fog_energy = HAZE_FOG
	lamp.add_child(spot)
	lamp.add_child(halo())
	return lamp


## Halo at the headlight glass: a flat spot always turned to the camera, brighter toward
## the middle and fading softly to nothing at the edge.
static func halo() -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(HALO_SIZE, HALO_SIZE)
	var look := ShaderMaterial.new()
	look.shader = HALO_SHADER
	look.set_shader_parameter(&"tint", Color(CarModel.HEADLIGHT, HALO_ALPHA))
	quad.material = look
	var halo := MeshInstance3D.new()
	halo.name = "Halo"
	halo.mesh = quad
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return halo


## Whether the headlights are on right now.
func lights_on() -> bool:
	return _beam != null and _beam.visible


## The car pulled away carrying Otto: engine, headlights and acceleration from standstill.
func drive_away() -> void:
	_leaving = true
	if traffic != null:
		traffic.keep_running()
	_speed = START_SPEED
	set_lights(true)
	_say(Sounds.CAR_AWAY)


## Whether the car is moving.
func is_leaving() -> bool:
	return _leaving


## Car speed right now, m/s.
func speed_now() -> float:
	return _speed


## Rocks the car that took the driver: a decaying tilt along the body.
func settle(delta: float) -> void:
	if _rocking <= 0.0:
		return
	_rocking = maxf(_rocking - delta, 0.0)
	var left := _rocking / ROCK_TIME
	rotation.z = sin((1.0 - left) * TAU * 2.0) * ROCK_ANGLE * left


## Drives the car. Returns true on the frame it left the frame
## [param view] — up to the building edge the car would crawl five times longer. The level
## gives the frame from the rules ([method SideCamera.rule_view]), not the smoothed
## player frame: handing over a building is a game event and must come from physics.
func advance(delta: float, view: Rect2) -> bool:
	if not _leaving:
		return false
	_speed = _speed_now(delta)
	_signal(delta)
	position.x += towards * _speed * delta
	_climb()
	_merge()
	# The wheels roll around their axles ([method CarModel.roll]).
	CarModel.roll(_wheels, _hubs, _speed * delta, _wheel_radius)
	var left := position.x - LENGTH * 0.5
	if left + LENGTH < view.position.x or left > view.end.x:
		_leaving = false
		return true
	return false


## Speed for this step: acceleration up the ramp, braking to the kerb,
## waiting for a gap and lane travel after.
func _speed_now(delta: float) -> float:
	if traffic == null:
		return minf(_speed + ACCELERATION * delta, SPEED)
	match stage:
		Stage.CLIMB:
			return _climb_speed(delta)
		Stage.WAIT:
			waited += delta
			traffic.hold_back(waited >= traffic.wait_limit())
			if not traffic.is_clear_for(position.x):
				return 0.0
			traffic.hold_back(false)
			traffic.join(self)
			stage = Stage.MERGE
			return minf(START_SPEED, traffic.near_speed())
	return minf(_speed + ACCELERATION * delta, traffic.near_speed())


## Speed approaching the kerb: there is a gap — merges on the move, none —
## brakes and stops at the kerb.
func _climb_speed(delta: float) -> float:
	var left := _to_the_kerb()
	if left <= ROLL_IN and traffic.is_clear_for(stop_x()):
		# There is a gap: without stopping, merges into the lane on the move.
		traffic.join(self)
		stage = Stage.MERGE
		return minf(_speed + ACCELERATION * delta, traffic.near_speed())
	if left <= 0.01:
		position.x = stop_x()
		stage = Stage.WAIT
		return 0.0
	var braked := sqrt(2.0 * BRAKING * left)
	return minf(minf(_speed + ACCELERATION * delta, SPEED), braked)


## How far the car still has to the kerb, m; past it — less than zero.
func _to_the_kerb() -> float:
	return (position.x - stop_x()) * -towards


## Where the car waits for a gap, by the middle's X: at the kerb past the ramp top.
## Since M24b it always drives off left, and the ramp top is left of its start.
func stop_x() -> float:
	return _ramp_start - _ramp_run - STOP_PAST_RAMP


## Moving from the kerb to the middle of the near lane on a smooth curve: the bonnet
## turns with the travel and straightens out in the lane.
func _merge() -> void:
	if traffic == null or (stage != Stage.MERGE and stage != Stage.CRUISE):
		return
	var run := (stop_x() - position.x) * -towards
	var share := clampf(run / MERGE_RUN, 0.0, 1.0)
	var lane := traffic.near_lane_z()
	position.z = lerpf(Z, lane, smoothstep(0.0, 1.0, share))
	# The curve slope is the derivative of smoothstep: 6u(1 - u) over the merge length.
	var slope := (lane - Z) * 6.0 * share * (1.0 - share) / MERGE_RUN
	rotation.y = atan(slope)
	if share >= 1.0:
		stage = Stage.CRUISE


## Finds the door, dome light and turn signal in the model [param model] and measures the side:
## the one getting in steps to the near one. Models without an interior have no door, and Otto
## gets in at the middle, as before.
func _fit_the_cabin(model: Node3D) -> void:
	var box := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var part := (model.transform * _to_model(model, mesh)) * mesh.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	_near_side = box.end.z
	_door = model.find_child("DriverDoor", true, false) as Node3D
	if _door != null:
		var door_mesh := _door as MeshInstance3D
		var span := door_mesh.mesh.get_aabb() if door_mesh != null else AABB()
		# Middle of the door in the model's frame: the hinge plus half its length toward the boot.
		_door_offset = _door.position.x + span.get_center().x
	_dome = OmniLight3D.new()
	_dome.name = "Dome"
	_dome.light_color = DOME
	_dome.omni_range = DOME_RANGE
	_dome.shadow_enabled = false
	var anchor := model.find_child("DomeLight", true, false) as Node3D
	if anchor != null:
		anchor.add_child(_dome)
	else:
		_dome.position = Vector3(towards * _door_offset, box.end.y - 0.1, 0.0)
		add_child(_dome)
	_hook_the_indicator(model)
	set_door(0.0)


## The model's right turn signal: its own material instead of the shared one from the cache.
func _hook_the_indicator(model: Node3D) -> void:
	var lamps := model.find_child("IndicatorRight", true, false) as MeshInstance3D
	if lamps == null:
		return
	_indicator = GreyboxLook.light(INDICATOR).duplicate() as StandardMaterial3D
	_indicator.emission_energy_multiplier = 0.0
	lamps.material_override = _indicator


## Whether the right turn signal blinks: approaching the kerb, while the car waits for
## a gap and while it merges into the lane.
func is_signalling() -> bool:
	if not _leaving or traffic == null:
		return false
	if stage == Stage.CLIMB:
		return _to_the_kerb() <= SIGNAL_AHEAD
	return stage == Stage.WAIT or stage == Stage.MERGE


## Whether the turn signal lamp is lit at this moment of the blink.
func indicator_lit() -> bool:
	return _indicator_on


## Blink progress: lit for the first half of the period, off for the second.
func _signal(delta: float) -> void:
	if _indicator == null:
		return
	var on := false
	if is_signalling():
		_blink += delta
		on = fmod(_blink, BLINK_HALF * 2.0) < BLINK_HALF
		# The turn signal relay clicks on every flash.
		if on and not indicator_lit() and is_inside_tree():
			_say(Sounds.TURN_SIGNAL)
	else:
		_blink = 0.0
	_indicator.emission_energy_multiplier = BLINK_GLOW if on else 0.0
	_indicator_on = on


## Transform of mesh [param mesh] in the frame of model [param model].
static func _to_model(model: Node3D, mesh: Node3D) -> Transform3D:
	var chain := Transform3D.IDENTITY
	var node: Node = mesh
	while node != null and node != model:
		var spatial := node as Node3D
		if spatial != null:
			chain = spatial.transform * chain
		node = node.get_parent()
	return chain


## Places the car on the ramp past the gate: height by the car's middle, tilt by the
## climb. The ramp runs left from the pad at the gate, above it is the street, level.
func _climb() -> void:
	if _ramp_run <= 0.0:
		return
	var along := clampf((_ramp_start - position.x) / _ramp_run, 0.0, 1.0)
	var at := WorldSpace.to_plane(position)
	at.y = _floor_y - _ramp_rise * GarageRamp.rise_share(along)
	var z := position.z
	position = WorldSpace.to_scene(at)
	position.z = z
	# The bonnet faces left, and the nose lifts on the climb: rotation about +Z
	# clockwise as seen from the camera — minus. Tilt follows the tangent to the climb
	# curve: at its ends it eases to zero smoothly, without a kink.
	rotation.z = -atan(_ramp_rise / _ramp_run * GarageRamp.rise_slope(along))


## Sound at the car's position: a positional source that drives away with it.
func _say(sound: String) -> void:
	var player := Sounds.source(self, sound, SOUND_REACH)
	player.finished.connect(player.queue_free)
	player.play()


## Sets up its own copies of headlight and brake light materials instead of the shared cached ones.
func _own_the_lamps() -> void:
	var shared: Array[StandardMaterial3D] = [
		GreyboxLook.light(CarModel.HEADLIGHT), GreyboxLook.light(CarModel.TAILLIGHT)
	]
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in mesh.get_surface_override_material_count():
			var material := mesh.get_surface_override_material(surface) as StandardMaterial3D
			if material == null or not shared.has(material):
				continue
			var own := material.duplicate() as StandardMaterial3D
			mesh.set_surface_override_material(surface, own)
			_lamps.append(own)
			_lamp_glow.append(material.emission_energy_multiplier)
