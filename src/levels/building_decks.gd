class_name BuildingDecks
extends RefCounted

## Who in the building runs as a double-deck pair.
##
## The rule is one, but it has three conditions, and each cost the milestone a separate finding — so
## it is its own file, not a line in [BuildingPlan]: that one has already hit the thousand-line
## ceiling.
##
## The pair's own design is in [ADR-0025](../../docs/adr/0025-shafts-escalators-and-riders.md),
## decision 1. Here is only the choice of shaft; everything the pair changes in the cab's motion is
## known to [method BuildingPlan.ShaftSpot.ride_span].

## The largest number of pairs placed in a building.
##
## Two — that is how many the original has: "two shafts featured a kind of double-decker elevator".
## Fewer come up where not enough shafts with a live alternative were found; a building without a
## pair is not a breakage.
const MOST: int = 2


## Marks the shafts in which a pair runs.
##
## Candidates are recomputed after each choice: a placed pair itself becomes a worse path — it does
## not carry to its extreme floors — and a second pair must not rely on it.
static func lay(plan: BuildingPlan, rules: BuildingRules, rng: RandomNumberGenerator) -> void:
	# Computed once before everything: the pair must leave reachable exactly what was reachable without
	# it.
	var whole := BuildingRoute.reachable(plan, rules).size()

	for _left in MOST:
		# Places in the shaft array are accumulated, not the shafts themselves: picking from a set is one
		# line for the whole project ([method BuildingPlan.pick_any]), because the seed count depends on
		# the order of calls to the generator.
		var fitting: Array[int] = []
		for index in plan.shafts.size():
			if not plan.shafts[index].double_deck and _takes_a_pair(plan, index):
				fitting.append(index)

		var placed := false
		while not fitting.is_empty():
			var index := BuildingPlan.pick_any(rng, fitting)
			fitting.erase(index)
			plan.shafts[index].double_deck = true
			if BuildingRoute.reachable(plan, rules).size() == whole:
				placed = true
				break
			plan.shafts[index].double_deck = false

		# None of the fitting shafts took a pair — a second pass would go over exactly the same set with
		# the same outcome, and computing the graph is not free.
		if not placed:
			return


## Whether a pair fits in the shaft and whether it would block the descent.
##
## The condition is structural and coarse: it looks at the floor as a whole, while movement goes by
## floor pieces, and the neighbouring shaft may stand beyond an opening. The real guard is the count
## of reachable nodes in [method lay]; this condition just weeds out obviously unfit shafts without
## computing the graph.
##
## **The reachability threshold here is stricter than for a wall.** For a wall [method
## BuildingRoute.is_winnable] is enough — it watches the documents and the exit. For a pair that is
## too little: on seed 3 it took away the only way out from two pieces of the nineteenth floor,
## there was one shaft there, and the pieces became a pocket. There is no document in them, the
## building's traversability did not suffer — but the bot, having walked in there, stood until the
## end of the run.
static func _takes_a_pair(plan: BuildingPlan, index: int) -> bool:
	var shaft := plan.shafts[index]
	if shaft.height() < BuildingRules.MIN_SHAFT_FLOORS:
		return false
	# The tower shaft is the only one for the top third of the building, and there is no other way
	# there at all, but there is no need to check this separately — the condition below will not let it
	# through anyway.
	for floor_index in range(shaft.top, shaft.bottom + 1):
		if not _another_way_off(plan, shaft, floor_index):
			return false
	return true


## Whether there is a way off the floor besides this shaft: a neighbouring shaft or an escalator. An
## escalator one floor above also fits: it leads down, but you can also go up it by standing on the
## lower landing (ADR-0004, item 8).
static func _another_way_off(
	plan: BuildingPlan, besides: BuildingPlan.ShaftSpot, floor_index: int
) -> bool:
	for other in plan.shafts:
		if other == besides:
			continue
		var span := other.ride_span()
		if floor_index >= span.x and floor_index <= span.y:
			return true
	for escalator in plan.escalators:
		if escalator.floor_index == floor_index or escalator.floor_index + 1 == floor_index:
			return true
	return false
