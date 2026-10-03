class_name FloorHall
extends Node3D

## Halls of special floors behind the play plane (ADR-0057, decisions 2–5).
##
## On a special floor, instead of the corridor's back wall there are columns, glass or
## mesh, and behind them a hall through the full depth of the slab: lobby, restaurant,
## pool, boiler room, server room. The floor's role follows the ROM's structure
## ([FloorRole]); here only the look. No bodies, no shadows: primitives and pack
## furniture are assembled into multimeshes ([MeshBatch]) — hundreds of details per
## floor, tens of draw calls per hall. Each floor's hall is its own node, and halls out
## of the frame are hidden ([method light_span], ADR-0060): one set for the whole
## building was drawn every frame wherever the camera was.
##
## A special floor's door opens into the hall itself ([member Door.opens_into_hall]):
## there is no room behind it, and in front of the door only the leaf's strip is free.
##
## At night on the ROM's dark floors everything that glows by itself is off: screens,
## indicators, bar bottles, the furnace window. The steam over the boiler lives on in
## the dark too.
##
## Coordinates: x — along the floor, height — above the floor, depth d — from the
## corridor's back wall into the hall (0 … [constant WorldSpace.ROOM_DEPTH]).

## Chain-link mesh posts and their step, m: the mesh is placed by [BuildingShell].
const MESH_POST := Color(0.34, 0.35, 0.36)
const MESH_POST_STEP: float = 1.5

## Hall depth, m: up to the far wall, with a gap.
const DEPTH: float = WorldSpace.ROOM_DEPTH - 0.15
## The hall places nothing closer than this to the span's edge, m.
const EDGE: float = 0.5
## The hall places no reception or bar counter shorter than this, m: it does not fit on
## a short span between shafts.
const MIN_COUNTER: float = 1.0
## Leaf strip of an office door, m: one may stand deeper.
const LEAF_CLEAR: float = DoorRoom.LEAF_CLEAR

## Hall light: shadowless point lights every [constant LIGHT_STEP] m at mid-depth.
## Corridor lamps shine down, as a cone, and do not reach deep into the hall; without
## its own light the hall would read as a black hole. Like the lamps, they burn only
## on floors in the frame ([method light_span]).
const LIGHT_STEP: float = 5.0
const LIGHT_HEIGHT: float = 2.4
const LIGHT_RANGE: float = 5.5
const LIGHT_ENERGY: float = 1.3
## Pool basin: middle depth-wise and width, m. The near edge is behind the door room,
## the far one — in front of the window strip.
const POOL_DEPTH: float = 5.15
const POOL_WIDTH: float = 2.6
## The boiler's flue starts above it, m; steam rises from its top and melts under the
## ceiling.
const CHIMNEY_FROM: float = 2.0
const STEAM_FROM: float = 2.15

## Its own tint for a hall where the light is special: water, servers, furnace, bar neon.
const POOL_LIGHT := Color(0.55, 0.85, 1.0)
const SERVER_LIGHT := Color(0.6, 0.75, 1.0)
const BOILER_LIGHT := Color(1.0, 0.6, 0.35)
const BAR_LIGHT := Color(1.0, 0.55, 0.6)

## Hall floor by role: marble, parquet, tile, rubber, concrete.
const MARBLE := Color(0.78, 0.74, 0.66)
const DARK_STONE := Color(0.16, 0.17, 0.19)
const TERRAZZO := Color(0.55, 0.53, 0.48)
const PARQUET := Color(0.42, 0.25, 0.13)
const POOL_TILE := Color(0.7, 0.78, 0.8)
const RUBBER := Color(0.1, 0.1, 0.11)
const CONCRETE := Color(0.38, 0.38, 0.37)
const RAISED_FLOOR := Color(0.6, 0.62, 0.63)
const LINOLEUM := Color(0.46, 0.44, 0.36)
const CARPET_HALL := Color(0.3, 0.12, 0.14)
const OFFICE_CARPET := Color(0.22, 0.25, 0.3)
const DINER_TILE := Color(0.62, 0.6, 0.55)

## Colours of hall details.
const WOOD := Color(0.3, 0.17, 0.1)
const BRASS := Color(0.74, 0.56, 0.28)
const STEEL := Color(0.6, 0.62, 0.64)
const DARK_STEEL := Color(0.2, 0.21, 0.23)
const PAINTED_GREEN := Color(0.22, 0.34, 0.26)
const PAINTED_RED := Color(0.5, 0.12, 0.1)
const PIPE := Color(0.36, 0.33, 0.3)
const INSULATION := Color(0.72, 0.7, 0.64)
const CHALK := Color(0.85, 0.85, 0.82)
const RACK := Color(0.08, 0.085, 0.09)
const SCREEN := Color(0.45, 0.75, 0.95)
const TABLE_GREEN := Color(0.1, 0.32, 0.2)
const LINEN := Color(0.88, 0.87, 0.82)
const CARDBOARD := Color(0.55, 0.42, 0.27)
const FIRE := Color(1.0, 0.45, 0.12)
const CANDLE := Color(1.0, 0.75, 0.4)
const NEON := Color(1.0, 0.3, 0.55)
const BOTTLES: Array[Color] = [
	Color(0.9, 0.55, 0.15), Color(0.3, 0.75, 0.35), Color(0.85, 0.85, 0.7), Color(0.6, 0.2, 0.15)
]

var _rules: BuildingRules = null
var _plan: BuildingPlan = null
var _batch := MeshBatch.new()
## The floor being built now.
var _index: int = 0
var _surface: float = 0.0
var _lit: bool = true
var _doors: Array[float] = []
var _steam: Array[Vector3] = []
## Hall lights by floor: [method light_span] puts out the invisible ones.
var _lights: Dictionary = {}
## Hall nodes by floor: [method light_span] hides the ones out of the frame.
var _halls: Dictionary = {}
## Placements of all hall details ([method placements]).
var _placed: Array[Transform3D] = []


