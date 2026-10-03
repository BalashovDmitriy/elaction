extends GutTest

## Tests of inner walls splitting a floor in two (ADR-0024, decision 5).
##
## A wall is the only thing that cuts a floor without making a hole in it, and that is
## why it is more dangerous than an opening: an opening is visible, a locked half is not.
## Both where a wall stands and that it has locked nobody in are checked here.
##
## In its own file, not in [code]test_building_plan.gd[/code]: that one has already hit
## the ceiling of public methods, and walls are a separate story with their own count of
## floor pieces.

## Seeds on which the rules are checked. The building is random, and one check on one
## seed confirms only that seed — while holes come out on rare ones.
const SEEDS: Array[int] = [1, 2, 3, 5, 8, 13, 21, 34]


func _rules() -> BuildingRules:
	return BuildingRules.new()


## A wall stands on the slab and between slots, not over an opening: ADR-0024,
## decision 5. A wall over a shaft would hang in the air, and at the very edge it would
## cut off not half the floor but a strip with nothing to stand on.
func test_walls_stand_on_the_slab_between_the_openings() -> void:
	var rules := _rules()
	var floors_with_walls := 0
	for building_seed in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		floors_with_walls += plan.walls.size()
		for wall in plan.walls:
			var index := wall.floor_index
			var band := wall.band(rules)
			var where := "сид %d, этаж %d" % [building_seed, index]

			for gap: Vector2 in plan.gaps_on(rules, index):
				var over := band.y > gap.x and band.x < gap.y
				assert_false(over, "стена висит над проёмом: " + where)

			var span := rules.floor_span(index)
			var edge := rules.slot_x(1) - rules.slot_x(0)
			assert_gt(band.x, span.x + edge, "стена у самой стены: " + where)
			assert_lt(band.y, span.y - edge, "стена у самой стены: " + where)

	assert_gt(floors_with_walls, 0, "стены должны хоть где-то появляться")


## A wall does not grow through a shaft — on none of its levels, bottom included.
##
## The shaft bottom is the only level where there is no opening in the slab: the cab
## stands on it rather than passing through. The layout looked for a place for a wall by
## openings alone ([method BuildingPlan.gaps_on]), and at the bottom the shaft vanished
## for it: on seed 6 a wall grew 0.45 m into the cab of shaft 15..21, and on seed 7 into
## two at once. Otto entering such a cab ended up in the wall.
##
## The gap is measured the same as everywhere: half a grid step from the opening's edge
## (ADR-0024).
func test_no_wall_grows_through_a_shaft() -> void:
	var rules := _rules()
	var clearance := rules.slot_x(1) - rules.slot_x(0)
	var half := rules.shaft_width * 0.5
	for building_seed in range(1, 40):
		var plan := BuildingPlan.generate(rules, building_seed)
		for wall in plan.walls:
			var band := wall.band(rules)
			for shaft in plan.shafts:
				if shaft.top > wall.floor_index or shaft.bottom < wall.floor_index:
					continue
				assert_false(
					(
						band.y > shaft.x - half - clearance * 0.5
						and band.x < shaft.x + half + clearance * 0.5
					),
					(
						"сид %d: стена %.1f жмётся к шахте %.1f на этаже %d"
						% [building_seed, wall.x, shaft.x, wall.floor_index]
					)
				)


## A wall is not on every floor: it is a detour through another floor, and in a row they
## would turn the descent into a maze.
func test_walls_are_not_on_every_floor() -> void:
	var rules := _rules()
	for building_seed in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		var walled: Dictionary = {}
		for wall in plan.walls:
			assert_false(walled.has(wall.floor_index), "на этаже не больше одной стены")
			walled[wall.floor_index] = true
		var share := float(walled.size()) / float(rules.floors)
		assert_lt(share, 0.6, "сид %d: стены почти на каждом этаже" % building_seed)


## A wall that made a document or the exit unreachable is removed during layout. Checked
## on many seeds: not every wall locks, and not always.
func test_no_wall_locks_a_document_or_the_exit_away() -> void:
	var rules := _rules()
	for building_seed in range(1, 60):
		var plan := BuildingPlan.generate(rules, building_seed)
		var missing := BuildingRoute.unreachable_spots(plan, rules)
		assert_true(missing.is_empty(), "сид %d: заперто — %s" % [building_seed, str(missing)])


## A layout with walls must be heavier than a layout without them, otherwise the check
## above confirms not that the rejection works but that it is absent: a building where no
## walls appear at all is passable by itself.
func test_walls_really_cut_the_floors_they_stand_on() -> void:
	var rules := _rules()
	var cut := 0
	for building_seed in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for wall in plan.walls:
			var span := rules.floor_span(wall.floor_index)
			var slab := BuildingPlan.spans_between(plan.gaps_on(rules, wall.floor_index), span)
			var walk := BuildingPlan.spans_between(plan.blocks_on(rules, wall.floor_index), span)
			assert_gt(walk.size(), slab.size(), "стена обязана добавлять кусок этажу")
			cut += 1
	assert_gt(cut, 0, "стены должны хоть где-то появляться")


## An agent on the other side of a solid wall does not see Otto: no point shooting at a
## wall. This is resolved the same way as darkness — does not see, so not a target.
func test_a_wall_hides_otto_from_an_agent_on_the_same_floor() -> void:
	var rules := _rules()
	var plan := BuildingPlan.generate(rules, 1)
	var wall := BuildingPlan.WallSpot.new()
	wall.floor_index = 5
	wall.x = 18.0
	plan.walls.append(wall)

	assert_true(plan.wall_between(5, 14.0, 22.0), "стена между ними")
	assert_true(plan.wall_between(5, 22.0, 14.0), "порядок точек не важен")
	assert_false(plan.wall_between(5, 19.0, 22.0), "по одну сторону стены нет")
	assert_false(plan.wall_between(6, 14.0, 22.0), "стена делит только свой этаж")
