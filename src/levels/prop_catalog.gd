class_name PropCatalog
extends RefCounted

## Catalogue of dressing models (ADR-0033, decision 3).
##
## Pack models sit in `assets/models/props/` as they came: each has its own height and
## its own front. A catalogue entry brings a model in line with the game — height in metres,
## rotation to face the camera, where it hangs and in which building it fits. Height is set at
## assembly from the model's bounds, not by a scale number: a re-exported pack with different
## units will not diverge from the game.
##
## Attribution is in `assets/models/props/credits.json` and `CREDITS.md`; a test checks
## that every entry has it.

## Where an item goes: stands on the floor by the wall, hangs on the wall, stands on the roof, is
## only on top of another (a lamp on a dresser — does not enter the draw itself), stands in
## the room behind a door ([DoorRoom]) — does not go into the corridor; stands in a special
## floor hall ([FloorHall], ADR-0057) — does not enter the corridor draw.
enum Place { FLOOR, WALL, ROOF, TOP, ROOM, HALL }

## For which building: hotel, office, residential building, any.
enum Fit { HOTEL, OFFICE, RESIDENTIAL, ANY }

## Render layer of dressing. Items are visible like everything else, but cast no shadow from the
## lamp fill light: the fill is a weak wide light, the shadow of a chair from it is not visible
## in the frame, and drawing the dressing once more into its shadow map cost a third of the frame
## at the bottom of the building, where there are three times more lamps (ADR-0042, decision 2).
## The shadow under a lamp's cone stays for items.
##
## Its own layer instead of the first one, not in addition to it: the shadow mask takes an item if
## at least one layer matches, and on the first layer the fill mask would not let it go.
const RENDER_LAYER: int = 1 << 10
const DIR := "res://assets/models/props"

## Furniture stands this many metres from the back wall: in front of the pilasters
## ([constant BuildingRibs.PILASTER_DEPTH]) and the panel, with a gap. So a wide
## sofa passes in front of a pilaster, not through it.
const FLOOR_OFFSET: float = 0.24

## Furniture is never deeper than this, m: from [constant FLOOR_OFFSET] to the actor's body,
## which starts 0.2 m from the play plane. A deeper model is squeezed in
## depth, like the car at the exit (ADR-0032): from the side this is not visible.
const MAX_DEPTH: float = 0.54

## An item on the wall is no wider than this, m: it hangs between pilasters. A wider one
## is scaled down as a whole, not flattened.
const WALL_MAX_WIDTH: float = 0.7

## At what height the middle of an item on the wall is, m, unless the entry says otherwise.
const WALL_CENTRE: float = 1.65


## Catalogue entry.
class Entry:
	extends RefCounted

	var name: String
	var place: Place = Place.FLOOR
	var fit: Fit = Fit.ANY
	## Height in metres: the model is brought to it by a single scale.
	var height: float = 1.0
	## Rotation around the vertical, degrees: the model's front — toward the camera (+Z).
	var yaw: float = 0.0
	## Tilt around X, degrees: a picture that came lying flat stands up on the wall.
	var pitch: float = 0.0
	## What stands on top: a lamp on a side table, on a dresser.
	var top: String = ""
	## Middle of an item on the wall above the floor, m.
	var centre: float = WALL_CENTRE

	static func of(
		prop_name: String, where: Place, which: Fit, tall: float, turn: float = 0.0
	) -> Entry:
		var entry := Entry.new()
		entry.name = prop_name
		entry.place = where
		entry.fit = which
		entry.height = tall
		entry.yaw = turn
		return entry

	## Tilt around X. Returns itself: entries are built as a chain.
	func tilted(degrees: float) -> Entry:
		pitch = degrees
		return self

	## What to put on top.
	func topped(with_prop: String) -> Entry:
		top = with_prop
		return self

	## Hangs higher or lower than usual.
	func raised(middle: float) -> Entry:
		centre = middle
		return self


