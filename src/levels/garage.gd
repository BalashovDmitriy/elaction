class_name Garage
extends Node3D

## Underground garage — the bottom floor of the building (ADR-0038, decision 3).
##
## Until M24b the bottom floor was a corridor with a concrete wall and stripes on the floor.
## Here it is a garage: there is no back wall, behind the play plane opens a hall as deep
## as a room, with bays holding other people's cars nose to the far wall, columns along
## the front line of the bays, beams, a ventilation duct and fluorescent fixtures,
## markings, oil stains, numbers on the columns and signs. The corridor is the driveway:
## Otto's car leaves along it — through the gate in the left end wall, with a ramp up behind it.
##
## Looks only, there are no bodies here: everything stands behind the play plane or overhead.
## The garage adds no real light — the floor lamps shine, as everywhere; the fixture
## tubes are emissive and go dark together with their lamp's zone ([method darken]).
##
## Layout is done by static functions: tests check where the columns, bays and other cars
## are without a scene, on any seed.
##
## The gate in the left end wall is [GarageGate], node [member gate]; finishing
## the building raises it via [method open_gate].

## Wall by the gate: from the left wall to the first column the hall is closed — the corner
## where the sign and the arrow hang, m.
const GATE_BAY: float = 0.8
## Column: cross-section and middle in depth — right behind the line of the former back
## wall, the front face behind Otto's back with a margin.
const COLUMN: float = 0.5
const COLUMN_Z: float = WorldSpace.BACK_WALL_Z - 0.35
## Column pitch — two bays of one and a half grid steps; a column does not stand closer
## than this to a shaft core or a wall, m.
const COLUMN_PITCH: float = Proportions.SLOT * 3.0
const COLUMN_CLEARANCE: float = 0.15
## Bay: not narrower than this, m. Between the columns there are two bays of 2.45.
const BAY_MIN: float = 2.4
## Bays in depth: from the front line to the wheel stop, m.
const BAY_FRONT_Z: float = WorldSpace.BACK_WALL_Z - 0.25
const BAY_BACK_Z: float = -5.6
## Far wall of the hall: middle and thickness, m.
const FAR_Z: float = -7.2
const FAR_THICKNESS: float = 0.2

## Car in a bay: the width the pack model is stretched to (in the pack it is squeezed
## to the gap between the wall and Otto, [CarModel]), and the middle in depth.
const CAR_WIDTH: float = 1.62
const CAR_Z: float = -3.35
## Share of occupied bays.
const PARKED_SHARE: float = 0.65

## Beam: width, how far it hangs below the slab, m.
const BEAM := Vector2(0.4, 0.4)
## A beam across the driveway does not come closer than this to a lamp: the lamp cord would
## pass through it.
const BEAM_LAMP_CLEARANCE: float = 0.7
## Under the ceiling everything is visible only below the band hidden by the slab
## edge ([method FloorSigns.hidden_band]), and this band is wider the
## deeper the thing is. So the rows go not by height but by offset from the edge on
## screen: fixtures — at the front line, right under the edge; pipes — behind them
## slightly lower; the ventilation duct — deeper and lower still. Put them all "right
## under the edge of their depth" — and on screen they would line up in one row, with
## the front one covering the rest (the milestone's first shot: a fixture tube entirely
## behind the red pipe).
##
## Fixture: housing, diffuser, row depth, m.
const FIXTURE := Vector3(1.3, 0.07, 0.16)
const DIFFUSER := Vector3(1.22, 0.05, 0.1)
const FIXTURE_Z: float = WorldSpace.BACK_WALL_Z + 0.06
## A fixture does not stand in front of a floor lamp closer than this, m: the shade would
## cover it.
const FIXTURE_LAMP_CLEARANCE: float = 1.0
## Light pool of a tube on the bay floor: width and depth, m, and brightness.
const POOL := Vector2(2.3, 2.6)
const POOL_ENERGY: float = 0.22
## Tube light: a cone down and into the hall, onto the bay's car. Only above an occupied
## bay — there is no point lighting an empty one, and there are already many sources in
## the frame (budget — ADR-0010, item 1). No shadow — only lamps cast shadows in the
## building (ADR-0023, decision 3) — weak and short: it does not reach the slab
## above. Goes dark with its lamp's zone and off-frame, like the lamps. Without it the hall
## behind the driveway stayed blue blackness, and the cars in it did not read.
const TUBE_LIGHT_ENERGY: float = 1.6
const TUBE_LIGHT_RANGE: float = 4.6
const TUBE_LIGHT_ANGLE: float = 62.0
## Tilt of the cone from vertical into the depth of the hall, degrees.
const TUBE_LIGHT_TILT: float = 38.0
## Above Otto's car at the gate the fixture shines not into the hall but onto the driveway:
## the car stands in front of it, and in the dark by the end wall it could not be made out.
const EXIT_CAR_TILT: float = -24.0
## Pipes along the hall: radius, middle in depth and offset from the edge on
## screen, m. They run through the columns — there the concrete covers them.
const PIPE_RADIUS: float = 0.06
const PIPE_Z: float = COLUMN_Z + 0.1
const PIPE_DROP: float = 0.12
## Ventilation duct: cross-section, middle in depth, offset from the edge, m.
const DUCT := Vector2(0.5, 0.28)
const DUCT_Z: float = -2.4
const DUCT_DROP: float = 0.14

