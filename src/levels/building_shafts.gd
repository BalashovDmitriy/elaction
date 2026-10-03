class_name BuildingShafts
extends Node3D

## Dressing of the building's shafts: steel sheet, guide rails, braces, floor portals with
## the cab indicator board and call buttons, buffers and the machine room.
##
## As its own node, not as direct children of the level. There are over fifty parts per
## building, and agents, cabs and half the tests all walk the level's children: every
## such walk would also go through posts and door panels. For exactly this reason the
## background was moved out of the level at the time.
##
## Nothing here has a body: nobody walks on the rails, they are only seen. The cab
## moves, and the opening in the slab is cut by the slab itself.
##
## Since M21b the shaft is steel (ADR-0033, decision 6): at the back wall, full height,
## a metal sheet with bolts, braces along the slabs, at the portal a
## chrome casing and a checker-plate steel threshold. Above the portal is a board with
## the floor where the cab is now and a travel arrow; at the side are call buttons, the
## lit one is the direction in which the cab travels to this floor (decision 7, look only).

## Width of a shaft guide rail, m. The post runs along the edge of the opening at its
## full height.
const RAIL_WIDTH: float = 0.18

## Share of the round palette's shaft tone in the rails (ADR-0031, decision 5).
const SHAFT_TONE: float = 0.25

## The shaft portal on a floor (ADR-0031, decision 1): share of width for each
## open door panel, the casing, lintel and threshold, m; metal colors.
const PORTAL_LEAF_SHARE: float = 0.22
const PORTAL_JAMB: float = 0.07
const PORTAL_HEAD: float = 0.1
const PORTAL_SILL: float = 0.03
const PORTAL_RECESS := Color(0.07, 0.08, 0.1)
## Portal and board by building kind (ADR-0057, decision 6): brass at the hotel, chrome
## at the office, the painted steel of a freight elevator at the residential building;
## digits are cream at the hotel, cold at the office, white at the residential building.
## Not amber and not red: these are the colors of the game's indicator lights, the door
## board and the document door (ADR-0023, decision 6). By [enum BuildingIdentity.Kind].
const KIND_TRIM: Array[Color] = [
	Color(0.8, 0.62, 0.32), Color(0.78, 0.8, 0.83), Color(0.3, 0.35, 0.31)
]
const KIND_LEAF: Array[Color] = [
	Color(0.52, 0.4, 0.22), Color(0.5, 0.5, 0.48), Color(0.36, 0.41, 0.36)
]
const KIND_DIGITS: Array[Color] = [
	Color(0.98, 0.92, 0.78), Color(0.55, 0.82, 1.0), Color(0.85, 0.88, 0.9)
]
## The hotel dial above the board: radius, hand and its sweep, rad, from the shaft's
## bottom floor on the left to the top one on the right, as in thirties elevators.
const DIAL_RADIUS: float = 0.15
const DIAL_FACE := Color(0.92, 0.86, 0.7)
const NEEDLE := Vector3(0.014, 0.12, 0.01)
const NEEDLE_SWING: float = deg_to_rad(75.0)

## How far the opening and the portal panels stop short of the floor and the lintel, m:
## a fraction of a pixel, but faces of different materials are no longer in one plane.
const PORTAL_EPSILON: float = 0.004

## The full-height shaft sheet: how much wider than the opening, and thickness, m.
const PLATE_MARGIN: float = 0.05
const PLATE_THICKNESS: float = 0.02

## A brace between the rails at slab level: height, m.
const BRACE_HEIGHT: float = 0.12

## The cab board above the portal: size, gap above the lintel, m; digit color is
## a cold LED, as on the M19 board (not red: a red light at the height of the
## door sign is the mark of a document door, M19 code review).
const BOARD := Vector3(0.7, 0.26, 0.05)
const BOARD_GAP: float = 0.06
## The travel arrow on the board is a geometric triangle, not a font glyph: ▲ and ▼ are
## in neither Exo 2 nor the former Pixellari, and they were drawn by the system fallback
## font, which another machine may not have. The arrow size, how far it is
## left of the board's middle and how far the digits next to it are to the right, m.
const ARROW := Vector3(0.09, 0.08, 0.008)
const ARROW_SHIFT: float = 0.2
const DIGITS_SHIFT: float = 0.06

