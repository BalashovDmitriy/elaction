class_name BuildingShell
extends Node3D

## Building shell: slabs, outer walls, inner walls and the room
## behind the corridor.
##
## As its own node, like [BuildingShafts] and [BuildingRibs]: the level assembles the building from
## several builders, and keeping them in one file means keeping the whole building in one
## file at once. There are no rules here, only geometry from a finished layout.
##
## What cuts what is decided by [BuildingPlan], and it has two counts: the slab — by openings
## ([method BuildingPlan.gaps_on]), walking — by openings and walls (ADR-0024,
## decision 5). The shell builds by the first: a wall stands on the slab, not instead of it.

## Thickness of the level's outer wall, m.
const WALL_WIDTH: float = 0.48

## Thickness of a wall that has no body: it is only seen.
const PANEL_THICKNESS: float = 0.1

## Width of the building exit, m. Before M24b the shell cut an opening this wide in the back wall;
## since M24b the exit is a car at the garage gate in the end wall ([Garage]), boarded at
## the driver door ([constant ExitBoarding.DOOR_REACH]), and there is no opening in the back
## wall. It remains the measure of the exit spot on the plan: other cars in the garage
## avoid it ([method Garage.keep_out] — via [constant Proportions.EXIT_WIDTH]).
##
## It did not grow with Otto in M18c, it narrowed: the slot pitch does not let it be wider. The cab
## of the neighbouring shaft starts 0.9 m from the middle of the exit, and the former 1.92 m
## went over it by 6 cm; the 2.56 m that growth by 4/3 would give would also cut out
## the wall above the neighbouring door (ADR-0026, decision 7). Otto, 0.72 wide, passes
## through 1.68 freely.
const EXIT_WIDTH: float = Proportions.EXIT_WIDTH

## How much of the round palette tone goes into materials: the back wall takes the
## floor tone, outer walls — the masonry (ADR-0029, decision 5). A little: the palette is
## a round's tint, not a fill, and readability holds everywhere.
const PALETTE_SHARE: float = 0.18

## Share of the palette floor tone in the back wall — more than in the masonry: at 18% rounds
## could not be told apart in the frame (user's question, ADR-0031, decision 5).
const STORY_SHARE: float = 0.45

## How many times darker the back wall of a dark floor is than a lit one (ADR-0029, decision 6).
## M18e frames: in the dusky tower a dark floor without lamps differed from a lit one
## weakly — the wall reflected the overall tone the same way as on a lit one.
const UNLIT_SHADE: float = 0.45

## Office glass wall (ADR-0056, decision 4): glass colour and transparency,
## mullion pitch and their tone.
const GLASS := Color(0.55, 0.7, 0.78, 0.07)
const GLASS_MULLION: float = 1.8
const GLASS_FRAME := Color(0.62, 0.65, 0.7)

## Roof parapet: visible height, the coping on top and its overhang, m (ADR-0031, decision 2).
const PARAPET_HEIGHT: float = 1.05
## The largest parapet cornice overhang, m: the margin of the boxes in which the roof catches
## precipitation ([RoofCatch]). Where a drop still lands on the cornice and where it drips from its
## edge — by the cornice overhang of its own building ([method coping_overhang]).
const COPING_OVERHANG: float = 0.22
## Parapet cornice by building kind (ADR-0058, decision 1): the hotel has a stone
## cornice with an overhang, the office — a thin aluminium coping, the residential building —
## a brick band with terracotta tile. Height and overhang, m, and colour by [enum
## BuildingIdentity.Kind].
const KIND_COPING: Array[Vector2] = [Vector2(0.22, 0.2), Vector2(0.08, 0.06), Vector2(0.14, 0.12)]
const KIND_COPING_COLOUR: Array[Color] = [
	Color(0.62, 0.56, 0.46), Color(0.7, 0.72, 0.75), Color(0.52, 0.27, 0.18)
]

## Halls of special floors (ADR-0057): the level turns their light off by frame.
var halls: FloorHall = null

