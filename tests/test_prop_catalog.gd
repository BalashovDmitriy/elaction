extends GutTest

## Dressing model catalogue ([PropCatalog], ADR-0033, decisions 3 and 4): every
## model has an author, an item has no bodies, and it fits where it stands.

const CREDITS_JSON := "res://assets/models/props/credits.json"
const CREDITS_MD := "res://CREDITS.md"

## Kinds that have their own furniture: everything except "any".
const FITS: Array[PropCatalog.Fit] = [
	PropCatalog.Fit.HOTEL, PropCatalog.Fit.OFFICE, PropCatalog.Fit.RESIDENTIAL
]


func _credits() -> Dictionary:
	var text := FileAccess.get_file_as_string(CREDITS_JSON)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


## The CC-BY licence requires an author, and there can be no model without a line in CREDITS.
func test_every_model_has_an_author_and_a_licence() -> void:
	var credits := _credits()
	var page := FileAccess.get_file_as_string(CREDITS_MD)
	for entry in PropCatalog.entries():
		assert_true(credits.has(entry.name), "%s: not in credits.json" % entry.name)
		if not credits.has(entry.name):
			continue
		var line: Dictionary = credits[entry.name]
		var licence := String(line.get("licence", ""))
		# Our own models (`tools/build_residential.py`) are under the code licence.
		var own := String(line.get("author", "")) == "elaction" and licence == "MIT"
		assert_true(
			own or licence.begins_with("CC0") or licence.begins_with("CC-BY"),
			"%s: licence %s is not an allowed one" % [entry.name, licence]
		)
		assert_false(String(line.get("author", "")).is_empty(), "%s: no author" % entry.name)
		assert_string_contains(page, "`%s`" % entry.name, false)


## A model in the folder without a catalogue entry is dead weight in the repository.
func test_every_model_file_is_in_the_catalog() -> void:
	for file in DirAccess.get_files_at(PropCatalog.DIR):
		if file.ends_with(".glb"):
			var name := file.get_basename()
			assert_not_null(
				PropCatalog.entry(name), "%s is in the folder but not in the catalog" % name
			)


func test_props_have_no_bodies() -> void:
	for entry in PropCatalog.entries():
		var prop := PropCatalog.make(entry.name)
		assert_not_null(prop, "%s does not build" % entry.name)
		if prop == null:
			continue
		var bodies := prop.find_children("*", "CollisionObject3D", true, false)
		assert_eq(bodies.size(), 0, "%s: the decor has a body" % entry.name)
		prop.free()


## Height — as in the catalogue; furniture fits between the wall and the actor's body; an
## item on the wall — between the pilasters.
func test_props_take_their_size_from_the_catalog() -> void:
	for entry in PropCatalog.entries():
		var size := PropCatalog.footprint(entry.name)
		match entry.place:
			PropCatalog.Place.FLOOR:
				assert_lte(
					size.z,
					PropCatalog.MAX_DEPTH + 0.001,
					"%s is deeper than its place" % entry.name
				)
				if entry.top.is_empty():
					assert_almost_eq(size.y, entry.height, 0.01, "%s: height" % entry.name)
			PropCatalog.Place.WALL:
				assert_lte(
					size.x,
					PropCatalog.WALL_MAX_WIDTH + 0.001,
					"%s is wider than the wall section" % entry.name
				)
				assert_lte(
					size.y, entry.height + 0.01, "%s: not taller than the catalog" % entry.name
				)
			PropCatalog.Place.ROOM:
				# The room behind a door has enough depth: it is not squeezed in depth.
				if entry.top.is_empty():
					assert_almost_eq(size.y, entry.height, 0.01, "%s: height" % entry.name)
			_:
				assert_almost_eq(size.y, entry.height, 0.01, "%s: height" % entry.name)


## Furniture stands on the floor with its back face against the wall: the model zero is the
## bottom in height, the back in depth, the middle in width.
func test_a_prop_stands_on_its_origin() -> void:
	for entry in PropCatalog.pick(PropCatalog.Place.FLOOR, PropCatalog.Fit.ANY):
		var prop := PropCatalog.make(entry.name)
		var box := PropCatalog.bounds_of(prop)
		assert_almost_eq(box.position.y, 0.0, 0.01, "%s: bottom on the floor" % entry.name)
		assert_almost_eq(box.position.z, 0.0, 0.01, "%s: back at the wall" % entry.name)
		assert_almost_eq(box.get_center().x, 0.0, 0.05, "%s: centered in width" % entry.name)
		prop.free()


## Each building kind has its own items and shared ones — and there are enough of each for a
## floor.
func test_each_kind_of_building_has_its_own_furniture() -> void:
	for fit: PropCatalog.Fit in FITS:
		var floor_items := PropCatalog.pick(PropCatalog.Place.FLOOR, fit)
		var wall_items := PropCatalog.pick(PropCatalog.Place.WALL, fit)
		assert_gt(floor_items.size(), 8, "too little furniture")
		assert_gt(wall_items.size(), 4, "too little for the walls")
		var own := 0
		for item in floor_items + wall_items:
			assert_true(
				item.fit == fit or item.fit == PropCatalog.Fit.ANY,
				"%s is not from this building" % item.name
			)
			if item.fit == fit:
				own += 1
		assert_gt(own, 3, "kind %d has too few items of its own" % fit)


func test_the_lamp_on_top_is_never_drawn_on_its_own() -> void:
	for fit: PropCatalog.Fit in FITS:
		for item in PropCatalog.pick(PropCatalog.Place.FLOOR, fit):
			assert_ne(item.place, PropCatalog.Place.TOP, "%s stands only on furniture" % item.name)


func test_the_first_building_is_the_empire_hotel() -> void:
	var identity := BuildingIdentity.of(1, 12345)
	assert_true(identity.is_hotel())
	assert_eq(identity.name, "EMPIRE")
	assert_eq(identity.sign_lines(), PackedStringArray(["EMPIRE", "HOTEL"]))


## Equal draw over the three kinds (ADR-0055, decision 2): all three come up, none
## takes more than half, the name is from its kind's list, the sign is its own.
func test_buildings_draw_all_three_kinds_and_keep_their_draw() -> void:
	var kinds := {}
	var draws := 300
	for building in range(2, draws + 2):
		var one := BuildingIdentity.of(building, building * 17)
		var again := BuildingIdentity.of(building, building * 17)
		assert_eq(one.kind, again.kind, "the draw repeats for the same building")
		assert_eq(one.name, again.name)
		assert_has(BuildingIdentity.names_of(one.kind), one.name, "the name is from its own list")
		kinds[one.kind] = int(kinds.get(one.kind, 0)) + 1
		var lines := one.sign_lines()
		assert_eq(lines[0], one.name, "the sign starts with the name")
		match one.kind:
			BuildingIdentity.Kind.OFFICE:
				assert_eq(lines.size(), 1, "an office has one name")
			BuildingIdentity.Kind.RESIDENTIAL:
				assert_eq(
					lines[1], BuildingIdentity.RESIDENTIAL_WORD, "a residential building has APTS"
				)
	assert_eq(kinds.size(), 3, "hotels, offices and residential buildings all come up")
	for kind: int in kinds:
		assert_lt(int(kinds[kind]), draws / 2, "kind %d comes up too often" % kind)