## The button panel at the side of the portal: size, middle height, offset from the
## casing, button; colors of a lit and a dark button.
const CALL_PANEL := Vector3(0.12, 0.26, 0.02)
const CALL_RISE: float = 1.15
const CALL_GAP: float = 0.14
const CALL_BUTTON := Vector3(0.055, 0.055, 0.02)
const CALL_LIT := Color(0.92, 0.96, 1.0)
const CALL_DARK := Color(0.2, 0.21, 0.23)

## The board and panel hang in front of the pilasters, like the floor sign
## ([constant FloorSigns.STANDOFF]): at the pier edge the pilaster stands close
## to the portal, sticks out of the wall by [constant BuildingRibs.PILASTER_DEPTH], and
## a panel on the wall itself sank into it entirely (M21b code review).
const MOUNT_Z: float = WorldSpace.BACK_WALL_Z + BuildingRibs.PILASTER_DEPTH + 0.01

## What the board shows while the cab is on the roof: there is no floor with that number.
const ROOF_LABEL := "R"

## Height of the buffer at the end of the shaft band, m.
const BUFFER_HEIGHT: float = 0.24

## How much narrower and shallower the buffer is than the rails, m (ADR-0037, decision
## 2). The buffer stands between the posts and does not reach their faces: faces of
## different materials in one plane flickered as the camera moved: they have the same
## depth, and which of the two is closer was decided by chance.
const BUFFER_INSET: float = 0.01

## The machine room structure on the roof, m.
const MACHINE_ROOM_SIZE := Vector2(2.16, 1.32)

## Depth of the posts and buffers and how far they are recessed: behind the cab, but in
## front of the wall. The cab moves in the play plane and covers them as it passes.
const RAIL_DEPTH: float = 0.3
const RAIL_Z: float = -0.45

## Thickness of the shaft panels and the machine room. The panels hang on the back wall,
## like the floor doors; the hut stands on the roof by the same wall.
##
## The hut does not reach the play plane: its front face ends behind Otto's back (a body
## [constant WorldSpace.BODY_DEPTH] thick around zero), otherwise he would pass through
## the hut's wall rather than in front of it (M15 code review).
##
## And 4 cm deeper than the rails: at 0.7 m its facade fell into one plane
## with the front face of the posts, and the top of the shaft on the roof flickered
## (ADR-0037, decision 2).
const PANEL_THICKNESS: float = 0.08
const MACHINE_ROOM_DEPTH: float = 0.74

## The light column in the shaft: radius, brightness, color and offset in front of the
## rails, m.
##
## A debt since M12 ([ADR-0017](../../../docs/adr/0017-spectrum-palette-and-shafts.md),
## decision 3), closed in M18b
## ([ADR-0025](../../../docs/adr/0025-shafts-escalators-and-riders.md), decision 3).
## The source is real, not material glow: the light must fall on the rails, the panels
## and the floor in front of the opening, otherwise on an unlit floor the shaft hangs as
## a glowing strip in the blackness and "the way down is here" reads worse than with a
## knocked-down lamp.
##
## Cold against the warm lamps (ADR-0023, decision 3): the shaft is metal, and the light
## in it is not homely. It casts no shadows: there is nowhere to drop them in the shaft,
## and they cost more than everything else.
## The radius is slightly wider than the shaft itself (1.2 m), and this is not stinginess.
## At 4.2 m the columns of the five podium shafts flooded the whole floor, and an unlit
## floor stopped being unlit: the M17 darkness was canceled by light that has nothing
## to do with it. The column must light the shaft, not replace the lamps.
const GLOW_RANGE: float = 1.8
const GLOW_ENERGY: float = 1.1
const GLOW_COLOR := Color(0.74, 0.84, 1.0)
const GLOW_Z: float = -0.35