## Shaft core — a concrete wall around the portal and buttons, m beyond them.
const CORE_MARGIN: float = 0.15
## Pier under the floor sign: how much wider than the sign to the left, m.
const PIER_MARGIN: float = 0.35

## Colours: concrete, marking paint, wheel stops, stains, fixtures.
const CONCRETE := Color(0.72, 0.72, 0.7)
const PAINT_WHITE := Color(0.72, 0.72, 0.68)
const PAINT_YELLOW := Color(0.82, 0.62, 0.1)
const PAINT_BLACK := Color(0.05, 0.05, 0.05)
## Garage by building kind (ADR-0058, decision 5): concrete tone — clean light for the
## hotel, cold for the office, dirty for the residential building; the paint band on the far
## wall — burgundy, blue, faded ochre. By [enum BuildingIdentity.Kind].
const KIND_CONCRETE: Array[Color] = [
	Color(1.04, 1.0, 0.94), Color(0.96, 1.0, 1.04), Color(0.78, 0.76, 0.7)
]
const KIND_BAND: Array[Color] = [
	Color(0.4, 0.08, 0.1), Color(0.12, 0.25, 0.5), Color(0.5, 0.4, 0.16)
]
const SIGN_BLUE := Color(0.08, 0.24, 0.62)
const OIL := Color(0.025, 0.025, 0.03)
const DUCT_METAL := Color(0.6, 0.62, 0.64)
const PIPE_RED := Color(0.55, 0.1, 0.08)
const PIPE_GREY := Color(0.34, 0.35, 0.37)
const TUBE := Color(0.82, 0.93, 1.0)
const TUBE_OFF := Color(0.42, 0.44, 0.46)
const FIXTURE_BODY := Color(0.7, 0.71, 0.72)
const HEADLIGHT_OFF := Color(0.6, 0.6, 0.56)
const TAILLIGHT_OFF := Color(0.32, 0.04, 0.03)

## Garage level label on the pier by the floor sign: the same "P" as on the
## floor sign, the shaft indicator boards and in the HUD.
const LEVEL_MARK := FloorSigns.PARKING_MARK

## Salt of the car draw: its own, so the garage does not move in step with the layout.
const SALT: int = 0x6A2A_6E00


## Fixture above a bay: tube, floor light pool and, above an occupied bay, light.
class Fixture:
	extends RefCounted

	var tube: MeshInstance3D = null
	var pool: MeshInstance3D = null
	var light: SpotLight3D = null
	var lit: bool = true


## Someone else's car in a bay: where, which one and which end faces the driveway.
class Parked:
	extends RefCounted

	var x: float = 0.0
	var choice: CarModel.Choice = CarModel.Choice.new()
	## Nose to the far wall — the boot faces the driveway.
	var nose_in: bool = true


## Light pool material — one for all pools.
static var _pool: StandardMaterial3D = null

## The gate in the left end wall: shutter, housing, EXIT sign and the ramp behind them.
var gate: GarageGate = null
## Garage finish by building kind (ADR-0058, decision 5).
var dressing: GarageDressing = null

var _rules: BuildingRules = null
var _plan: BuildingPlan = null
var _bottom: int = 0
var _surface: float = 0.0
var _top: float = 0.0
var _inner := Vector2.ZERO
var _concrete: StandardMaterial3D = null
## Fixtures by floor lamps: lamp x → [Fixture] of its zone.
var _tubes: Dictionary = {}
## All fixtures — for [method tube_lit_at] and picking light by frame.
var _fixtures: Array[Fixture] = []
## Whether the floor is in frame: tube light is on only then ([method show_lights]).
var _in_view: bool = true
var _lamp_xs := PackedFloat64Array()
## Hall layout computed once per build: every part asks for it.
var _cores: Array[Vector2] = []
var _columns := PackedFloat64Array()
var _bays: Array[Vector2] = []
var _parked: Array[Parked] = []


## Horizontal middle of the gate: inside the left wall of the bottom floor.
static func gate_x(rules: BuildingRules) -> float:
	return rules.floor_span(rules.floors - 1).x + BuildingShell.WALL_WIDTH * 0.5


## Inner span of the bottom floor — from wall to wall.
static func inner_span(rules: BuildingRules) -> Vector2:
	var bounds := rules.floor_span(rules.floors - 1)
	return Vector2(bounds.x + BuildingShell.WALL_WIDTH, bounds.y - BuildingShell.WALL_WIDTH)