## Builds the halls of all of the building's special floors.
func build(rules: BuildingRules, plan: BuildingPlan) -> void:
	name = "FloorHall"
	_rules = rules
	_plan = plan
	for index: int in range(0, rules.floors - 1):
		var role := FloorRole.at(rules, index)
		if FloorRole.is_hall(role):
			_floor(index, role)
			_commit(index)


## Turns on hall lights on visible floors and puts out the rest — by the same rule as
## lamps and shaft pillars (ADR-0010, point 8). The halls themselves are hidden out of
## the frame too (ADR-0060); until the first call every hall is visible.
func light_span(span: Vector2i, strip: Vector2 = Vector2(-INF, INF)) -> void:
	for index: int in _halls:
		(_halls[index] as Node3D).visible = VisibleFloors.covers(span, index)
	for index: int in _lights:
		var lit := VisibleFloors.covers(span, index)
		for light: OmniLight3D in _lights[index]:
			light.visible = lit and VisibleFloors.in_band(strip, light.global_position.x)


## Hall light sources: for tests.
func lights() -> Array[OmniLight3D]:
	var all: Array[OmniLight3D] = []
	for index: int in _lights:
		all.append_array(_lights[index] as Array[OmniLight3D])
	return all


## Placements of all hall details in the scene: for tests. A multimesh under the
## headless engine stores no placements ([method MeshBatch.places]).
func placements() -> Array[Transform3D]:
	return _placed


## How many details there are in the halls: for tests. [param shown_only] — only in
## halls that are not hidden.
func parts(shown_only: bool = false) -> int:
	var total := 0
	for index: int in _halls:
		var hall := _halls[index] as Node3D
		if shown_only and not hall.visible:
			continue
		for child: Node in hall.get_children():
			var many := child as MultiMeshInstance3D
			if many != null:
				total += many.multimesh.instance_count
	return total


## Floors that have a hall node: for tests.
func hall_floors() -> Array[int]:
	var floors: Array[int] = []
	floors.assign(_halls.keys())
	return floors


## Hands floor [param index]'s details and steam over to its own node.
func _commit(index: int) -> void:
	var hall := Node3D.new()
	hall.name = "Hall%d" % index
	add_child(hall)
	_halls[index] = hall
	_placed.append_array(_batch.places())
	_batch.commit(hall)
	for at: Vector3 in _steam:
		hall.add_child(HallLook.steam_plume(at))
	_steam.clear()


func _floor(index: int, role: FloorRole.Role) -> void:
	_index = index
	_surface = _rules.floor_surface(index)
	_lit = not _rules.is_unlit(index)
	_doors.clear()
	for spot: BuildingPlan.DoorSpot in _plan.doors:
		if spot.floor_index == index:
			_doors.append(spot.x)
	var bounds := _rules.floor_span(index)
	var inner := Vector2(bounds.x + BuildingShell.WALL_WIDTH, bounds.y - BuildingShell.WALL_WIDTH)
	for span: Vector2 in BuildingPlan.spans_between(_plan.blocks_on(_rules, index), inner):
		if span.y - span.x < EDGE * 4.0:
			continue
		_lay(role, Vector2(span.x + EDGE, span.y - EDGE))
		if _lit:
			_light(index, role, span)


## Hall light on span [param span]: the kind's lamp tint or the hall's own.
func _light(index: int, role: FloorRole.Role, span: Vector2) -> void:
	var colour: Color = BuildingAir.LAMP_LIGHT[_rules.kind]
	match role:
		FloorRole.Role.POOL:
			colour = POOL_LIGHT
		FloorRole.Role.SERVER:
			colour = SERVER_LIGHT
		FloorRole.Role.BOILER:
			colour = BOILER_LIGHT
		FloorRole.Role.BAR:
			colour = BAR_LIGHT
	if not _lights.has(index):
		_lights[index] = [] as Array[OmniLight3D]
	var count := maxi(1, roundi((span.y - span.x) / LIGHT_STEP))
	for step: int in count:
		var x := span.x + (span.y - span.x) * (float(step) + 0.5) / float(count)
		var light := OmniLight3D.new()
		light.name = "HallLight"
		light.light_color = colour
		light.light_energy = LIGHT_ENERGY
		light.omni_range = LIGHT_RANGE
		light.shadow_enabled = false
		light.position = MeshBatch.scene_of(Vector3(x, _surface - LIGHT_HEIGHT, _z(3.8)))
		light.visible = false
		add_child(light)
		(_lights[index] as Array[OmniLight3D]).append(light)


func _lay(role: FloorRole.Role, span: Vector2) -> void:
	match role:
		FloorRole.Role.LOBBY:
			_lobby(span)
		FloorRole.Role.DINING:
			_dining(span)
		FloorRole.Role.BALLROOM:
			_ballroom(span)
		FloorRole.Role.POOL:
			_pool(span)
		FloorRole.Role.BAR:
			_bar(span)
		FloorRole.Role.CONFERENCE:
			_conference(span)
		FloorRole.Role.MEETING:
			_meeting(span)
		FloorRole.Role.GYM:
			_gym(span)
		FloorRole.Role.COMMUNITY:
			_community(span)
		FloorRole.Role.LOCKERS:
			_lockers(span)
		FloorRole.Role.LAUNDRY:
			_laundry(span)
		FloorRole.Role.BOILER:
			_boiler(span)
		FloorRole.Role.MECHANICAL:
			_mechanical(span)
		FloorRole.Role.SERVER:
			_server(span)
		FloorRole.Role.ARCHIVE:
			_archive(span)
		FloorRole.Role.KITCHEN:
			_kitchen(span)
		FloorRole.Role.STORAGE:
			_storage(span)
		FloorRole.Role.WORKSHOP:
			_workshop(span)