var _rules: BuildingRules = null
var _plan: BuildingPlan = null
var _ribs: BuildingRibs = null
## Walls without bodies as a separate node: there are many, and in the tree they must not get mixed
## in among the bodies people walk on.
var _panels: Node3D = null


## Parapet cornice overhang of a building of kind [param kind], m ([constant KIND_COPING]):
## rain drips from its edge, drops and flakes fall up to it.
static func coping_overhang(kind: BuildingIdentity.Kind) -> float:
	return KIND_COPING[kind].x


## Pieces of the level's slab as rules rectangles.
##
## Static and public: it is used to check that an opening cuts the slab exactly where
## the layout promised — without a scene and without nodes.
static func slab_segments(
	surface: float, gaps: Array[Vector2], bounds: Vector2, thickness: float
) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for span in BuildingPlan.spans_between(gaps, bounds):
		rects.append(Rect2(span.x, surface, span.y - span.x, thickness))
	return rects


## Builds the whole shell. [param ribs] gets slab edges and piers —
## ribs are placed by the same geometry as the walls, and a second pass would make them diverge.
func build(rules: BuildingRules, plan: BuildingPlan, ribs: BuildingRibs) -> void:
	_rules = rules
	_plan = plan
	_ribs = ribs
	_panels = Node3D.new()
	_panels.name = "Panels"
	add_child(_panels)

	_build_floors()
	_build_room()


func _build_floors() -> void:
	# The slab is a floor: polished, reflections fall into it (ADR-0023, decision 5).
	var slab := GreyboxLook.polished(GreyboxLook.SLAB)
	var wall := GreyboxLook.surface(GreyboxLook.WALL.lerp(_rules.palette.masonry, PALETTE_SHARE))

	for index: int in _rules.levels():
		var surface := _rules.floor_surface(index)
		var bounds := _rules.floor_span(index)
		var gaps := _plan.gaps_on(_rules, index)
		# The slab is wider than its own walls where the silhouette makes a step: it is also
		# the ceiling of the floor below, and that one is wider than its upper neighbour.
		var holes := _plan.escalator_holes_on(_rules, index)
		for rect in slab_segments(
			surface, gaps + holes, _rules.slab_span(index), _rules.slab_height
		):
			_build_solid(rect, slab)
			_ribs.edge_of(rect)
		# Under an escalator the slab is cut only in the back strip of the corridor: in front of
		# it the floor is solid, behind the back wall — the room floor (ADR-0044, decision 10).
		for hole: Vector2 in holes:
			var rect := Rect2(hole.x, surface, hole.y - hole.x, _rules.slab_height)
			_build_solid_between(
				rect, slab, WorldSpace.CORRIDOR_DEPTH * 0.5, Escalator.HOLE_FRONT_Z
			)
			_ribs.edge_of(rect)
			_build_solid_between(
				rect, slab, WorldSpace.BACK_WALL_Z, WorldSpace.BACK_WALL_Z - WorldSpace.ROOM_DEPTH
			)
		_build_side_walls(index, surface, bounds, wall)
		_build_inner_walls(index, surface, wall)


## Inner walls of a floor: solid, from floor to ceiling (ADR-0024, decision 5).
##
## Neither people nor bullets pass through them, and an agent behind a wall cannot reach Otto.
## Where they stand is decided by the layout: it also removed those that locked a document or
## the exit, and the reachability graph counts the floor pieces with them already.
func _build_inner_walls(index: int, surface: float, material: StandardMaterial3D) -> void:
# From the underside of the slab above to the floor: a wall stands on the slab, not instead of it.
	var top := _rules.story_top(index)
	var height := surface - top
	if height <= 0.0:
		return
	for inner_wall in _plan.walls:
		if inner_wall.floor_index != index:
			continue
		var band := inner_wall.band(_rules)
		_build_solid(Rect2(band.x, top, band.y - band.x, height), material)