## Cores of the shafts that go down to the basement: portal with a casing and a button panel.
static func cores(rules: BuildingRules, plan: BuildingPlan) -> Array[Vector2]:
	var bottom := rules.floors - 1
	var found: Array[Vector2] = []
	var reach := (
		rules.shaft_width * 0.5
		+ BuildingShafts.PORTAL_JAMB
		+ BuildingShafts.CALL_GAP
		+ BuildingShafts.CALL_PANEL.x
		+ CORE_MARGIN
	)
	for shaft in plan.shafts:
		if shaft.top <= bottom and bottom <= shaft.bottom:
			found.append(Vector2(shaft.x - reach, shaft.x + reach))
	return found


## Pier under the floor sign: the sign hangs at the back wall, and in the open hall
## it needs a wall behind it.
static func pier(rules: BuildingRules) -> Vector2:
	var sign_x := FloorSigns.centre_on(rules, rules.floors - 1).x
	var left := sign_x - Proportions.FLOOR_SIGN.x * 0.5 - PIER_MARGIN
	return Vector2(left, inner_span(rules).y)


## Everything that closes the hall from the front line: the wall by the gate, shaft cores,
## the sign pier, inner walls and escalator spans. Columns and bays are
## not here.
static func busy_spans(rules: BuildingRules, plan: BuildingPlan) -> Array[Vector2]:
	var bottom := rules.floors - 1
	var inner := inner_span(rules)
	var busy: Array[Vector2] = [Vector2(inner.x, inner.x + GATE_BAY), pier(rules)]
	busy.append_array(cores(rules, plan))
	for wall in plan.walls:
		if wall.floor_index == bottom:
			busy.append(wall.band(rules))
	for escalator in plan.escalators:
		if escalator.floor_index == bottom - 1 or escalator.floor_index == bottom:
			var gap := escalator.gap(rules)
			busy.append(Vector2(gap.x - 1.0, gap.y + 1.0))
	return busy


## Front line columns: on a grid with pitch [constant COLUMN_PITCH], except
## those that would stand in a shaft core, in a wall or by the gate.
static func column_xs(rules: BuildingRules, plan: BuildingPlan) -> PackedFloat64Array:
	var inner := inner_span(rules)
	var busy := busy_spans(rules, plan)
	var reach := COLUMN * 0.5 + COLUMN_CLEARANCE
	var found := PackedFloat64Array()
	var x := rules.slot_x(0) - Proportions.SLOT * 0.5
	while x + reach <= inner.y:
		var free := x - reach >= inner.x
		for span in busy:
			if x + reach > span.x and x - reach < span.y:
				free = false
		if free:
			found.append(x)
		x += COLUMN_PITCH
	return found


## Garage bays: "left edge, right edge" pairs between columns and walls,
## not narrower than [constant BAY_MIN].
static func bays(rules: BuildingRules, plan: BuildingPlan) -> Array[Vector2]:
	var blocks := busy_spans(rules, plan)
	for x in column_xs(rules, plan):
		blocks.append(Vector2(x - COLUMN * 0.5, x + COLUMN * 0.5))
	var found: Array[Vector2] = []
	for span in BuildingPlan.spans_between(blocks, inner_span(rules)):
		var count := floori((span.y - span.x) / BAY_MIN)
		if count <= 0:
			continue
		var width := (span.y - span.x) / float(count)
		for index in count:
			found.append(Vector2(span.x + width * index, span.x + width * (index + 1)))
	return found


## Where another car may not go: near the exit and Otto's car — its spot
## ([method ExitCar.spot]) and the strip by the gate ([method ExitCar.parked_span]), with
## a clearance. Otto's car stands in the driveway, the others in the hall, but in the frame
## they are one above the other, and Otto's spot must read as free.
static func keep_out(rules: BuildingRules, plan: BuildingPlan) -> Array[Vector2]:
	var exit_half := Proportions.EXIT_WIDTH * 0.5
	var spot := ExitCar.spot(plan.exit_x, rules, plan)
	var car_half := CarModel.LENGTH * 0.5 + ExitCar.GAP
	var at_gate := ExitCar.parked_span(rules)
	return (
		[
			Vector2(plan.exit_x - exit_half, plan.exit_x + exit_half),
			Vector2(spot - car_half, spot + car_half),
			Vector2(at_gate.x - ExitCar.GAP, at_gate.y + ExitCar.GAP),
		]
		as Array[Vector2]
	)


