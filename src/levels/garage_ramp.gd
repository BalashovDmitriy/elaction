class_name GarageRamp
extends Node3D

## Exit from the garage beyond the gate: tunnel, ramp up and the street (ADR-0038,
## decision 3).
##
## From boarding the frame widens to the left past the end wall
## ([method ExitBoarding.exit_frame]) and follows the car up the ramp to the street. The
## first version — a bare retaining wall half a frame wide, three lamps and flat houses —
## looked worse in shots than the rest of the game. Now the exit is built like the building
## itself, as a cross-section:
##
## - beyond the gate — a **tunnel**: a low ceiling with fluorescent fixtures,
##   their light pools on the ramp and the wall, a cable tray, a sprinkler pipe,
##   a crash barrier in yellow-black stripes and an EXIT arrow painted on the wall;
## - further on the ramp comes out into an **open ramp**: a cast concrete retaining wall
##   (form panels, ties, streaks — [code]street_concrete.gdshader[/code]), a railing
##   on top, "barrel" fixtures and a downpipe;
## - at the top — the **street** ([ExitStreet]): paving, a street light over the entrance and
##   a row of houses across the road; the sidewalk runs above the tunnel;
## - under it all — soil in cross-section, with strata.
##
## Light: the street light over the entrance is one shadowless source, and it is lit only
## while the exit is in frame ([method show_light]); the rest is emission and light pools.
##
## Looks only, no bodies: Otto does not come out here; the car — looks without a body —
## drives through.

## Soil under the basement floor, m — down to the bottom of any frame.
const SOIL_DEPTH: float = 6.0
## Gap of the soil wedge from the slab and walls, m.
const SOIL_GAP: float = 0.01
## How far the wedge goes into the soil stratum under the floor, m.
const SOIL_SINK: float = 0.05
## Into how many segments the curved rise is split: no facets are visible on it.
const SLOPE_PIECES: int = 24
## Tunnel: how much of the ramp from the gate is covered by the ceiling, m. Further on the
## ceiling would touch the car roof: the ramp floor rises, but the ceiling does not.
const TUNNEL: float = 5.0
## Retaining wall: thickness, m.
const WALL_THICKNESS: float = 0.24
## Driveway width in depth — of the landing by the gate, the ramp and the tunnel, m: a
## corridor with a margin, the middle in the play plane. The office barrier also extends
## its arm by it to the tunnel wall ([GarageDressing]).
const WIDTH: float = WorldSpace.CORRIDOR_DEPTH + 0.4
## Sidewalk above the tunnel and along the ramp: how much higher than the paving, m.
const KERB: float = 0.15
## Ramp railing: height above the sidewalk, post pitch, m.
const RAIL_HEIGHT: float = 1.0
const RAIL_STEP: float = 1.25
## Street light over the entrance: pole height above the sidewalk, arm reach, m, and the
## light — sodium, like the light behind the gate shutter ([constant GarageGate.OUTSIDE]).
const LAMP_HEIGHT: float = 4.6
const LAMP_ARM: float = 1.0
const LAMP_RANGE: float = 11.0
const LAMP_ENERGY: float = 9.0
## Where the street light stands — left of the end wall, m: in frame both at the entrance
## and on the street.
const LAMP_FROM_WALL: float = 7.0
## Tunnel fixtures: pitch from the gate, tube length, m, and their light pools.
const TUBE_STEP: float = 1.6
const TUBE := Vector3(1.1, 0.04, 0.1)
const WASH := Vector2(2.0, 2.2)
const WASH_ENERGY: float = 0.18
const POOL_ENERGY: float = 0.24
## "Barrel" fixtures on the ramp wall: size, height above the driveway and pitch, m.
const BULKHEAD := Vector3(0.34, 0.16, 0.08)
const BULKHEAD_RISE: float = 1.5
const BULKHEAD_STEP: float = 3.0
## Crash barrier by the wall: height and depth, m.
const BUMPER := Vector2(0.14, 0.14)

const SOIL := Color(0.12, 0.105, 0.095)
const SOIL_CUT := Color(0.16, 0.13, 0.11)
const WALL_TONE := Color(0.5, 0.5, 0.49)
const PAVEMENT := Color(0.22, 0.22, 0.23)
const KERB_TONE := Color(0.42, 0.42, 0.4)
const RAIL := Color(0.36, 0.37, 0.39)
const TRAY := Color(0.4, 0.41, 0.43)
const CABLE := Color(0.03, 0.03, 0.035)
const BULKHEAD_GLOW := Color(1.0, 0.8, 0.55)
const POLE := Color(0.16, 0.17, 0.19)
const WALL_PAINT := Color(0.78, 0.78, 0.74)

