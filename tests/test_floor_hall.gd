extends GutTest

## Special floors (ADR-0057, decisions 2–4): a floor's role follows the ROM layout, on a
## special floor there is a hall instead of the back wall. Roles are checked without a
## scene at any building height, the hall in an assembled building of each kind: no
## bodies or shadows, not standing in front of doors, the light goes out together with
## the floor.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const SETTLE_FRAMES: int = 5
## How many seeds the scene-less hall check goes through.
const SEEDS: int = 30
## Height slack with which a detail belongs to its floor ([method _story_of]), m.
const STORY_SLACK: float = 0.2
const KINDS: Array[BuildingIdentity.Kind] = [
	BuildingIdentity.Kind.HOTEL, BuildingIdentity.Kind.OFFICE, BuildingIdentity.Kind.RESIDENTIAL
]


func after_each() -> void:
	GameState.instance().start_game()
	HallLook.forget()


## Halls are exactly on ROM floors 1–7 and 11–15; the rest have a corridor.
func test_halls_stand_on_the_rom_bands() -> void:
	for kind: BuildingIdentity.Kind in KINDS:
		for rom: int in range(1, Arcade.FLOORS + 1):
			var hall := FloorRole.is_hall(FloorRole.of_rom(kind, rom))
			var banded := rom <= 7 or (rom >= 11 and rom <= 15)
			assert_eq(hall, banded, "kind %d, ROM floor %d" % [kind, rom])


## The lower band is public halls, the dark one technical ones.
func test_dark_band_is_technical_and_lower_band_public() -> void:
	for kind: BuildingIdentity.Kind in KINDS:
		for rom: int in range(11, 16):
			var role := FloorRole.of_rom(kind, rom)
			assert_true(
				FloorRole.is_technical(role) or role == FloorRole.Role.LAUNDRY,
				"kind %d, ROM %d: %s" % [kind, rom, FloorRole.name_of(role)]
			)
		for rom: int in range(3, 8):
			assert_false(FloorRole.is_technical(FloorRole.of_rom(kind, rom)), "ROM %d" % rom)


## Each floor of a band is its own: neighboring halls do not repeat (decision 2), the
## lobby on 1–2 is one and the same two-story room, and the garage takes the first.
func test_neighbour_halls_differ() -> void:
	for kind: BuildingIdentity.Kind in KINDS:
		for rom: int in range(2, 15):
			if rom == 7 or rom == 10:
				continue
			var role := FloorRole.of_rom(kind, rom)
			var above := FloorRole.of_rom(kind, rom + 1)
			if FloorRole.is_hall(role) and FloorRole.is_hall(above):
				assert_ne(role, above, "kind %d, ROM %d and %d" % [kind, rom, rom + 1])


## The kinds are set apart: for every pair of kinds, the halls on the same floors differ
## on at least half of the band.
func test_kinds_get_their_own_halls() -> void:
	for first: int in KINDS.size():
		for second: int in range(first + 1, KINDS.size()):
			var same := 0
			var total := 0
			for rom: int in range(3, 16):
				var role := FloorRole.of_rom(KINDS[first], rom)
				if not FloorRole.is_hall(role):
					continue
				total += 1
				if role == FloorRole.of_rom(KINDS[second], rom):
					same += 1
			assert_lt(same * 2, total, "kinds %d and %d" % [first, second])


## The roof and the garage are not halls at any building height; a building of any
## height has halls and all roles come from the table.
func test_roof_and_garage_are_never_halls() -> void:
	for floors: int in [6, 8, 12, 20, 30]:
		var rules := BuildingRules.new()
		rules.floors = floors
		for kind: BuildingIdentity.Kind in KINDS:
			rules.kind = kind
			assert_false(FloorRole.hall_at(rules, BuildingRules.ROOF), "roof, %d floors" % floors)
			assert_false(FloorRole.hall_at(rules, floors - 1), "parking, %d floors" % floors)
			var halls := 0
			for index: int in floors - 1:
				halls += 1 if FloorRole.hall_at(rules, index) else 0
			assert_gt(halls, 0, "kind %d, %d floors: has special ones" % [kind, floors])