var _rules: BuildingRules
var _plan: BuildingPlan
## Column light sources: floor → those standing on it. They go out off-frame, like lamps.
var _glow: Dictionary = {}
## Portal boards and buttons: shaft x → floor → [ShaftBoard]. One column can hold
## several shafts; their floors do not intersect, so the "x and floor" key is
## unambiguous, but boards must be updated by the floors of their own shaft, not by
## column.
var _boards: Dictionary = {}
## Cabs the boards watch: cab → its shaft.
var _watched: Dictionary = {}
## What the boards already show: cab → [floor, direction]. The labels change
## only on a change, not every frame.
var _shown: Dictionary = {}
## Floors in frame: boards are redrawn only on them (M24h, ADR-0044,
## decision 11). The building's cabs move in step, and on every floor passed all
## boards of all shafts rebuilt their labels at once: a hundred and fifty in one frame,
## up to 10 ms of a physics step. Invisible boards are updated when the floor enters the
## frame ([method light_span]) or when they are asked ([method board_text]).
## Until the first [method light_span] everything is visible.
var _span := Vector2i(-1_000_000, 1_000_000)
## Boards and buttons as their own node: tests look for shaft parts among the shafts'
## direct children (rails, buffers, the descent rope), and a 12 cm wide button panel
## would pass for a rope.
var _board_host: Node3D = null
## The arrow triangle, one for all boards.
var _arrow_mesh: PrismMesh = null
## The rim and face of the hotel dial: one for all boards of the building.
var _dial_discs: Array[CylinderMesh] = []


## The board and buttons of one portal.
class ShaftBoard:
	extends RefCounted
	var floor_index: int = 0
	var digits: Label3D = null
	var arrow: MeshInstance3D = null
	## The board's middle: digits shift from it when the arrow is lit.
	var center: Vector3 = Vector3.ZERO
	var up_button: MeshInstance3D = null
	var down_button: MeshInstance3D = null
	## The hand of the hotel dial; null for other kinds.
	var needle: Node3D = null
	## Which button is lit: [constant Intent.UP], [constant Intent.DOWN] or 0.
	var lit: float = 0.0


## Dresses all shafts of the building at once.
func dress(rules: BuildingRules, plan: BuildingPlan) -> void:
	_rules = rules
	_plan = plan
	set_physics_process(false)
	_board_host = Node3D.new()
	_board_host.name = "Boards"
	add_child(_board_host)
	for shaft in plan.shafts:
		_dress_shaft(shaft)
	_spawn_machine_room()
	add_to_group(Graphics.GROUP)
	apply_graphics()


## Shaft light columns in volumetric fog, by quality level (ADR-0034,
## decision 1): on "Ultra" a beam is visible in the shaft.
func apply_graphics() -> void:
	for index: int in _glow:
		for light: OmniLight3D in _glow[index]:
			light.light_volumetric_fog_energy = Graphics.light_in_fog()


## Lights the light columns on visible floors and turns off the rest.
##
## By the same rule as the lamps (ADR-0010, item 8): a building has up to a dozen shafts
## with a source for each of their floors, and two and a half floors fit into the frame.
## The source goes out, but not the column itself: an unlit floor differs from an
## invisible one in that it can be seen.
func light_span(span: Vector2i, strip: Vector2 = Vector2(-INF, INF)) -> void:
	if span != _span:
		_span = span
		for car: ElevatorCar in _watched:
			if is_instance_valid(car) and _shown.has(car):
				_paint(car, _span)
	for index: int in _glow:
		var lit := VisibleFloors.covers(span, index)
		for light: OmniLight3D in _glow[index]:
			light.visible = lit and VisibleFloors.in_band(strip, light.global_position.x)


## Top of the shaft: how far its posts and buffer go.
##
## A shaft reaching the roof has no ceiling: the sky is above it, and [method
## BuildingRules.story_top] returns the top of the world. The post and buffer would go
## into the open sky above the roof; such a shaft ends inside the machine room, which is
## its top.
func top_of(shaft: BuildingPlan.ShaftSpot) -> float:
	if shaft.top > BuildingRules.ROOF:
		return _rules.story_top(shaft.top)
	return _rules.floor_surface(BuildingRules.ROOF) - MACHINE_ROOM_SIZE.y * 0.5


