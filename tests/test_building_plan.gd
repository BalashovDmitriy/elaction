extends GutTest

## Building layout tests.
##
## The layout knows nothing about nodes: it is computed from the rules and the seed, so it is
## checked directly. The main thing guarded here is passability: shafts do not go through,
## and if the generator forgets an escalator at a band junction, there is no way down.

## Seeds the layout rules are checked on. The building is random, and one
## check on one seed confirms only that seed — while holes show up on rare ones.
const SEEDS: Array[int] = [1, 2, 3, 5, 8, 13, 21, 34]


func _rules() -> BuildingRules:
	return BuildingRules.new()


## Building fingerprint: two runs with the same seed are compared by it.
func _fingerprint(plan: BuildingPlan) -> String:
	var parts := PackedStringArray()
	for shaft in plan.shafts:
		parts.append("s%d:%d:%.0f" % [shaft.top, shaft.bottom, shaft.x])
	for escalator in plan.escalators:
		parts.append("e%d:%.0f" % [escalator.floor_index, escalator.x])
	for door in plan.doors:
		parts.append("d%d:%.0f:%s" % [door.floor_index, door.x, door.has_document])
	for lamp in plan.lamps:
		parts.append("l%d:%.0f" % [lamp.floor_index, lamp.x])
	return "|".join(parts)


func test_same_seed_builds_the_same_building() -> void:
	var first := BuildingPlan.generate(_rules(), 7)
	var second := BuildingPlan.generate(_rules(), 7)
	assert_eq(_fingerprint(first), _fingerprint(second), "the seed defines the whole building")


func test_another_seed_moves_the_documents() -> void:
	var first := BuildingPlan.generate(_rules(), 1)
	var second := BuildingPlan.generate(_rules(), 2)
	assert_ne(_fingerprint(first), _fingerprint(second), "buildings differ")


func test_building_holds_exactly_the_wanted_documents() -> void:
	var rules := _rules()
	var plan := BuildingPlan.generate(rules, 6)
	assert_eq(plan.document_floors().size(), BuildingDocuments.count(rules, 6))


func test_documents_lie_on_different_floors() -> void:
	var plan := BuildingPlan.generate(_rules(), 8)
	var seen: Dictionary = {}
	for index: int in plan.document_floors():
		assert_false(seen.has(index), "no more than one red door per floor")
		seen[index] = true


func test_documents_are_spread_over_the_height() -> void:
	var rules := _rules()
	var plan := BuildingPlan.generate(rules, 9)
	var floors := plan.document_floors()
	var lowest: int = floors[floors.size() - 1]
	# Otherwise the whole building could be skipped.
	assert_gt(lowest, rules.floors / 2, "the lowest document is in the lower half of the building")
	assert_lt(floors[0], rules.floors / 2, "the top one is in the upper half")


func test_nothing_shares_a_place_on_a_floor() -> void:
	var rules := _rules()
	var plan := BuildingPlan.generate(rules, 10)
	var busy: Dictionary = {}

	for shaft in plan.shafts:
		for index in range(shaft.top, shaft.bottom + 1):
			_claim(busy, index, shaft.x)
	for escalator in plan.escalators:
		# The upper landing is on its own floor, the lower one at the edge of the floor below: a
		# 45° span takes two slots (ADR-0043, decision 15).
		_claim(busy, escalator.floor_index, escalator.x)
		_claim(busy, escalator.floor_index + 1, escalator.landing(rules))
	_claim(busy, plan.floors - 1, plan.exit_x)
	for door in plan.doors:
		_claim(busy, door.floor_index, door.x)
	for lamp in plan.lamps:
		_claim(busy, lamp.floor_index, lamp.x)


## The exit must not be placed on the respawn spot: otherwise Otto would leave the building
## right after coming back to life — and with the last document this would also finish
## the building by itself.
func test_otto_does_not_come_back_to_life_inside_the_exit() -> void:
	var rules := _rules()
	for building_seed in range(1, 12):
		var plan := BuildingPlan.generate(rules, building_seed)
		assert_ne(plan.safe_x(rules, plan.floors - 1), plan.exit_x, "seed %d" % building_seed)


## The respawn spot must not fall into an opening: falling right after death is not it.
func test_safe_spot_never_hangs_over_a_hole() -> void:
	var rules := _rules()
	var plan := BuildingPlan.generate(rules, 12)
	for index in plan.floors:
		var x := plan.safe_x(rules, index)
		for escalator in plan.escalators:
			if escalator.floor_index != index:
				continue
			var gap := escalator.gap(rules)
			assert_false(x >= gap.x and x <= gap.y, "floor %d stands above the opening" % index)


## Above the roof is sky, there is nothing to hang a lamp on: it would hang in the air.
func test_no_lamp_hangs_over_the_roof() -> void:
	var plan := BuildingPlan.generate(_rules(), 13)
	for lamp in plan.lamps:
		assert_gt(lamp.floor_index, BuildingRules.ROOF, "no ceiling above the roof")