## The building's other cars: a draw by seed, in bays [method bays], avoiding
## [method keep_out].
static func parked(rules: BuildingRules, plan: BuildingPlan, building_seed: int) -> Array[Parked]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, SALT])
	var banned := keep_out(rules, plan)
	var found: Array[Parked] = []
	for bay in bays(rules, plan):
		# The draw is taken for every bay, occupied or not: otherwise a change
		# of the keep-out zone would rearrange cars throughout the garage.
		var roll := rng.randf()
		# Red is Otto's car in the first building: the others do not repeat it. Model and
		# paint — by building kind (ADR-0058, decision 4).
		var drawn := CarModel.draw(rng, rules.kind, [0])
		var nose_in := rng.randf() < 0.75
		if roll > PARKED_SHARE or bay.y - bay.x < CAR_WIDTH + 0.4:
			continue
		var free := true
		for span in banned:
			if bay.y > span.x and bay.x < span.y:
				free = false
		if not free:
			continue
		var car := Parked.new()
		car.x = (bay.x + bay.y) * 0.5
		car.choice = drawn
		car.nose_in = nose_in
		found.append(car)
	return found


## Builds the garage on the bottom floor.
func build(rules: BuildingRules, plan: BuildingPlan, building_seed: int) -> void:
	_rules = rules
	_plan = plan
	_bottom = rules.floors - 1
	_surface = rules.floor_surface(_bottom)
	_top = rules.story_top(_bottom)
	_inner = inner_span(rules)
	_concrete = BuildingFinish.shaft_concrete(CONCRETE * KIND_CONCRETE[rules.kind])
	for lamp in plan.lamps:
		if lamp.floor_index == _bottom:
			_lamp_xs.append(lamp.x)
	_cores = cores(rules, plan)
	_columns = column_xs(rules, plan)
	_bays = bays(rules, plan)
	_parked = parked(rules, plan, building_seed)

	_build_walls()
	_build_columns()
	_build_ceiling()
	_build_fixtures()
	_mark_the_floor(building_seed)
	_park_cars()
	gate = GarageGate.new()
	gate.name = "Gate"
	add_child(gate)
	gate.build(rules, building_seed)
	_hang_signs()
	# Garage by building kind (ADR-0058, decision 5).
	dressing = GarageDressing.new()
	add_child(dressing)
	dressing.build(rules, plan, building_seed)
	# A dark floor gets no lamps at all ([method BuildingRules.lamps_on]), and
	# there is nothing to darken by lamp zones: all fixtures go dark at once.
	if rules.is_unlit(_bottom):
		for fixture in _fixtures:
			_put_out(fixture)


## Darkens the tubes in the zone of the lamp closest to [param x] — where it hung.
## Called by the level when a bottom floor lamp has fallen: the zone is dark, and the fixture
## above it must not be lit.
func darken(x: float) -> void:
	var nearest := _nearest_lamp(x)
	if is_nan(nearest):
		return
	for fixture: Fixture in _tubes.get(nearest, []):
		_put_out(fixture)


func _put_out(fixture: Fixture) -> void:
	fixture.lit = false
	fixture.tube.material_override = GreyboxLook.surface(TUBE_OFF)
	fixture.pool.visible = false
	if fixture.light != null:
		fixture.light.visible = false


## Whether the fixture tube above [param x] is lit; false — there is no fixture there.
func tube_lit_at(x: float) -> bool:
	for fixture in _fixtures:
		if absf(fixture.tube.position.x - x) <= FIXTURE.x * 0.5:
			return fixture.lit
	return false


## Tube light is on only while the bottom floor is in frame — by the same rule as
## the lamps ([VisibleFloors]); called by the level.
func show_lights(in_view: bool) -> void:
	if in_view == _in_view:
		return
	_in_view = in_view
	for fixture in _fixtures:
		if fixture.light != null:
			fixture.light.visible = in_view and fixture.lit


## How many fixtures cast real light — for budget tests.
func lights() -> Array[SpotLight3D]:
	var found: Array[SpotLight3D] = []
	for fixture in _fixtures:
		if fixture.light != null:
			found.append(fixture.light)
	return found


## Raises the gate shutter over [param duration] seconds to the gate motor sound — see
## [method GarageGate.open]. The gate sound plays here, finishing the building does not
## repeat it.
func open_gate(duration: float = GarageGate.OPEN_TIME) -> Tween:
	# The office barrier — together with the gate (ADR-0058, decision 6).
	if dressing != null:
		dressing.raise_barrier(duration)
	return gate.open(duration)


## Whether the gate is fully open.
func is_gate_open() -> bool:
	return gate.is_open()


func _nearest_lamp(x: float) -> float:
	var best := NAN
	for lamp_x in _lamp_xs:
		if is_nan(best) or absf(lamp_x - x) < absf(best - x):
			best = lamp_x
	return best