## Street entrance to the building by kind ([StreetFront]).
var front: StreetFront = null

var _rules: BuildingRules = null
## Basement floor and street, in the rules plane; the building's end wall; driveway width.
var _surface: float = 0.0
var _street: float = 0.0
var _left: float = 0.0
var _width: float = 0.0
var _weather: Weather.Kind = Weather.Kind.CLEAR
var _light: OmniLight3D = null
var _street_node: ExitStreet = null


## Builds the exit at the left end wall of the bottom floor.
func build(rules: BuildingRules, building_seed: int = 1) -> void:
	name = "Ramp"
	_rules = rules
	_surface = rules.floor_surface(rules.floors - 1)
	_street = _surface - rules.floor_height
	_left = rules.floor_span(rules.floors - 1).x
	_width = WIDTH
	_weather = Weather.of_building(rules, building_seed)
	_street_node = ExitStreet.new()
	add_child(_street_node)
	_street_node.build(_left, _street, building_seed, _weather, rules.time_of_day)
	# Street entrance to the building by kind (ADR-0058, decision 5): on the sidewalk above
	# the tunnel by the end wall — its height is set by [method _build_street_edge].
	front = StreetFront.new()
	_street_node.add_child(front)
	front.build(rules, _left, _street - KERB, building_seed, _weather)
	# The street is outside: by day the building's sun is on it (ADR-0052, decision 3).
	Outdoors.mark(_street_node)
	_build_slabs()
	_build_soil()
	_build_street_edge()
	_build_tunnel()
	_build_open_ramp()
	_build_lamp()


## Turns the exit light on or off: it is lit while the exit is in frame.
func show_light(on: bool) -> void:
	if _light != null:
		_light.visible = on
	if _street_node != null:
		_street_node.show_light(on)
	# The hotel valet stands the way pedestrians walk: only while the exit is in frame.
	if front != null:
		front.set_active(on)


## Street traffic by the exit.
func traffic() -> StreetTraffic:
	return _street_node.traffic() if _street_node != null else null


## Real light sources of the exit — for budget tests.
func lights() -> Array[Light3D]:
	var found: Array[Light3D] = []
	if _light != null:
		found.append(_light)
	if _street_node != null:
		found.append_array(_street_node.lights())
	return found


## Left end of the rise — the top of the ramp, in the rules plane.
func top_x() -> float:
	return _left - GarageGate.RAMP_APRON - GarageGate.RAMP_RUN


## Driveway height above the basement floor at [param x], m: the landing by the gate, the
## rise, the street. The rise is a smooth curve (ADR-0043, decision 17): a gentle entry,
## steeper towards the middle, a gentle exit to the street. A straight ramp broke into
## corners at its ends, and the car snapped over them.
static func climb_at(rules: BuildingRules, x: float) -> float:
	return rules.floor_height * rise_share(_along(rules, x))


## Driveway slope at [param x], rad: the tangent to the same curve.
static func slope_at(rules: BuildingRules, x: float) -> float:
	var t := _along(rules, x)
	return atan(rules.floor_height / GarageGate.RAMP_RUN * rise_slope(t))


## Share of the rise at path fraction [param t]: a smoothstep — the tangent is horizontal
## at both ends.
static func rise_share(t: float) -> float:
	var at := clampf(t, 0.0, 1.0)
	return at * at * (3.0 - 2.0 * at)


## Derivative of [method rise_share] with respect to path fraction.
static func rise_slope(t: float) -> float:
	var at := clampf(t, 0.0, 1.0)
	return 6.0 * at * (1.0 - at)


## Path fraction along the rise at [param x]: 0 — at the landing, 1 — at the top.
static func _along(rules: BuildingRules, x: float) -> float:
	var start := rules.floor_span(rules.floors - 1).x - GarageGate.RAMP_APRON
	return clampf((start - x) / GarageGate.RAMP_RUN, 0.0, 1.0)


## Where the tunnel ceiling ends, in the rules plane.
func mouth_x() -> float:
	return _left - TUNNEL


