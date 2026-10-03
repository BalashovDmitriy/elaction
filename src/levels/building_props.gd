class_name BuildingProps
extends Node3D

## Floor dressing, door plaques and pipes under the ceiling
## (ADR-0029, decision 3; since M21b — pack models, ADR-0033, decision 3).
##
## All without bodies: an item is decor, not cover. Where things stand is decided by
## [BuildingDressing], what they look like — by [PropCatalog]. Only what glows in real
## life glows — the display, the lamp on the dresser: an item behind an actor must not
## compete with his silhouette (outline — ADR-0022).

## How far an item on the wall stands off it, m: flush, it would flicker with it.
const STANDOFF: float = 0.04

## Door plaque: size, the height of its middle, m, and how far it is right of the door's
## edge.
const PLATE := Vector3(0.16, 0.1, 0.015)
const PLATE_RISE: float = 1.5
const PLATE_GAP: float = 0.14
## The plaque hangs in front of the pilasters, like the floor plaque
## ([constant FloorSigns.STANDOFF]): at the edge of the pier next to the door stands a
## pilaster, and a plaque on the wall itself sank into it entirely (code review M21b).
const PLATE_Z: float = WorldSpace.BACK_WALL_Z + BuildingRibs.PILASTER_DEPTH + 0.01
## The office glass has no pilasters (ADR-0056, decision 4): the plaque is on the glass,
## in front of the door casing and the partition posts, not in the air in front of them.
const GLASS_PLATE_Z: float = WorldSpace.BACK_WALL_Z + Door.FRAME_DEPTH + 0.01
## Gap of a wall item above the lower panel's handrail, m.
const PANEL_CLEAR: float = 0.02
## Plaques: brass with dark numbers in the hotel, steel in the office, dull aluminium in
## the residential building.
const PLATE_HOTEL := Color(0.62, 0.48, 0.22)
const PLATE_OFFICE := Color(0.55, 0.57, 0.6)
const PLATE_RESIDENTIAL := Color(0.46, 0.46, 0.44)
const PLATE_INK := Color(0.08, 0.07, 0.06)

## Pipe under the ceiling: thickness, m. It hangs in front of the pilasters — they stick
## out of the wall by [constant BuildingRibs.PILASTER_DEPTH] — and right under the strip
## that the slab's edge hides from the tilted camera
## ([method FloorSigns.hidden_band]). Before code review M19 it ran 7 cm under the
## ceiling and hid entirely behind the edge: not a single pipe was in the frame.
const PIPE_THICKNESS: float = 0.14
## Pipe gap from the pilasters and from the strip under the edge, m.
const PIPE_GAP: float = 0.03
## How far short of the floor plaque the pipe stops, m: in front of it, it would cover
## the plaque's top.
const PIPE_CLEARANCE: float = 0.1
## A pipe piece shorter than this is not placed, m: a stub at the wall reads as garbage.
const PIPE_MIN_LENGTH: float = 0.3

const PIPE := Color(0.22, 0.22, 0.24)

var _rules: BuildingRules = null
## A wall item does not hang lower than this above the floor, m: the top of the lower
## wall panel with the handrail. In the hotel it is picture height (ADR-0056,
## decision 4), and the bottom of a picture went behind the handrail.
var _panel_top: float = 0.0


## Middle of the pipe in depth: in front of the pilasters, with a gap.
static func pipe_z() -> float:
	return WorldSpace.BACK_WALL_Z + BuildingRibs.PILASTER_DEPTH + PIPE_GAP + PIPE_THICKNESS * 0.5


## Top of the pipe on the floor, in rules coordinates: right under the strip that the
## slab's edge hides at the depth of its front face.
static func pipe_top(rules: BuildingRules, floor_index: int) -> float:
	var front := pipe_z() + PIPE_THICKNESS * 0.5
	return rules.story_top(floor_index) + FloorSigns.hidden_band(front) + PIPE_GAP


## Pieces of a floor's pipe: "left edge, right edge" pairs.
##
## Breaks are where the pipe would pass through something or cover it: a shaft (the cab
## travels), an escalator opening from the floor above (the belt goes through the
## ceiling) and the floor number plaque. Static: the pipe layout is checked without a
## scene.
static func pipe_spans(
	rules: BuildingRules, plan: BuildingPlan, floor_index: int
) -> Array[Vector2]:
	var bounds := rules.floor_span(floor_index)
	var inner := Vector2(bounds.x + BuildingShell.WALL_WIDTH, bounds.y - BuildingShell.WALL_WIDTH)
	var cuts: Array[Vector2] = []
	var half := rules.shaft_width * 0.5
	for shaft in plan.shafts:
		if shaft.top <= floor_index and floor_index <= shaft.bottom:
			cuts.append(Vector2(shaft.x - half, shaft.x + half))
	for escalator in plan.escalators:
		if escalator.floor_index + 1 == floor_index:
			cuts.append(escalator.gap(rules))
	var plate := FloorSigns.centre_on(rules, floor_index).x
	var plate_reach := Proportions.FLOOR_SIGN.x * 0.5 + PIPE_CLEARANCE
	cuts.append(Vector2(plate - plate_reach, plate + plate_reach))

	var spans: Array[Vector2] = []
	for span in BuildingPlan.spans_between(cuts, inner):
		if span.y - span.x >= PIPE_MIN_LENGTH:
			spans.append(span)
	return spans