# --- Public halls -----------------------------------------------------------


## Lobby: for a hotel — marble, a reception counter with keys behind it, and sofas; for
## an office — dark stone, a security desk with monitors, and turnstiles; for a
## residential building — terrazzo, mailboxes, a doorman's desk and a bench.
func _lobby(span: Vector2) -> void:
	match _rules.kind:
		BuildingIdentity.Kind.OFFICE:
			_floor_cover(span, GreyboxLook.polished(DARK_STONE))
			_windows(span)
			var middle := (span.x + span.y) * 0.5
			_desk_row(middle, 2.4, 3.2, STEEL, true)
			for x: float in _along(span, 1.1, 0.0):
				if absf(x - middle) < 2.0:
					continue
				_turnstile(x, 5.0)
			for x: float in _along(span, 4.0, 2.0):
				if not _free(x + 0.6, 1.0, 1.4):
					continue
				_prop("bench_cushion", x, 1.4)
				_prop("houseplant_c", x + 1.2, 1.2)
		BuildingIdentity.Kind.RESIDENTIAL:
			_floor_cover(span, GreyboxLook.polished(TERRAZZO))
			_far_wall(span, GreyboxLook.surface(Color(0.5, 0.45, 0.36)))
			for x: float in _along(span, _width_of("mailboxes", 0.05), 0.0):
				_prop("mailboxes", x, DEPTH - 0.2, 0.0, 1.0)
			var middle := (span.x + span.y) * 0.5
			_desk_row(middle, 1.4, 3.6, Color(0.35, 0.24, 0.15), false)
			for x: float in _along(span, 3.5, 1.5):
				if absf(x - middle) < 1.6 or not _free(x + 0.6, 1.2, 0.5):
					continue
				_prop("bench_hotel", x, 1.2)
				_prop("radiator", x + 1.2, 0.5)
		_:
			_floor_cover(span, GreyboxLook.polished(MARBLE))
			_far_wall(span, GreyboxLook.surface(Color(0.36, 0.22, 0.14)))
			var middle := (span.x + span.y) * 0.5
			# The counter spans the span with a metre's margin at the edges: on a short span
			# the width came out negative, and the box turned inside out.
			var counter := minf(span.y - span.x - 2.0, 6.0)
			if counter >= MIN_COUNTER:
				_on(GreyboxLook.surface(WOOD), Vector3(counter, 1.1, 0.7), middle, 0.0, 4.6)
				_on(GreyboxLook.metal(BRASS), Vector3(counter + 0.1, 0.05, 0.8), middle, 1.1, 4.6)
				_key_rack(middle, counter)
			for x: float in _along(span, 3.2, 1.0):
				if not _free(x, 1.4, 1.1):
					continue
				_prop("lounge_sofa", x, 2.0)
				_prop("coffee_table", x, 1.1)
				_prop("floor_lamp_round", x + 1.3, 2.0)
			for x: float in [span.x + 0.4, span.y - 0.4]:
				_prop("houseplant_c", x, 5.5)


## Hotel restaurant — tables with tablecloths and candles, windows onto the city; office
## canteen — long tables, a serving line at the far wall.
func _dining(span: Vector2) -> void:
	if _rules.kind == BuildingIdentity.Kind.OFFICE:
		_floor_cover(span, GreyboxLook.polished(DINER_TILE))
		_far_wall(span, GreyboxLook.surface(Color(0.7, 0.7, 0.68)))
		for x: float in _along(span, _width_of("kitchen_cabinet", 0.0), 0.0):
			_prop("kitchen_cabinet", x, DEPTH - 0.4)
		_on(GreyboxLook.metal(STEEL), Vector3(span.y - span.x, 0.04, 0.3), _mid(span), 0.95, 6.1)
		for row: float in [2.4, 4.4]:
			for x: float in _along(span, 2.6, 0.0):
				if not _free(x, 1.0, row):
					continue
				_prop("long_table", x, row)
				for side: float in [-0.55, 0.55]:
					_prop("desk_chair", x + side, row - 0.6, 180.0)
		return
	_floor_cover(span, GreyboxLook.surface(CARPET_HALL))
	_windows(span)
	for row: float in [2.0, 3.9, 5.6]:
		for x: float in _along(span, 2.2, 0.0 if row != 3.9 else 1.1):
			if not _free(x, 0.8, row):
				continue
			_prop("dining_table", x, row)
			_prop("dining_chair", x - 0.62, row, 90.0)
			_prop("dining_chair", x + 0.62, row, -90.0)
			_glow(CANDLE, 0.05, Vector3(x, 0.82, row))


## Ballroom: parquet, a stage with a grand piano and speakers at the far wall, round
## tables around the dance floor and a mirror ball.
func _ballroom(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.polished(PARQUET))
	_far_wall(span, GreyboxLook.surface(Color(0.32, 0.08, 0.1)))
	var middle := _mid(span)
	var stage := minf(span.y - span.x - 1.0, 7.0)
	_on(GreyboxLook.surface(Color(0.15, 0.1, 0.08)), Vector3(stage, 0.5, 1.8), middle, 0.0, 6.0)
	_piano(middle - stage * 0.25, 5.9)
	for side: float in [-1.0, 1.0]:
		_prop("speaker", middle + side * (stage * 0.5 - 0.4), 6.2)
	_glow(Color(0.9, 0.9, 1.0), 0.45, Vector3(middle, 2.4, 3.5))
	for x: float in _along(span, 2.4, 0.0):
		if absf(x - middle) < 2.5:
			continue
		for row: float in [1.8, 3.6]:
			if _free(x, 0.8, row):
				_prop("round_table", x, row)
				_prop("dining_chair", x - 0.7, row, 90.0)
				_prop("dining_chair", x + 0.7, row, -90.0)