## Dresses a shaft: rails over its full height and panels on each of its floors.
##
## Before M12 the shaft was a hole in the slab: it was almost absent from the frame,
## although descending through the building is the game (ADR-0017, decision 3). Rails
## give it edges, panels a floor mark: they show where the cab stops.
func _dress_shaft(shaft: BuildingPlan.ShaftSpot) -> void:
	_mark_shaft_ends(shaft)
	var top := top_of(shaft)
	var bottom := _rules.floor_surface(shaft.bottom)
	var half := _rules.shaft_width * 0.5
	# The shaft is metal (ADR-0023, decision 5): the rails catch the lamp glint.
	var rail := GreyboxLook.metal(GreyboxLook.SHAFT.lerp(_rules.palette.shaft, SHAFT_TONE))

	for side: float in [-1.0, 1.0]:
		var x := shaft.x + half * side
		var left := x if side < 0.0 else x - RAIL_WIDTH
		_add_part(Rect2(left, top, RAIL_WIDTH, bottom - top), rail, RAIL_Z, RAIL_DEPTH)

	# A bolted sheet over the full shaft height, at the back wall: the shaft is a steel
	# column through the building, not a continuation of the corridor wallpaper.
	var plate_half := half + PORTAL_JAMB + PLATE_MARGIN
	_add_part(
		# Millimeters below the bottom: the bottom of the sheet is not in the plane of the
		# bottom of the opening.
		Rect2(shaft.x - plate_half, top, plate_half * 2.0, bottom - top + PORTAL_EPSILON),
		BuildingFinish.shaft_plates(),
		WorldSpace.BACK_WALL_Z + PLATE_THICKNESS * 0.5 + 0.002,
		PLATE_THICKNESS
	)

	for index: int in range(shaft.top, shaft.bottom + 1):
		var surface := _rules.floor_surface(index)
		if index > BuildingRules.ROOF:
			_build_portal(shaft.x, surface)
			_build_board(shaft.x, index, surface)
		if index > shaft.top:
			# A brace at slab level above the floor: the cab does not stop there.
			var slab := _rules.story_top(index)
			_add_part(
				Rect2(shaft.x - half, slab, half * 2.0, BRACE_HEIGHT), rail, RAIL_Z, RAIL_DEPTH
			)
		_light_the_shaft(shaft.x, index, surface)


## The shaft portal on a floor, as in the reference: a dark opening, open panels on the
## sides, a casing, lintel and threshold (ADR-0031, decision 1). All at the back wall
## and without bodies: the cab moves in front of it and is visible in full.
func _build_portal(x: float, surface: float) -> void:
	var half := _rules.shaft_width * 0.5
	var height := Proportions.DOOR.y
	var back_z := WorldSpace.BACK_WALL_Z + PANEL_THICKNESS * 0.5 + 0.01
	var recess := GreyboxLook.metal(PORTAL_RECESS)
	var leaf := GreyboxLook.metal(KIND_LEAF[_rules.kind])
	var trim := GreyboxLook.metal(KIND_TRIM[_rules.kind])

	# The panels and threshold stop just short of the floor and lintel: the bottom of the
	# opening, panels and threshold fell into one plane (ADR-0037, decision 2). The opening
	# is the full door height: the dressing tests recognize it by that.
	_add_part(
		Rect2(x - half, surface - height, half * 2.0, height), recess, back_z, PANEL_THICKNESS
	)
	var leaf_width := half * 2.0 * PORTAL_LEAF_SHARE
	for side: float in [-1.0, 1.0]:
		var from := x - half if side < 0.0 else x + half - leaf_width
		_add_part(
			Rect2(
				from, surface - height + PORTAL_EPSILON, leaf_width, height - PORTAL_EPSILON * 3.0
			),
			leaf,
			back_z + 0.03,
			PANEL_THICKNESS
		)
		var jamb_from := x - half - PORTAL_JAMB if side < 0.0 else x + half
		_add_part(
			Rect2(jamb_from, surface - height, PORTAL_JAMB, height),
			trim,
			back_z + 0.05,
			PANEL_THICKNESS
		)
	var head := Rect2(
		x - half - PORTAL_JAMB,
		surface - height - PORTAL_HEAD,
		(half + PORTAL_JAMB) * 2.0,
		PORTAL_HEAD
	)
	_add_part(head, trim, back_z + 0.05, PANEL_THICKNESS)
	_add_part(
		Rect2(x - half, surface - PORTAL_SILL, half * 2.0, PORTAL_SILL - PORTAL_EPSILON),
		BuildingFinish.tread_plate(),
		back_z + 0.12,
		0.2
	)