## Far wall, shaft cores, the wall by the gate and the sign pier.
func _build_walls() -> void:
	var height := _surface - _top
	var far_front := FAR_Z + FAR_THICKNESS * 0.5
	_box(
		Vector3(_inner.y - _inner.x, height, FAR_THICKNESS),
		_concrete,
		_at((_inner.x + _inner.y) * 0.5, _top + height * 0.5, FAR_Z)
	)
	# The paint band along the far wall and the bay numbers above it are near the floor: the
	# top of the wall in the depth is hidden by the slab edge.
	var band := GreyboxLook.surface(KIND_BAND[_rules.kind])
	for span in BuildingPlan.spans_between(_cores, _inner):
		_box(
			Vector3(span.y - span.x, 0.5, 0.01),
			band,
			_at((span.x + span.y) * 0.5, _surface - 0.55, far_front + 0.005),
			false
		)
	var number := 0
	for bay in _bays:
		number += 1
		var digits := label("%02d" % number, 800, 0.34, PAINT_WHITE)
		digits.position = _at((bay.x + bay.y) * 0.5, _surface - 1.1, far_front + 0.004)
		add_child(digits)

	# Shaft core — concrete from the front line to the far wall: the portal, plate and
	# shaft buttons hang on its front face, as they hung on the back wall.
	var core_depth := WorldSpace.BACK_WALL_Z - far_front
	for core in _cores:
		_box(
			Vector3(core.y - core.x, height, core_depth),
			_concrete,
			_at(
				(core.x + core.y) * 0.5,
				_top + height * 0.5,
				WorldSpace.BACK_WALL_Z - core_depth * 0.5
			)
		)
	var wall_depth := 0.5
	var walls: Array[Vector2] = [Vector2(_inner.x, _inner.x + GATE_BAY), pier(_rules)]
	for wall in walls:
		# The sign pier sticks out slightly: the sign hangs in front of the back
		# wall by [constant FloorSigns.STANDOFF], and without support it would float.
		var front := WorldSpace.BACK_WALL_Z
		if wall == walls[1]:
			front = WorldSpace.BACK_WALL_Z + FloorSigns.STANDOFF - 0.03
		_box(
			Vector3(wall.y - wall.x, height, wall_depth),
			_concrete,
			_at((wall.x + wall.y) * 0.5, _top + height * 0.5, front - wall_depth * 0.5)
		)
	var mark := label(LEVEL_MARK, 700, 0.62, PAINT_YELLOW)
	var pier_span := pier(_rules)
	mark.position = _at(
		(pier_span.x + pier_span.y) * 0.5,
		_surface - 1.25,
		WorldSpace.BACK_WALL_Z + FloorSigns.STANDOFF - 0.03 + 0.004
	)
	add_child(mark)


## Front line columns: concrete, paint bands at the bottom, number and "P" sign.
func _build_columns() -> void:
	var height := _surface - _top
	var yellow := GreyboxLook.surface(PAINT_YELLOW)
	var black := GreyboxLook.surface(PAINT_BLACK)
	var white := GreyboxLook.surface(PAINT_WHITE)
	var blue := GreyboxLook.surface(SIGN_BLUE)
	var front := COLUMN_Z + COLUMN * 0.5
	var number := 0
	for x in _columns:
		number += 1
		_box(Vector3(COLUMN, height, COLUMN), _concrete, _at(x, _top + height * 0.5, COLUMN_Z))
		# Paint as a wrap slightly wider than the column and slightly above the floor — no face
		# lies in the plane of the concrete.
		_box(
			Vector3(COLUMN + 0.02, 0.9, COLUMN + 0.02),
			yellow,
			_at(x, _surface - 0.005 - 0.45, COLUMN_Z),
			false
		)
		for rise: float in [0.25, 0.6]:
			_box(
				Vector3(COLUMN + 0.03, 0.12, COLUMN + 0.03),
				black,
				_at(x, _surface - rise, COLUMN_Z),
				false
			)
		_box(Vector3(0.36, 0.26, 0.006), white, _at(x, _surface - 1.55, front + 0.005), false)
		var code := label("%s·%02d" % [LEVEL_MARK, number], 700, 0.1, PAINT_BLACK)
		code.position = _at(x, _surface - 1.55, front + 0.01)
		add_child(code)
		if number % 2 == 1:
			_box(Vector3(0.34, 0.34, 0.02), blue, _at(x, _surface - 2.1, front + 0.012), false)
			var letter := label("P", 800, 0.26, Color(0.95, 0.96, 1.0))
			letter.position = _at(x, _surface - 2.1, front + 0.025)
			add_child(letter)