## Pool: light tile, a basin of rippling water, a coping, ladders, loungers at the edge
## and windows onto the city.
func _pool(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.polished(POOL_TILE))
	_windows(span)
	var length := span.y - span.x - 1.0
	var middle := _mid(span)
	# The basin is behind the door rooms ([constant DoorRoom.DEPTH]): across the whole
	# span it would pass through the floor of an open room.
	var near := POOL_DEPTH - POOL_WIDTH * 0.5
	var water := HallLook.water()
	_batch.box(
		water, Vector3(length, 0.03, POOL_WIDTH), Vector3(middle, _surface - 0.035, _z(POOL_DEPTH))
	)
	var rim := GreyboxLook.polished(Color(0.86, 0.88, 0.88))
	for edge: float in [near - 0.1, near + POOL_WIDTH + 0.1]:
		_on(rim, Vector3(length + 0.3, 0.06, 0.15), middle, 0.0, edge)
	for side: float in [-1.0, 1.0]:
		_on(
			rim,
			Vector3(0.15, 0.06, POOL_WIDTH + 0.35),
			middle + side * (length * 0.5 + 0.08),
			0.0,
			POOL_DEPTH
		)
	var rail := GreyboxLook.metal(STEEL)
	for x: float in [span.x + 1.2, span.y - 1.2]:
		if not _free(x, 0.3, near - 0.05):
			continue
		for offset: float in [-0.25, 0.25]:
			_batch.cylinder_on(
				rail, 0.025, 1.0, _surface, Vector3(x + offset, 0.0, _z(near - 0.05))
			)
	for x: float in _along(span, 1.6, 0.0):
		if _free(x, 0.5, 1.4):
			_prop("bench_cushion", x, 1.4)
	_glow(Color(1.0, 0.4, 0.2), 0.3, Vector3(span.x + 0.4, 1.4, 6.6))


## Sky lobby bar: a counter with stools, shelves of glowing bottles behind it, neon and
## sofas by the columns.
func _bar(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.polished(Color(0.14, 0.08, 0.05)))
	_far_wall(span, GreyboxLook.surface(Color(0.12, 0.08, 0.07)))
	var middle := _mid(span)
	for x: float in [span.x + 1.0, span.y - 1.0]:
		if _free(x, 1.0, 1.6):
			_prop("lounge_armchair", x, 1.6)
	var unit_width := _width_of("bar_counter", 0.0)
	# At least three sections, but not wider than the span: on a short span three
	# sections stuck out past the edge — past the shaft, into the neighbouring hall.
	var units := mini(
		clampi(int((span.y - span.x - 2.0) / unit_width), 3, 10),
		int((span.y - span.x) / unit_width)
	)
	if float(units) * unit_width < MIN_COUNTER:
		return
	var left := middle - units * unit_width * 0.5
	for unit: int in units:
		_prop("bar_counter", left + unit_width * (unit + 0.5), 4.2)
		if unit % 2 == 0:
			_prop("bar_stool", left + unit_width * (unit + 0.5), 3.4)
	_shelves(middle, units * unit_width + 0.6)
	if _lit:
		_batch.box_on(
			GreyboxLook.light(NEON),
			Vector3(units * 0.3, 0.05, 0.03),
			_surface,
			Vector3(middle, 2.5, _z(DEPTH))
		)


## Conference hall: rows of chairs with backs to the camera, a podium and a screen at the far wall.
func _conference(span: Vector2) -> void:
	var office := _rules.kind == BuildingIdentity.Kind.OFFICE
	_floor_cover(span, GreyboxLook.surface(OFFICE_CARPET if office else CARPET_HALL))
	_far_wall(span, GreyboxLook.surface(Color(0.3, 0.3, 0.32) if office else Color(0.3, 0.2, 0.14)))
	var middle := _mid(span)
	var screen := minf(span.y - span.x - 1.0, 4.0)
	var face := GreyboxLook.light(SCREEN) if _lit else GreyboxLook.surface(RACK)
	_batch.box_on(face, Vector3(screen, 1.8, 0.04), _surface, Vector3(middle, 0.9, _z(DEPTH)))
	_on(GreyboxLook.surface(WOOD), Vector3(0.6, 1.1, 0.5), middle + screen * 0.5 + 0.6, 0.0, 6.2)
	for row: float in [1.6, 2.6, 3.6, 4.6]:
		for x: float in _along(span, 0.7, 0.0):
			if _free(x, 0.3, row):
				_prop("dining_chair" if not office else "desk_chair", x, row, 180.0)


## Office meeting rooms: glass boxes with a long table, chairs and a TV on the wall.
func _meeting(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.surface(OFFICE_CARPET))
	_windows(span)
	var glass := HallLook.glass()
	var frame := GreyboxLook.metal(STEEL)
	for x: float in _along(span, 4.2, 0.0):
		if not _free(x, 2.0, 2.0):
			continue
		for wall: float in [-2.0, 2.0]:
			_batch.box_on(glass, Vector3(0.03, 2.4, 4.6), _surface, Vector3(x + wall, 0.0, _z(4.0)))
			_on(frame, Vector3(0.06, 2.4, 0.06), x + wall, 0.0, 1.7)
		_batch.box_on(glass, Vector3(4.0, 2.4, 0.03), _surface, Vector3(x, 0.0, _z(1.7)))
		_prop("long_table", x, 4.0)
		for side: float in [-0.9, -0.3, 0.3, 0.9]:
			_prop("desk_chair", x + side, 3.3)
			_prop("desk_chair", x + side, 4.7, 180.0)
		_prop("tv_modern", x, 6.2)