## What separates a hall: technical ones by mesh, the server room and meeting rooms by
## glass, the office's public ones by glass, the rest by columns.
func test_screen_follows_the_role() -> void:
	var office := BuildingIdentity.Kind.OFFICE
	var hotel := BuildingIdentity.Kind.HOTEL
	assert_eq(FloorRole.screen_of(FloorRole.Role.BOILER, hotel), FloorRole.Screen.MESH)
	assert_eq(FloorRole.screen_of(FloorRole.Role.SERVER, office), FloorRole.Screen.GLASS)
	assert_eq(FloorRole.screen_of(FloorRole.Role.LOBBY, office), FloorRole.Screen.GLASS)
	assert_eq(FloorRole.screen_of(FloorRole.Role.LOBBY, hotel), FloorRole.Screen.COLUMNS)


## In an assembled building of any kind: there are halls on every special floor, without
## bodies or shadows; light only on lit floors, and it goes out off-frame; no small
## detail stands in front of a door to the depth of its room.
func test_halls_in_a_built_building_of_every_kind() -> void:
	for kind: BuildingIdentity.Kind in KINDS:
		var level := await _level(kind)
		var rules := level.rules
		assert_eq(rules.kind, kind, "the level puts the kind into the rules")
		var halls := level.find_children("FloorHall", "FloorHall", true, false)
		assert_eq(halls.size(), 1, "kind %d: halls are assembled" % kind)
		if halls.is_empty():
			continue
		var hall := halls[0] as FloorHall
		assert_gt(hall.parts(), 0, "the details stayed in multimeshes")
		assert_eq(hall.find_children("*", "PhysicsBody3D", true, false).size(), 0, "no bodies")
		for many: Node in hall.find_children("*", "MultiMeshInstance3D", true, false):
			assert_eq(
				(many as MultiMeshInstance3D).cast_shadow,
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"no shadows"
			)
		for light: OmniLight3D in hall.lights():
			assert_false(light.shadow_enabled, "the hall light has no shadows")
			var index := _story_of(rules, WorldSpace.to_plane(light.position).y)
			assert_true(FloorRole.hall_at(rules, index), "light — on special floor %d" % index)
			assert_false(rules.is_unlit(index), "on a dark floor the hall light is off")
		hall.light_span(Vector2i(-10, -5))
		for light: OmniLight3D in hall.lights():
			assert_false(light.visible, "out of frame the hall light goes off")
		_assert_clear_of_doors(level.rules, level.plan(), hall, kind)


## Halls of any building, not of one seed: on a short span between shafts a detail does
## not turn inside out or stick out beyond the span edge, and none stands in front of a
## door. Short spans do not occur on every seed: the first one had none, and a reception
## desk of negative width passed the test.
func test_halls_of_any_building_stay_in_their_spans() -> void:
	for kind: BuildingIdentity.Kind in KINDS:
		var rules := BuildingRules.new()
		rules.kind = kind
		for building_seed: int in range(1, SEEDS + 1):
			var plan := BuildingPlan.generate(rules, building_seed)
			var hall := FloorHall.new()
			hall.build(rules, plan)
			var inverted := 0
			var outside := 0
			for place: Transform3D in hall.placements():
				if place.basis.determinant() <= 0.0:
					inverted += 1
				if not _within_a_span(rules, plan, place.origin):
					outside += 1
			assert_eq(inverted, 0, "kind %d, seed %d: details inside out" % [kind, building_seed])
			assert_eq(
				outside, 0, "kind %d, seed %d: details outside the span" % [kind, building_seed]
			)
			_assert_clear_of_doors(rules, plan, hall, kind)
			hall.free()