## Floor zero stopped being the roof and finally gets a lamp: it has a ceiling
## now, and before that the whole top of the building was the only floor without light.
func test_the_top_floor_gets_a_lamp_now_that_it_has_a_ceiling() -> void:
	var plan := BuildingPlan.generate(_rules(), 13)
	var on_top := 0
	for lamp in plan.lamps:
		if lamp.floor_index == 0:
			on_top += 1
	assert_gt(on_top, 0, "the top floor has a ceiling, so it has a lamp")


## A floor has as many lamps as its width asks for — if there were enough slots: lamps
## give way to doors, shafts and escalators. A dark floor of the map gets none
## (ADR-0028, decision 4); any other gets at least one.
func test_floors_get_as_many_lamps_as_their_width_asks() -> void:
	var rules := _rules()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for index: int in rules.floors:
			var on_floor := _lamps_on(plan, index)
			if rules.is_unlit(index):
				assert_eq(
					on_floor.size(),
					0,
					"seed %d: dark floor %d with a lamp" % [building_seed, index]
				)
				continue
			assert_gte(
				on_floor.size(), 1, "seed %d: floor %d without lamps" % [building_seed, index]
			)
			assert_lte(
				on_floor.size(),
				rules.lamps_on(index),
				"seed %d: floor %d — more lamps than the width asks for" % [building_seed, index]
			)
		assert_gt(
			_lamps_on(plan, rules.floors - 1).size(),
			_lamps_on(plan, 0).size(),
			"seed %d: more lamps at the bottom than at the top" % building_seed
		)


## Lamps do not bunch up at one end of a floor: each one's zone is a unit of darkness, and
## a floor with lamps in one corner is dark in the other with all of them lit. Lamps take
## the free slots nearest to the middles of their zones, so on a crowded floor
## they may stand side by side — but the middle between them stays in the middle of the floor.
func test_lamps_are_spread_along_the_floor() -> void:
	var rules := _rules()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for index: int in rules.floors:
			var on_floor := _lamps_on(plan, index)
			if on_floor.size() < 2:
				continue
			var span := rules.floor_span(index)
			var quarter := (span.y - span.x) * 0.25
			var mean := 0.0
			for x in on_floor:
				mean += x
			mean /= float(on_floor.size())
			assert_between(
				mean,
				span.x + quarter,
				span.y - quarter,
				"seed %d: floor %d — lamps bunched at one edge" % [building_seed, index]
			)
			assert_gt(
				on_floor[on_floor.size() - 1] - on_floor[0],
				0.0,
				"seed %d: floor %d — two lamps in one place" % [building_seed, index]
			)


## A crowded building: floors where the shaft, escalators and the mandatory door leave
## no free slot for a lamp. Such a floor must still get a lamp —
## otherwise it is not lit and there is nothing to put out, and the darkness rule considers it
## lit forever.
##
## The layout's fallback branch (a lamp shares a slot with a door) does not fire under these
## rules since M20: lamps are placed before extra doors, there is one mandatory door, and
## the exit floor, where the exit, shaft and door used to eat all three slots, became
## a garage without doors (ADR-0031, decision 4). The branch is kept as insurance for
## rules that do not exist yet; the test holds the guarantee — a lamp on every lit floor.
func test_a_crowded_floor_still_gets_a_lamp() -> void:
	var rules := _rules()
	# Three slots, not five: since M18e doors beyond the mandatory one are placed after lamps
	# (ADR-0028, decision 2), and with five slots there is always room for a lamp.
	rules.slots = 3
	rules.top_slots = 3
	rules.width = 16.8
	rules.floors = 6
	# A building of one width: the threshold is below the bottom, and there is no narrow part
	# at all.
	rules.wide_from = 0
	rules.documents_cap = 1
	rules.doors_cap = 3
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for index: int in rules.floors:
			var on_floor := _lamps_on(plan, index)
			if rules.is_unlit(index):
				continue
			assert_gte(
				on_floor.size(),
				1,
				"seed %d: floor %d is left without a single lamp" % [building_seed, index]
			)


func _lamps_on(plan: BuildingPlan, floor_index: int) -> PackedFloat64Array:
	var xs := PackedFloat64Array()
	for lamp in plan.lamps:
		if lamp.floor_index == floor_index:
			xs.append(lamp.x)
	xs.sort()
	return xs


## The roof is a place, not a floor: agents do not appear on it because there are no doors.
## While it was floor zero, two stood in the line of fire from the starting point.
func test_the_roof_carries_no_doors() -> void:
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(_rules(), building_seed)
		for door in plan.doors:
			assert_gt(door.floor_index, BuildingRules.ROOF, "seed %d" % building_seed)