## The board above the portal and buttons at the side. The digits are the floor where the
## cab is now; until the board has seen the cab, its own floor is lit.
func _build_board(x: float, index: int, surface: float) -> void:
	var board := ShaftBoard.new()
	board.floor_index = index
	var head_top := surface - Proportions.DOOR.y - PORTAL_HEAD
	var frame := GreyboxLook.box(BOARD, GreyboxLook.metal(PORTAL_RECESS))
	frame.position = WorldSpace.to_scene(Vector2(x, head_top - BOARD_GAP - BOARD.y * 0.5))
	frame.position.z = WorldSpace.BACK_WALL_Z + PANEL_THICKNESS + 0.06
	_board_host.add_child(frame)
	board.digits = Label3D.new()
	board.digits.font = NeonStyle.scene_font(700)
	board.digits.font_size = 64
	board.digits.pixel_size = 0.0034
	board.digits.modulate = KIND_DIGITS[_rules.kind]
	board.digits.outline_size = 0
	board.center = frame.position + Vector3(0.0, 0.0, BOARD.z * 0.5 + 0.003)
	board.digits.position = board.center
	_board_host.add_child(board.digits)
	if _arrow_mesh == null:
		_arrow_mesh = PrismMesh.new()
		_arrow_mesh.size = ARROW
		# The arrow glows the same as the digits next to it: [Label3D] is not shaded, and
		# a shaded arrow would go out on a dark floor and be overexposed under a lamp.
		var ink := StandardMaterial3D.new()
		ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ink.albedo_color = KIND_DIGITS[_rules.kind]
		_arrow_mesh.material = ink
	board.arrow = MeshInstance3D.new()
	board.arrow.mesh = _arrow_mesh
	board.arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	board.arrow.position = board.center + Vector3(-ARROW_SHIFT, 0.0, ARROW.z * 0.5)
	board.arrow.visible = false
	_board_host.add_child(board.arrow)
	if _rules.kind == BuildingIdentity.Kind.HOTEL:
		board.needle = _dial(frame.position + Vector3(0.0, BOARD.y * 0.5 + DIAL_RADIUS + 0.03, 0.0))

	var side := call_side(_rules, _plan, x, index)
	if side != 0.0:
		var panel_x := x + side * (_rules.shaft_width * 0.5 + PORTAL_JAMB + CALL_GAP)
		var panel := GreyboxLook.box(CALL_PANEL, GreyboxLook.metal(KIND_TRIM[_rules.kind]))
		panel.position = WorldSpace.to_scene(Vector2(panel_x, surface - CALL_RISE))
		panel.position.z = MOUNT_Z + CALL_PANEL.z * 0.5
		_board_host.add_child(panel)
		for up: bool in [true, false]:
			var button := GreyboxLook.box(CALL_BUTTON, GreyboxLook.metal(CALL_DARK))
			var lift := CALL_PANEL.y * 0.22 * (1.0 if up else -1.0)
			button.position = panel.position + Vector3(0.0, lift, CALL_PANEL.z * 0.5 + 0.005)
			_board_host.add_child(button)
			if up:
				board.up_button = button
			else:
				board.down_button = button

	if not _boards.has(x):
		_boards[x] = {}
	(_boards[x] as Dictionary)[index] = board
	_show(board, floor_label(_rules, index), 0.0, 0.0)


