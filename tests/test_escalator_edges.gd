extends GutTest

## Escalators at the floor edge, at 45°, zigzagging (ADR-0043, decision 15).
##
## In the middle of a floor an escalator looked absurd. Now it descends to the edge: the upper
## landing is inside the floor, the lower one at the edge of the floor below, the opening runs from
## the landing to the edge and floor leads to the landing, not a jump over a hole.

const SEEDS: Array[int] = [1, 2, 3, 5, 8, 13, 21, 34, 55, 89]


func _rules() -> BuildingRules:
	return BuildingRules.new()


func test_the_flight_is_forty_five_degrees() -> void:
	var rules := _rules()
	var angle := rad_to_deg(atan2(rules.floor_height, rules.escalator_run))
	assert_almost_eq(angle, 45.0, 0.01, "пролёт под 45°")


## The lower landing is at the edge the run goes to: no further than a slot from
## the margin, and the belt faces that edge.
func test_every_escalator_lands_at_the_edge() -> void:
	var rules := _rules()
	var pitch := rules.slot_x(1) - rules.slot_x(0)
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for escalator in plan.escalators:
			var index := escalator.floor_index
			var here := rules.floor_span(index)
			var below := rules.floor_span(index + 1)
			var left := escalator.towards < 0.0
			var edge := maxf(here.x, below.x) if left else minf(here.y, below.y)
			var from_edge := absf(escalator.landing(rules) - edge)
			var where := "сид %d, этаж %d" % [building_seed, index]
			assert_gte(
				from_edge, rules.escalator_edge_margin - 0.001, where + ": площадка не в стене"
			)
			assert_lt(from_edge, rules.escalator_edge_margin + pitch, where + ": площадка у края")


## The opening goes from the landing to the edge, and between the middle of the floor and the
## landing there is no hole: the escalator is reached on foot.
func test_the_gap_runs_from_the_pad_to_the_edge() -> void:
	var rules := _rules()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for escalator in plan.escalators:
			var gap := escalator.gap(rules)
			var span := rules.floor_span(escalator.floor_index)
			var where := "сид %d, этаж %d" % [building_seed, escalator.floor_index]
			if escalator.towards < 0.0:
				assert_almost_eq(gap.x, span.x, 0.001, where + ": проём до левого края")
				assert_lt(gap.y, escalator.x, where + ": площадка справа от проёма")
			else:
				assert_almost_eq(gap.y, span.y, 0.001, where + ": проём до правого края")
				assert_gt(gap.x, escalator.x, where + ": площадка слева от проёма")


## An escalator from a floor another one arrived at first tries descending toward the other
## edge: zigzag (decision 15). The second one on a floor — only in the opposite direction to
## the first. The rule is checked directly: in default buildings consecutive escalators
## hardly occur — the pair from the floor above takes the edges of the floor below.
func test_the_next_escalator_tries_the_other_edge_first() -> void:
	var plan := BuildingPlan.new()
	var arrived := EscalatorSpot.new()
	arrived.floor_index = 4
	arrived.towards = -1.0
	plan.escalators.append(arrived)
	for coin: int in [0, 1]:
		var sides: Array[float] = plan._escalator_sides(coin, 5, 0.0)
		assert_eq(sides[0], 1.0, "пришли слева — первым вправо, жребий %d" % coin)
	assert_eq(plan._escalator_sides(0, 5, 1.0), [-1.0] as Array[float], "второй — в другую сторону")


## The landing an escalator arrived at does not lie in the next one's opening.
func test_no_arrival_lands_in_the_next_gap() -> void:
	var rules := _rules()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for upper in plan.escalators:
			for lower in plan.escalators:
				if lower.floor_index != upper.floor_index + 1:
					continue
				var arrival := upper.landing(rules)
				var gap := lower.gap(rules)
				assert_false(
					arrival >= gap.x and arrival <= gap.y,
					(
						"сид %d, этаж %d: площадка прибытия в проёме"
						% [building_seed, lower.floor_index]
					)
				)
		assert_true(true, "сид %d разобран" % building_seed)


## A lamp hangs on the ceiling: there is none under the opening of an escalator from the floor
## above.
func test_no_lamp_hangs_under_an_escalator_gap() -> void:
	var rules := _rules()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for lamp in plan.lamps:
			for escalator in plan.escalators:
				if escalator.floor_index != lamp.floor_index - 1:
					continue
				var gap := escalator.gap(rules)
				assert_false(
					lamp.x > gap.x and lamp.x < gap.y,
					"сид %d, этаж %d: лампа под проёмом" % [building_seed, lamp.floor_index]
				)


## A run at 45° hangs over the floor below from the lower landing to the upper: a wall
## under it would pass through the belt.
func test_no_wall_stands_under_a_flight() -> void:
	var rules := _rules()
	var half := rules.inner_wall_width * 0.5
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for escalator in plan.escalators:
			var landing := escalator.landing(rules)
			var low := minf(landing, escalator.x)
			var high := maxf(landing, escalator.x)
			for wall in plan.walls:
				if wall.floor_index != escalator.floor_index + 1:
					continue
				assert_false(
					wall.x + half > low and wall.x - half < high,
					"сид %d, этаж %d: стена под пролётом" % [building_seed, wall.floor_index]
				)


## Under the bottom of the run the belt is below head height: no place for dressing there.
func test_no_furniture_stands_under_the_low_flight() -> void:
	var rules := _rules()
	var under: Array[String] = []
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for escalator in plan.escalators:
			var lower := escalator.floor_index + 1
			var landing := escalator.landing(rules)
			var start := landing - escalator.towards * rules.escalator_low_span
			for x: float in BuildingDressing.free_spots(rules, plan, lower):
				if x > minf(landing, start) and x < maxf(landing, start):
					under.append("сид %d, этаж %d, x %.2f" % [building_seed, lower, x])
	assert_eq(under, [] as Array[String], "места под низом пролёта")