## Side walls of the level. They go in steps following the silhouette, not as solid
## full-height columns: the building widens toward the bottom (ADR-0014, point 3).
##
## At the roof the wall goes up to the top of the world: it is the parapet, and it also keeps one
## from stepping off the roof past the building. A jump takes 2.4 m: Otto would clear a low rail.
func _build_side_walls(
	index: int, surface: float, bounds: Vector2, material: StandardMaterial3D
) -> void:
	var top := _rules.story_top(index)
	var height := surface + _rules.slab_height - top
	if height <= 0.0:
		return

	if index == BuildingRules.ROOF:
		_build_parapets(surface, bounds, top, material)
		return
	# The garage's left wall is a body without looks: it has the gate, and the visible pieces
	# around the opening are placed by [Garage] (ADR-0038, decision 3). Otto does not go out
	# through the gate — the body is whole.
	var garage := index == _rules.floors - 1
	_build_solid(Rect2(bounds.x, top, WALL_WIDTH, height), material, not garage)
	_build_solid(Rect2(bounds.y - WALL_WIDTH, top, WALL_WIDTH, height), material)


## Roof walls: a body the full height of the sky — a jump takes almost two metres, and Otto
## would clear a low rail — while only a waist-high parapet with coping on top is visible
## (ADR-0031, decision 2). Before M20 the whole wall was visible, and dark columns up to the top
## of the frame stood at the roof edges.
func _build_parapets(
	surface: float, bounds: Vector2, top: float, material: StandardMaterial3D
) -> void:
	var kind := _rules.kind
	var coping := (
		GreyboxLook.metal(KIND_COPING_COLOUR[kind])
		if kind == BuildingIdentity.Kind.OFFICE
		else GreyboxLook.surface(KIND_COPING_COLOUR[kind])
	)
	var size := KIND_COPING[kind]
	for left: float in [bounds.x, bounds.y - WALL_WIDTH]:
		_build_solid(Rect2(left, top, WALL_WIDTH, surface - top), material, false)
		var wall := Rect2(left, surface - PARAPET_HEIGHT, WALL_WIDTH, PARAPET_HEIGHT)
		_build_block(wall, material, WorldSpace.CORRIDOR_DEPTH + WorldSpace.ROOM_DEPTH)
		var cap := Rect2(
			left - size.x, surface - PARAPET_HEIGHT - size.y, WALL_WIDTH + size.x * 2.0, size.y
		)
		_build_block(cap, coping, WorldSpace.CORRIDOR_DEPTH + WorldSpace.ROOM_DEPTH + 0.1)