## Everything the layout places must stand inside the silhouette of its level:
## beyond it is the street, and a door there would hang in the air.
func test_nothing_is_placed_outside_its_own_floor() -> void:
	var rules := _rules()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for door in plan.doors:
			var span := rules.floor_span(door.floor_index)
			assert_true(
				door.x > span.x and door.x < span.y,
				"seed %d: door on floor %d behind the wall" % [building_seed, door.floor_index]
			)
		for lamp in plan.lamps:
			var span := rules.floor_span(lamp.floor_index)
			assert_true(
				lamp.x > span.x and lamp.x < span.y,
				"seed %d: lamp on floor %d behind the wall" % [building_seed, lamp.floor_index]
			)


func _claim(busy: Dictionary, floor_index: int, x: float) -> void:
	var key := "%d:%.0f" % [floor_index, x]
	assert_false(busy.has(key), "spot %s taken twice" % key)
	busy[key] = true


## Slots are not shared — but the footprints must not overlap either.
##
## A slot is a grid point, and the thing on it is a band: a door leaf 1.2 m, a shaft
## opening 1.8, a lamp 0.6, a wall 0.9. With a 1.8 m step (ADR-0026, decision 3) a slot is
## almost fully taken, and neighbours are left 0.6 m apart. A slot check does not
## see this: two neighbouring shafts would each stand in their own slot and close up
## with no floor between them.
##
## A shaft opening counts on all its levels, the bottom included: the cab stands there too.
## An escalator opening counts only on its floor: on the floor below there is floor there.
func test_nothing_on_a_floor_overlaps_its_neighbours() -> void:
	var rules := _rules()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for index: int in rules.levels():
			var bands := _footprints(plan, rules, index)
			bands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
			for number in range(1, bands.size()):
				var before: Array = bands[number - 1]
				var after: Array = bands[number]
				assert_lte(
					before[1] as float,
					(after[0] as float) + 0.001,
					(
						"seed %d, floor %d: %s overlaps %s"
						% [building_seed, index, before[2], after[2]]
					)
				)


## Two shafts in neighbouring slots would close up: there would be no floor left between
## them, and one could step out of a cab only into the neighbouring one.
func test_shafts_never_stand_side_by_side() -> void:
	var rules := _rules()
	var pitch := rules.slot_x(1) - rules.slot_x(0)
	for building_seed: int in range(1, 41):
		var plan := BuildingPlan.generate(rules, building_seed)
		for one in plan.shafts:
			for other in plan.shafts:
				if one == other or one.top > other.bottom or other.top > one.bottom:
					continue
				assert_gt(
					absf(one.x - other.x),
					pitch * 1.5,
					"seed %d: shafts %d and %d are adjacent" % [building_seed, one.slot, other.slot]
				)


## Bands items take on a floor: [left edge, right edge, what it is].
func _footprints(plan: BuildingPlan, rules: BuildingRules, index: int) -> Array:
	var bands: Array = []
	var shaft_half := rules.shaft_width * 0.5
	for shaft in plan.shafts:
		if shaft.top <= index and index <= shaft.bottom:
			bands.append([shaft.x - shaft_half, shaft.x + shaft_half, "shaft"])
	for escalator in plan.escalators:
		if escalator.floor_index == index:
			var gap := escalator.gap(rules)
			bands.append([gap.x, gap.y, "escalator"])
	var door_half := Door.LEAF_SIZE.x * 0.5
	for door in plan.doors:
		if door.floor_index == index:
			bands.append([door.x - door_half, door.x + door_half, "door"])
	if index == plan.floors - 1:
		var exit_half := BuildingShell.EXIT_WIDTH * 0.5
		bands.append([plan.exit_x - exit_half, plan.exit_x + exit_half, "exit"])
	var wall_half := rules.inner_wall_width * 0.5
	for wall in plan.walls:
		if wall.floor_index == index:
			bands.append([wall.x - wall_half, wall.x + wall_half, "wall"])
	return bands


## Floor between two openings — either there is none at all, or a body fits on it.
##
## A strip narrower than a body is a trap: one cannot stand on it, and an agent who came out
## of a cab bumps into it with his probe and freezes half his body in the shaft. With a
## 1.8 m step this came from an escalator going down to a shaft one slot away: 0.6 m of
## floor against a 0.72 body (code review M18c).
func test_floor_between_openings_fits_a_body() -> void:
	var rules := _rules()
	for building_seed: int in range(1, 41):
		var plan := BuildingPlan.generate(rules, building_seed)
		for index: int in rules.levels():
			var holes: Array = []
			for band: Array in _footprints(plan, rules, index):
				if band[2] == "shaft" or band[2] == "escalator":
					holes.append(band)
			holes.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
			for number in range(1, holes.size()):
				var strip: float = (holes[number][0] as float) - (holes[number - 1][1] as float)
				if strip <= 0.001:
					continue
				assert_gte(
					strip,
					Proportions.BODY_WIDTH,
					(
						"seed %d, floor %d: between %s and %s there is %.2f m of floor"
						% [building_seed, index, holes[number - 1][2], holes[number][2], strip]
					)
				)