## Beams across the hall above the columns, the ventilation duct and pipes.
func _build_ceiling() -> void:
	var far_front := FAR_Z + FAR_THICKNESS * 0.5
	# Beam ends — as teeth under the slab edge: across the driveway, above
	# a column. Above a lamp a beam starts behind the front line.
	for x in _columns:
		var front := WorldSpace.CORRIDOR_DEPTH * 0.5 - 0.02
		for lamp_x in _lamp_xs:
			if absf(lamp_x - x) < BEAM_LAMP_CLEARANCE:
				front = COLUMN_Z - COLUMN * 0.5
		var depth := front - far_front
		_box(
			Vector3(BEAM.x, BEAM.y, depth),
			_concrete,
			_at(x, _top + BEAM.y * 0.5, front - depth * 0.5)
		)

	# Galvanised steel is rough, not mirror-like: a mirror would reflect the blue of the hall.
	var duct := GreyboxLook.surface(DUCT_METAL)
	var duct_front := DUCT_Z + DUCT.x * 0.5
	var duct_top := _top + FloorSigns.hidden_band(duct_front) + DUCT_DROP
	for span in BuildingPlan.spans_between(_cores, _inner):
		if span.y - span.x < 1.0:
			continue
		_box(
			Vector3(span.y - span.x, DUCT.y, DUCT.x),
			duct,
			_at((span.x + span.y) * 0.5, duct_top + DUCT.y * 0.5, DUCT_Z)
		)
		# Joint flanges: a box slightly larger than the cross-section every 1.5 m.
		var flange_x := span.x + 0.75
		while flange_x < span.y - 0.3:
			_box(
				Vector3(0.05, DUCT.y + 0.04, DUCT.x + 0.04),
				duct,
				_at(flange_x, duct_top + DUCT.y * 0.5, DUCT_Z),
				false
			)
			flange_x += 1.5

	# Pipes along the hall: a red sprinkler one and a grey one below it. Breaks — at
	# the shaft cores and the sign pier: the pipes go into the concrete.
	var cuts: Array[Vector2] = [pier(_rules)]
	cuts.append_array(_cores)
	var pipe_top := _top + FloorSigns.hidden_band(PIPE_Z + PIPE_RADIUS) + PIPE_DROP
	var pipes: Array[Array] = [
		[GreyboxLook.metal(PIPE_RED), pipe_top + PIPE_RADIUS, PIPE_RADIUS],
		[GreyboxLook.metal(PIPE_GREY), pipe_top + PIPE_RADIUS * 2.0 + 0.06, PIPE_RADIUS * 0.7],
	]
	for span in BuildingPlan.spans_between(cuts, _inner):
		if span.y - span.x < 0.4:
			continue
		for pipe in pipes:
			var mesh := CylinderMesh.new()
			mesh.top_radius = pipe[2]
			mesh.bottom_radius = pipe[2]
			mesh.height = span.y - span.x
			mesh.radial_segments = 12
			mesh.rings = 1
			var part := MeshInstance3D.new()
			part.mesh = mesh
			part.material_override = pipe[0]
			part.rotation.z = PI * 0.5
			part.position = _at((span.x + span.y) * 0.5, pipe[1], PIPE_Z)
			add_child(part)


## Fluorescent fixtures above the bays: housing on hangers, the tube is
## emissive, below it on the floor a light pool, above an occupied bay a weak light
## without shadow. All of it goes dark together with the zone of the nearest lamp.
func _build_fixtures() -> void:
	var taken := PackedFloat64Array()
	for car in _parked:
		taken.append(car.x)
	var at_gate := ExitCar.parked_span(_rules)
	var body := GreyboxLook.metal(FIXTURE_BODY)
	var tube := GreyboxLook.light(TUBE)
	var front := FIXTURE_Z + FIXTURE.z * 0.5
	var fixture_top := _top + FloorSigns.hidden_band(front) + 0.03
	var reach := (FIXTURE.x - 0.1) * 0.5
	for bay in _bays:
		var x := _fixture_x(bay)
		if is_nan(x):
			continue
		_box(FIXTURE, body, _at(x, fixture_top + FIXTURE.y * 0.5, FIXTURE_Z), false)
		for side: float in [-1.0, 1.0]:
			_box(
				Vector3(0.015, fixture_top - _top, 0.015),
				body,
				_at(x + side * reach * 0.8, (_top + fixture_top) * 0.5, FIXTURE_Z),
				false
			)
		var glow := _box(
			DIFFUSER,
			tube,
			_at(x, fixture_top + FIXTURE.y + DIFFUSER.y * 0.5 - 0.015, FIXTURE_Z + 0.01),
			false
		)
		var fixture := Fixture.new()
		fixture.tube = glow
		fixture.pool = _light_pool()
		fixture.pool.position = _at(x, _surface - 0.012, FIXTURE_Z - POOL.y * 0.5 + 0.2)
		add_child(fixture.pool)
		var over_car := bay.y > at_gate.x and bay.x < at_gate.y
		if taken.has((bay.x + bay.y) * 0.5) or over_car:
			fixture.light = _tube_light(EXIT_CAR_TILT if over_car else TUBE_LIGHT_TILT)
			fixture.light.position = _at(x, fixture_top + FIXTURE.y + DIFFUSER.y, FIXTURE_Z)
			add_child(fixture.light)
		_fixtures.append(fixture)
		var owner := _nearest_lamp(x)
		if is_nan(owner):
			continue
		var list: Array = _tubes.get(owner, [])
		list.append(fixture)
		_tubes[owner] = list