## The room behind the corridor: the back wall with door openings and the far wall.
##
## This is the frame depth per ADR-0021, decision 1: play happens in a plane, and
## volume is behind the back wall, seen through the openings. Openings are cut by the same
## [method BuildingPlan.spans_between] as the slabs: a door takes exactly its width
## in the wall, above it — a lintel up to the ceiling.
##
## The roof gets no wall: above it is sky, and behind it — the city ([CityBackdrop]).
## The bottom floor — neither: it is the garage, the hall behind the driveway is built by [Garage]
## (ADR-0038, decision 3).
func _build_room() -> void:
	# The wall is the building kind's texture in the floor tone (ADR-0033, decision 5): the pattern
	# comes from the texture, the colour — from the round.
	var tone := GreyboxLook.BACK_WALL.lerp(_rules.palette.story, STORY_SHARE)
	var paper := tone.lightened(0.55)
	var lit_back := BuildingFinish.wall(_ribs.identity(), paper)
	var unlit_back := BuildingFinish.wall(
		_ribs.identity(), Color(paper.r * UNLIT_SHADE, paper.g * UNLIT_SHADE, paper.b * UNLIT_SHADE)
	)
	var far := GreyboxLook.surface(GreyboxLook.SKY_WALL)
	var back_z := WorldSpace.BACK_WALL_Z - PANEL_THICKNESS * 0.5
	var far_z := WorldSpace.BACK_WALL_Z - WorldSpace.ROOM_DEPTH
	var glazed := BuildingStyle.of(_ribs.identity()).glass_wall
	if glazed:
		var hall := OpenSpace.new()
		add_child(hall)
		hall.build(_rules, _plan)
	# Halls of special floors (ADR-0057, decision 3): behind the corridor instead of a wall.
	halls = FloorHall.new()
	add_child(halls)
	halls.build(_rules, _plan)

	for index: int in _rules.levels():
		if index == BuildingRules.ROOF or index == _rules.floors - 1:
			continue
		var surface := _rules.floor_surface(index)
		var top := _rules.story_top(index)
		var bounds := _rules.floor_span(index)
		var inner := Vector2(bounds.x + WALL_WIDTH, bounds.y - WALL_WIDTH)
		var back := unlit_back if _rules.is_unlit(index) else lit_back

		var openings := _openings_on(index)
		var lintel_top := surface - Door.LEAF_SIZE.y
		var role := FloorRole.at(_rules, index)
		for span in BuildingPlan.spans_between(openings, inner):
			if FloorRole.is_hall(role):
				_build_screen(
					FloorRole.screen_of(role, _rules.kind), span, top, lintel_top, surface, back
				)
				continue
			if glazed:
				# Office (ADR-0056, decision 4): glass at door height, above it —
				# a solid strip up to the ceiling, behind the glass — an [OpenSpace] hall.
				_build_panel(Rect2(span.x, top, span.y - span.x, lintel_top - top), back, back_z)
				_build_glass(Rect2(span.x, lintel_top, span.y - span.x, surface - lintel_top))
				continue
			_build_panel(Rect2(span.x, top, span.y - span.x, surface - top), back, back_z)
		for opening in openings:
			_build_panel(
				Rect2(opening.x, top, opening.y - opening.x, lintel_top - top), back, back_z
			)
		_ribs.line_the_wall(index, inner, openings)

		_build_panel(Rect2(inner.x, top, inner.y - inner.x, surface - top), far, far_z)


## Door openings in a floor's back wall. Since M24b the exit is the garage gate in
## the end wall ([Garage]), not an opening in the back wall.
func _openings_on(index: int) -> Array[Vector2]:
	var openings: Array[Vector2] = []
	var half := Door.LEAF_SIZE.x * 0.5
	for spot in _plan.doors:
		if spot.floor_index == index:
			openings.append(Vector2(spot.x - half, spot.x + half))
	return openings


## A box with a body in place of a rules rectangle: people walk on it and bullets
## stop against it.
##
## Deep enough for the corridor and the room together: the slab is the floor not only of the
## corridor but also of the room behind the wall, otherwise the door opening would show emptiness
## underfoot. The front face falls on the corridor's front face, not on the play plane.
##
## [param shown] — whether the box is visible: the roof wall above the parapet is a bare body.
## Not `visible`: that is the name of a [Node3D] property, and the parameter would shadow it.
func _build_solid(rect: Rect2, material: StandardMaterial3D, shown: bool = true) -> void:
	var depth := WorldSpace.CORRIDOR_DEPTH + WorldSpace.ROOM_DEPTH
	var size := Vector3(rect.size.x, rect.size.y, depth)
	var centre := WorldSpace.to_scene(rect.get_center())
	centre.z = WorldSpace.CORRIDOR_DEPTH * 0.5 - depth * 0.5

	var body := StaticBody3D.new()
	body.position = centre

	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	if shown:
		body.add_child(GreyboxLook.box(size, material))

	add_child(body)


## A body with looks in place of a rectangle, but not the full depth, from [param front]
## to [param back] along scene Z: a piece of slab around an escalator opening.
func _build_solid_between(
	rect: Rect2, material: StandardMaterial3D, front: float, back: float
) -> void:
	var size := Vector3(rect.size.x, rect.size.y, front - back)
	var body := StaticBody3D.new()
	body.position = WorldSpace.to_scene(rect.get_center())
	body.position.z = (front + back) * 0.5
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	body.add_child(GreyboxLook.box(size, material))
	add_child(body)