## Gym: rubber floor, treadmills, bench presses with barbells, a dumbbell rack and a
## mirror across the whole far wall.
func _gym(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.surface(RUBBER))
	_far_wall(span, GreyboxLook.metal(Color(0.24, 0.27, 0.29)))
	var steel := GreyboxLook.metal(DARK_STEEL)
	var belt := GreyboxLook.surface(Color(0.06, 0.06, 0.06))
	for x: float in _along(span, 1.4, 0.0):
		if not _free(x, 0.5, 3.0):
			continue
		_on(belt, Vector3(0.75, 0.2, 1.7), x, 0.0, 3.4)
		_on(steel, Vector3(0.7, 0.08, 0.08), x, 1.2, 2.6)
		for side: float in [-0.35, 0.35]:
			_on(steel, Vector3(0.05, 1.2, 0.05), x + side, 0.0, 2.6)
		var console := GreyboxLook.light(HallLook.LED_AMBER) if _lit else steel
		_on(console, Vector3(0.4, 0.15, 0.05), x, 1.25, 2.58)
	for x: float in _along(span, 2.8, 1.4):
		_prop("bench_cushion", x, 5.4)
		_batch.pipe_x(steel, 0.02, 1.6, Vector3(x, _surface - 1.1, _z(5.4)))
		for side: float in [-0.7, 0.7]:
			_batch.pipe_x(
				GreyboxLook.surface(RACK), 0.18, 0.06, Vector3(x + side, _surface - 1.1, _z(5.4))
			)
	_on(steel, Vector3(span.y - span.x - 1.0, 0.05, 0.4), _mid(span), 0.8, DEPTH - 0.3)


## Residential common room: folding tables with chairs, ping-pong, a TV and a sofa.
func _community(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.surface(LINOLEUM))
	_far_wall(span, GreyboxLook.surface(Color(0.55, 0.5, 0.38)))
	_windows(span)
	var middle := _mid(span)
	var green := GreyboxLook.surface(TABLE_GREEN)
	_on(green, Vector3(2.7, 0.05, 1.5), middle, 0.74, 4.2)
	_on(GreyboxLook.surface(CHALK), Vector3(0.03, 0.15, 1.5), middle, 0.79, 4.2)
	for side: float in [-1.2, 1.2]:
		_on(GreyboxLook.metal(DARK_STEEL), Vector3(0.05, 0.74, 1.2), middle + side, 0.0, 4.2)
	for x: float in _along(span, 2.4, 1.2):
		if absf(x - middle) < 2.2 or not _free(x, 1.0, 2.0):
			continue
		_prop("long_table", x, 2.0)
		_prop("dining_chair", x - 0.5, 2.6, 180.0)
		_prop("dining_chair", x + 0.5, 2.6, 180.0)
	_prop("tv_modern", span.x + 1.0, 6.4)
	_prop("couch_medium", span.x + 1.0, 5.2, 180.0)


## Storage cages: rows of mesh compartments on posts, each with boxes, a bicycle or an
## old armchair.
func _lockers(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.surface(CONCRETE))
	var net := HallLook.chain_link()
	var post := GreyboxLook.metal(MESH_POST)
	var stuff: Array[String] = [
		"box_closed", "bicycle", "cardboard_boxes", "armchair", "box_closed"
	]
	var cell := 1.8
	var turn := 0
	for row: float in [2.4, 5.0]:
		for x: float in _along(span, cell, 0.0):
			if not _free(x, cell * 0.5, row):
				continue
			_batch.box_on(net, Vector3(cell, 2.2, 0.02), _surface, Vector3(x, 0.0, _z(row - 1.0)))
			_batch.box_on(
				net, Vector3(0.02, 2.2, 2.0), _surface, Vector3(x - cell * 0.5, 0.0, _z(row))
			)
			_on(post, Vector3(0.05, 2.2, 0.05), x - cell * 0.5, 0.0, row - 1.0)
			var thing := stuff[turn % stuff.size()]
			turn += 1
			_prop(thing, x, row)
			if thing == "box_closed":
				_prop("box_closed", x + 0.3, row + 0.2)


## Laundry: a row of washers and dryers at the far wall, a folding table and carts.
func _laundry(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.polished(DINER_TILE.darkened(0.2)))
	_far_wall(span, GreyboxLook.surface(Color(0.62, 0.64, 0.6)))
	var machines: Array[String] = ["washer", "washer", "dryer", "washer_dryer"]
	var turn := 0
	for x: float in _along(span, _width_of("washer", 0.08), 0.0):
		_prop(machines[turn % machines.size()], x, DEPTH - 0.4)
		turn += 1
	var cart := GreyboxLook.surface(Color(0.5, 0.45, 0.35))
	for x: float in _along(span, 3.0, 0.8):
		if not _free(x, 0.8, 3.4):
			continue
		_prop("long_table", x, 3.4)
		_on(GreyboxLook.surface(LINEN), Vector3(0.6, 0.2, 0.4), x, 0.76, 3.4)
		_on(cart, Vector3(0.8, 0.6, 0.5), x + 1.3, 0.15, 2.3)
		_on(GreyboxLook.surface(LINEN), Vector3(0.7, 0.15, 0.45), x + 1.3, 0.75, 2.3)


# --- Technical floors -------------------------------------------------------


