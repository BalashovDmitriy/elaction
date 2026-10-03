extends GutTest

## Building passability tests.
##
## The building is a pure function of the seed, so what needs checking is not "this level
## works" but "any building that gets generated works". The three M5a bugs did not show
## up on all seeds — on seed 1 they were not visible.

const SEEDS: int = 40


func _rules() -> BuildingRules:
	return BuildingRules.new()


func test_every_building_can_be_finished() -> void:
	var rules := _rules()
	for building_seed in range(1, SEEDS + 1):
		var plan := BuildingPlan.generate(rules, building_seed)
		var missing := BuildingRoute.unreachable_spots(plan, rules)
		assert_true(missing.is_empty(), "сид %d: недостижимо — %s" % [building_seed, missing])


func test_start_is_reachable_from_itself() -> void:
	var rules := _rules()
	var plan := BuildingPlan.generate(rules, 1)
	assert_false(BuildingRoute.reachable(plan, rules).is_empty())


func test_route_reaches_every_floor() -> void:
	var rules := _rules()
	var plan := BuildingPlan.generate(rules, 2)
	var seen := BuildingRoute.reachable(plan, rules)

	var floors_seen: Dictionary = {}
	for node: String in seen:
		floors_seen[node.split(":")[0]] = true
	assert_eq(floors_seen.size(), rules.floors + 1, "до каждого уровня можно добраться")


## Passability must be caught, not always confirmed.
##
## Before M18 the building was broken by removing the escalators: shaft bands met end to
## end and did not connect without them. Now the shafts overlap (ADR-0024, decision 3),
## and without escalators the descent remains — it has to be broken differently.
func test_an_isolated_bottom_floor_is_not_winnable() -> void:
	var rules := _rules()
	var plan := BuildingPlan.generate(rules, 3)
	assert_true(BuildingRoute.is_winnable(plan, rules), "целое здание проходимо")

	var bottom := plan.floors - 1
	var kept: Array[BuildingPlan.ShaftSpot] = []
	for shaft in plan.shafts:
		if shaft.bottom < bottom:
			kept.append(shaft)
	plan.shafts = kept
	plan.escalators.clear()
	assert_false(BuildingRoute.is_winnable(plan, rules), "до отрезанного низа не добраться")


## A wall cuts walking but not the slab (ADR-0024, decision 5). There are two
## computations, and they must not diverge: a floor with a wall stays a whole slab, which
## still cannot be crossed.
func test_a_wall_cuts_walking_but_not_the_slab() -> void:
	var rules := _rules()
	var plan := BuildingPlan.generate(rules, 4)
	var index := plan.floors - 1
	var span := rules.floor_span(index)

	var before := BuildingPlan.spans_between(plan.blocks_on(rules, index), span)
	var wall := BuildingPlan.WallSpot.new()
	wall.floor_index = index
	wall.x = (span.x + span.y) * 0.5
	plan.walls.append(wall)

	var slab := BuildingPlan.spans_between(plan.gaps_on(rules, index), span)
	var walk := BuildingPlan.spans_between(plan.blocks_on(rules, index), span)
	assert_eq(slab.size(), 1, "нижний этаж — цельная плита, стена на ней стоит")
	assert_eq(walk.size(), before.size() + 1, "а ходьба разрезана ею надвое")


## The graph does not promise a ride the pair will not make.
##
## The decks are joined a floor apart, and whoever enters does not choose which of them
## meets him: the upper one does not go down to the shaft's bottom floor, the lower one
## does not go up to the top (ADR-0025, decision 1). Only what either of the two will
## deliver can be promised — otherwise the bot, planning such a ride, will hold "down"
## until its budget runs out, and the player will decide the elevator is broken.
##
## Crossing through the opening remains on all of the shaft's floors: the cab stops on
## them, and people pass through it from one edge to the other.
func test_a_pair_promises_only_what_both_decks_reach() -> void:
	var rules := _rules()
	var found := 0
	for building_seed in range(1, 21):
		var plan := BuildingPlan.generate(rules, building_seed)
		var graph := BuildingRoute.walkable(plan, rules)
		var moves: Dictionary = graph["moves"]
		for shaft in plan.shafts:
			if not shaft.double_deck:
				continue
			found += 1
			for from_node: String in moves:
				var from_floor := int(from_node.split(":")[0])
				for move: Dictionary in moves[from_node]:
					if move["kind"] != "shaft" or not is_equal_approx(move["x"], shaft.x):
						continue
					var to_floor := int(move["floor"])
					if to_floor == from_floor:
						continue
					# The column alone does not identify a shaft: bands do not overlap by
					# floor, but the same grid slot is taken by different shafts at
					# different heights.
					if not _inside(shaft, from_floor) or not _inside(shaft, to_floor):
						continue
					assert_true(
						shaft.rides_between(from_floor, to_floor),
						(
							"сид %d: шахта %d..%d с парой обещает %d -> %d"
							% [building_seed, shaft.top, shaft.bottom, from_floor, to_floor]
						)
					)
	assert_gt(found, 0, "на двадцати сидах хоть одна пара обязана выпасть")


## Whether the floor lies in the shaft's band.
func _inside(shaft: BuildingPlan.ShaftSpot, floor_index: int) -> bool:
	return floor_index >= shaft.top and floor_index <= shaft.bottom