## Corridor dressing and items on the wall are not placed on a special floor: there is
## no wall.
func test_no_corridor_dressing_on_hall_floors() -> void:
	for kind: BuildingIdentity.Kind in KINDS:
		var level := await _level(kind)
		var rules := level.rules
		var scenery := level.get_node("Scenery") as BuildingScenery
		for prop: BuildingDressing.PropSpot in scenery.dressing.props:
			assert_false(
				FloorRole.hall_at(rules, prop.floor_index),
				"corridor furniture on floor %d" % prop.floor_index
			)
		for decor: BuildingDressing.PropSpot in scenery.dressing.decor:
			assert_false(
				FloorRole.hall_at(rules, decor.floor_index),
				"a thing on the wall of floor %d" % decor.floor_index
			)


## Whether the middle of detail [param origin] (scene) stands in the hall span of its
## floor: between shafts and walls, with a tolerance at the edge.
func _within_a_span(rules: BuildingRules, plan: BuildingPlan, origin: Vector3) -> bool:
	var index := _story_of(rules, -origin.y)
	var bounds := rules.floor_span(index)
	var inner := Vector2(bounds.x + BuildingShell.WALL_WIDTH, bounds.y - BuildingShell.WALL_WIDTH)
	for span: Vector2 in BuildingPlan.spans_between(plan.blocks_on(rules, index), inner):
		if origin.x >= span.x - 0.05 and origin.x <= span.y + 0.05:
			return true
	return false


func _assert_clear_of_doors(
	rules: BuildingRules, plan: BuildingPlan, hall: FloorHall, kind: BuildingIdentity.Kind
) -> void:
	# A special floor's door opens into the hall (ADR-0057): the door leaf's strip is free.
	var reach := FloorHall.LEAF_CLEAR
	var clear := Door.LEAF_SIZE.x * 0.5
	# Placements come from the set, not from the multimesh: under the headless engine the
	# multimesh does not store them and returns identity ones, and the check saw no details.
	var places := hall.placements()
	assert_eq(places.size(), hall.parts(), "the places of all details are known")
	var checked := 0
	for place: Transform3D in places:
		# Floor, walls and window bands span the whole span; their middle can be anywhere.
		if absf(place.basis.get_scale().x) > 2.5:
			continue
		var depth := WorldSpace.BACK_WALL_Z - place.origin.z
		if depth > reach - 0.2 or depth < 0.0:
			continue
		checked += 1
		var index := _story_of(rules, -place.origin.y)
		for spot: BuildingPlan.DoorSpot in plan.doors:
			if spot.floor_index != index:
				continue
			assert_true(
				absf(place.origin.x - spot.x) >= clear - 0.05,
				(
					"kind %d, floor %d: a detail at %.2f in front of the door at %.2f"
					% [kind, index, place.origin.x, spot.x]
				)
			)
	# The door leaf's strip is narrow, and few small items end up in it: as many are
	# checked as were found; zero is an honest answer too.
	gut.p("kind %d: details checked at doors %d" % [kind, checked])


## The floor whose height contains [param y]: from the floor of the floor above to its
## own floor. Furniture stands with its bottom on the floor, and some models have the
## mesh origin a centimeter lower: without the [constant STORY_SLACK] slack, a detail
## belonged to the floor below. There are no details above the hall ceiling, and the
## slack does not touch the floor above.
func _story_of(rules: BuildingRules, y: float) -> int:
	return int(ceilf((y - STORY_SLACK - rules.sky_height) / rules.floor_height)) - 1


func _level(kind: BuildingIdentity.Kind, building_seed: int = 1) -> GreyboxLevel:
	GameState.instance().start_game()
	GameState.instance().building = BuildingIdentity.first_of(kind, building_seed)
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	var rules := BuildingRules.new()
	rules.floors = 30
	rules.documents_cap = 0
	level.rules = rules
	level.building_seed = building_seed
	level.spawn_agents = false
	add_child_autofree(level)
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	return level