## Boiler room: barrel boilers on supports with a furnace window, risers and pipes under
## the ceiling, pressure gauges; steam above the boiler.
func _boiler(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.surface(CONCRETE.darkened(0.2)))
	_far_wall(span, GreyboxLook.surface(Color(0.3, 0.3, 0.28)))
	var shell := GreyboxLook.metal(
		PAINTED_RED if _rules.kind == BuildingIdentity.Kind.HOTEL else PAINTED_GREEN
	)
	var pipe := GreyboxLook.metal(PIPE)
	var lagging := GreyboxLook.surface(INSULATION)
	for x: float in _along(span, 4.2, 0.0):
		if not _free(x, 1.9, 4.5):
			continue
		_batch.pipe_x(shell, 0.85, 3.2, Vector3(x, _surface - 1.25, _z(4.5)))
		for side: float in [-1.2, 1.2]:
			_on(GreyboxLook.surface(DARK_STEEL), Vector3(0.2, 0.45, 1.4), x + side, 0.0, 4.5)
		var door := GreyboxLook.light(FIRE) if _lit else GreyboxLook.surface(RACK)
		_batch.box_on(door, Vector3(0.35, 0.25, 0.02), _surface, Vector3(x - 1.62, 1.1, _z(4.5)))
		# The flue runs from the boiler to the ceiling: at two metres it went through the
		# slab into the hall of the floor above, and steam from under the ceiling rose
		# there too.
		var ceiling := _surface - _rules.story_top(_index)
		_batch.cylinder_on(
			pipe, 0.12, ceiling - CHIMNEY_FROM, _surface, Vector3(x + 0.8, CHIMNEY_FROM, _z(4.5))
		)
		_batch.sphere(GreyboxLook.surface(CHALK), 0.16, Vector3(x - 0.6, _surface - 2.15, _z(3.6)))
		_steam.append(
			WorldSpace.to_scene(Vector2(x + 0.3, _surface - STEAM_FROM)) + Vector3(0, 0, _z(4.5))
		)
	_overhead(span, pipe, lagging)


## Ventilation and pumps: air handling unit casings with grilles, fans, pumps on frames
## and ducts.
func _mechanical(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.surface(CONCRETE))
	_far_wall(span, GreyboxLook.surface(Color(0.34, 0.35, 0.34)))
	var unit := GreyboxLook.metal(Color(0.58, 0.6, 0.6))
	var grille := GreyboxLook.surface(DARK_STEEL)
	var pump := GreyboxLook.metal(Color(0.15, 0.3, 0.55))
	var pipe := GreyboxLook.metal(PIPE)
	for x: float in _along(span, 3.6, 0.0):
		if _free(x, 1.5, 5.0):
			_on(unit, Vector3(2.8, 1.8, 1.6), x, 0.0, 5.0)
			for grid: int in 4:
				_on(grille, Vector3(0.5, 1.2, 0.02), x - 1.0 + grid * 0.66, 0.3, 4.19)
		if _free(x + 1.8, 0.4, 2.2):
			_on(GreyboxLook.surface(DARK_STEEL), Vector3(0.8, 0.12, 0.5), x + 1.8, 0.0, 2.2)
			_batch.pipe_x(pump, 0.18, 0.5, Vector3(x + 1.7, _surface - 0.35, _z(2.2)))
			_batch.cylinder_on(pump, 0.12, 0.45, _surface, Vector3(x + 2.05, 0.12, _z(2.2)))
	_overhead(span, pipe, GreyboxLook.metal(Color(0.7, 0.72, 0.72)))


## Office server room: raised floor, two rows of racks with blinking indicators, cold
## light and a cable tray duct.
func _server(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.polished(RAISED_FLOOR))
	_far_wall(span, GreyboxLook.surface(Color(0.25, 0.27, 0.3)))
	var body := GreyboxLook.metal(RACK)
	var leds: Material = HallLook.led() if _lit else GreyboxLook.surface(DARK_STEEL)
	for row: float in [2.6, 5.2]:
		for x: float in _along(span, 0.66, 0.0):
			if not _free(x, 0.33, row):
				continue
			_on(body, Vector3(0.6, 2.0, 1.0), x, 0.0, row)
			for slot: int in 8:
				_on(leds, Vector3(0.36, 0.03, 0.01), x, 0.3 + slot * 0.2, row - 0.505)
	var tray := GreyboxLook.metal(Color(0.45, 0.47, 0.5))
	_on(tray, Vector3(span.y - span.x, 0.08, 0.4), _mid(span), 2.3, 2.6)
	_on(tray, Vector3(span.y - span.x, 0.08, 0.4), _mid(span), 2.3, 5.2)


## Archive: rows of shelving with file boxes and filing cabinets.
func _archive(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.surface(LINOLEUM.darkened(0.2)))
	_far_wall(span, GreyboxLook.surface(Color(0.5, 0.5, 0.47)))
	for row: float in [2.2, 4.0, 5.8]:
		for x: float in _along(span, 1.6, 0.0 if row != 4.0 else 0.8):
			if _free(x, 0.8, row):
				_shelf_unit(x, row, CARDBOARD)
	for x: float in _along(span, 3.0, 1.5):
		if _free(x, 0.3, 1.0):
			_prop("file_cabinet", x, 1.0)


## Hotel kitchen: a line of stoves under hoods, sinks, refrigerators and stainless steel
## prep tables.
func _kitchen(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.polished(Color(0.5, 0.42, 0.36)))
	_far_wall(span, GreyboxLook.polished(Color(0.82, 0.82, 0.78)))
	var line: Array[String] = ["kitchen_stove", "kitchen_stove", "kitchen_sink", "kitchen_cabinet"]
	var turn := 0
	for x: float in _along(span, _width_of("kitchen_cabinet", 0.0), 0.0):
		var item := line[turn % line.size()]
		_prop(item, x, DEPTH - 0.4)
		if item == "kitchen_stove":
			_prop("kitchen_hood", x, DEPTH - 0.3, 0.0, 1.5)
		turn += 1
	var steel := GreyboxLook.metal(STEEL)
	for x: float in _along(span, 3.2, 0.0):
		if _free(x, 1.0, 3.6):
			_on(steel, Vector3(2.0, 0.05, 0.9), x, 0.88, 3.6)
			for side: float in [-0.9, 0.9]:
				_on(steel, Vector3(0.05, 0.88, 0.8), x + side, 0.0, 3.6)
			_on(steel, Vector3(1.9, 0.03, 0.8), x, 0.2, 3.6)
		if _free(x + 1.6, 0.4, 2.0):
			_prop("kitchen_fridge", x + 1.6, 2.0)