## Tube light above an occupied bay or Otto's car: a shadowless cone downwards,
## tilted by [param tilt] degrees.
static func _tube_light(tilt: float) -> SpotLight3D:
	var light := SpotLight3D.new()
	light.light_color = TUBE
	light.light_energy = TUBE_LIGHT_ENERGY
	light.spot_range = TUBE_LIGHT_RANGE
	light.spot_angle = TUBE_LIGHT_ANGLE
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = 0.0
	# The cone shines along its -Z: a rotation around X points it down and
	# tilts it — plus into the depth of the hall, minus towards the driveway.
	light.rotation.x = deg_to_rad(tilt - 90.0)
	return light


## Where in bay [param bay] the fixture hangs: in the middle or shifted away from the
## floor lamp. NAN — no room: the lamp shade would cover it.
func _fixture_x(bay: Vector2) -> float:
	var middle := (bay.x + bay.y) * 0.5
	var x := middle
	var slack := maxf((bay.y - bay.x - FIXTURE.x) * 0.5 - 0.05, 0.0)
	for lamp_x in _lamp_xs:
		var gap := x - lamp_x
		if absf(gap) >= FIXTURE_LAMP_CLEARANCE:
			continue
		x = lamp_x + (1.0 if gap >= 0.0 else -1.0) * FIXTURE_LAMP_CLEARANCE
		if absf(x - middle) > slack:
			return NAN
	return x


## Light pool on the floor: a plane with a radial gradient, added to the floor.
## Not a source — a picture of light, like the readability indicator lights.
static func _light_pool() -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = POOL
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = _pool_material()
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return part


static func _pool_material() -> StandardMaterial3D:
	if _pool != null:
		return _pool
	var gradient := Gradient.new()
	gradient.set_color(0, Color(TUBE, POOL_ENERGY))
	gradient.set_color(1, Color(TUBE, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 64
	texture.height = 64
	_pool = StandardMaterial3D.new()
	_pool.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pool.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pool.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_pool.albedo_texture = texture
	_pool.disable_receive_shadows = true
	return _pool


## Markings: bay lines, wheel stops, driveway edge, arrows to the gate, oil stains.
func _mark_the_floor(building_seed: int) -> void:
	var white := GreyboxLook.surface(PAINT_WHITE)
	var yellow := GreyboxLook.surface(PAINT_YELLOW)
	var stop := GreyboxLook.surface(PAINT_YELLOW.darkened(0.3))
	var oil := GreyboxLook.polished(OIL)
	var depth := BAY_FRONT_Z - BAY_BACK_Z
	var edges := PackedFloat64Array()
	for bay in _bays:
		for edge: float in [bay.x, bay.y]:
			if not edges.has(edge):
				edges.append(edge)
		_box(
			Vector3(minf(1.2, bay.y - bay.x - 0.6), 0.1, 0.15),
			stop,
			_at((bay.x + bay.y) * 0.5, _surface - 0.05, BAY_BACK_Z + 0.2)
		)
	# Paint is two millimetres above the floor: a line goes under a column and a
	# wall, and otherwise its bottom would lie in one plane with theirs.
	for edge in edges:
		_box(
			Vector3(0.1, 0.005, depth),
			white,
			_at(edge, _surface - 0.0045, BAY_FRONT_Z - depth * 0.5),
			false
		)

	# Driveway edge — a yellow line along the front line of the bays.
	for span in BuildingPlan.spans_between(busy_spans(_rules, _plan), _inner):
		_box(
			Vector3(span.y - span.x, 0.005, 0.1),
			yellow,
			_at((span.x + span.y) * 0.5, _surface - 0.0045, WorldSpace.BACK_WALL_Z + 0.1),
			false
		)

	# Arrows to the gate along the driveway: one by the gate, then every other span.
	# The first is right behind Otto's car at the gate: under it the arrow is not visible.
	var arrow_x := ExitCar.parked_span(_rules).y + 1.2
	while arrow_x < _inner.y - 1.0:
		_paint_arrow(arrow_x, white)
		arrow_x += COLUMN_PITCH * 2.0

	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, SALT, "oil"])
	for bay in _bays:
		for _stain in rng.randi_range(0, 2):
			var x := rng.randf_range(bay.x + 0.4, bay.y - 0.4)
			var z := rng.randf_range(BAY_BACK_Z + 0.8, BAY_FRONT_Z - 1.2)
			_stain_at(x, z, rng.randf_range(0.18, 0.42), oil)
	for _stain in 4:
		var x := rng.randf_range(_inner.x + 1.0, _inner.y - 1.0)
		_stain_at(x, rng.randf_range(-0.8, 0.8), rng.randf_range(0.12, 0.3), oil)