## The landing by the opening and the rise to the left onto the floor. The car leaves
## along the rise ([method ExitCar._climb]).
func _build_slabs() -> void:
	var concrete := BuildingFinish.shaft_concrete(Garage.CONCRETE)
	var thickness := _rules.slab_height
	var apron := GarageGate.RAMP_APRON
	var run := GarageGate.RAMP_RUN
	_box(
		Vector3(apron, thickness, _width),
		concrete,
		_at(_left - apron * 0.5, _surface + thickness * 0.5, 0.0)
	)
	var incline := _slope(Vector3(0.0, thickness, _width), concrete, 0.0, thickness * 0.5)
	incline.name = "Incline"
	# Crash barrier by the wall: yellow, with black ends on the landing.
	var yellow := GreyboxLook.surface(Garage.PAINT_YELLOW)
	var black := GreyboxLook.surface(Garage.PAINT_BLACK)
	var bumper_z := -_width * 0.5 + BUMPER.y * 0.5
	var x := _left - 0.25
	var index := 0
	while x > _left - apron + 0.2:
		_box(
			Vector3(0.5, BUMPER.x, BUMPER.y),
			yellow if index % 2 == 0 else black,
			_at(x, _surface - BUMPER.x * 0.5, bumper_z),
			false
		)
		x -= 0.5
		index += 1
	_slope(Vector3(0.0, BUMPER.x, BUMPER.y), yellow, bumper_z, -BUMPER.x * 0.5)


## A strip along the rise made of short boxes on the curve: along its whole length,
## [param size] — thickness and depth (x does not count), [param z] — middle in
## depth, [param lift] — how much the middle is below (+) or above (−) the ramp
## surface. There are enough segments that no facets are visible on the curve.
func _slope(size: Vector3, material: Material, z: float, lift: float) -> Node3D:
	var strip := Node3D.new()
	add_child(strip)
	var run := GarageGate.RAMP_RUN
	var rise := _rules.floor_height
	var start := _left - GarageGate.RAMP_APRON
	for index in SLOPE_PIECES:
		var t0 := float(index) / float(SLOPE_PIECES)
		var t1 := float(index + 1) / float(SLOPE_PIECES)
		var from := Vector2(start - run * t0, _surface - rise * rise_share(t0))
		var to := Vector2(start - run * t1, _surface - rise * rise_share(t1))
		var chord := to - from
		# Overlapped by the thickness: with short segments at different angles, gaps would
		# otherwise shine between the faces.
		var part := _box(
			Vector3(chord.length() + size.y, size.y, size.z), material, Vector3.ZERO, false
		)
		var angle := atan2(-chord.y, -chord.x)
		part.rotation.z = -angle
		# The offset from the surface is along the normal to the rise, not along the vertical.
		var normal := Vector2(sin(angle), cos(angle))
		var centre := (from + to) * 0.5 + normal * lift * Vector2(-1.0, 1.0)
		part.position = _at(centre.x, centre.y, z)
		part.reparent(strip)
	return strip


## Soil in cross-section: a wedge under the rise and a stratum under the whole exit. The
## cut face is flush with the driveway, as with the building slabs; the cut edge is lighter.
func _build_soil() -> void:
	var soil := _soil()
	var run := GarageGate.RAMP_RUN
	var rise := _rules.floor_height
	var depth := _width + 1.0
	var z := _width * 0.5 - depth * 0.5
	# The wedge: the high side on the left, at the top of the ramp. Slightly below the slab so
	# the faces do not lie in one plane.
	# The wedge under the curved rise is made of columns: each from the soil stratum to the
	# bottom of the slab above it.
	var start := _left - GarageGate.RAMP_APRON
	var step := run / float(SLOPE_PIECES)
	for index in SLOPE_PIECES:
		var t := (float(index) + 0.5) / float(SLOPE_PIECES)
		# Slightly below the slab and slightly narrower than the cut: the wedge faces do not lie
		# in one plane with either the slab or the walls.
		var top := _surface - rise * rise_share(t) + _rules.slab_height + SOIL_GAP
		# The bottom goes into the soil stratum under the floor: flush with its top the faces
		# would coincide with the tunnel.
		var bottom := _surface + _rules.slab_height + SOIL_SINK
		if bottom - top <= SOIL_SINK + 0.02:
			continue
		var pillar := _box(
			Vector3(step + 0.01, bottom - top, depth - SOIL_GAP * 2.0),
			soil,
			_at(start - run * t, (top + bottom) * 0.5, z),
			false
		)
		pillar.name = "Wedge%d" % index
		pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var span := ExitStreet.FROM
	_box(
		Vector3(span, SOIL_DEPTH, depth),
		soil,
		_at(_left - span * 0.5, _surface + _rules.slab_height + SOIL_DEPTH * 0.5, z)
	)
	# Under the street left of the ramp — soil up to the asphalt.
	var street_span := span - GarageGate.RAMP_APRON - run
	var fill := _surface + _rules.slab_height - _street - ExitStreet.ASPHALT
	_box(
		Vector3(street_span, fill, depth),
		soil,
		_at(top_x() - street_span * 0.5, _street + ExitStreet.ASPHALT + fill * 0.5, z)
	)
	# Cut edge under the basement floor: a light strip, like a slab end.
	_box(
		Vector3(span, 0.05, 0.01),
		GreyboxLook.surface(SOIL_CUT),
		_at(_left - span * 0.5, _surface + _rules.slab_height + 0.025, _width * 0.5 + 0.005),
		false
	)