static var _entries: Dictionary = _build()
## Bounds of assembled items by name: the layout draw asks for them at
## every spot, while the model is loaded once.
static var _footprints: Dictionary = {}
## Bounds of the rotated model before scaling, by name.
static var _boxes: Dictionary = {}
## Model scenes by name. The loader cache keeps a resource only while there is a
## reference to it, and an assembled item does not reference the scene: the room behind a door,
## assembled on opening and removed on closing, would read the .glb from disk anew
## on every door leaf — in the middle of a physics step (code review M24i).
static var _scenes: Dictionary = {}


## All catalogue entries.
static func entries() -> Array[Entry]:
	var all: Array[Entry] = []
	for entry: Entry in _entries.values():
		all.append(entry)
	return all


## Entry by name, or null.
static func entry(prop_name: String) -> Entry:
	return _entries.get(prop_name) as Entry


## Entries for a place and a building.
static func pick(where: Place, which: Fit) -> Array[Entry]:
	var found: Array[Entry] = []
	for item: Entry in _entries.values():
		if item.place == where and (item.fit == which or item.fit == Fit.ANY):
			found.append(item)
	found.sort_custom(func(a: Entry, b: Entry) -> bool: return a.name < b.name)
	return found


## Assembles an item: the model rotated to the camera and brought to height, the origin —
## at the middle of the bottom in width and at the back face in depth. So an item is placed
## against the wall with one shift, whatever its depth. A node without bodies.
##
## [param full_depth] — do not squeeze in depth: for the room behind a door, where
## corridor furniture stands at its real depth.
static func make(prop_name: String, full_depth: bool = false) -> Node3D:
	var item := entry(prop_name)
	var scene := _scenes.get(prop_name) as PackedScene
	if scene == null:
		var path := "%s/%s.glb" % [DIR, prop_name]
		if not ResourceLoader.exists(path):
			push_error("no furniture model: %s" % path)
			return null
		scene = load(path) as PackedScene
		_scenes[prop_name] = scene
	var model := scene.instantiate() as Node3D
	# Rotation — a separate node above the model: the bounds are computed already rotated.
	var turned := Node3D.new()
	turned.add_child(model)
	if item != null:
		turned.rotation = Vector3(deg_to_rad(item.pitch), deg_to_rad(item.yaw), 0.0)
	# A model's bounds are one for all its copies: the mesh walk happens once per name, not for
	# every item in the building.
	if not _boxes.has(prop_name):
		_boxes[prop_name] = PropCatalog.bounds_of_turned(turned)
	var box: AABB = _boxes[prop_name]
	var height := item.height if item != null else box.size.y
	var factor := height / maxf(box.size.y, 0.001)
	if item != null and item.place == Place.WALL:
		factor = minf(factor, WALL_MAX_WIDTH / maxf(box.size.x, 0.001))
		height = box.size.y * factor
	var squeeze := minf(1.0, MAX_DEPTH / maxf(box.size.z * factor, 0.001))
	# The roof and the room behind a door have enough depth: only what
	# stands in the corridor between the wall and the actors is squeezed.
	var deep := [Place.ROOF, Place.ROOM, Place.HALL]
	if full_depth or (item != null and item.place in deep):
		squeeze = 1.0
	var sized := Node3D.new()
	sized.add_child(turned)
	sized.scale = Vector3(factor, factor, factor * squeeze)
	var centre := box.get_center()
	sized.position = Vector3(
		-centre.x * factor, -box.position.y * factor, -box.position.z * factor * squeeze
	)
	var holder := Node3D.new()
	holder.name = prop_name
	holder.add_child(sized)
	_mark_as_props(model)
	if item != null and not item.top.is_empty():
		var on_top := make(item.top, full_depth)
		if on_top != null:
			# On top, at the middle of the bottom's depth: the lamp stands on the tabletop, not
			# on its back edge.
			var depth := box.size.z * factor * squeeze
			var top_depth := footprint(item.top).z
			on_top.position = Vector3(0.0, height, (depth - top_depth) * 0.5)
			holder.add_child(on_top)
	return holder