## The hotel dial centered at [param centre]: a brass rim, a light face, a
## hand. Returns the hand node: [method _paint] rotates it.
func _dial(centre: Vector3) -> Node3D:
	var brass := GreyboxLook.metal(KIND_TRIM[BuildingIdentity.Kind.HOTEL])
	if _dial_discs.is_empty():
		for radius: float in [DIAL_RADIUS, DIAL_RADIUS - 0.02]:
			var made := CylinderMesh.new()
			made.top_radius = radius
			made.bottom_radius = radius
			made.height = 0.02
			made.radial_segments = 24
			_dial_discs.append(made)
	for ring: Array in [[_dial_discs[0], brass, 0.0], [_dial_discs[1], null, 0.012]]:
		var face := MeshInstance3D.new()
		face.mesh = ring[0] as CylinderMesh
		face.material_override = (
			ring[1] as StandardMaterial3D
			if ring[1] != null
			else GreyboxLook.light(DIAL_FACE.darkened(0.35))
		)
		face.rotation.x = PI * 0.5
		face.position = centre + Vector3(0.0, 0.0, float(ring[2]))
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_board_host.add_child(face)
	var pivot := Node3D.new()
	pivot.position = centre + Vector3(0.0, 0.0, 0.03)
	var hand := GreyboxLook.box(NEEDLE, GreyboxLook.metal(Color(0.08, 0.06, 0.05)))
	hand.position.y = NEEDLE.y * 0.4
	hand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(hand)
	_board_host.add_child(pivot)
	return pivot


## Rotation of the dial hand for floor [param index] of shaft [param shaft]:
## the bottom one fully left, the top one to the right.
static func needle_angle(shaft: BuildingPlan.ShaftSpot, index: int) -> float:
	var reach := maxi(shaft.bottom - shaft.top, 1)
	var up := float(shaft.bottom - clampi(index, shaft.top, shaft.bottom)) / float(reach)
	return lerpf(NEEDLE_SWING, -NEEDLE_SWING, up)


## What the board writes about floor [param index]: the floor sign label, a number, "P"
## for the garage ([method FloorSigns.label_of]), and on the roof
## [constant ROOF_LABEL]. The roof number by formula would come out one more than the
## top floor: a floor the building does not have.
static func floor_label(rules: BuildingRules, index: int) -> String:
	if index <= BuildingRules.ROOF:
		return ROOF_LABEL
	return FloorSigns.label_of(rules, index)


## How much the button panel takes at shaft [param x] on floor [param index]:
## a "left edge, right edge" pair, or a zero pair if there is no panel. Furniture
## does not stand in front of it ([method BuildingDressing.blocked_zones]).
static func call_panel_span(
	rules: BuildingRules, plan: BuildingPlan, x: float, index: int
) -> Vector2:
	var side := call_side(rules, plan, x, index)
	if side == 0.0:
		return Vector2.ZERO
	var near := x + side * (rules.shaft_width * 0.5 + PORTAL_JAMB + CALL_GAP - CALL_PANEL.x * 0.5)
	var far := near + side * CALL_PANEL.x
	return Vector2(minf(near, far), maxf(near, far))


## On which side of the portal the button panel has room: where there is enough wall
## before the door and the panel does not go into the building's side wall. Right if
## both are free; 0 if both are taken.
##
## The door counts with its casing, and left of the shaft also with the number sign,
## which hangs to the right of the door ([BuildingProps]): by the middle of the door the
## panel landed on the casing of the neighboring spot's door and on its sign.
static func call_side(rules: BuildingRules, plan: BuildingPlan, x: float, index: int) -> float:
	var reach := rules.shaft_width * 0.5 + PORTAL_JAMB + CALL_GAP + CALL_PANEL.x
	var bounds := rules.floor_span(index)
	var right := x + reach < bounds.y - BuildingShell.WALL_WIDTH
	var left := x - reach > bounds.x + BuildingShell.WALL_WIDTH
	var door_half := Door.LEAF_SIZE.x * 0.5 + Door.FRAME_WIDTH
	var plate_reach := Door.LEAF_SIZE.x * 0.5 + BuildingProps.PLATE_GAP + BuildingProps.PLATE.x
	var openings: Array[Vector2] = []
	for door in plan.doors:
		if door.floor_index == index:
			openings.append(Vector2(door.x - door_half, door.x + maxf(door_half, plate_reach)))
	for opening in openings:
		if opening.x > x and opening.x < x + reach:
			right = false
		if opening.y < x and opening.y > x - reach:
			left = false
	if right:
		return 1.0
	return -1.0 if left else 0.0


## Boards of shaft [param shaft] watch cab [param car]: floor and direction of
## travel. For a two-deck one, the leading deck.
func watch(car: ElevatorCar, shaft: BuildingPlan.ShaftSpot) -> void:
	_watched[car] = shaft
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	for car: ElevatorCar in _watched:
		if not is_instance_valid(car):
			continue
		refresh(car)