## The street edge by the exit: asphalt left of the top of the ramp — the car drives out
## onto it — and the sidewalk above the tunnel and along the ramp.
func _build_street_edge() -> void:
	var from := _left - ExitStreet.FROM
	var right := top_x()
	var near := _width * 0.5
	var depth := near - ExitStreet.NEAR_Z
	_box(
		Vector3(right - from, ExitStreet.ASPHALT, depth),
		_street_node.road(),
		_at((from + right) * 0.5, _street + ExitStreet.ASPHALT * 0.5, near - depth * 0.5)
	)
	# The cut edge along the asphalt — a light line, like the end of a building slab.
	_box(
		Vector3(right - from, 0.03, 0.01),
		GreyboxLook.surface(KERB_TONE),
		_at((from + right) * 0.5, _street + 0.015, near + 0.005)
	)
	var walk := GreyboxLook.surface(PAVEMENT)
	var back := -_width * 0.5 - WALL_THICKNESS
	# Along the ramp the sidewalk is behind the wall, from the railing to the paving.
	var strip := back - ExitStreet.NEAR_Z
	_box(
		Vector3(_left - right, KERB, strip),
		walk,
		_at((right + _left) * 0.5, _street - KERB * 0.5, back - strip * 0.5)
	)
	# Above the tunnel — the full depth of the driveway.
	_box(
		Vector3(TUNNEL, KERB, near - back),
		walk,
		_at(_left - TUNNEL * 0.5, _street - KERB * 0.5, (near + back) * 0.5)
	)
	# Curb by the paving, a centimetre above the sidewalk.
	_box(
		Vector3(_left - right, KERB + 0.01, 0.16),
		GreyboxLook.surface(KERB_TONE),
		_at((right + _left) * 0.5, _street - (KERB + 0.01) * 0.5, ExitStreet.NEAR_Z - 0.08)
	)