## Storeroom: shelving with boxes; for a hotel, linen storage — stacks of white linen.
func _storage(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.surface(CONCRETE))
	_far_wall(span, GreyboxLook.surface(Color(0.4, 0.4, 0.38)))
	var goods := LINEN if _rules.kind == BuildingIdentity.Kind.HOTEL else CARDBOARD
	for row: float in [2.4, 4.8]:
		for x: float in _along(span, 1.6, 0.0):
			if _free(x, 0.8, row):
				_shelf_unit(x, row, goods)
	for x: float in _along(span, 2.6, 1.3):
		if _free(x, 0.4, 6.4):
			_prop("cardboard_boxes", x, 6.4)


## Residential workshop: a workbench, a tool board on the wall, cabinets and a stepladder.
func _workshop(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.surface(CONCRETE.darkened(0.1)))
	_far_wall(span, GreyboxLook.surface(Color(0.42, 0.38, 0.3)))
	var board := GreyboxLook.surface(Color(0.55, 0.42, 0.25))
	var tool := GreyboxLook.metal(DARK_STEEL)
	for x: float in _along(span, 3.0, 0.0):
		if not _free(x, 1.2, 5.6):
			continue
		_on(GreyboxLook.surface(WOOD.lightened(0.15)), Vector3(2.2, 0.08, 0.8), x, 0.86, 5.8)
		for side: float in [-1.0, 1.0]:
			_on(GreyboxLook.surface(WOOD), Vector3(0.08, 0.86, 0.7), x + side, 0.0, 5.8)
		_batch.box_on(board, Vector3(2.0, 1.0, 0.03), _surface, Vector3(x, 1.25, _z(DEPTH - 0.02)))
		for peg: int in 6:
			_batch.box_on(
				tool,
				Vector3(0.05, 0.35, 0.03),
				_surface,
				Vector3(x - 0.8 + peg * 0.32, 1.5, _z(DEPTH - 0.05))
			)
		_prop("cabinet", x + 1.5, 3.0)
	if not _free(span.x + 0.6, 0.3, 2.5):
		return
	var ladder := GreyboxLook.metal(STEEL)
	for side: float in [-0.25, 0.25]:
		_on(ladder, Vector3(0.04, 2.0, 0.04), span.x + 0.6 + side, 0.0, 2.5)
	for rung: int in 6:
		_on(ladder, Vector3(0.5, 0.03, 0.04), span.x + 0.6, 0.3 + rung * 0.3, 2.5)


# --- Details ----------------------------------------------------------------


## Hall floor over the slab: the full depth of the hall along the span.
func _floor_cover(span: Vector2, material: Material) -> void:
	_batch.box(
		material,
		Vector3(span.y - span.x + EDGE * 2.0, 0.02, WorldSpace.ROOM_DEPTH),
		Vector3(_mid(span), _surface - 0.01, WorldSpace.BACK_WALL_Z - WorldSpace.ROOM_DEPTH * 0.5)
	)


## The hall's far wall in its own colour: over the common wall of [BuildingShell].
func _far_wall(span: Vector2, material: Material) -> void:
	var height := _surface - _rules.story_top(_index)
	_batch.box(
		material,
		Vector3(span.y - span.x + EDGE * 2.0, height, 0.04),
		Vector3(_mid(span), _surface - height * 0.5, _z(WorldSpace.ROOM_DEPTH - 0.04))
	)


## Windows onto the city at the far wall — for public halls.
func _windows(span: Vector2) -> void:
	OpenSpace.ribbon_windows(
		_batch,
		TimeOfDay.window_look(_rules.time_of_day, OpenSpace.NIGHT_GLASS),
		GreyboxLook.metal(OpenSpace.FRAME),
		Vector2(span.x - EDGE, span.y + EDGE),
		_surface,
		WorldSpace.BACK_WALL_Z - WorldSpace.ROOM_DEPTH + 0.05
	)


## Pipes under the ceiling of a technical floor: two mains along and drops down.
func _overhead(span: Vector2, pipe: Material, lagging: Material) -> void:
	var length := span.y - span.x + EDGE * 2.0
	var middle := _mid(span)
	_batch.pipe_x(lagging, 0.16, length, Vector3(middle, _surface - 2.75, _z(6.4)))
	_batch.pipe_x(pipe, 0.09, length, Vector3(middle, _surface - 2.55, _z(5.9)))
	for x: float in _along(span, 2.2, 1.1):
		_batch.cylinder_on(pipe, 0.06, 2.6, _surface, Vector3(x, 0.0, _z(6.6)))


## A full-length desk: a security or doorman's counter, with monitors.
func _desk_row(x: float, length: float, d: float, colour: Color, screens: bool) -> void:
	_on(GreyboxLook.metal(colour), Vector3(length, 1.05, 0.7), x, 0.0, d)
	if not screens:
		_prop("desk_chair", x, d + 0.7, 180.0)
		return
	for side: float in [-0.5, 0.0, 0.5]:
		_on(GreyboxLook.surface(RACK), Vector3(0.45, 0.32, 0.05), x + side, 1.1, d + 0.15)
		var face := GreyboxLook.light(SCREEN) if _lit else GreyboxLook.surface(RACK)
		_on(face, Vector3(0.39, 0.26, 0.01), x + side, 1.13, d + 0.12)


## Turnstile: a pedestal with a glass leaf.
func _turnstile(x: float, d: float) -> void:
	_on(GreyboxLook.metal(STEEL), Vector3(0.18, 1.0, 1.0), x, 0.0, d)
	_batch.box_on(
		HallLook.glass(), Vector3(0.7, 0.6, 0.02), _surface, Vector3(x + 0.45, 0.4, _z(d))
	)
	var lamp := GreyboxLook.light(HallLook.LED_GREEN) if _lit else GreyboxLook.surface(RACK)
	_on(lamp, Vector3(0.1, 0.02, 0.1), x, 1.0, d - 0.3)