## Shows cab [param car]'s floor and travel on its shaft's boards, if something
## has changed since last time.
func refresh(car: ElevatorCar) -> void:
	# The lower deck of a two-deck cab does not drive the boards: the leading one shows the
	# floor.
	if not _watched.has(car):
		return
	var shaft := _watched[car] as BuildingPlan.ShaftSpot
	var index := _nearest_floor(car)
	var heading := heading_of(car.speed_now())
	var last: Array = _shown.get(car, [])
	if not last.is_empty() and last[0] == index and last[1] == heading:
		return
	_shown[car] = [index, heading]
	_paint(car, _span)


## Writes on the boards of cab [param car]'s shaft what it shows now,
## on the floors of band [param span].
func _paint(car: ElevatorCar, span: Vector2i) -> void:
	var shaft := _watched[car] as BuildingPlan.ShaftSpot
	var shown: Array = _shown[car]
	var index := int(shown[0])
	var heading := float(shown[1])
	var label := floor_label(_rules, index)
	# Only the floors of its own shaft: the same column can hold another one with its own
	# cab, and the boards of the whole column would show now one cab, now the other.
	var column := _boards.get(shaft.x, {}) as Dictionary
	for floor_index in range(maxi(shaft.top, span.x), mini(shaft.bottom, span.y) + 1):
		var board := column.get(floor_index) as ShaftBoard
		if board != null:
			_show(board, label, heading, coming(heading, index, floor_index))
			if board.needle != null:
				board.needle.rotation.z = needle_angle(shaft, index)


## Cab travel by its velocity: [constant Intent.UP], [constant Intent.DOWN] or
## 0. Velocity is in the rules plane, where y grows downward: a cab going down
## reports a positive velocity, as in [method ElevatorCar.speed_now].
static func heading_of(speed: float) -> float:
	if is_zero_approx(speed):
		return 0.0
	return Intent.DOWN if speed > 0.0 else Intent.UP


## Whether the cab travels toward the board's floor: down means floors below it, up means
## floors above it. Directions are [Intent]; floor indices grow downward, zero is the top.
static func coming(heading: float, car_floor: int, board_floor: int) -> float:
	if heading == Intent.DOWN and board_floor > car_floor:
		return Intent.DOWN
	if heading == Intent.UP and board_floor < car_floor:
		return Intent.UP
	return 0.0


## The floor of its shaft nearest to the cab floor.
func _nearest_floor(car: ElevatorCar) -> int:
	var index := _rules.floor_index_near(WorldSpace.to_plane(car.global_position).y)
	var shaft := _watched.get(car) as BuildingPlan.ShaftSpot
	return clampi(index, shaft.top, shaft.bottom) if shaft != null else index


## Writes the floor and the cab's travel arrow [param heading] on the board and lights
## button [param call], the one in whose direction the cab travels to this floor.
func _show(board: ShaftBoard, label: String, heading: float, call: float) -> void:
	board.digits.text = label
	# Travel comes from [method heading_of]: up, down or 0; there is nothing else.
	var moving := heading != 0.0
	board.arrow.visible = moving
	board.arrow.rotation.z = PI if heading == Intent.DOWN else 0.0
	board.digits.position = board.center + Vector3(DIGITS_SHIFT if moving else 0.0, 0.0, 0.0)
	board.lit = call if board.up_button != null else 0.0
	if board.up_button != null:
		# A button that goes out returns to dark metal: without a material the box
		# would be drawn with the engine's default white material.
		var lit := GreyboxLook.light(CALL_LIT)
		var dark := GreyboxLook.metal(CALL_DARK)
		board.up_button.material_override = lit if call == Intent.UP else dark
		board.down_button.material_override = lit if call == Intent.DOWN else dark


## Whether the boards watch this cab.
func watches(car: ElevatorCar) -> bool:
	return _watched.has(car)


## What the portal board of shaft [param x] on floor [param index] shows.
func board_text(x: float, index: int) -> String:
	_catch_up(x, index)
	var board := (_boards.get(x, {}) as Dictionary).get(index) as ShaftBoard
	return board.digits.text if board != null else ""


