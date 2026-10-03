extends GutTest

## Hotel and office are different corridors (ADR-0048): in the M24i shots they read the
## same, and the difference is now held by the building style [BuildingStyle].
##
## The building is assembled whole, and what is visible is checked: fixtures, doors,
## sconces, the runner. The building kind is a draw of the number and seed: the test
## finds a building of the needed kind itself rather than taking a number at random.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const SETTLE_FRAMES: int = 5


func after_each() -> void:
	GameState.instance().start_game()


func _level(kind: BuildingIdentity.Kind, building_seed: int = 1) -> GreyboxLevel:
	GameState.instance().start_game()
	GameState.instance().building = BuildingIdentity.first_of(kind, building_seed)
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	var rules := BuildingRules.new()
	rules.floors = 8
	rules.documents_cap = 0
	level.rules = rules
	level.building_seed = building_seed
	level.spawn_agents = false
	add_child_autofree(level)
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	return level


func test_hotel_and_office_styles_differ_in_every_look() -> void:
	var hotel := BuildingStyle.of(BuildingIdentity.new())
	var identity := BuildingIdentity.new()
	identity.kind = BuildingIdentity.Kind.OFFICE
	var office := BuildingStyle.of(identity)
	assert_ne(hotel.runner, office.runner, "runner only in the hotel")
	assert_ne(hotel.fixture, office.fixture, "fixtures differ")
	assert_ne(hotel.sconces, office.sconces, "sconces only in the hotel")
	assert_ne(hotel.panels, office.panels, "panels in the hotel, glass in the office")
	assert_ne(hotel.vision_glass, office.vision_glass)
	assert_ne(hotel.departments, office.departments, "department plates in the office")
	assert_false(hotel.crown.is_equal_approx(office.crown), "cornice differs")


## The residential building looks like neither the hotel nor the office (ADR-0055,
## decision 4): its own fixture, checkerboard tile, peepholes, apartment letters, mats
## by the doors.
func test_a_residential_style_differs_from_both() -> void:
	var home := BuildingStyle.of(BuildingIdentity.typed(BuildingIdentity.Kind.RESIDENTIAL))
	for kind: BuildingIdentity.Kind in [BuildingIdentity.Kind.HOTEL, BuildingIdentity.Kind.OFFICE]:
		var other := BuildingStyle.of(BuildingIdentity.typed(kind))
		assert_ne(home.fixture, other.fixture, "own fixture")
		assert_ne(home.checker, other.checker, "checkerboard only in the residential building")
		assert_ne(home.peephole, other.peephole, "peephole on apartments")
		assert_ne(home.apartment_letters, other.apartment_letters, "apartment letters")
		assert_false(home.leaf_tone.is_equal_approx(other.leaf_tone), "leaf in its own colour")
	assert_false(home.runner, "no runner")
	assert_gt(home.door_mat_share, 0.0, "door mats")
	var red := GreyboxLook.DOOR_RED
	var gap := Vector3(home.leaf_tone.r - red.r, home.leaf_tone.g - red.g, home.leaf_tone.b - red.b)
	assert_gt(gap.length(), 0.4, "an apartment leaf is not confused with the red door")


func test_a_residential_building_hangs_domes_and_peepholes() -> void:
	var level := await _level(BuildingIdentity.Kind.RESIDENTIAL)
	assert_eq(level.identity.kind, BuildingIdentity.Kind.RESIDENTIAL, "the building is residential")
	for lamp: Lamp in level.find_children("*", "Lamp", true, false):
		assert_has(
			[BuildingStyle.Fixture.DOME, BuildingStyle.Fixture.BULB],
			lamp.fixture,
			"residential: a plate or a bare bulb"
		)
	var peepholes := 0
	var mats := 0
	for door: Door in level.doors():
		if door.find_child("Peephole", true, false) != null:
			peepholes += 1
		if door.find_child("Doormat", true, false) != null:
			mats += 1
		assert_null(door.find_child("VisionGlass", true, false), "no glass in the apartment door")
	assert_gt(peepholes, 0, "apartment doors have a peephole")
	assert_gt(mats, 0, "apartment doors have mats")
	assert_eq(level.find_children("Sconce", "", true, false).size(), 0, "no sconces")


func test_an_office_hangs_panels_and_glazed_doors() -> void:
	var level := await _level(BuildingIdentity.Kind.OFFICE)
	assert_false(level.identity.is_hotel(), "the building is an office")
	for lamp: Lamp in level.find_children("*", "Lamp", true, false):
		assert_eq(lamp.fixture, BuildingStyle.Fixture.PANEL, "office: a daylight panel box")
	var glazed := 0
	for door: Door in level.doors():
		if door.find_child("VisionGlass", true, false) != null:
			glazed += 1
	assert_gt(glazed, 0, "office doors have glass")
	assert_eq(level.find_children("Sconce", "", true, false).size(), 0, "no sconces in the office")


