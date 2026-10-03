extends GutTest

## Building by the original's map (ADR-0028): doors, red doors and dark floors
## by ROM tables — on any seed and any skill, not on a single building.
##
## The building is generated, so what is checked is not "this level is correct" but "any
## building that gets generated is correct" (`docs/testing.md`).

const SEEDS: Array[int] = [1, 2, 3, 5, 8, 13, 21, 34]

## Skills: the first building, the middle and the one where red quotas no longer grow.
const SKILLS: Array[int] = [0, 3, 8]


func _rules(skill: int) -> BuildingRules:
	var rules := BuildingRules.new()
	rules.skill = skill
	return rules


func _doors_on(plan: BuildingPlan, floor_index: int) -> int:
	var count := 0
	for door in plan.doors:
		if door.floor_index == floor_index:
			count += 1
	return count


## Doors on a floor are no more than the map's number for the width and at least one where the map
## gives them; on ROM floor seven and on the roof — none.
func test_doors_follow_the_map_on_any_building() -> void:
	for skill: int in SKILLS:
		var rules := _rules(skill)
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			for index: int in rules.levels():
				var placed := _doors_on(plan, index)
				var wanted := rules.doors_on(index)
				var where := "skill %d, seed %d, floor %d" % [skill, building_seed, index]
				assert_lte(placed, wanted, where + ": more doors than the map has")
				if wanted > 0:
					assert_gte(placed, 1, where + ": no doors at all")
				else:
					assert_eq(placed, 0, where + ": doors where the map puts none")


## A floor in the frame is not emptier than the original: doors stand by the map while room remains.
##
## On a floor without escalators there are exactly as many doors as the map gives, or
## as many as slots remain after shafts, lamps and the exit. Floors with a wall
## are skipped: a wall takes slots next to itself. An escalator
## takes slots both on its own floor and on the one below, and its floors are checked only
## from above: in the tower's escalator band they eat four slots out of seven, and
## there is one door there (ADR-0028, decision 2).
func test_floors_hold_their_map_doors_while_there_is_room() -> void:
	for skill: int in SKILLS:
		var rules := _rules(skill)
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			for index: int in rules.floors:
				if _touched_by_an_escalator(plan, index) or _has_a_wall(plan, index):
					continue
				var span := rules.slot_range(index)
				var room := span.y - span.x + 1 - _shafts_on(plan, index) - _lamps_on(plan, index)
				if index == rules.floors - 1:
					room -= 1
				assert_eq(
					_doors_on(plan, index),
					mini(rules.doors_on(index), maxi(room, 0)),
					"skill %d, seed %d, floor %d" % [skill, building_seed, index]
				)


## The wide base is not emptier than the original's screen: at least as many doors as the
## original has on one screen.
func test_wide_floors_are_not_emptier_than_a_screen_of_the_original() -> void:
	var rules := _rules(0)
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		# The exit floor is a garage without doors, like the original's basement (ADR-0031, decision 4).
		for index: int in rules.floors - 1:
			if not rules.is_wide(index):
				continue
			var rom := Arcade.rom_floor(index, rules.floors)
			assert_gte(
				_doors_on(plan, index),
				Arcade.doors_on_floor(rom),
				(
					"seed %d: wide floor %d is emptier than the original screen"
					% [building_seed, index]
				)
			)


func _has_a_wall(plan: BuildingPlan, floor_index: int) -> bool:
	for wall in plan.walls:
		if wall.floor_index == floor_index:
			return true
	return false


func _touched_by_an_escalator(plan: BuildingPlan, floor_index: int) -> bool:
	for escalator in plan.escalators:
		if escalator.floor_index == floor_index or escalator.floor_index + 1 == floor_index:
			return true
	return false


func _shafts_on(plan: BuildingPlan, floor_index: int) -> int:
	var count := 0
	for shaft in plan.shafts:
		if shaft.top <= floor_index and shaft.bottom >= floor_index:
			count += 1
	return count


func _lamps_on(plan: BuildingPlan, floor_index: int) -> int:
	var count := 0
	for lamp in plan.lamps:
		if lamp.floor_index == floor_index:
			count += 1
	return count


