class_name BuildingRoute
extends RefCounted

## Reachability across the building: where one can get from the starting point.
##
## A floor is cut by openings into pieces, and on foot one can only move within a piece.
## Shafts and escalators carry between pieces and floors — the graph is built on them.
##
## Falls are left out of the graph on purpose: if the building is passable without them, it
## is all the more passable with them. And a fall of more than a floor is fatal besides.
##
## Everything is computed from the layout, without nodes and physics, so it is checked on
## dozens of seeds in a fraction of a second — and it is on rare seeds that generation holes
## show up.

## How far into a floor piece to go from its edge, m. That much is needed to stand
## on it rather than on the very edge of an opening.
const STEP_INSIDE: float = 0.3

## Adjacency tolerance: for floating-point arithmetic, and only for it.
##
## It used to be a metre, and with it the graph promised a connection that did not exist:
## an inner wall almost a metre wide (ADR-0024, decision 5) fit into the tolerance entirely,
## and the piece behind it counted as reachable straight from the cab. A building with such a
## "passage" passed the check, and the player ran into a wall.
const TOUCHING_SLACK: float = 0.05


## Nodes reachable from the starting point. Key — "floor:piece".
static func reachable(plan: BuildingPlan, rules: BuildingRules) -> Dictionary:
	return reachable_in(plan, rules, _floor_segments(plan, rules))


## Pieces of all levels: level -> "left edge, right edge" pairs.
##
## Exposed so nodes can be computed in bulk: [method node_in] over ready pieces
## costs next to nothing, while the pieces themselves are a pass over the whole layout.
##
## A dictionary, not a list: levels count from [constant BuildingRules.ROOF], i.e.
## from −1, and [code]Array[-1][/code] in GDScript returns the last element — the roof would
## silently pretend to be the first floor instead of crashing the traversal (ADR-0014).
static func segments(plan: BuildingPlan, rules: BuildingRules) -> Dictionary:
	return _floor_segments(plan, rules)


## Node of a level point by the ready pieces from [method segments]. It is used to check
## whether the route leads there: [method reachable] returns a set of the same nodes.
static func node_in(floors: Dictionary, floor_index: int, x: float) -> String:
	return _node(floor_index, _segment_at(floors[floor_index], x))


## The same nodes as [method reachable], but from the ready pieces of
## [method segments]: whoever has already computed them does not pay twice per pass.
static func reachable_in(
	plan: BuildingPlan, rules: BuildingRules, floors: Dictionary
) -> Dictionary:
	var links: Dictionary = _graph(plan, rules, floors, false)["links"]

	# The descent starts from the roof, not from the top floor: Otto gets there by elevator,
	# and a building that cannot be reached from the roof is impassable.
	var from := BuildingRules.ROOF
	var start := _node(from, _segment_at(floors[from], plan.safe_x(rules, from)))
	var seen := {start: true}
	var queue: Array[String] = [start]

	while not queue.is_empty():
		var current: String = queue.pop_front()
		for next: String in links.get(current, [] as Array[String]):
			if seen.has(next):
				continue
			seen[next] = true
			queue.append(next)
	return seen


## Whether the building is passable: all documents can be collected and the exit is reachable.
static func is_winnable(plan: BuildingPlan, rules: BuildingRules) -> bool:
	return unreachable_spots(plan, rules).is_empty()


## What is unreachable from the starting point: descriptions of places, one per place.
##
## Returns descriptions rather than indices so a failed test says at once where the hole is.
static func unreachable_spots(plan: BuildingPlan, rules: BuildingRules) -> Array[String]:
	var floors := _floor_segments(plan, rules)
	var seen := reachable_in(plan, rules, floors)
	var missing: Array[String] = []

	for door in plan.doors:
		if not door.has_document:
			continue
		var node := _node(door.floor_index, _segment_at(floors[door.floor_index], door.x))
		if not seen.has(node):
			missing.append("document on floor %d (x=%.0f)" % [door.floor_index, door.x])

	var bottom := plan.floors - 1
	var exit_node := _node(bottom, _segment_at(floors[bottom], plan.exit_x))
	if not seen.has(exit_node):
		missing.append("exit on floor %d (x=%.0f)" % [bottom, plan.exit_x])
	return missing


