extends GutTest

## Tests of shafts and escalators: what the descent is made of.
##
## Since M18 shafts overlap and the number of routes grows toward the bottom (ADR-0024, decision 3),
## and escalators stand in a band at the threshold and at overlap gaps (decision 4). Both
## things are checked by the layout, without nodes and a scene, and therefore on dozens of seeds
## in fractions of a second — and holes in generation show up exactly on rare ones.
##
## In its own file, not in [code]test_building_plan.gd[/code]: that one hit the ceiling
## of public methods, and the descent is its largest part.

## Seeds the rules are checked on. The building is random, and one check on
## one seed confirms only that seed.
const SEEDS: Array[int] = [1, 2, 3, 5, 8, 13, 21, 34]


func _rules() -> BuildingRules:
	return BuildingRules.new()


## A floor without a shaft is a floor one cannot ride away from. Overlap here
## is not only allowed but required toward the bottom: ADR-0024, decision 3.
func test_shafts_cover_every_floor() -> void:
	var rules := _rules()
	var plan := BuildingPlan.generate(rules, 3)
	var serving: Dictionary = {}
	for shaft in plan.shafts:
		for index in range(shaft.top, shaft.bottom + 1):
			serving[index] = int(serving.get(index, 0)) + 1

	for index: int in rules.levels():
		assert_true(serving.has(index), "level %d is left without a shaft" % index)
	assert_true(serving.has(BuildingRules.ROOF), "the top shaft reaches the roof")


## A short shaft is not a shaft: the cab in it has nowhere to go.
##
## Length is set by [code]_shaft_length[/code], but the bottom is cut at the building's bottom, and
## a band opened at the very bottom came out shorter than the rule — on seed 2 one such
## stood on floor 29 all on its own. This is caught only on a rare seed,
## so the check runs over all of them at once.
##
## The threshold is [constant BuildingRules.MIN_SHAFT_FLOORS], four floors, and four is
## not accidental: the M18b two-storey pair travels only between [code]top + 1[/code] and
## [code]bottom - 1[/code], and in a shorter shaft it has nowhere to go (ADR-0025,
## decision 2).
func test_no_shaft_is_too_short_to_ride() -> void:
	var rules := _rules()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for shaft in plan.shafts:
			assert_gte(
				shaft.bottom - shaft.top + 1,
				BuildingRules.MIN_SHAFT_FLOORS,
				(
					"seed %d: the shaft at x=%.1f serves floors %d..%d"
					% [building_seed, shaft.x, shaft.top, shaft.bottom]
				)
			)


## The lower, the more routes — the main conclusion of the check against the original, where on
## the bottom seven floors five shafts converge, while in the upper third one works.
func test_paths_multiply_towards_the_ground() -> void:
	var rules := _rules()
	for building_seed in range(1, 12):
		var plan := BuildingPlan.generate(rules, building_seed)
		var serving: Dictionary = {}
		for shaft in plan.shafts:
			for index in range(shaft.top, shaft.bottom + 1):
				serving[index] = int(serving.get(index, 0)) + 1

		for index: int in rules.levels():
			var here := int(serving.get(index, 0))
			var wanted := rules.shafts_on(index)
			assert_eq(here, wanted, "seed %d: floor %d is served wrongly" % [building_seed, index])

		var top := int(serving.get(BuildingRules.ROOF, 0))
		var above := int(serving.get(rules.floors - 2, 0))
		var bottom := int(serving.get(rules.floors - 1, 0))
		assert_eq(top, 1, "at the top the way down has no alternative")
		assert_eq(above, rules.shafts_max, "above the basement all of them meet")
		# To the basement — one, by draw, as in the ROM (ADR-0038, decision 3).
		assert_eq(bottom, 1, "one goes down to the basement")


func test_neighbouring_shafts_stand_in_different_columns() -> void:
	var plan := BuildingPlan.generate(_rules(), 4)
	for index in plan.shafts.size() - 1:
		var here := plan.shafts[index].x
		var below := plan.shafts[index + 1].x
		assert_ne(here, below, "otherwise going down would boil down to 'hold down'")


## From the bottom of a shaft one has to get down somehow: either another shaft takes this floor
## and the next one at once, or an escalator stands on the floor (ADR-0024, decision 4).
##
## Before M18 shafts ran end to end and an escalator had to stand at every joint. Now
## shafts overlap, and an escalator is needed only where there is no overlap.
func test_every_shaft_bottom_is_bridged() -> void:
	for building_seed in range(1, 12):
		var plan := BuildingPlan.generate(_rules(), building_seed)
		var bridged: Dictionary = {}
		for escalator in plan.escalators:
			bridged[escalator.floor_index] = true

		for shaft in plan.shafts:
			if shaft.bottom >= plan.floors - 1:
				continue
			var overlapped := false
			for other in plan.shafts:
				if other.top <= shaft.bottom and other.bottom > shaft.bottom:
					overlapped = true
					break
			var where := "floor %d, seed %d" % [shaft.bottom, building_seed]
			assert_true(
				overlapped or bridged.has(shaft.bottom),
				"one must get down from the shaft bottom somehow: " + where
			)


## Escalators live in a band at the threshold, where the tower shaft ends above the podium
## (ADR-0024, decision 4). Everything outside the band is justified by a gap: a shaft ended
## there and no other one covered that joint.
func test_escalators_live_in_the_band_or_bridge_a_gap() -> void:
	var rules := _rules()
	for building_seed in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		var in_band := 0
		for escalator in plan.escalators:
			var index := escalator.floor_index
			if rules.in_escalator_band(index):
				in_band += 1
				continue
			var ends_here := false
			for shaft in plan.shafts:
				if shaft.bottom == index:
					ends_here = true
					break
			var where := "seed %d, floor %d" % [building_seed, index]
			assert_true(
				ends_here, "an escalator outside the band is justified by a break: " + where
			)
		assert_gt(in_band, 0, "seed %d: the escalator band is empty" % building_seed)