## Places the dressing by the layout and the door plaques.
func build(
	rules: BuildingRules,
	plan: BuildingPlan,
	dressing: BuildingDressing,
	identity: BuildingIdentity = BuildingIdentity.new()
) -> void:
	_rules = rules
	_panel_top = BuildingStyle.of(identity).wainscot_height + BuildingRibs.RAIL_HEIGHT
	for prop in dressing.props:
		_stand(prop)
	for item in dressing.decor:
		_hang(item)
	_plate_the_doors(plan, identity)
	for index: int in dressing.pipes:
		_lay_pipe(plan, index)


## Furniture by the wall: in front of the pilasters, on the floor.
func _stand(prop: BuildingDressing.PropSpot) -> void:
	var item := PropCatalog.make(prop.name)
	if item == null:
		return
	item.position = WorldSpace.to_scene(Vector2(prop.x, _rules.floor_surface(prop.floor_index)))
	item.position.z = WorldSpace.BACK_WALL_Z + PropCatalog.FLOOR_OFFSET
	add_child(item)


## A wall item: its middle at the height from the catalogue, but no lower than the top
## of the lower wall panel ([member _panel_top]).
func _hang(prop: BuildingDressing.PropSpot) -> void:
	var item := PropCatalog.make(prop.name)
	if item == null:
		return
	var entry := PropCatalog.entry(prop.name)
	var height := PropCatalog.footprint(prop.name).y
	var low := maxf(entry.centre - height * 0.5, _panel_top + PANEL_CLEAR)
	var bottom := _rules.floor_surface(prop.floor_index) - low
	item.position = WorldSpace.to_scene(Vector2(prop.x, bottom))
	item.position.z = WorldSpace.BACK_WALL_Z + STANDOFF
	add_child(item)


## Door plaques: the room number is the floor and the door's ordinal from left to right,
## as in a hotel: 2904 — the fourth door of the twenty-ninth floor.
func _plate_the_doors(plan: BuildingPlan, identity: BuildingIdentity) -> void:
	var counted := {}
	var plate_tone := PLATE_OFFICE
	match identity.kind:
		BuildingIdentity.Kind.HOTEL:
			plate_tone = PLATE_HOTEL
		BuildingIdentity.Kind.RESIDENTIAL:
			plate_tone = PLATE_RESIDENTIAL
	var metal := GreyboxLook.metal(plate_tone)
	var style := BuildingStyle.of(identity)
	var plate_z := GLASS_PLATE_Z if style.glass_wall else PLATE_Z
	var doors := plan.doors.duplicate()
	doors.sort_custom(
		func(a: BuildingPlan.DoorSpot, b: BuildingPlan.DoorSpot) -> bool: return a.x < b.x
	)
	for door: BuildingPlan.DoorSpot in doors:
		var number := FloorSigns.number_of(_rules, door.floor_index)
		counted[door.floor_index] = int(counted.get(door.floor_index, 0)) + 1
		var x := door.x + Door.LEAF_SIZE.x * 0.5 + PLATE_GAP
		var y := _rules.floor_surface(door.floor_index) - PLATE_RISE
		var room := "%d%02d" % [number, counted[door.floor_index]]
		# In the office the plaque is wider: the department above the office number (ADR-0048).
		var size := PLATE
		var text := room
		# An apartment gets the floor and a letter in door order, like 12C (ADR-0055).
		if style.apartment_letters:
			text = "%d%s" % [number, String.chr(64 + int(counted[door.floor_index]))]
		if style.departments:
			var names := BuildingStyle.DEPARTMENTS
			text = "%s\n%s" % [names[hash([number, room]) % names.size()], room]
			size = Vector3(PLATE.x * 2.2, PLATE.y * 1.6, PLATE.z)
			x += (size.x - PLATE.x) * 0.5
		var plate := GreyboxLook.box(size, metal)
		plate.position = WorldSpace.to_scene(Vector2(x, y))
		plate.position.z = plate_z + PLATE.z * 0.5
		add_child(plate)
		var label := Label3D.new()
		label.text = text
		label.font = NeonStyle.scene_font(700)
		label.font_size = 24 if style.departments else 32
		label.pixel_size = 0.0022
		label.modulate = PLATE_INK
		label.outline_size = 0
		label.shaded = true
		label.position = plate.position + Vector3(0.0, 0.0, PLATE.z * 0.5 + 0.002)
		add_child(label)


## Pipe under the ceiling along the back wall, in [method pipe_spans] pieces.
func _lay_pipe(plan: BuildingPlan, floor_index: int) -> void:
	var y := pipe_top(_rules, floor_index) + PIPE_THICKNESS * 0.5
	for span in pipe_spans(_rules, plan, floor_index):
		var pipe := GreyboxLook.box(
			Vector3(span.y - span.x, PIPE_THICKNESS, PIPE_THICKNESS), GreyboxLook.metal(PIPE)
		)
		pipe.position = WorldSpace.to_scene(Vector2((span.x + span.y) * 0.5, y))
		pipe.position.z = pipe_z()
		add_child(pipe)