## Whether nothing is cut off: documents and the exit are reachable, and **all pieces of
## floor [param floor_index] too**.
##
## The second part is about pockets. A wall cuts its floor in two, and the cut-off half
## may be of no use to anyone: there is no document in it, [method is_winnable] does not
## notice it — and a bot that walks in there gets stuck till the end of the run (seed 1,
## floor 22, 3001 steps of "no move").
##
## This cannot be measured by the number of reachable nodes, unlike the two-floor pair:
## a pair changes only edges, while a wall adds a new node, and their number grows
## by itself. So the question is asked specifically about the floor's pieces.
static func nothing_is_cut_off(plan: BuildingPlan, rules: BuildingRules, floor_index: int) -> bool:
	var floors := _floor_segments(plan, rules)
	var seen := reachable_in(plan, rules, floors)

	for door in plan.doors:
		if not door.has_document:
			continue
		if not seen.has(_node(door.floor_index, _segment_at(floors[door.floor_index], door.x))):
			return false

	var bottom := plan.floors - 1
	if not seen.has(_node(bottom, _segment_at(floors[bottom], plan.exit_x))):
		return false

	for segment in (floors[floor_index] as Array[Vector2]).size():
		if not seen.has(_node(floor_index, segment)):
			return false
	return true


## The building graph ready for walking: level pieces and labelled transitions between them.
##
## Computed once per building and handed to whoever walks it: the layout does not change
## during a game, and [method step_toward] is called every frame.
##
## Separate from [method reachable]: that one only needs to know whether nodes are linked,
## while a walker needs to know by what — which shaft to go to and at which level to get out.
static func walkable(plan: BuildingPlan, rules: BuildingRules) -> Dictionary:
	var pieces := _floor_segments(plan, rules)
	return {
		"pieces": pieces,
		"moves": _graph(plan, rules, pieces, true)["moves"],
		# How far someone standing in the cab can reach: it covers the opening itself,
		# and one can step out of it to either side.
		"reach": rules.shaft_width * 0.5 + TOUCHING_SLACK,
	}


## The first step towards the goal over the ready graph from [method walkable].
##
## One step is returned, not the whole route: the walker re-evaluates the decision every
## frame — he misses the cab, fights, falls and moves off his spot, and a
## remembered route would be stale by the next frame.
##
## Answer keys: [code]kind[/code] — [code]walk[/code], [code]shaft[/code] or
## [code]escalator[/code]; [code]x[/code] — where to go; [code]floor[/code] — at
## which level to end up. An empty dictionary — the goal is unreachable.
static func step_toward(
	graph: Dictionary, from_floor: int, from_x: float, to_floor: int, to_x: float
) -> Dictionary:
	var pieces: Dictionary = graph["pieces"]
	var moves: Dictionary = graph["moves"]
	var goal := _node(to_floor, _segment_at(pieces[to_floor], to_x))

	# There can be several starting points. Someone standing in a cab stands in an opening, and
	# an opening has no floor piece: he is free to step out to either side, and both are open
	# to him. Returning one would lock him into whichever came first, and he would
	# ride back and forth trying to get into the neighbouring one.
	var first: Dictionary = {}
	var queue: Array[String] = []
	for segment: int in _segments_near(pieces[from_floor], from_x, float(graph["reach"])):
		var start := _node(from_floor, segment)
		if start == goal:
			return {"kind": "walk", "x": to_x, "floor": to_floor}
		first[start] = {}
		queue.append(start)
	while not queue.is_empty():
		var here: String = queue.pop_front()
		for move: Dictionary in moves.get(here, [] as Array[Dictionary]):
			var next: String = move["to"]
			if first.has(next):
				continue
			first[next] = move if first[here].is_empty() else first[here]
			if next == goal:
				return first[next]
			queue.append(next)
	return {}