## Tunnel: the wall behind the driveway, the ceiling, fixtures and what is on the wall.
func _build_tunnel() -> void:
	var back := -_width * 0.5 - WALL_THICKNESS
	var ceiling := _street + _rules.slab_height
	var mouth := mouth_x()
	var depth := _surface + _rules.slab_height - ceiling
	_box(
		Vector3(TUNNEL, depth, WALL_THICKNESS),
		_wall(ceiling, _surface),
		_at(_left - TUNNEL * 0.5, ceiling + depth * 0.5, back + WALL_THICKNESS * 0.5)
	)
	var concrete := BuildingFinish.shaft_concrete(Garage.CONCRETE.darkened(0.15))
	var near := _width * 0.5
	_box(
		Vector3(TUNNEL, _rules.slab_height, near - back),
		concrete,
		_at(_left - TUNNEL * 0.5, _street + _rules.slab_height * 0.5, (near + back) * 0.5)
	)
	# Clearance stripes on the ceiling end at the tunnel exit.
	var yellow := GreyboxLook.surface(Garage.PAINT_YELLOW)
	var black := GreyboxLook.surface(Garage.PAINT_BLACK)
	for index in 6:
		_box(
			Vector3(0.2, _rules.slab_height - 0.1, 0.008),
			yellow if index % 2 == 0 else black,
			_at(mouth + 0.1 + 0.2 * index, _street + _rules.slab_height * 0.5, near + 0.004),
			false
		)
	var face := -_width * 0.5
	var steel := GreyboxLook.metal(TRAY)
	# Cable tray with cables in it, under the ceiling.
	_box(
		Vector3(TUNNEL - 0.4, 0.08, 0.24),
		steel,
		_at(_left - TUNNEL * 0.5 - 0.1, ceiling + 0.4, face + 0.12),
		false
	)
	_box(
		Vector3(TUNNEL - 0.5, 0.05, 0.18),
		GreyboxLook.surface(CABLE),
		_at(_left - TUNNEL * 0.5 - 0.1, ceiling + 0.335, face + 0.12),
		false
	)
	# Sprinkler pipe — red, along the ceiling.
	var pipe := _pipe(TUNNEL - 0.2, 0.035, GreyboxLook.metal(Garage.PIPE_RED))
	pipe.rotation.z = PI * 0.5
	pipe.position = _at(_left - TUNNEL * 0.5, ceiling + 0.14, face + 0.42)
	# Fixtures: tubes by the wall under the ceiling, light pools on the wall and the ramp.
	var x := _left - TUBE_STEP * 0.5
	while x > mouth + TUBE.x * 0.5:
		_box(
			Vector3(TUBE.x + 0.08, 0.07, TUBE.z + 0.06),
			GreyboxLook.metal(Garage.FIXTURE_BODY),
			_at(x, ceiling + 0.035, face + 0.4),
			false
		)
		_box(TUBE, GreyboxLook.light(Garage.TUBE), _at(x, ceiling + 0.09, face + 0.4), false)
		var wash := _glow(WASH, Garage.TUBE, WASH_ENERGY, true)
		wash.position = _at(x, ceiling + WASH.y * 0.5 - 0.1, face + 0.006)
		add_child(wash)
		var pool := _glow(Vector2(2.2, 2.2), Garage.TUBE, POOL_ENERGY, false)
		var ground := climb_at(_rules, x)
		pool.position = _at(x, _surface - ground - 0.012, 0.0)
		if ground > 0.0:
			pool.rotation.z = -slope_at(_rules, x)
		add_child(pool)
		x -= TUBE_STEP
	# EXIT arrow painted on the wall — cars leave by it.
	var words := Garage.label("◀ EXIT", 800, 0.42, WALL_PAINT)
	words.position = _at(_left - 1.9, _surface - 1.45, face + 0.004)
	add_child(words)
	var bar := GreyboxLook.surface(Garage.PAINT_YELLOW)
	_box(Vector3(2.1, 0.06, 0.004), bar, _at(_left - 1.9, _surface - 1.1, face + 0.002), false)


## Open ramp behind the tunnel: retaining wall, downpipe, "barrels" and
## the railing on top.
func _build_open_ramp() -> void:
	var back := -_width * 0.5 - WALL_THICKNESS
	var right := mouth_x()
	var left := top_x()
	var top := _street - KERB
	var height := _surface + _rules.slab_height - top
	_box(
		Vector3(right - left, height, WALL_THICKNESS),
		_wall(top, _surface, 0.7 if Weather.is_raining(_weather) else 0.0),
		_at((left + right) * 0.5, top + height * 0.5, back + WALL_THICKNESS * 0.5)
	)
	# Parapet coping — a light strip along the top.
	_box(
		Vector3(right - left, 0.05, WALL_THICKNESS + 0.06),
		GreyboxLook.surface(KERB_TONE),
		_at((left + right) * 0.5, top - 0.025, back + WALL_THICKNESS * 0.5),
		false
	)
	var face := -_width * 0.5
	# Downpipe — from the coping down to the driveway, at the tunnel exit.
	var drain_x := right - 0.35
	var drain_ground := _surface - climb_at(_rules, drain_x)
	var drain := _pipe(drain_ground - top, 0.05, GreyboxLook.metal(Garage.PIPE_GREY))
	drain.position = _at(drain_x, (drain_ground + top) * 0.5, face + 0.07)
	# The fixtures above the driveway go along the rise: each at its own height above
	# it, while it fits under the coping.
	var x := right - 1.2
	while x > left + 0.5:
		var ground := _surface - climb_at(_rules, x)
		var lamp_y := ground - BULKHEAD_RISE
		if lamp_y - BULKHEAD.y < top + 0.2:
			break
		_box(
			BULKHEAD,
			GreyboxLook.light(BULKHEAD_GLOW),
			_at(x, lamp_y, face + BULKHEAD.z * 0.5),
			false
		)
		x -= BULKHEAD_STEP
	# Railing: posts on the coping and two bars on top.
	var metal := GreyboxLook.metal(RAIL)
	var rail_z := back + WALL_THICKNESS * 0.5
	var coping := top - 0.05
	var post := right - 0.3
	while post > left + 0.1:
		_box(
			Vector3(0.05, RAIL_HEIGHT, 0.05),
			metal,
			_at(post, coping - RAIL_HEIGHT * 0.5, rail_z),
			false
		)
		post -= RAIL_STEP
	for rise: float in [RAIL_HEIGHT - 0.03, RAIL_HEIGHT * 0.5]:
		_box(
			Vector3(right - left - 0.2, 0.04, 0.04),
			metal,
			_at((left + right) * 0.5, coping - rise, rail_z + 0.005),
			false
		)