## An arrow on the driveway floor pointing to the gate: shaft and head.
func _paint_arrow(x: float, paint: StandardMaterial3D) -> void:
	var z := WorldSpace.CORRIDOR_DEPTH * 0.25
	_box(Vector3(0.9, 0.005, 0.16), paint, _at(x + 0.35, _surface - 0.0045, z), false)
	var head := PrismMesh.new()
	head.size = Vector3(0.5, 0.45, 0.006)
	var part := MeshInstance3D.new()
	part.mesh = head
	part.material_override = paint
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The prism triangle is in the XY plane pointing up; to lie on the floor pointing
	# left — a rotation around X onto the floor, then around Y.
	part.basis = Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, -PI * 0.5)
	part.position = _at(x - 0.3, _surface - 0.0045, z)
	add_child(part)


## Oil stain: a dark glossy oval on the floor.
func _stain_at(x: float, z: float, radius: float, material: StandardMaterial3D) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.004
	mesh.radial_segments = 16
	mesh.rings = 1
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.scale = Vector3(1.0, 1.0, 0.6)
	part.position = _at(x, _surface - 0.002, z)
	add_child(part)


## Other cars: pack models, widened to real width and turned
## nose into the hall or towards the driveway. Headlights and brake lights are off: the cars
## are parked.
func _park_cars() -> void:
	var cars := Node3D.new()
	cars.name = "ParkedCars"
	add_child(cars)
	for spot in _parked:
		var model := CarModel.build(spot.choice)
		model.name = "Parked"
		model.scale = Vector3(1.0, 1.0, CAR_WIDTH / depth_of(model))
		# The model's hood is at +X; a quarter turn around Y takes it to -Z.
		model.rotation.y = PI * 0.5 if spot.nose_in else -PI * 0.5
		model.position = _at(spot.x, _surface, CAR_Z)
		switch_lights_off(model)
		cars.add_child(model)


## Depth of the pack model by its meshes, m. The street behind the exit places the car by it.
static func depth_of(model: Node3D) -> float:
	var low := INF
	var high := -INF
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box := mesh.transform * mesh.mesh.get_aabb()
		low = minf(low, box.position.z)
		high = maxf(high, box.end.z)
	return maxf(high - low, 0.1)


static func switch_lights_off(model: Node3D) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface)
			var name := material.resource_name if material != null else ""
			if name == "Headlights":
				mesh.set_surface_override_material(surface, GreyboxLook.polished(HEADLIGHT_OFF))
			elif name == "TailLights":
				mesh.set_surface_override_material(surface, GreyboxLook.polished(TAILLIGHT_OFF))


## Arrow to the gate and hazard stripes on the wall by the gate.
func _hang_signs() -> void:
	var inner_x := _inner.x
	var arrow := label("◀", 800, 0.5, PAINT_WHITE)
	arrow.position = _at(inner_x + GATE_BAY * 0.5, _surface - 1.2, WorldSpace.BACK_WALL_Z + 0.004)
	add_child(arrow)
	# Hazard stripes along the bottom of the wall by the gate — the corner bumpers hit.
	var yellow := GreyboxLook.surface(PAINT_YELLOW)
	var black := GreyboxLook.surface(PAINT_BLACK)
	for index in 4:
		_box(
			Vector3(GATE_BAY, 0.15, 0.008),
			yellow if index % 2 == 0 else black,
			_at(
				inner_x + GATE_BAY * 0.5,
				_surface - 0.003 - 0.075 - 0.15 * index,
				WorldSpace.BACK_WALL_Z + 0.004
			),
			false
		)


## Lettering in paint or light in the game font.
## Static: the gate is labelled with it too ([GarageGate]).
static func label(text: String, weight: int, height: float, color: Color) -> Label3D:
	var painted := Label3D.new()
	painted.text = text
	painted.font = NeonStyle.scene_font(weight)
	painted.font_size = 64
	painted.pixel_size = height / 64.0
	painted.modulate = color
	painted.outline_size = 0
	painted.shaded = true
	painted.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return painted


## Scene point: x and height in rules coordinates, depth as is.
static func scene_point(x: float, y: float, z: float) -> Vector3:
	var point := WorldSpace.to_scene(Vector2(x, y))
	point.z = z
	return point


static func _at(x: float, y: float, z: float) -> Vector3:
	return scene_point(x, y, z)


## A bodiless box at point [param centre] under [param parent]. Small things — markings,
## paint, signs — cast no shadows: they add no shadows to the frame, but
## shadow passes cost. Static: the gate is built the same way ([GarageGate]).
static func put_box(
	parent: Node, size: Vector3, material: StandardMaterial3D, centre: Vector3, shadow: bool
) -> MeshInstance3D:
	var part := GreyboxLook.box(size, material)
	part.position = centre
	if not shadow:
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


func _box(
	size: Vector3,
	material: StandardMaterial3D,
	centre: Vector3,
	shadow: bool = true,
	parent: Node = null
) -> MeshInstance3D:
	return put_box(parent if parent != null else self, size, material, centre, shadow)
