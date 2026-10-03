extends GutTest

## Building rules tests.
##
## All vertical arithmetic comes from here: where a floor surface is, which floor is
## closer to a point, where the ceiling is. The respawn spot after death and the geometry
## of the darkening band are computed by them too. And agent anger — it grows from two places
## at once, and the cap on it keeps the game passable.


func _rules() -> BuildingRules:
	var rules := BuildingRules.new()
	rules.floors = 30
	# The test building is its own small world in integers, and it is set in full:
	# all the lengths the checks below depend on. While part was taken from the
	# defaults, the test relied on 480 and 3840 being exact in any float; since
	# M15 the defaults are metric — 4.8 and 38.4 — and exact equalities drifted in the
	# last bit of the fraction ([Vector2] also stores float32).
	rules.floor_height = 120.0
	rules.slab_height = 20.0
	rules.sky_height = 160.0
	rules.width = 3840.0
	rules.margin = 240.0
	return rules


func test_the_roof_lies_above_the_top_floor() -> void:
	var rules := _rules()
	assert_lt(rules.floor_surface(BuildingRules.ROOF), rules.floor_surface(0))
	assert_eq(
		rules.floor_surface(0) - rules.floor_surface(BuildingRules.ROOF),
		rules.floor_height,
		"крыша отстоит от верхнего этажа на целый пролёт"
	)


## This is why floor zero was unplayable: a clearance of 20 px against 100 px
## for all the others, and Otto's head went past the top edge of the frame (ADR-0014).
func test_every_level_has_the_same_headroom() -> void:
	var rules := _rules()
	var expected := rules.floor_height - rules.slab_height
	for index: int in [0, 1, 7, rules.floors - 1]:
		var headroom := rules.floor_surface(index) - rules.story_top(index)
		assert_eq(headroom, expected, "этаж %d" % index)


func test_the_roof_has_sky_above_it() -> void:
	var rules := _rules()
	var roof := BuildingRules.ROOF
	assert_eq(rules.story_top(roof), 0.0, "над крышей край мира, а не перекрытие")
	assert_eq(rules.floor_surface(roof) - rules.story_top(roof), rules.sky_height)


## Otto's jump is 80 px. If it does not fit above the roof, the player flies out of frame.
func test_a_jump_from_the_roof_stays_inside_the_world() -> void:
	var rules := _rules()
	var otto := preload("res://src/actors/otto/otto.tscn").instantiate() as Otto
	var apex := otto.jump_speed * otto.jump_speed / (2.0 * otto.gravity)
	otto.free()
	assert_gt(rules.sky_height, apex, "над крышей должно быть выше прыжка")


func test_floors_go_down_by_their_height() -> void:
	var rules := _rules()
	assert_eq(rules.floor_surface(1) - rules.floor_surface(0), rules.floor_height)


func test_nearest_floor_is_the_one_underfoot() -> void:
	var rules := _rules()
	assert_eq(rules.floor_index_near(rules.floor_surface(4)), 4)
	assert_eq(rules.floor_index_near(rules.floor_surface(4) + 10.0), 4, "чуть ниже — тот же")


func test_nearest_floor_never_leaves_the_building() -> void:
	var rules := _rules()
	assert_eq(rules.floor_index_near(-500.0), BuildingRules.ROOF, "выше крыши уровней нет")
	assert_eq(rules.floor_index_near(100000.0), rules.floors - 1)


func test_nearest_level_finds_the_roof() -> void:
	var rules := _rules()
	var roof := BuildingRules.ROOF
	assert_eq(rules.floor_index_near(rules.floor_surface(roof)), roof)
	assert_eq(rules.floor_index_near(rules.floor_surface(roof) + 10.0), roof, "чуть ниже — та же")


func test_ceiling_is_the_underside_of_the_slab_above() -> void:
	var rules := _rules()
	var expected := rules.floor_surface(0) + rules.slab_height
	assert_eq(rules.story_top(1), expected)


func test_slots_spread_between_the_margins() -> void:
	var rules := _rules()
	assert_eq(rules.slot_x(0), rules.margin, "первое место — у левого отступа")
	assert_eq(rules.slot_x(rules.slots - 1), rules.width - rules.margin)


## Skill grows with every building and starts from the game's difficulty level — as
## in the ROM, where cleared buildings are added to the DIP switch (ADR-0027).
func test_skill_grows_building_by_building() -> void:
	assert_eq(BuildingRules.for_building(1).skill, 0, "первое здание на лёгком — ноль")
	assert_eq(BuildingRules.for_building(2).skill, 1, "каждое следующее — на единицу")
	assert_eq(BuildingRules.for_building(1, 3).skill, 3, "уровень сложности — стартовый навык")
	assert_eq(BuildingRules.for_building(5, 2).skill, 6)


## Manual agent cap — for runs; without it — the ROM's, three or four.
func test_agents_at_once_follow_the_rom_unless_capped() -> void:
	var rules := BuildingRules.new()
	assert_eq(rules.agents_at_once(0.0), 3, "с начала здания трое")
	rules.agents_at_once_cap = 7
	assert_eq(rules.agents_at_once(0.0), 7, "ручной потолок важнее")


func test_stance_heights_hold_together() -> void:
	var rules := BuildingRules.new()
	assert_lt(rules.agent_prone_height, rules.agent_kneel_height, "лёжа ниже, чем на колене")
	assert_gt(rules.agent_dark_fire_range, 0.0, "в темноте вплотную агент Otto видит")


## Lamps by width: a narrow top — one, a wide bottom — three. A row of fixtures along the
## ceiling, as in the reference, and one darkness zone each (ADR-0023). Dark
## floors of the map have no lamps, and the growth downwards does not count through them
## (ADR-0028).
func test_wider_floors_hang_more_lamps() -> void:
	var rules := _rules()
	assert_eq(rules.lamps_on(0), 1, "наверху одна лампа")
	assert_eq(rules.lamps_on(rules.floors - 1), 3, "внизу три")
	assert_eq(rules.lamps_on(BuildingRules.ROOF), 0, "у крыши ламп нет: ей светит город")
	var previous := 0
	for index: int in rules.floors:
		var count := rules.lamps_on(index)
		if rules.is_unlit(index):
			assert_eq(count, 0, "тёмный этаж %d с лампами" % index)
			continue
		assert_gte(count, 1, "этаж %d без ламп" % index)
		assert_lte(count, rules.lamps_per_floor, "этаж %d выше потолка" % index)
		assert_gte(count, previous, "этаж %d: книзу ламп не становится меньше" % index)
		previous = count
