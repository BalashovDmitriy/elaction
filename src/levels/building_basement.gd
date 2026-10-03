class_name BuildingBasement
extends RefCounted

## The basement on the plan: one shaft down and the exit at the gate (ADR-0038, decision 3).
##
## The bottom floor is an underground garage, like the ROM basement. One shaft goes down there,
## drawn from those reaching the floor above it (the ROM exit shaft, $802D,
## @273F); the rest end one floor higher, escalators do not lead down. Otto's
## car stands at the gate in the left end wall, and the path to it depends on which
## shaft was drawn.
##
## Separate from [BuildingPlan], like [BuildingDecks] and [BuildingDocuments]:
## the layout hit the line limit, and the basement rules are a topic of their own. The count is
## the same: without nodes, by the rules and the plan's draw.


## The lowest floor reached by all shafts but one: the floor above the basement.
static func lowest_landing(rules: BuildingRules) -> int:
	return rules.floors - 2


## Whether slot [param x] suits a shaft with bottom [param bottom].
##
## One that reaches the bottom may be drawn as the basement shaft, and there at the left end wall
## stands the car: such a shaft has no room at the end wall ([method ExitCar.clears_shaft]). Checked
## when the shaft is opened, not at the draw: then there is always something to choose from.
static func fits_shaft(rules: BuildingRules, bottom: int, x: float) -> bool:
	return bottom != lowest_landing(rules) or ExitCar.clears_shaft(rules, x)


## The shaft that will go to the basement: one drawn from those reaching the floor above it.
## [code]null[/code] — there are no shafts at all.
##
## Any building with shafts has a candidate: the top one always reaches the bottom
## unless the building itself makes it shorter, and none touches the car —
## [method fits_shaft] guards that.
static func pick_shaft(
	plan: BuildingPlan, rules: BuildingRules, rng: RandomNumberGenerator
) -> BuildingPlan.ShaftSpot:
	var candidates: Array[int] = []
	for number in plan.shafts.size():
		var shaft := plan.shafts[number]
		if shaft.bottom == lowest_landing(rules) and ExitCar.clears_shaft(rules, shaft.x):
			candidates.append(number)
	if candidates.is_empty():
		if not plan.shafts.is_empty():
			push_error("в подвал не спускается ни одна шахта")
		return null
	return plan.shafts[BuildingPlan.pick_any(rng, candidates)]


## The basement shaft: the only one that reaches the bottom floor. An empty building
## has no shafts, so the answer can be empty too.
static func shaft_of(plan: BuildingPlan) -> BuildingPlan.ShaftSpot:
	for shaft in plan.shafts:
		if shaft.bottom == plan.floors - 1:
			return shaft
	return null


## Exit slot: the leftmost slot of the basement.
##
## Not by draw but at the end wall: there are the garage gate and Otto's car with its bonnet toward
## it — in ROM the car is always on the left. The slot falls on the car at the driver's door
## ([method ExitCar.parked_span]); the basement shaft does not touch the car, so it is always free.
static func exit_slot(rules: BuildingRules) -> int:
	return rules.slot_range(rules.floors - 1).x