## A box without a body in place of a rectangle, [param depth] deep from the corridor's front
## face — as with shell bodies.
func _build_block(rect: Rect2, material: StandardMaterial3D, depth: float) -> void:
	var block := GreyboxLook.box(Vector3(rect.size.x, rect.size.y, depth), material)
	block.position = WorldSpace.to_scene(rect.get_center())
	block.position.z = WorldSpace.CORRIDOR_DEPTH * 0.5 - depth * 0.5
	_panels.add_child(block)


## What separates a special floor hall from the corridor on pier [param span]
## (ADR-0057, decision 3): above the door-height opening — a wall strip up to the ceiling, in
## the opening — glass, chain-link mesh on posts or nothing: the columns are placed by the ribs
## ([method BuildingRibs.line_the_wall]).
func _build_screen(
	screen: FloorRole.Screen,
	span: Vector2,
	top: float,
	lintel_top: float,
	surface: float,
	wall: StandardMaterial3D
) -> void:
	var back_z := WorldSpace.BACK_WALL_Z - PANEL_THICKNESS * 0.5
	_build_panel(Rect2(span.x, top, span.y - span.x, lintel_top - top), wall, back_z)
	var opening := Rect2(span.x, lintel_top, span.y - span.x, surface - lintel_top)
	match screen:
		FloorRole.Screen.GLASS:
			_build_glass(opening)
		FloorRole.Screen.MESH:
			_build_mesh(opening)


## Chain-link mesh of the technical floor on steel posts, without bodies — like a wall;
## a crossbar — on top.
func _build_mesh(rect: Rect2) -> void:
	_build_infill(
		rect,
		HallLook.chain_link(),
		GreyboxLook.metal(FloorHall.MESH_POST),
		FloorHall.MESH_POST_STEP,
		Rect2(rect.position.x, rect.position.y, rect.size.x, 0.05)
	)


## Office glass partition in the back wall: glass and aluminium mullions
## with pitch [constant GLASS_MULLION], without bodies — like the wall itself; a crossbar —
## at the bottom. One glass per building and for the special floor halls ([method HallLook.glass]).
func _build_glass(rect: Rect2) -> void:
	_build_infill(
		rect,
		HallLook.glass(),
		GreyboxLook.metal(GLASS_FRAME),
		GLASS_MULLION,
		Rect2(rect.position.x, rect.end.y - 0.08, rect.size.x, 0.08)
	)


## A partition in opening [param rect] of the back wall: pane [param sheet] without
## shadows, posts [param post] with pitch [param step] and crossbar [param rail].
func _build_infill(
	rect: Rect2, sheet: StandardMaterial3D, post: StandardMaterial3D, step: float, rail: Rect2
) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var z := WorldSpace.BACK_WALL_Z - PANEL_THICKNESS * 0.5
	var pane := GreyboxLook.box(Vector3(rect.size.x, rect.size.y, 0.02), sheet)
	pane.position = WorldSpace.to_scene(rect.get_center())
	pane.position.z = z
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_panels.add_child(pane)
	var count := maxi(1, roundi(rect.size.x / step))
	for stand: int in count + 1:
		var x := rect.position.x + rect.size.x * stand / count
		_build_panel(Rect2(x - 0.03, rect.position.y, 0.06, rect.size.y), post, z + 0.03)
	_build_panel(rail, post, z + 0.03)


## A wall that is only seen: without a body, [constant PANEL_THICKNESS] thick,
## centred at [param z].
func _build_panel(rect: Rect2, material: StandardMaterial3D, z: float) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var panel := GreyboxLook.box(Vector3(rect.size.x, rect.size.y, PANEL_THICKNESS), material)
	panel.position = WorldSpace.to_scene(rect.get_center())
	panel.position.z = z
	_panels.add_child(panel)