## The escalator opening lies to the side of the landing, and one must reach it without crossing it.
## Otherwise Otto, walking from the lift, falls to the floor below past the escalator.
func test_escalator_pad_shields_its_gap_from_the_shaft() -> void:
	var rules := _rules()
	for building_seed in range(1, 12):
		var plan := BuildingPlan.generate(rules, building_seed)
		for escalator in plan.escalators:
			var from_x := _shaft_x_on(plan, escalator.floor_index)
			var gap := escalator.gap(rules)
			var near := minf(from_x, escalator.x)
			var far := maxf(from_x, escalator.x)
			assert_false(
				near < gap.y and gap.x < far,
				(
					"seed %d, floor %d: a gap between the lift and the landing"
					% [building_seed, escalator.floor_index]
				)
			)


## A shaft passes through floors of different widths, and its column must stand
## on each of them: the building widens toward the bottom, the tightest is the top of the band.
func test_every_shaft_stands_on_a_slot_its_whole_band_offers() -> void:
	var rules := _rules()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for shaft in plan.shafts:
			for index in range(shaft.top, shaft.bottom + 1):
				var span := rules.floor_span(index)
				var half := rules.shaft_width * 0.5
				assert_true(
					shaft.x - half >= span.x and shaft.x + half <= span.y,
					"seed %d: the shaft on floor %d went outside the wall" % [building_seed, index]
				)


## The passenger passes through the opening, not through the slab.
##
## Since M18b the ride polyline is a landing along the floor up to the opening and one straight
## flight down ([ADR-0025](../docs/adr/0025-shafts-escalators-and-riders.md), decision 4).
## The bend is moved inside the hole by [constant EscalatorSpot.BEND_CLEARANCE],
## and the whole margin there is 15 cm: what goes through the opening is not a line but a body
## half a torso wide. It is changed by one number in the rules — the opening width or
## its offset — and then the shoulder gets eaten silently.
##
## Both dangerous points are checked: the start of the flight, where it enters the slab,
## and its exit from under the slab one floor below.
func test_escalator_carries_its_rider_through_the_gap() -> void:
	var rules := _rules()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for escalator in plan.escalators:
			var gap := escalator.gap(rules)
			var bend_x := escalator.x + escalator.bend(rules).x
			var end_x := escalator.x + escalator.towards * rules.escalator_run
# Where the flight comes out from under the slab: the share of the descent done to its underside.
			var under := bend_x + (end_x - bend_x) * rules.slab_height / rules.floor_height
			for at: float in [bend_x, under]:
				assert_true(
					at - OttoBot.BODY_HALF_WIDTH >= gap.x and at + OttoBot.BODY_HALF_WIDTH <= gap.y,
					(
						"seed %d, floor %d: the passenger at x=%.2f does not fit the opening %.2f..%.2f"
						% [building_seed, escalator.floor_index, at, gap.x, gap.y]
					)
				)


func _shaft_x_on(plan: BuildingPlan, floor_index: int) -> float:
	for shaft in plan.shafts:
		if floor_index >= shaft.top and floor_index <= shaft.bottom:
			return shaft.x
	return 0.0


## No more than two pairs per building, and each stands in a shaft that holds it.
##
## "A two-storey cab in a three-floor shaft" is a motionless lift: the decks
## take up two floors in height, and only one remains to travel (ADR-0025,
## decision 2). So not only the number of pairs is checked, but also that the range
## of their travel has not degenerated.
func test_double_deck_pairs_are_few_and_fit_their_shaft() -> void:
	var rules := _rules()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		var pairs := 0
		for shaft in plan.shafts:
			if not shaft.double_deck:
				continue
			pairs += 1
			var span := shaft.ride_span()
			assert_gte(
				shaft.height(),
				BuildingRules.MIN_SHAFT_FLOORS,
				"seed %d: a pair in a shaft of %d floors" % [building_seed, shaft.height()]
			)
			assert_lt(
				span.x,
				span.y,
				(
					"seed %d: a pair in the shaft %d..%d has nowhere to go"
					% [building_seed, shaft.top, shaft.bottom]
				)
			)
		assert_lte(
			pairs, BuildingDecks.MOST, "seed %d: pairs in the building %d" % [building_seed, pairs]
		)


## A pair appears in every building where there is room for it.
##
## A measurement, not a wish: "not in every building, about one in three" from
## ADR-0024 was a made-up number, and with it most games would never see
## the curiosity. The room condition is strict, so the share is measured
## by number — if it ever drops, it will be visible here, not in the game.
func test_double_deck_shows_up_in_every_building() -> void:
	var rules := _rules()
	var with_pair := 0
	for building_seed in range(1, 41):
		var plan := BuildingPlan.generate(rules, building_seed)
		for shaft in plan.shafts:
			if shaft.double_deck:
				with_pair += 1
				break
	assert_eq(with_pair, 40, "a pair found a shaft in each of the forty buildings")


## A pair does not block the descent: a building with it is traversable on any seed.
##
## Guards the reason a pair is placed last and removed on breakage:
## the condition "every floor has another route" looks at the floor as a whole, while people walk
## on floor pieces, and the neighbouring shaft may turn out to be beyond an opening.
func test_double_deck_never_locks_the_descent() -> void:
	var rules := _rules()
	for building_seed in range(1, 41):
		var plan := BuildingPlan.generate(rules, building_seed)
		var missing := BuildingRoute.unreachable_spots(plan, rules)
		assert_true(missing.is_empty(), "seed %d: unreachable - %s" % [building_seed, missing])