## The point inside a piece closest to [param x]: with a margin from the edges, so one
## can get to it and stand on it.
##
## If the piece is narrower than two margins, its middle is taken: it is a tight strip
## between openings, and one cannot stand any more precisely in it.
static func _inside(piece: Vector2, x: float) -> float:
	if piece.y - piece.x <= STEP_INSIDE * 2.0:
		return (piece.x + piece.y) * 0.5
	return clampf(x, piece.x + STEP_INSIDE, piece.y - STEP_INSIDE)


## The building graph: who is linked to whom and, on request, by what exactly.
##
## One traversal for both answers. There used to be two — [code]_moves[/code] and
## [code]_links[/code] — and they computed the same thing differently: a change for
## the two-floor pair (ADR-0025, decision 1) would land in one and not
## in the other, and they already diverged on a degenerate escalator end.
##
## [param detailed] — whether each transition needs a label. The reachability traversal
## is content with neighbours, while a walker needs to know what to use and where he
## ends up. A dictionary per edge is expensive, and [method is_winnable] is called
## about ten times per building — so the label is computed on request, but
## the rule of who is linked to whom stays one for both answers.
static func _graph(
	plan: BuildingPlan, rules: BuildingRules, pieces: Dictionary, detailed: bool
) -> Dictionary:
	var links: Dictionary = {}
	var moves: Dictionary = {}

	for shaft in plan.shafts:
		# A cab links the levels of its shaft, and also both edges of the opening on the same
		# level: one walks straight through a standing cab. A move to the same level
		# looks empty, but it is exactly the passage through the opening — without it the halves
		# of a floor cut by a shaft are unreachable from each other.
		#
		# Boarding nodes — three parallel arrays, not a dictionary per node.
		# A dictionary here cost twice the whole generation: a dozen shafts, each with dozens
		# of nodes, and pairing them is quadratic. Measured: 24.5 ms per building
		# against 12.2 after.
		var nodes: Array[String] = []
		var on_floor := PackedInt32Array()
		# One steps out not onto the shaft axis but into the piece itself: otherwise the passage
		# through the opening would end right in the cab, and "arrived" would come without moving.
		var inside := PackedFloat64Array()
		# Whether the cab carries from this node. Computed in advance, not in the pass:
		# [method BuildingPlan.ShaftSpot.ride_span] creates a [Vector2i], and
		# the pass is quadratic in the number of nodes.
		var rides := PackedByteArray()
		var span := shaft.ride_span()
		for index in range(shaft.top, shaft.bottom + 1):
			for segment in _segments_touching(pieces[index], shaft.x, rules.shaft_width):
				var piece: Vector2 = pieces[index][segment]
				nodes.append(_node(index, segment))
				on_floor.append(index)
				inside.append(_inside(piece, shaft.x))
				rides.append(1 if index >= span.x and index <= span.y else 0)

		for from_index in nodes.size():
			for to_index in nodes.size():
				if from_index == to_index:
					continue
				# The passage through the opening is on its own floor, and any standing cab
				# provides it. A ride goes only where any of the pair's tiers
				# would take you: whoever enters does not choose which tier meets him.
				var to_floor := on_floor[to_index]
				var from_floor := on_floor[from_index]
				if to_floor != from_floor and (rides[from_index] == 0 or rides[to_index] == 0):
					continue
				_join(links, nodes[from_index], nodes[to_index])
				if detailed:
					_offer(
						moves,
						nodes[from_index],
						"shaft",
						shaft.x,
						inside[to_index],
						to_floor,
						nodes[to_index]
					)

	for escalator in plan.escalators:
		var upper := escalator.floor_index
		var top_segment := _segment_at(pieces[upper], escalator.x)
		var landing := escalator.landing(rules)
		var bottom_segment := _segment_at(pieces[upper + 1], landing)
		# -1 — the escalator end fell into an opening or behind a wall. There is no node with such a
		# number on the floor, and it cannot be linked: the traversal would mark it reachable,
		# and after that any floor point inside the hole would count as reachable.
		if top_segment < 0 or bottom_segment < 0:
			push_error("escalator on floor %d runs into an opening" % upper)
			continue
		# The escalator goes both ways: from the landing below one rides up on it.
		var above := _node(upper, top_segment)
		var below := _node(upper + 1, bottom_segment)
		_join(links, above, below)
		_join(links, below, above)
		if detailed:
			_offer(moves, above, "escalator", escalator.x, landing, upper + 1, below)
			_offer(moves, below, "escalator", landing, escalator.x, upper, above)

	return {"links": links, "moves": moves}