## As many red doors as the draw gave, one per floor, and in each
## band — the ROM column quota for that number (ADR-0037, decision 8).
func test_documents_follow_the_rom_bands() -> void:
	for skill: int in SKILLS:
		var rules := _rules(skill)
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			var floors := plan.document_floors()
			var where := "skill %d, seed %d" % [skill, building_seed]
			var wanted := BuildingDocuments.count(rules, building_seed)
			var column := BuildingDocuments.column(rules, building_seed)
			assert_eq(floors.size(), wanted, where + ": documents")
			assert_eq(Arcade.red_doors(column), wanted, where + ": ROM column with the same count")
			var per_band: Dictionary = {}
			var seen: Dictionary = {}
			for index: int in floors:
				assert_false(seen.has(index), where + ": two red doors on floor %d" % index)
				seen[index] = true
				var rom := Arcade.rom_floor(index, rules.floors)
				for band: int in Arcade.RED_DOOR_BANDS.size():
					var span := Arcade.RED_DOOR_BANDS[band]
					if rom >= span.x and rom <= span.y:
						per_band[band] = int(per_band.get(band, 0)) + 1
			for band: int in Arcade.RED_DOOR_BANDS.size():
				assert_eq(
					int(per_band.get(band, 0)),
					Arcade.red_doors_in_band(band, column),
					where + ": band %d" % band
				)


## Ten documents at skill eight are reachable just like five at skill zero.
func test_every_building_can_be_finished_on_any_skill() -> void:
	for skill: int in SKILLS:
		var rules := _rules(skill)
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			assert_true(
				BuildingRoute.is_winnable(plan, rules),
				"skill %d, seed %d: the building cannot be completed" % [skill, building_seed]
			)


## Dark floors of the map — ROM 11–15 — without lamps, other floors — with at least one.
func test_dark_floors_carry_no_lamps() -> void:
	var rules := _rules(0)
	var dark := 0
	for index: int in rules.floors:
		if rules.is_unlit(index):
			dark += 1
	assert_eq(dark, 5, "five dark floors, as in the original")
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		var lamps: Dictionary = {}
		for lamp in plan.lamps:
			lamps[lamp.floor_index] = true
		for index: int in rules.floors:
			assert_eq(
				lamps.has(index),
				not rules.is_unlit(index),
				"seed %d, floor %d: lamp is not per the map" % [building_seed, index]
			)


## Salt zero — the seed equals the building number, as before M18e; different salt — different
## buildings (ADR-0028, decision 6).
func test_salt_changes_the_building_and_zero_keeps_it() -> void:
	var game: GameState = autofree(GameState.new())
	game.building = 3
	game.salt = 0
	assert_eq(game.building_seed(), 3, "without salt the seed is the building number")
	game.salt = 12345
	var salted := game.building_seed()
	assert_ne(salted, 3, "salt changes the seed")
	game.salt = 54321
	assert_ne(game.building_seed(), salted, "different salt - different seed")

	var rules := _rules(0)
	var plain := BuildingPlan.generate(rules, 3)
	var other := BuildingPlan.generate(rules, salted)
	assert_ne(plain.document_floors(), other.document_floors(), "a different building")


## Dense doors do not crowd out walls: walls are placed before doors beyond the
## mandatory one. When it was the other way round, 22 of 156 remained on the tower over 120
## buildings (code review M18e); at the [member BuildingRules.wall_chance] rate over
## the same 120 buildings there are about a hundred and forty.
##
## 120 buildings, not 24 as before: on 24 the draw spread is of the same order as
## the margin to the threshold — with the basement shaft (M24b) the same 24 gave 18 walls at
## the former average, and the test failed on reshuffling, not on crowding out.
func test_dense_doors_leave_room_for_walls_in_the_tower() -> void:
	var tower := 0
	for skill: int in SKILLS:
		var rules := _rules(skill)
		for building_seed: int in range(1, 41):
			var plan := BuildingPlan.generate(rules, building_seed)
			for wall in plan.walls:
				if not rules.is_wide(wall.floor_index):
					tower += 1
	assert_gte(tower, 100, "walls on the tower %d - doors pushed them out" % tower)


## Documents 5–10 by draw from the seed, from the first building (ADR-0037, decision 8):
## at any skill the whole spread comes up, and one building repeats.
func test_the_document_count_is_drawn_per_building() -> void:
	for skill: int in [0, 8]:
		var rules := _rules(skill)
		var seen: Dictionary = {}
		for building_seed: int in 200:
			var wanted := BuildingDocuments.count(rules, building_seed)
			assert_between(wanted, BuildingDocuments.FEWEST, BuildingDocuments.MOST)
			assert_eq(
				wanted, BuildingDocuments.count(rules, building_seed), "the seed repeats the count"
			)
			seen[wanted] = true
		for wanted: int in range(BuildingDocuments.FEWEST, BuildingDocuments.MOST + 1):
			assert_true(seen.has(wanted), "skill %d: %d also comes up" % [skill, wanted])