func test_a_hotel_lights_its_pilasters_but_not_on_dark_floors() -> void:
	var level := await _level(BuildingIdentity.Kind.HOTEL)
	assert_true(level.identity.is_hotel(), "the building is a hotel")
	var sconces := level.find_children("Sconce", "", true, false)
	assert_gt(sconces.size(), 0, "hotel sconces on pilasters")
	for sconce: Node in sconces:
		var at := WorldSpace.to_plane((sconce as Node3D).global_position)
		var index := level.rules.floor_index_near(at.y + WallSconce.HEIGHT)
		assert_false(level.rules.is_unlit(index), "sconce is off on a dark floor")
	for door: Door in level.doors():
		assert_null(door.find_child("VisionGlass", true, false), "hotel doors have no glass")


## The office wall is glass with a hall behind it (ADR-0056, decision 4); the hotel and
## the residential building have no hall. The hall has no bodies and no shadows, on a
## dark floor the screens do not glow. There are no wall panel joints in front of the
## glass: dark stripes would hang on it.
func test_only_an_office_opens_its_hall_behind_glass() -> void:
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		var level := await _level(kind)
		var halls := level.find_children("OpenSpace", "OpenSpace", true, false)
		var joints := level.get_node_or_null("Scenery/FloorDetail/Joint")
		if kind != BuildingIdentity.Kind.OFFICE:
			assert_eq(halls.size(), 0, "kind %d: no hall" % kind)
			assert_not_null(joints, "kind %d: panel joints on the wall" % kind)
			continue
		assert_null(joints, "office glass has no panel joints")
		assert_eq(halls.size(), 1, "the office has a hall behind glass")
		var hall := halls[0] as OpenSpace
		assert_eq(
			hall.find_children("*", "PhysicsBody3D", true, false).size(), 0, "hall without bodies"
		)
		for part: Node in hall.get_children():
			var many := part as MultiMeshInstance3D
			assert_not_null(many, "hall as multimeshes")
			if many != null:
				assert_eq(
					many.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "no shadows"
				)


## A picture hangs above the handrail of the lower wall panel: the hotel's panel is tall
## (ADR-0056, decision 4), and a picture bottom at 0.9 m went behind the handrail.
## The engine renames repeated items, and the catalogue recognises the first of each
## type — that is enough: the height is the same for a type.
func test_wall_decor_hangs_above_the_wainscot() -> void:
	for kind: BuildingIdentity.Kind in [
		BuildingIdentity.Kind.HOTEL, BuildingIdentity.Kind.RESIDENTIAL
	]:
		# Special floors (ADR-0057) have no wall: a small building has few corridors, and
		# on one seed the walls may be empty — so there are several seeds.
		var hung := 0
		for building_seed: int in [1, 2, 3]:
			var level := await _level(kind, building_seed)
			var rules := level.rules
			var style := BuildingStyle.of(level.identity)
			var rail_top := style.wainscot_height + BuildingRibs.RAIL_HEIGHT
			for item: Node in level.get_node("Scenery/Props").get_children():
				var entry := PropCatalog.entry(String(item.name))
				if entry == null or entry.place != PropCatalog.Place.WALL:
					continue
				var bottom := WorldSpace.to_plane((item as Node3D).position).y
				# The floor above whose floor the item hangs: the nearest floor below.
				var index := int(ceilf((bottom - rules.sky_height) / rules.floor_height)) - 1
				assert_gte(
					rules.floor_surface(index) - bottom,
					rail_top - 0.001,
					"kind %d: %s behind the rail" % [kind, item.name]
				)
				hung += 1
			level.queue_free()
			await get_tree().process_frame
		assert_gt(hung, 0, "kind %d: nothing on the walls" % kind)


## An office door opens into the hall: there is no room of its own behind it.
func test_an_office_door_opens_into_the_hall() -> void:
	var door := (preload("res://src/systems/doors/door.tscn")).instantiate() as Door
	door.furnish(BuildingIdentity.typed(BuildingIdentity.Kind.OFFICE), 11)
	add_child_autofree(door)
	await wait_physics_frames(2)
	assert_true(door.summon_agent(), "the door opens for an agent")
	for _frame: int in 120:
		await wait_physics_frames(1)
		if door.openness() > 0.5:
			break
	assert_gt(door.openness(), 0.0, "opened")
	assert_null(door.room(), "no room behind the office door")