## Marks that one node can be reached from another.
static func _join(links: Dictionary, from_node: String, to_node: String) -> void:
	if not links.has(from_node):
		links[from_node] = [] as Array[String]
	if not links[from_node].has(to_node):
		links[from_node].append(to_node)


## [param x] — where to go to use the transition; [param to_x] — where
## you end up. For a shaft they are the same, for an escalator — different ends of the belt.
static func _offer(
	moves: Dictionary,
	from_node: String,
	kind: String,
	x: float,
	to_x: float,
	to_floor: int,
	to_node: String
) -> void:
	if not moves.has(from_node):
		moves[from_node] = [] as Array[Dictionary]
	moves[from_node].append({"kind": kind, "x": x, "to_x": to_x, "floor": to_floor, "to": to_node})


## Pieces of each level: "left edge, right edge" pairs between whatever interrupts
## walking.
##
## Both openings and inner walls cut ([method BuildingPlan.blocks_on]): one cannot pass
## through a wall even though there is floor under it. The slab stays whole in that case —
## it is computed from openings alone, ADR-0024, decision 5.
##
## The bounds are taken from the level itself: the building widens downwards, and a piece
## the full width of the building would lead, on a narrow floor, through a wall to the street.
static func _floor_segments(plan: BuildingPlan, rules: BuildingRules) -> Dictionary:
	var floors: Dictionary = {}
	for index in rules.levels():
		var blocks := plan.blocks_on(rules, index)
		floors[index] = BuildingPlan.spans_between(blocks, rules.floor_span(index))
	return floors


## Floor pieces adjacent to a column of width [param width] around [param x].
static func _segments_touching(pieces: Array, x: float, width: float) -> Array[int]:
	var half := width * 0.5
	var found: Array[int] = []
	for index in pieces.size():
		var piece: Vector2 = pieces[index]
		# Either the piece reaches the edge of the column, or the column is entirely inside it.
		if piece.y >= x - half - TOUCHING_SLACK and piece.x <= x + half + TOUCHING_SLACK:
			found.append(index)
	return found


## Pieces from which a point is reachable on foot: the one it lies in, and if
## it is in an opening — all whose edge adjoins it.
##
## Separate from [method _segment_at]: for that one "nowhere" is a legitimate answer, on
## which reachability refuses to link the node. But a walker always needs an answer: he
## can be in an opening too — standing in an elevator cab — and can step out of it to either
## side, because the cab covers the opening itself.
static func _segments_near(pieces: Array, x: float, reach: float) -> Array[int]:
	var here := _segment_at(pieces, x)
	if here >= 0:
		return [here] as Array[int]

	# There is nothing to reach beyond the cab: in an opening wider than it there is no floor,
	# and no one stands there. If no edge was found, the nearest one is returned: an inexact
	# answer is better than one stuck forever.
	var found: Array[int] = []
	var nearest := -1
	var best := INF
	for index in pieces.size():
		var piece: Vector2 = pieces[index]
		var away := maxf(piece.x - x, x - piece.y)
		if away <= reach:
			found.append(index)
		if away < best:
			best = away
			nearest = index
	if found.is_empty() and nearest >= 0:
		found.append(nearest)
	return found


static func _segment_at(pieces: Array, x: float) -> int:
	for index in pieces.size():
		var piece: Vector2 = pieces[index]
		if x >= piece.x and x <= piece.y:
			return index
	return -1


static func _node(floor_index: int, segment: int) -> String:
	return "%d:%d" % [floor_index, segment]