## Key board behind the reception counter: cells with brass tags.
func _key_rack(x: float, width: float) -> void:
	var board := GreyboxLook.surface(WOOD.darkened(0.3))
	_batch.box_on(board, Vector3(width, 1.2, 0.05), _surface, Vector3(x, 1.0, _z(DEPTH - 0.05)))
	var tag := GreyboxLook.metal(BRASS)
	var columns := int(width / 0.25)
	for column: int in columns:
		for row: int in 4:
			_batch.box_on(
				tag,
				Vector3(0.05, 0.08, 0.02),
				_surface,
				Vector3(
					x - width * 0.5 + 0.125 + column * 0.25, 1.15 + row * 0.27, _z(DEPTH - 0.09)
				)
			)


## Grand piano: body, raised lid and legs.
func _piano(x: float, d: float) -> void:
	var black := GreyboxLook.polished(Color(0.02, 0.02, 0.025))
	_on(black, Vector3(1.6, 0.3, 1.2), x, 1.15, d)
	_batch.box(black, Vector3(1.5, 0.02, 1.1), Vector3(x, _surface - 1.75, _z(d - 0.1)))
	for side: float in [-0.65, 0.65]:
		_on(black, Vector3(0.08, 0.65, 0.08), x + side, 0.5, d)
	_on(GreyboxLook.surface(CHALK), Vector3(1.2, 0.03, 0.15), x, 1.2, d - 0.55)


## Bar shelves at the far wall: three tiers of bottles, glowing when lit.
func _shelves(x: float, width: float) -> void:
	var wood := GreyboxLook.surface(WOOD.darkened(0.2))
	_batch.box_on(wood, Vector3(width, 1.6, 0.3), _surface, Vector3(x, 0.9, _z(DEPTH - 0.15)))
	var count := int(width / 0.14)
	for tier: int in 3:
		for bottle: int in count:
			var colour := BOTTLES[(bottle * 7 + tier * 3) % BOTTLES.size()]
			var look := (
				GreyboxLook.light(colour) if _lit else GreyboxLook.surface(colour.darkened(0.6))
			)
			_batch.box_on(
				look,
				Vector3(0.06, 0.26, 0.06),
				_surface,
				Vector3(
					x - width * 0.5 + 0.07 + bottle * 0.14, 1.05 + tier * 0.48, _z(DEPTH - 0.33)
				)
			)


## Shelving: posts, four shelves and the load on them.
func _shelf_unit(x: float, d: float, goods: Color) -> void:
	var steel := GreyboxLook.metal(Color(0.42, 0.44, 0.46))
	var load := GreyboxLook.surface(goods)
	for side: float in [-0.7, 0.7]:
		_on(steel, Vector3(0.05, 2.2, 0.6), x + side, 0.0, d)
	for tier: int in 4:
		_on(steel, Vector3(1.45, 0.03, 0.6), x, 0.15 + tier * 0.55, d)
		for box: int in 3:
			if (box + tier) % 4 == 3:
				continue
			_on(load, Vector3(0.38, 0.3, 0.45), x - 0.45 + box * 0.45, 0.18 + tier * 0.55, d)


## A glowing point: candle, mirror ball, display. Off on a dark floor.
func _glow(colour: Color, size: float, at: Vector3) -> void:
	if not _lit:
		return
	_batch.sphere(GreyboxLook.light(colour), size, Vector3(at.x, _surface - at.y, _z(at.z)))


## A box on the floor: [param h] — height of the bottom, [param d] — depth of the middle.
func _on(material: Material, size: Vector3, x: float, h: float, d: float) -> void:
	_batch.box_on(material, size, _surface, Vector3(x, h, _z(d)))


## A pack item centred on (x, d), bottom at [param h] above the floor, rotated by
## [param turn] degrees around the vertical.
func _prop(prop_name: String, x: float, d: float, turn: float = 0.0, h: float = 0.0) -> void:
	var parts := HallLook.template(prop_name, _rules.kind)
	if parts.is_empty():
		return
	var place := Transform3D(
		Basis(Vector3.UP, deg_to_rad(turn)), MeshBatch.scene_of(Vector3(x, _surface - h, _z(d)))
	)
	for part: Array in parts:
		_batch.mesh(part[0] as Mesh, place * (part[1] as Transform3D))


## Whether the spot of an item with half-width [param half] at depth [param d] is free:
## in front of a door the leaf's strip is free — it opens into the hall.
func _free(x: float, half: float, d: float) -> bool:
	if d - 0.5 > LEAF_CLEAR:
		return true
	for door: float in _doors:
		if absf(x - door) < Door.LEAF_SIZE.x + half:
			return false
	return true


## Spots along the span with step [param step] from the edge, shifted by [param offset].
func _along(span: Vector2, step: float, offset: float) -> Array[float]:
	var places: Array[float] = []
	var length := span.y - span.x
	var count := int((length - offset) / step)
	if count <= 0:
		return places
	var start := span.x + offset + (length - offset - (count - 1) * step) * 0.5
	for place: int in count:
		places.append(start + place * step)
	return places


## Width of a pack item at its catalogue height plus gap [param gap]: the step of a row
## of machines, cabinets, bar counters.
func _width_of(prop_name: String, gap: float) -> float:
	return PropCatalog.footprint(prop_name).x + gap


func _mid(span: Vector2) -> float:
	return (span.x + span.y) * 0.5


## Scene Z by hall depth.
func _z(d: float) -> float:
	return WorldSpace.BACK_WALL_Z - d