## Street light over the entrance: a pole on the sidewalk behind the railing, an arm over
## the ramp.
func _build_lamp() -> void:
	var pole_x := _left - LAMP_FROM_WALL
	var pole_z := ExitStreet.NEAR_Z + 0.35
	var base := _street - KERB
	var metal := GreyboxLook.metal(POLE)
	_box(Vector3(0.12, LAMP_HEIGHT, 0.12), metal, _at(pole_x, base - LAMP_HEIGHT * 0.5, pole_z))
	_box(
		Vector3(0.08, 0.08, LAMP_ARM),
		metal,
		_at(pole_x, base - LAMP_HEIGHT, pole_z + LAMP_ARM * 0.5),
		false
	)
	var head_z := pole_z + LAMP_ARM
	_box(Vector3(0.34, 0.1, 0.5), metal, _at(pole_x, base - LAMP_HEIGHT + 0.02, head_z), false)
	_box(
		Vector3(0.28, 0.04, 0.42),
		GreyboxLook.light(GarageGate.OUTSIDE),
		_at(pole_x, base - LAMP_HEIGHT + 0.09, head_z),
		false
	)
	_light = OmniLight3D.new()
	_light.name = "StreetLight"
	_light.light_color = GarageGate.OUTSIDE
	_light.light_energy = LAMP_ENERGY
	_light.omni_range = LAMP_RANGE
	_light.omni_attenuation = 0.7
	_light.shadow_enabled = false
	_light.position = _at(pole_x, base - LAMP_HEIGHT + 0.3, head_z)
	_light.visible = false
	add_child(_light)
	if Weather.is_raining(_weather):
		add_child(
			RainLook.halo(
				_light.position + Vector3(0.0, 0.0, -1.4),
				GarageGate.OUTSIDE,
				0.22,
				Vector2(5.5, 5.0)
			)
		)


## Wall material: cast concrete with top and bottom heights, from which the streaks and
## dampness go.
func _wall(top: float, bottom: float, wetness: float = 0.0) -> ShaderMaterial:
	var grain := BuildingFinish.shaft_concrete(WALL_TONE)
	var look := ShaderMaterial.new()
	look.shader = preload("res://src/levels/street_concrete.gdshader")
	look.set_shader_parameter("tone", WALL_TONE)
	look.set_shader_parameter("grain", grain.albedo_texture)
	look.set_shader_parameter("grain_normal", grain.normal_texture)
	look.set_shader_parameter("top_y", WorldSpace.height_to_scene(top))
	look.set_shader_parameter("bottom_y", WorldSpace.height_to_scene(bottom))
	look.set_shader_parameter("wetness", wetness)
	return look


## Soil material: strata from the street level.
func _soil() -> ShaderMaterial:
	var look := ShaderMaterial.new()
	look.shader = preload("res://src/levels/street_soil.gdshader")
	look.set_shader_parameter("tone", SOIL)
	look.set_shader_parameter("street_y", WorldSpace.height_to_scene(_street))
	return look


## A pipe of length [param length] and radius [param radius], standing along Y.
func _pipe(length: float, radius: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	return part


## Light pool — a plane with a gradient, added to whatever it lies on.
## [param upright] — on a wall, lighter at the top, by the fixture; otherwise — on the
## floor, round.
static func _glow(size: Vector2, tone: Color, energy: float, upright: bool) -> MeshInstance3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(tone, energy))
	gradient.set_color(1, Color(tone, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.0) if upright else Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 1.0) if upright else Vector2(0.5, 0.0)
	texture.width = 64
	texture.height = 64
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_texture = texture
	material.disable_receive_shadows = true
	var part := MeshInstance3D.new()
	part.name = "Glow"
	if upright:
		var quad := QuadMesh.new()
		quad.size = size
		part.mesh = quad
	else:
		var plane := PlaneMesh.new()
		plane.size = size
		part.mesh = plane
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return part


func _at(x: float, y: float, z: float) -> Vector3:
	return Garage.scene_point(x, y, z)


## A box of the exit. The exit casts no shadows: its sources are shadowless.
func _box(
	size: Vector3, material: Material, centre: Vector3, shadow: bool = false
) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.material_override = material
	part.position = centre
	if not shadow:
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	return part