## Updates an off-frame portal board that was asked about: it has fallen behind.
func _catch_up(x: float, index: int) -> void:
	for car: ElevatorCar in _watched:
		var shaft := _watched[car] as BuildingPlan.ShaftSpot
		if is_instance_valid(car) and _shown.has(car) and is_equal_approx(shaft.x, x):
			if index >= shaft.top and index <= shaft.bottom:
				_paint(car, Vector2i(index, index))


## Which button is lit on this portal: [constant Intent.UP], [constant
## Intent.DOWN] or 0, none (or there is no panel).
func lit_button(x: float, index: int) -> float:
	_catch_up(x, index)
	var board := (_boards.get(x, {}) as Dictionary).get(index) as ShaftBoard
	return board.lit if board != null else 0.0


## The column source on one floor of a shaft: in the middle of the span, in front of
## the rails.
##
## One source per floor, not one for the whole shaft: a band can be fourteen
## floors, and one source with such a radius would light its middle and leave
## both ends dark, while the cab moves along the whole band.
func _light_the_shaft(x: float, index: int, surface: float) -> void:
	var light := OmniLight3D.new()
	light.omni_range = GLOW_RANGE
	light.light_energy = GLOW_ENERGY
	light.light_color = GLOW_COLOR
	light.shadow_enabled = false
	light.position = WorldSpace.to_scene(Vector2(x, surface - _rules.floor_height * 0.5))
	light.position.z = GLOW_Z
	add_child(light)

	if not _glow.has(index):
		_glow[index] = [] as Array[OmniLight3D]
	(_glow[index] as Array[OmniLight3D]).append(light)


## Buffers at the ends of the band: the cab goes no further, and that is visible.
##
## Feedback after playing: "the elevator does not obey commands and stands still, and
## once I stepped off it drove away". That was the end of the band: the cab heard the
## command but had nowhere further to go, and empty, it immediately drove off on its
## schedule. A buffer explains the limit without a single word; the second pointer is the
## arrows in the cab itself.
##
## The lower buffer lies at the shaft bottom, that is, above the floor of its bottom
## floor, not inside the slab, where it is not visible at all.
##
## The buffer is between the posts, narrower and shallower than them by
## [constant BUFFER_INSET]: across the full shaft width its faces fell onto the post faces
## (ADR-0037, decision 2).
func _mark_shaft_ends(shaft: BuildingPlan.ShaftSpot) -> void:
	var inner := _rules.shaft_width * 0.5 - RAIL_WIDTH - BUFFER_INSET
	var top := top_of(shaft)
	var bottom := _rules.floor_surface(shaft.bottom) - BUFFER_HEIGHT
	var buffer := GreyboxLook.marker(GreyboxLook.DOOR)
	var depth := RAIL_DEPTH - BUFFER_INSET * 2.0

	for from: float in [top, bottom]:
		_add_part(Rect2(shaft.x - inner, from, inner * 2.0, BUFFER_HEIGHT), buffer, RAIL_Z, depth)


## A piece of shaft dressing: a box without a body at the place of a rules rectangle.
func _add_part(rect: Rect2, material: StandardMaterial3D, z: float, depth: float) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var part := GreyboxLook.box(Vector3(rect.size.x, rect.size.y, depth), material)
	part.position = WorldSpace.to_scene(rect.get_center())
	part.position.z = z
	add_child(part)


## The machine room structure above the top shaft.
##
## It has no body on purpose: under it is the opening of the very shaft the descent
## starts from, and a solid structure would lock Otto on the roof. It stands at the back
## wall, and he passes in front of it.
func _spawn_machine_room() -> void:
	var shaft := _plan.roof_shaft()
	if shaft == null:
		return

	var surface := _rules.floor_surface(BuildingRules.ROOF)
	var rect := Rect2(
		Vector2(shaft.x - MACHINE_ROOM_SIZE.x * 0.5, surface - MACHINE_ROOM_SIZE.y),
		MACHINE_ROOM_SIZE
	)
	var z := WorldSpace.BACK_WALL_Z + MACHINE_ROOM_DEPTH * 0.5
	_add_part(rect, BuildingFinish.shaft_concrete(GreyboxLook.WALL), z, MACHINE_ROOM_DEPTH)
