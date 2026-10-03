extends GutTest

## The basement on the plan: one shaft down, no escalators, the car at the gate on the left
## (ADR-0038, decision 3).
##
## The shaft into the basement is a draw of the building, and the path to the car depends on which
## one came up. So not one building is checked but any that gets generated (`docs/testing.md`): on a
## hundred seeds, at different skills and on the small buildings from the assembly and bot tests.


## A building to check: rules, seed and the assembled plan.
class Case:
	extends RefCounted
	var rules: BuildingRules
	var building_seed: int = 0
	var plan: BuildingPlan

	func label() -> String:
		return "этажей %d, навык %d, сид %d" % [rules.floors, rules.skill, building_seed]


## More seeds than in the neighbouring plan checks: the shaft into the basement is chosen out of
## five, and a locked descent, which the shaft re-layout cures, came up on seeds 65 and 79 — it is
## not visible in the first tens.
const SEEDS: int = 100

## Skills: the first building, the middle and the one where the red door quotas no longer grow.
const SKILLS: Array[int] = [0, 3, 8]

## Plans are assembled once per file: five hundred buildings anew for each test would cost half a
## minute of the run, and the plan does not change between tests.
var _cases: Array[Case] = []


func before_all() -> void:
	for rules: BuildingRules in _buildings():
		for building_seed: int in SEEDS:
			var case := Case.new()
			case.rules = rules
			case.building_seed = building_seed
			case.plan = BuildingPlan.generate(rules, building_seed)
			_cases.append(case)


## Buildings on which the basement is checked: real ones at three skills and small ones — the car,
## assembly and bot tests assemble those.
func _buildings() -> Array[BuildingRules]:
	var all: Array[BuildingRules] = []
	for skill: int in SKILLS:
		var rules := BuildingRules.new()
		rules.skill = skill
		all.append(rules)
	for floors: int in [4, 8]:
		var small := BuildingRules.new()
		small.floors = floors
		small.documents_cap = 1
		small.shaft_span = 2
		all.append(small)
	return all


## Exactly one shaft goes down into the basement, and it is the one that reaches the floor above it;
## the others end higher, as in the ROM ($802D).
func test_exactly_one_shaft_goes_down_to_the_basement() -> void:
	for case in _cases:
		var basement := case.rules.floors - 1
		var down: Array[BuildingPlan.ShaftSpot] = []
		for shaft in case.plan.shafts:
			if shaft.bottom >= basement:
				down.append(shaft)
		assert_eq(down.size(), 1, "%s: в подвал шахт %d" % [case.label(), down.size()])
		if down.size() != 1:
			continue
		var shaft := down[0]
		assert_eq(
			BuildingBasement.shaft_of(case.plan), shaft, "%s: план знает свою шахту" % case.label()
		)
		assert_lte(shaft.top, basement - 1, "%s: шахта идёт с этажа над подвалом" % case.label())
		assert_true(
			shaft.rides_between(basement - 1, basement),
			"%s: кабина возит в подвал — пара ярусов его не отрезает" % case.label()
		)


## Escalators do not go down into the basement: only a shaft leads there.
func test_no_escalator_lands_in_the_basement() -> void:
	for case in _cases:
		for escalator in case.plan.escalators:
			assert_lt(
				escalator.floor_index + 1,
				case.rules.floors - 1,
				"%s: эскалатор с этажа %d" % [case.label(), escalator.floor_index]
			)


## The exit is the leftmost place of the basement, at the car by the gate; the shaft into the
## basement does not touch the car, and the car stands exactly at the gate.
func test_the_exit_is_at_the_left_gate_clear_of_the_shaft() -> void:
	for case in _cases:
		var rules := case.rules
		var plan := case.plan
		var basement := rules.floors - 1
		var car := ExitCar.parked_span(rules)
		var bounds := rules.floor_span(basement)
		var label := case.label()
		assert_almost_eq(
			car.x, bounds.x + BuildingShell.WALL_WIDTH + ExitCar.GAP, 0.001, "машина у торца"
		)
		assert_almost_eq(
			plan.exit_x,
			rules.slot_x(rules.slot_range(basement).x),
			0.001,
			"%s: выход на крайнем левом месте" % label
		)
		assert_between(plan.exit_x, car.x, car.y, "%s: выход приходится на машину" % label)
		var shaft := BuildingBasement.shaft_of(plan)
		if shaft == null:
			fail_test("%s: нет шахты в подвал" % label)
			continue
		assert_true(
			ExitCar.clears_shaft(rules, shaft.x),
			"%s: шахта x=%.1f задевает машину" % [label, shaft.x]
		)
		assert_almost_eq(
			ExitCar.spot(plan.exit_x, rules, plan),
			(car.x + car.y) * 0.5,
			0.001,
			"%s: машина встала у ворот" % label
		)


## The building can be traversed to the car: from the roof — by the shaft into the basement, and
## from it on foot — to the exit, with no wall or opening between them.
func test_the_car_is_reachable_through_the_basement_shaft() -> void:
	for case in _cases:
		var rules := case.rules
		var plan := case.plan
		var basement := rules.floors - 1
		var label := case.label()
		var shaft := BuildingBasement.shaft_of(plan)
		if shaft == null:
			fail_test("%s: нет шахты в подвал" % label)
			continue
		var floors := BuildingRoute.segments(plan, rules)
		var seen := BuildingRoute.reachable_in(plan, rules, floors)
		# In the basement there is no opening under the shaft — it is the bottom, and there is one piece
		# at the cab.
		var landing := BuildingRoute.node_in(floors, basement, shaft.x)
		assert_true(seen.has(landing), "%s: шахтой в подвал не спуститься" % label)
		var exit := BuildingRoute.node_in(floors, basement, plan.exit_x)
		assert_eq(landing, exit, "%s: от шахты до машины не дойти пешком" % label)
		assert_eq(
			BuildingRoute.unreachable_spots(plan, rules),
			[] as Array[String],
			"%s: здание не проходится" % label
		)
		# The same path through the graph the bot walks by: it must find a step toward the car right from
		# the roof.
		var graph := BuildingRoute.walkable(plan, rules)
		var roof_x := plan.safe_x(rules, BuildingRules.ROOF)
		var step := BuildingRoute.step_toward(
			graph, BuildingRules.ROOF, roof_x, basement, plan.exit_x
		)
		assert_false(step.is_empty(), "%s: бот не видит пути к машине" % label)