## Moves the model's meshes from the first layer to the dressing layer [constant
## RENDER_LAYER]: the lamp fill does not take dressing into its shadow (ADR-0042,
## decision 2).
static func _mark_as_props(model: Node) -> void:
	for node: Node in model.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		visual.layers = (visual.layers & ~1) | RENDER_LAYER


## Bounds of an assembled item, m: width, height, depth — with the lamp on top.
static func footprint(prop_name: String) -> Vector3:
	if not _footprints.has(prop_name):
		var built := make(prop_name)
		_footprints[prop_name] = bounds_of(built).size if built != null else Vector3.ZERO
		if built != null:
			built.free()
	return _footprints[prop_name]


## Bounds of a node including its own rotation — as it stands in its parent.
static func bounds_of_turned(node: Node3D) -> AABB:
	var wrapper_box := AABB()
	var first := true
	for child in node.get_children():
		var inner := child as Node3D
		if inner == null:
			continue
		var part := node.transform * (inner.transform * bounds_of(inner))
		wrapper_box = part if first else wrapper_box.merge(part)
		first = false
	return wrapper_box


## Bounds of all meshes of a node in its own space. The node may not be in the
## tree yet: transforms are combined by hand, not via global_transform.
static func bounds_of(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [[node, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var current := pair[0] as Node3D
		var placed := pair[1] as Transform3D
		var mesh := current as MeshInstance3D
		if mesh != null and mesh.mesh != null:
			var part := placed * mesh.mesh.get_aabb()
			box = part if first else box.merge(part)
			first = false
		for child in current.get_children():
			var node_3d := child as Node3D
			if node_3d != null:
				stack.append([node_3d, placed * node_3d.transform])
	return box


## The catalogue. Height — in metres, as in life next to Otto at 1.68; rotation — by
## the frame `tools/props_shot.tscn -- --raw`: which models came sideways, backwards
## or lying flat.
static func _build() -> Dictionary:
	var list: Array[Entry] = [
		# Floor, any building.
		Entry.of("houseplant_a", Place.FLOOR, Fit.ANY, 0.9),
		Entry.of("houseplant_b", Place.FLOOR, Fit.ANY, 1.0),
		Entry.of("houseplant_c", Place.FLOOR, Fit.ANY, 1.3),
		Entry.of("potted_plant", Place.FLOOR, Fit.ANY, 0.8),
		Entry.of("coat_rack", Place.FLOOR, Fit.ANY, 1.75),
		Entry.of("trashcan", Place.FLOOR, Fit.ANY, 0.6),
		Entry.of("vending_machine", Place.FLOOR, Fit.ANY, 1.85),
		Entry.of("fire_extinguisher", Place.FLOOR, Fit.ANY, 0.6),
		# A "Wet floor" sign — in any building: the cleaner has passed (ADR-0048).
		Entry.of("wet_floor_sign", Place.FLOOR, Fit.ANY, 0.62),
		# Floor, hotel: a lounge by the lifts, not a storeroom.
		Entry.of("couch_medium", Place.FLOOR, Fit.HOTEL, 0.8),
		Entry.of("armchair", Place.FLOOR, Fit.HOTEL, 0.9),
		Entry.of("floor_lamp", Place.FLOOR, Fit.HOTEL, 1.6),
		Entry.of("grandfather_clock", Place.FLOOR, Fit.HOTEL, 2.0),
		Entry.of("dresser", Place.FLOOR, Fit.HOTEL, 0.8).topped("table_lamp"),
		Entry.of("end_table", Place.FLOOR, Fit.HOTEL, 0.6).topped("table_lamp"),
		Entry.of("cabinet", Place.FLOOR, Fit.HOTEL, 0.9),
		Entry.of("table_lamp", Place.TOP, Fit.HOTEL, 0.5),
		Entry.of("bench_hotel", Place.FLOOR, Fit.HOTEL, 0.85),
		# Floor, office.
		Entry.of("water_cooler", Place.FLOOR, Fit.OFFICE, 1.2),
		Entry.of("file_cabinet", Place.FLOOR, Fit.OFFICE, 1.3, -90.0),
		Entry.of("copier", Place.FLOOR, Fit.OFFICE, 1.2),
		Entry.of("cardboard_boxes", Place.FLOOR, Fit.OFFICE, 1.0),
		Entry.of("bins", Place.FLOOR, Fit.OFFICE, 0.9),
		Entry.of("bookshelf", Place.FLOOR, Fit.OFFICE, 1.6),
		# A reception by the offices: an armchair for visitors and a floor lamp (ADR-0048).
		Entry.of("lounge_chair", Place.FLOOR, Fit.OFFICE, 0.85),
		Entry.of("light_stand", Place.FLOOR, Fit.OFFICE, 1.6),
		# Floor, residential building (ADR-0055, decision 4): a stairwell entrance, not a lounge —
		# a radiator, a bicycle by the wall, garbage bags until morning.
		Entry.of("radiator", Place.FLOOR, Fit.RESIDENTIAL, 0.68),
		Entry.of("stroller", Place.FLOOR, Fit.RESIDENTIAL, 1.0),
		Entry.of("bicycle", Place.FLOOR, Fit.RESIDENTIAL, 1.0),
		Entry.of("trash_bags", Place.FLOOR, Fit.RESIDENTIAL, 0.55),
		Entry.of("trash_bag", Place.FLOOR, Fit.RESIDENTIAL, 0.6),
		# Walls: pictures — everywhere, the rest — by building. Wall Art came
		# with its back to the camera, Painting — lying flat.
		Entry.of("painting", Place.WALL, Fit.ANY, 0.6).tilted(90.0),
		Entry.of("wall_art_02", Place.WALL, Fit.ANY, 0.9, 180.0),
		Entry.of("wall_art_03", Place.WALL, Fit.ANY, 0.9, 180.0),
		Entry.of("wall_art_05", Place.WALL, Fit.ANY, 0.9, 180.0),
		Entry.of("wall_art_06", Place.WALL, Fit.ANY, 0.9, 180.0),
		Entry.of("analog_clock", Place.WALL, Fit.OFFICE, 0.4, -90.0),
		Entry.of("whiteboard", Place.WALL, Fit.OFFICE, 0.9),
		Entry.of("message_board", Place.WALL, Fit.OFFICE, 0.9, -90.0),
		Entry.of("corkboard", Place.WALL, Fit.OFFICE, 0.7),
		Entry.of("calendar", Place.WALL, Fit.OFFICE, 0.45),
		Entry.of("vent", Place.WALL, Fit.OFFICE, 0.35),
		Entry.of("air_vent", Place.WALL, Fit.OFFICE, 0.45, 90.0),
		Entry.of("fire_exit_sign", Place.WALL, Fit.ANY, 0.3, -90.0).raised(2.35),
		Entry.of("mailboxes", Place.WALL, Fit.RESIDENTIAL, 0.66).raised(1.35),
		# The room behind a door (ADR-0047): it is visible through the open door leaf. dook
		# workstations came sideways — desk toward +X.
		Entry.of("bed_hotel", Place.ROOM, Fit.HOTEL, 0.8),
		Entry.of("bed_double", Place.ROOM, Fit.HOTEL, 1.15),
		Entry.of("night_stand", Place.ROOM, Fit.HOTEL, 0.58).topped("table_lamp"),
		Entry.of("night_stand_b", Place.ROOM, Fit.HOTEL, 0.62).topped("table_lamp"),
		Entry.of("curtains", Place.ROOM, Fit.HOTEL, 2.3),
		Entry.of("rug", Place.ROOM, Fit.HOTEL, 0.02),
		Entry.of("desk", Place.ROOM, Fit.OFFICE, 0.78),
		Entry.of("office_chair", Place.ROOM, Fit.OFFICE, 1.05),
		Entry.of("workstation_a", Place.ROOM, Fit.OFFICE, 1.45, 90.0),
		Entry.of("workstation_b", Place.ROOM, Fit.OFFICE, 1.35, 90.0),
		# Apartment (ADR-0055, decision 5): kitchen, living room, bedroom — the bed
		# and nightstands are taken from the hotel room.
		Entry.of("fridge", Place.ROOM, Fit.RESIDENTIAL, 1.7),
		Entry.of("stove", Place.ROOM, Fit.RESIDENTIAL, 0.92),
		Entry.of("counter_sink", Place.ROOM, Fit.RESIDENTIAL, 1.06),
		Entry.of("kettle", Place.TOP, Fit.RESIDENTIAL, 0.24),
		Entry.of("microwave", Place.TOP, Fit.RESIDENTIAL, 0.3, 180.0),
		Entry.of("tv_old", Place.ROOM, Fit.RESIDENTIAL, 0.9, 180.0),
		Entry.of("sofa", Place.ROOM, Fit.RESIDENTIAL, 0.78),
		Entry.of("paper_bag", Place.TOP, Fit.RESIDENTIAL, 0.38, 90.0),
		# Special floor halls (ADR-0057, decision 5): Kenney Furniture Kit, colour —
		# by building kind ([HallLook]). All came facing the camera.
		Entry.of("washer", Place.HALL, Fit.ANY, 0.85),
		Entry.of("dryer", Place.HALL, Fit.ANY, 0.85),
		Entry.of("washer_dryer", Place.HALL, Fit.ANY, 1.8),
		Entry.of("bar_stool", Place.HALL, Fit.ANY, 0.78),
		Entry.of("bar_counter", Place.HALL, Fit.ANY, 1.1),
		Entry.of("dining_table", Place.HALL, Fit.ANY, 0.76),
		Entry.of("round_table", Place.HALL, Fit.ANY, 0.74),
		Entry.of("dining_chair", Place.HALL, Fit.ANY, 0.95),
		Entry.of("kitchen_stove", Place.HALL, Fit.ANY, 0.9),
		Entry.of("kitchen_hood", Place.HALL, Fit.ANY, 0.75),
		Entry.of("kitchen_cabinet", Place.HALL, Fit.ANY, 0.9),
		Entry.of("kitchen_fridge", Place.HALL, Fit.ANY, 1.9),
		Entry.of("kitchen_sink", Place.HALL, Fit.ANY, 0.95),
		Entry.of("lounge_sofa", Place.HALL, Fit.ANY, 0.8),
		Entry.of("lounge_armchair", Place.HALL, Fit.ANY, 0.85),
		Entry.of("coffee_table", Place.HALL, Fit.ANY, 0.42),
		Entry.of("box_closed", Place.HALL, Fit.ANY, 0.4),
		Entry.of("desk_chair", Place.HALL, Fit.ANY, 1.05),
		Entry.of("long_table", Place.HALL, Fit.ANY, 0.76),
		Entry.of("bench_cushion", Place.HALL, Fit.ANY, 0.48),
		Entry.of("floor_lamp_round", Place.HALL, Fit.ANY, 1.65),
		Entry.of("tv_modern", Place.HALL, Fit.ANY, 0.75),
		Entry.of("speaker", Place.HALL, Fit.ANY, 1.1),
		# Roof (ADR-0033, decision 8).
		Entry.of("water_tower", Place.ROOF, Fit.ANY, 4.5),
		Entry.of("water_tank", Place.ROOF, Fit.ANY, 2.5),
		Entry.of("air_conditioner", Place.ROOF, Fit.ANY, 0.9),
		Entry.of("antenna", Place.ROOF, Fit.ANY, 0.9),
		Entry.of("antenna_small", Place.ROOF, Fit.ANY, 2.5),
		Entry.of("roof_antenna", Place.ROOF, Fit.ANY, 3.5),
		Entry.of("satellite_dish", Place.ROOF, Fit.ANY, 1.0),
		Entry.of("solar_panel", Place.ROOF, Fit.ANY, 1.4),
		Entry.of("roof_exit", Place.ROOF, Fit.ANY, 2.3),
	]
	var table := {}
	for item in list:
		table[item.name] = item
	return table
