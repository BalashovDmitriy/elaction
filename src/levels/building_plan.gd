class_name BuildingPlan
extends RefCounted

## Building layout: where the shafts, escalators, doors and lamps go.
##
## Computed from [BuildingRules] and a seed, knows nothing of nodes and scenes — so it
## is covered by tests. The seed is the building number mixed with the game's salt
## ([method GameState.building_seed]), so the same building is rebuilt the same way
## (ADR-0008, point 2; ADR-0028, decision 6).
##
## Shafts do not run the full height and split the building into bands; where a band
## ends, the generator must place an escalator — otherwise there is no way down.


## Elevator shaft: takes its own column on floors from [member top] to [member bottom].
class ShaftSpot:
	extends RefCounted
	var x: float = 0.0
	## Grid slot the shaft stands in. Kept next to [member x] because converting back
	## from the coordinate means comparing floats, and the slot must be exact.
	var slot: int = -1
	var top: int = 0
	var bottom: int = 0

	## Whether the shaft runs a double-deck pair
	## ([ADR-0025](../../docs/adr/0025-shafts-escalators-and-riders.md), decision 1).
	## Set by [method BuildingPlan.generate], and only where it does not lock the way
	## down: the pair serves a shortened range.
	var double_deck: bool = false

	## How many floors it serves.
	func height() -> int:
		return bottom - top + 1

	## Between which floors the cab carries: a "top, bottom" pair, inclusive.
	##
	## For a regular one — the whole band. For a pair — the band without the end floors,
	## and that is not caution but arithmetic: the upper deck serves
	## [code]top..bottom-1[/code], the lower one [code]top+1..bottom[/code], and whoever
	## steps in does not choose which deck meets them. Only what either of the two will
	## deliver can be promised.
	##
	## The shaft does not lose the end floors: the cab stops on them, and people still
	## cross through it from one edge of the opening to the other.
	func ride_span() -> Vector2i:
		if double_deck:
			return Vector2i(top + 1, bottom - 1)
		return Vector2i(top, bottom)

	## Whether the cab carries between these floors.
	##
	## The rule in one line — for those who ask about a pair of floors.
	## [BuildingRoute] computes the same thing differently: it walks the shaft nodes
	## pairwise, and creating a [Vector2i] for every pair there cost twice as much
	## as the whole generation.
	func rides_between(from_index: int, to_index: int) -> bool:
		var span := ride_span()
		return (
			from_index >= span.x
			and from_index <= span.y
			and to_index >= span.x
			and to_index <= span.y
		)


class DoorSpot:
	extends RefCounted
	var x: float = 0.0
	var floor_index: int = 0
	var has_document: bool = false


class LampSpot:
	extends RefCounted
	var x: float = 0.0
	var floor_index: int = 0


## Inner wall splitting a floor in two (ADR-0024, decision 5).
##
## Solid from floor to ceiling: neither people nor bullets pass through it. It stands
## on the border between slots, not on a slot: it is thin, and there is no point
## giving up a whole grid step for it.
class WallSpot:
	extends RefCounted
	var x: float = 0.0
	var floor_index: int = 0

	## Span the wall takes on the floor: a "left edge, right edge" pair.
	func band(rules: BuildingRules) -> Vector2:
		var half := rules.inner_wall_width * 0.5
		return Vector2(x - half, x + half)


## How many times to relay the shafts if the way down came out locked.
const SHAFT_ATTEMPTS: int = 8

var floors: int = 0
## Seed the plan is built from: it feeds its own draw of the document count.
var seed_value: int = 0
var shafts: Array[ShaftSpot] = []
var escalators: Array[EscalatorSpot] = []
var doors: Array[DoorSpot] = []
var lamps: Array[LampSpot] = []
var walls: Array[WallSpot] = []
## Where the building exit stands on the bottom floor.
var exit_x: float = 0.0

## Floor where the shafts ended and the escalator found no room; −1 — there is none.
var _unbridged: int = -1


## Builds the building from the rules and the seed.
##
## The shafts are relaid if the way down came out locked: the tower's shafts ended on
## one floor and there was no room for an escalator there. That happened to one
## building in a hundred (seeds 65, 79, 119), and the exit was unreachable. The first
## attempt uses the seed itself, so other buildings stay as they were; the next ones
## use the seed with the attempt number.
static func generate(rules: BuildingRules, seed_value: int) -> BuildingPlan:
	var plan: BuildingPlan = null
	for attempt in SHAFT_ATTEMPTS:
		plan = _generate_once(rules, seed_value, attempt)
		if plan._unbridged < 0 and BuildingBasement.shaft_of(plan) != null:
			return plan
	if plan._unbridged >= 0:
		push_error("floor %d is left without an escalator: no free spot" % plan._unbridged)
	return plan


static func _generate_once(rules: BuildingRules, seed_value: int, attempt: int) -> BuildingPlan:
	var plan := BuildingPlan.new()
	plan.floors = rules.floors

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if attempt == 0 else hash([seed_value, attempt])
	plan.seed_value = seed_value

	# Occupied slots: floor -> set of slots. Everything goes into free slots, so
	# nothing ends up inside a shaft or on an escalator's belt.
	var taken: Dictionary = {}
	plan._lay_shafts(rules, rng, taken)
	plan._lay_escalators(rules, rng, taken)
	var locked := plan._unbridged >= 0 or BuildingBasement.shaft_of(plan) == null
	if locked and attempt < SHAFT_ATTEMPTS - 1:
		# No point laying out further: the building is rebuilt anyway — and the
		# walls with their reachability check, the most expensive part here, are not built.
		return plan
	plan._lay_exit(rules, taken)
	plan._lay_doors(rules, rng, taken)
	BuildingLamps.lay(plan, rules, taken)
	# Walls — after the mandatory items and before the extra doors: a wall is checked
	# against reachability of the documents and the exit, while extra doors need it
	# already standing. If extra doors went first, no room would be left for a wall in
	# the tower: four doors on seven slots, and there were 22 walls instead of 156
	# (code review M18e).
	plan._lay_walls(rules, rng)
	plan._reserve_beside_walls(rules, taken)
	# Doors beyond the mandatory one go last: the map allows up to twelve per floor,
	# and if they took slots earlier, a lamp would have to share a slot with a door and
	# a wall would not fit at all (ADR-0028, decision 2).
	plan._lay_more_doors(rules, rng, taken)
	# Double-deck pairs are checked against reachability of the documents and the
	# exit, so those must already be in place.
	BuildingDecks.lay(plan, rules, rng)
	return plan


## Floors the documents lie on, bottom to top.
func document_floors() -> Array[int]:
	var found: Array[int] = []
	for door in doors:
		if door.has_document:
			found.append(door.floor_index)
	found.sort()
	return found


## Pieces of slab between openings: "left edge, right edge" pairs.
##
## The only place where a floor is cut by openings. These pieces build both the
## geometry ([method BuildingShell.slab_segments]) and the reachability graph
## ([BuildingRoute]) — they must not diverge, so there is one computation for all.
## Openings are accepted in any order and sorted right here: with an unsorted list
## the pieces overlap and the opening disappears.
static func spans_between(gaps: Array[Vector2], bounds: Vector2) -> Array[Vector2]:
	var ordered := gaps.duplicate()
	ordered.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

	var spans: Array[Vector2] = []
	var cursor := bounds.x
	for gap: Vector2 in ordered:
		# An opening past the level's edge cuts nothing: on narrow floors it can lie
		# entirely in the street, and without clipping the piece would go negative and flip.
		var from := clampf(gap.x, bounds.x, bounds.y)
		var to := clampf(gap.y, bounds.x, bounds.y)
		if from > cursor:
			spans.append(Vector2(cursor, from))
		# maxf, so a nested opening does not wind the cursor back.
		cursor = maxf(cursor, to)
	if cursor < bounds.y:
		spans.append(Vector2(cursor, bounds.y))
	return spans


## The shaft that reaches the roof. The machine room stands above it, and the descent
## starts with it: [method _lay_shafts] extends the topmost one to the roof.
##
## Asked from the layout rather than derived anew by everyone who needs it: the level
## places the rooftop structure by it, and the test finds it the same way. An empty
## building has no shafts at all, so the answer can be empty.
func roof_shaft() -> ShaftSpot:
	var highest: ShaftSpot = null
	for shaft in shafts:
		if highest == null or shaft.top < highest.top:
			highest = shaft
	return highest


## Through openings in a floor's slab — shafts: "left edge, right edge" pairs,
## in any order. Escalator openings are never through openings since M24h —
## [method escalator_holes_on].
##
## Computed here, not in the level: the reachability graph is built from the same
## holes, and they must not diverge. The order is deliberately not promised: the only
## consumer is [method spans_between], and it sorts on its own.
func gaps_on(rules: BuildingRules, floor_index: int) -> Array[Vector2]:
	var gaps: Array[Vector2] = []

	for shaft in shafts:
		# The cab passes through the slabs of its band, except the bottom one: there it
		# stands on the floor, and that floor is the bottom of the shaft.
		if floor_index >= shaft.top and floor_index < shaft.bottom:
			var half := rules.shaft_width * 0.5
			gaps.append(Vector2(shaft.x - half, shaft.x + half))

	return gaps


## Escalator openings in a floor's slab: a "left edge, right edge" pair.
##
## Since M24h the escalator stands deep inside, by the back wall (ADR-0044,
## decision 10): it cuts the slab only in the corridor's back strip, behind the play
## plane, while the floor in front of it is whole and people walk past the escalator.
## So escalator openings are not in [method gaps_on]: those cut the slab through its
## full depth, and walking along with it.
func escalator_holes_on(rules: BuildingRules, floor_index: int) -> Array[Vector2]:
	var holes: Array[Vector2] = []
	for escalator in escalators:
		if floor_index == escalator.floor_index:
			holes.append(escalator.hole(rules))
	return holes


## What cuts the floor for walking: openings plus inner walls.
##
## There are two computations, and ADR-0024, decision 5, separates them. The slab is
## cut only by openings ([method gaps_on]) — a wall stands on the slab, not instead of
## it. Walking is cut by both: you cannot pass through a wall even though there is
## floor under it.
func blocks_on(rules: BuildingRules, floor_index: int) -> Array[Vector2]:
	var blocks := gaps_on(rules, floor_index)
	for wall in walls:
		if wall.floor_index == floor_index:
			blocks.append(wall.band(rules))
	return blocks


## Whether a wall stands on the floor between two points.
##
## Asked by those who care whether one point is visible from another: an agent behind
## a solid wall does not see Otto and does not shoot — the bullet would hit the wall
## anyway (ADR-0024, decision 5).
func wall_between(floor_index: int, from_x: float, to_x: float) -> bool:
	var low := minf(from_x, to_x)
	var high := maxf(from_x, to_x)
	for wall in walls:
		if wall.floor_index == floor_index and wall.x > low and wall.x < high:
			return true
	return false


## A slot on the floor where one can stand without falling through or bumping into
## anything.
##
## Needed by those placed on the floor from outside the layout: Otto at the start and
## after death. Doors and lamps make no holes in the floor and so do not get in the way,
## but the exit does: respawning on it, Otto would leave the building without a step.
func safe_x(rules: BuildingRules, floor_index: int) -> float:
	var spots := safe_spots(rules, floor_index)
	if spots.is_empty():
		# All slots are taken — so there is nowhere to stand but the middle of the level.
		var span := rules.slot_range(floor_index)
		return rules.slot_x((span.x + span.y) / 2)
	return spots[0]


## All the slots of the level where one can stand, left to right.
##
## Needed by whoever chooses between them: returning to play picks the one nearest to
## the ROM point ([RespawnSpot]), not the first one at hand.
##
## A double-precision array, not single: slots are compared with layout coordinates
## through [method @GlobalScope.is_equal_approx], and rounding to float32 would set
## [method safe_x] apart from [method BuildingRules.slot_x] under any rules where the
## step between slots is not whole.
func safe_spots(rules: BuildingRules, floor_index: int) -> PackedFloat64Array:
	var spots := PackedFloat64Array()
	var span := rules.slot_range(floor_index)
	for slot in range(span.x, span.y + 1):
		var x := rules.slot_x(slot)
		if _is_clear(rules, floor_index, x):
			spots.append(x)
	return spots


func _is_clear(rules: BuildingRules, floor_index: int, x: float) -> bool:
	if floor_index == floors - 1 and is_equal_approx(x, exit_x):
		return false

	for shaft in shafts:
		if floor_index >= shaft.top and floor_index <= shaft.bottom and is_equal_approx(x, shaft.x):
			return false

	for escalator in escalators:
		if floor_index != escalator.floor_index:
			continue
		if is_equal_approx(x, escalator.x):
			return false
		# The hole under the belt beside the landing, and that is exactly where one can fall.
		var gap := escalator.gap(rules)
		if x >= gap.x and x <= gap.y:
			return false

	return true


## Shafts — unrolled top to bottom (ADR-0024, decision 3).
##
## On each level it is known how many shafts should serve it
## ([method BuildingRules.shafts_on]); those that have used up their span close,
## missing ones open. The overlap comes out by itself and comes out uneven: shafts
## opened on different floors close on different ones. Those opened at the very
## bottom are clipped by the bottom floor and reach the ground together — like 1–5,
## 1–6 and three 1–7 in the original.
##
## The bottom here is the floor above the basement: one shaft goes down into the
## basement ([BuildingBasement]).
func _lay_shafts(rules: BuildingRules, rng: RandomNumberGenerator, taken: Dictionary) -> void:
	var open: Array[ShaftSpot] = []
	var previous_slot := -1

	for index in rules.levels():
		if index > BuildingBasement.lowest_landing(rules):
			break
		# Those that used up their span close. A shaft's bottom is set when it opens
		# and never changes: it decides whether the shaft lives down to this level.
		var carried: Array[ShaftSpot] = []
		for shaft in open:
			if index <= shaft.bottom:
				carried.append(shaft)
		open = carried

		for _missing in range(open.size(), rules.shafts_on(index)):
			var shaft := _open_shaft(rules, rng, taken, index, previous_slot)
			if shaft == null:
				# No free slots — the floor is already denser than its width allows.
				# Not an error: the shaft count is a ceiling of the wish, not a promise.
				break
			open.append(shaft)
			shafts.append(shaft)
			previous_slot = shaft.slot

	var down := BuildingBasement.pick_shaft(self, rules, rng)
	if down != null:
		down.bottom = floors - 1
		occupy(taken, floors - 1, down.slot)


## A new shaft from [param index] down. [code]null[/code] — nowhere to put it.
##
## The top one is extended to the roof: in the original Otto enters the building by
## elevator, and that is the only opening in its deck (ADR-0014, point 2).
func _open_shaft(
	rules: BuildingRules,
	rng: RandomNumberGenerator,
	taken: Dictionary,
	index: int,
	previous_slot: int
) -> ShaftSpot:
	var shaft := ShaftSpot.new()
	var lowest := BuildingBasement.lowest_landing(rules)
	shaft.top = index
	shaft.bottom = mini(index + _shaft_length(rules, rng, index) - 1, lowest)

	# A shaft may end either high enough for its successor to have room to open, or
	# at the very bottom. There is nothing in between: closing on the second-to-last
	# floor, it leaves the lower ones without a path — a new one cannot open there,
	# bands shorter than [constant BuildingRules.MIN_SHAFT_FLOORS] do not exist.
	# That is what happened on seed 1: band 23..27 closed, and 28–29 were left with
	# four paths instead of five. The bottom here is the floor above the basement.
	if shaft.bottom > lowest - BuildingRules.MIN_SHAFT_FLOORS:
		shaft.bottom = lowest

	# The length is set by [method _shaft_length], but the bottom is clipped to the
	# building's bottom — and a shaft opened at the very bottom comes out shorter than
	# the rule. Such a shaft goes nowhere: the cab has nowhere to travel, it is useless
	# to the player, and both indicators in it go dark.
	#
	# It used to open because the shaft count per floor grows downward, and on the
	# lower floors the layout filled in the missing ones. The count rule is a ceiling
	# of the wish, not a promise (see the caller), so here it is more honest not to
	# open it at all.
	if shaft.bottom - shaft.top + 1 < BuildingRules.MIN_SHAFT_FLOORS:
		return null

	var levels: Array[int] = []
	for level in range(shaft.top, shaft.bottom + 1):
		levels.append(level)

	# The slot must hold on all of the shaft's levels at once: the building widens
	# downward, and the top of the shaft is its tightest spot.
	# A shaft is exactly one slot step wide (ADR-0026, decision 3), and two in
	# neighbouring slots would merge: no floor would be left between them — nowhere
	# to stand, and no way out of the cab except into the neighbouring one.
	var free: Array[int] = []
	for slot in _free_slots(rules, taken, levels):
		if _beside_a_shaft(slot, shaft.top, shaft.bottom):
			continue
		if not BuildingBasement.fits_shaft(rules, shaft.bottom, rules.slot_x(slot)):
			continue
		free.append(slot)
	if free.is_empty():
		return null

	# Adjacent shafts must not stand in one column: otherwise changing shafts would
	# come down to a step aside, and moving between shafts is the whole point of descent.
	shaft.slot = _pick_slot(rng, free, previous_slot)
	shaft.x = rules.slot_x(shaft.slot)
	for level in levels:
		occupy(taken, level, shaft.slot)
	return shaft


## Whether a shaft passing level [param index], bottom included, stands in the slot.
func _shaft_column_at(slot: int, index: int) -> bool:
	for shaft in shafts:
		if shaft.slot == slot and shaft.top <= index and index <= shaft.bottom:
			return true
	return false


## Whether a neighbouring slot holds a shaft sharing at least one level with the band
## [param top]..[param bottom].
func _beside_a_shaft(slot: int, top: int, bottom: int) -> bool:
	for other in shafts:
		if absi(other.slot - slot) != 1:
			continue
		if other.top <= bottom and top <= other.bottom:
			return true
	return false


## How many levels a new shaft will serve.
##
## A span with spread, not a constant: otherwise shafts opened on one level close on
## one level, and there is no overlap at all — everyone changes shafts on the same
## floor, as before M18. In the original the shaft lengths differ: 5, 6, 7, 3, 12.
##
## The top one goes by its own length and without spread — that is shaft 19–30,
## the building's landmark.
func _shaft_length(rules: BuildingRules, rng: RandomNumberGenerator, index: int) -> int:
	if index <= BuildingRules.ROOF:
		return maxi(rules.top_shaft_span, 1)
	var spread := maxi(rules.shaft_span_spread, 0)
	# Not shorter than [constant BuildingRules.MIN_SHAFT_FLOORS]: a short shaft goes
	# nowhere, and the M18b double-deck cab would not move in it at all.
	return maxi(rules.shaft_span + rng.randi_range(-spread, spread), BuildingRules.MIN_SHAFT_FLOORS)


## Escalators: a band at the threshold plus a guarantee at the break (ADR-0024,
## decision 4).
##
## The band is the lower floors of the single-shaft zone, where the tower's shaft ends
## above the podium; there are two escalators there if they fit. The guarantee is the
## floor where a shaft ended and no other connects it with the one below: without an
## escalator, everything below is unreachable.
func _lay_escalators(rules: BuildingRules, rng: RandomNumberGenerator, taken: Dictionary) -> void:
	for index in rules.levels():
		# The roof needs no escalator — a shaft leads off it — and the bottom floor
		# has nowhere to lead. Escalators do not go down into the basement, as in the
		# ROM: one shaft leads there ([BuildingBasement]), and the floor above is
		# connected by it.
		if index <= BuildingRules.ROOF or index >= BuildingBasement.lowest_landing(rules):
			continue

		var unbridged := _ends_at(index) and not _bridges(index)
		var wanted := 2 if rules.in_escalator_band(index) else int(unbridged)
		var built := 0
		# The second on a floor leads in the other direction from the first: in the
		# original on 17–20 there are escalators both left and right. Both in one
		# direction is a two-flight staircase, not two ways down.
		var taken_towards := 0.0
		for _each in range(wanted):
			# At a broken junction the first escalator is mandatory: without it,
			# everything below is unreachable, and neither a door nor a lamp is worth
			# sparing for it. The rest give way to them.
			var must := unbridged and built == 0
			var towards := _add_escalator(rules, rng, taken, index, taken_towards, must)
			if is_zero_approx(towards):
				break
			taken_towards = towards
			built += 1

		# It cannot be skipped silently: without an escalator everything below is
		# unreachable. It becomes an error only if relaying the shafts did not help
		# either ([method generate]).
		if built == 0 and unbridged and _unbridged < 0:
			_unbridged = index


## Whether at least one shaft ends on this level.
func _ends_at(index: int) -> bool:
	for shaft in shafts:
		if shaft.bottom == index:
			return true
	return false


## Whether a shaft connects this level with the next one down. While there is one,
## the change goes through the overlap and an escalator is not mandatory.
func _bridges(index: int) -> bool:
	for shaft in shafts:
		if shaft.top <= index and shaft.bottom > index:
			return true
	return false


## Places an escalator from [param index] to the next level down and returns where it
## descends to. [code]0.0[/code] — no room found; the caller stops there.
##
## [param avoid_towards] — the side another escalator on this floor already leads
## to; zero if this is the first.
##
## Since M24g the escalator stands at the floor's edge and descends toward it, at 45°
## (ADR-0043, decision 15): in the middle of the floor it looked absurd. The lower
## landing is at the edge, the upper one inside the floor, and people walk to it: the
## opening runs from it to the edge, past the passage. In a row — zigzag: arrive on
## the floor from the left, it leads to the right.
func _add_escalator(
	rules: BuildingRules,
	rng: RandomNumberGenerator,
	taken: Dictionary,
	index: int,
	avoid_towards: float,
	must: bool
) -> float:
	# Exactly one draw per placed escalator, as before M24g: the layout after the
	# escalators keeps drawing from the generator, and an extra roll would reshuffle
	# the doors, walls and lamps of the whole building for every seed.
	var before := rng.state
	var coin := rng.randi()
	for side: float in _escalator_sides(coin, index, avoid_towards):
		var spot := _edge_escalator(rules, taken, index, side)
		if spot.is_empty():
			continue
		# A 45° escalator takes a band of slots on two floors, and on a narrow floor it
		# eats almost everything: an optional one gives way to the door and lamps.
		if not must:
			var room := true
			for level: int in spot:
				room = room and _room_left(rules, taken, level, (spot[level] as Array).size())
			if not room:
				continue
		var escalator := EscalatorSpot.new()
		escalator.floor_index = index
		escalator.towards = side
		var first: int = (spot[index] as Array)[0]
		escalator.x = rules.slot_x(first)
		var span := rules.floor_span(index)
		escalator.edge = span.x if side < 0.0 else span.y
		for level: int in spot:
			for slot: int in spot[level]:
				occupy(taken, level, slot)
		escalators.append(escalator)
		return side
	rng.state = before
	return 0.0


## Which directions to try the descent in, in order. The second on a floor — only the
## other one from the first. The first — zigzag: away from the edge where the
## escalator from above arrived on this floor; if none arrived — by the [param coin]
## draw.
func _escalator_sides(coin: int, index: int, avoid_towards: float) -> Array[float]:
	if not is_zero_approx(avoid_towards):
		return [-avoid_towards] as Array[float]
	var arrived := 0.0
	for escalator in escalators:
		if escalator.floor_index == index - 1:
			arrived = escalator.towards
	var first := -arrived if not is_zero_approx(arrived) else (1.0 if coin % 2 == 0 else -1.0)
	return [first, -first] as Array[float]


## Escalator slots at edge [param side] from floor [param index]: level → slots taken
## on it, the upper landing's slot first. Empty — it does not fit: taken, blocked by a
## shaft, or the floor is narrow.
##
## The edge is that of the narrower of the two floors on this side: under the tower the
## podium is wider, and a flight to its edge would leave the tower for the street.
func _edge_escalator(
	rules: BuildingRules, taken: Dictionary, index: int, side: float
) -> Dictionary:
	var here := rules.floor_span(index)
	var below := rules.floor_span(index + 1)
	var edge := maxf(here.x, below.x) if side < 0.0 else minf(here.y, below.y)
	var lowest := edge - side * rules.escalator_edge_margin
	var goal := lowest - side * rules.escalator_run
	var slots := rules.slot_range(index)
	var top := -1
	# The slot nearest to the edge from which the flight does not cross the edge margin.
	for slot in range(slots.x, slots.y + 1):
		var x := rules.slot_x(slot)
		if side < 0.0 and x >= goal - 0.001:
			top = slot
			break
		if side > 0.0 and x <= goal + 0.001:
			top = slot
	if top < 0:
		return {}
	var top_x := rules.slot_x(top)
	var bottom_x := top_x + side * rules.escalator_run
	var used := {}
	used[index] = _slots_between(rules, index, top_x, edge)
	used[index + 1] = _slots_between(
		rules, index + 1, bottom_x - side * rules.escalator_low_span, edge
	)
	for level: int in used:
		for slot: int in used[level]:
			if is_taken(taken, level, slot):
				return {}
	# A shaft in the flight's band — the cab would pass through the belt.
	var near := minf(top_x, edge)
	var far := maxf(top_x, edge)
	for shaft in shafts:
		if shaft.bottom < index or shaft.top > index + 1:
			continue
		var half := rules.shaft_width * 0.5
		if shaft.x + half > near and shaft.x - half < far:
			return {}
	return used


## Slots of level [param level] between [param from_x] and [param to_x], the one
## nearest to [param from_x] first.
func _slots_between(rules: BuildingRules, level: int, from_x: float, to_x: float) -> Array[int]:
	var found: Array[int] = []
	var slots := rules.slot_range(level)
	var low := minf(from_x, to_x) - 0.001
	var high := maxf(from_x, to_x) + 0.001
	for slot in range(slots.x, slots.y + 1):
		var x := rules.slot_x(slot)
		if x >= low and x <= high:
			found.append(slot)
	if from_x > to_x:
		found.reverse()
	return found


## Whether room will be left on the level for the mandatory items — one door and the
## lamps — if [param taking] more slots are taken on it. Doors beyond one do not count
## as mandatory: they take what is left (ADR-0028, decision 2).
##
## Without this count the layout spends the floor's last slots on what need not be
## placed, and then a lamp shares a slot with a door: a floor without a lamp is black
## in the frame, and for the darkness rule it is forever lit — nothing to put out
## (ADR-0023).
func _room_left(rules: BuildingRules, taken: Dictionary, level: int, taking: int) -> bool:
	var free := _free_slots(rules, taken, [level] as Array[int])
	return free.size() - taking >= mini(rules.doors_on(level), 1) + rules.lamps_on(level)


## The building exit: its own slot on the bottom floor, so that neither a door, nor a
## lamp, nor the respawn point lands on it — otherwise Otto would leave as soon as he
## respawned. The slot is at the garage gate ([method BuildingBasement.exit_slot]).
func _lay_exit(rules: BuildingRules, taken: Dictionary) -> void:
	var bottom := floors - 1
	var slot := BuildingBasement.exit_slot(rules)
	if is_taken(taken, bottom, slot):
		push_error("the exit spot by the gate is taken")
	exit_x = rules.slot_x(slot)
	occupy(taken, bottom, slot)


func _lay_doors(rules: BuildingRules, rng: RandomNumberGenerator, taken: Dictionary) -> void:
	# Red ones go first: on an almost empty floor they find room more easily.
	#
	# And only where the route leads: an opening cuts the floor in two, and a document
	# beyond the hole can only be had by jumping over it, while a miss drops you a floor.
	var with_document := BuildingDocuments.lay(self, rules, rng, taken, seed_value)

	for index in floors:
		var already := 1 if with_document.has(index) else 0
		for _number in mini(rules.doors_on(index), 1) - already:
			if not place_door(rules, rng, taken, index, false):
				break


## Doors beyond the mandatory one: up to the map's count, as many as fit in what is left.
func _lay_more_doors(rules: BuildingRules, rng: RandomNumberGenerator, taken: Dictionary) -> void:
	# Per-floor count in a single pass: extra doors go only on their own floor and do
	# not change another floor's count.
	var placed: Dictionary = {}
	for door in doors:
		placed[door.floor_index] = int(placed.get(door.floor_index, 0)) + 1
	for index in floors:
		for _number in rules.doors_on(index) - int(placed.get(index, 0)):
			if not place_door(rules, rng, taken, index, false):
				break


## Takes the slots right against walls: a door behind a wall is a door that cannot be
## entered. With the same gap the wall itself avoids doors ([method _wall_blockers]).
func _reserve_beside_walls(rules: BuildingRules, taken: Dictionary) -> void:
	var reach := (rules.slot_x(1) - rules.slot_x(0)) * 0.5 + rules.inner_wall_width * 0.5
	for wall in walls:
		var span := rules.slot_range(wall.floor_index)
		for slot in range(span.x, span.y + 1):
			if absf(rules.slot_x(slot) - wall.x) < reach:
				occupy(taken, wall.floor_index, slot)


## Places a door on a free slot of the floor. Returns false if no slot was found.
##
## Public for [BuildingDocuments]: red doors are placed by the same draw as blue ones.
func place_door(
	rules: BuildingRules,
	rng: RandomNumberGenerator,
	taken: Dictionary,
	floor_index: int,
	with_document: bool,
	routed: Dictionary = {},
	spans: Dictionary = {}
) -> bool:
	var free := _free_slots(rules, taken, [floor_index] as Array[int])
	if not routed.is_empty():
		free = free.filter(
			func(candidate: int) -> bool:
				var x := rules.slot_x(candidate)
				return routed.has(BuildingRoute.node_in(spans, floor_index, x))
		)
	if free.is_empty():
		return false

	var slot := pick_any(rng, free)

	var door := DoorSpot.new()
	door.floor_index = floor_index
	door.x = rules.slot_x(slot)
	door.has_document = with_document
	occupy(taken, floor_index, slot)
	doors.append(door)
	return true


## Inner walls: not on every floor, and one that locks something is removed.
##
## A wall is placed and immediately checked against the fully assembled building. It
## cannot be checked beforehand: reachability depends on all walls at once, not on each
## separately — two walls harmless on their own lock a floor together.
##
## The check goes through [BuildingRoute], not a walk of its own: floor pieces and the
## links between them must not diverge, and there is one computation for the whole
## project.
##
## **The threshold is stricter than [method BuildingRoute.is_winnable]:** a wall may not
## cut off even a piece of floor where nothing lies. That one tracks the documents and
## the exit and does not care about pockets — while the bot, entering a pocket, gets
## stuck: on seed 1 it stood for 3001 steps on floor 22, "no move". The double-deck
## pair is checked by exactly the same threshold ([BuildingDecks]).
func _lay_walls(rules: BuildingRules, rng: RandomNumberGenerator) -> void:
	for index in range(floors):
		if rng.randf() >= rules.wall_chance:
			continue
		var x := _pick_wall_x(rules, rng, index)
		if is_inf(x):
			continue

		var wall := WallSpot.new()
		wall.floor_index = index
		wall.x = x
		walls.append(wall)
		if not BuildingRoute.nothing_is_cut_off(self, rules, index):
			walls.pop_back()


## Where on the floor a wall will stand: the border between neighbouring slots.
## [code]INF[/code] — no suitable border.
##
## Borders at the very edge of the floor are discarded: a wall there cuts off not half
## the floor but a strip with nothing to stand on. At least two slots remain on each side.
##
## A border inside an opening is no good either: there must be floor under the wall,
## otherwise it hangs over a shaft.
func _pick_wall_x(rules: BuildingRules, rng: RandomNumberGenerator, index: int) -> float:
	var span := rules.slot_range(index)
	var busy := _wall_blockers(rules, index)
	var half := rules.inner_wall_width * 0.5

	# Slots are collected, not coordinates: picking from a set is a single line for the
	# whole file ([method pick_any]), because the seed's outcome depends on the order
	# of calls to the generator.
	var fitting: Array[int] = []
	for slot in range(span.x + 1, span.y - 1):
		var x := _wall_x_at(rules, slot)
		var in_the_way := false
		for zone: Vector2 in busy:
			if x + half > zone.x and x - half < zone.y:
				in_the_way = true
				break
		if not in_the_way:
			fitting.append(slot)

	if fitting.is_empty():
		return INF
	return _wall_x_at(rules, pick_any(rng, fitting))


## Middle of the border between slot [param slot] and the next one: that is where the wall stands.
static func _wall_x_at(rules: BuildingRules, slot: int) -> float:
	return (rules.slot_x(slot) + rules.slot_x(slot + 1)) * 0.5


## Where a wall may not go: spans it would cover itself or press tight against.
##
## A half-step gap is not decoration: the wall is almost a metre thick, and placed
## flush against an opening it leaves no room to stand. The escalator was caught by
## this twice — by the upper landing and by the arrival landing on the floor below:
## the belt ran into the wall, and the reachability graph lost a link.
func _wall_blockers(rules: BuildingRules, index: int) -> Array[Vector2]:
	var clearance := (rules.slot_x(1) - rules.slot_x(0)) * 0.5
	var busy: Array[Vector2] = []
	# The escalator's slot too: a full-depth wall would stand across the flight.
	var openings := gaps_on(rules, index)
	for escalator in escalators:
		if escalator.floor_index == index:
			openings.append(escalator.gap(rules))
	for gap: Vector2 in openings:
		busy.append(Vector2(gap.x - clearance, gap.y + clearance))

	# The shaft's column is counted whole, not by the holes from [method gaps_on]: at the
	# bottom of a shaft there is no hole — the slab is whole there — but the cab stands on
	# it too, and a wall placed by the holes alone grew right through it. On seed 6 one
	# stood 0.45 m inside the cab of shaft 15..21: Otto entering it ended up in the wall,
	# and the reachability graph promised an exit in one direction only.
	#
	# [method _is_clear] counts the same way: a shaft takes the slot on all of its
	# levels, bottom included.
	var shaft_half := rules.shaft_width * 0.5 + clearance
	for shaft in shafts:
		if shaft.top <= index and index <= shaft.bottom:
			busy.append(Vector2(shaft.x - shaft_half, shaft.x + shaft_half))

	for escalator in escalators:
		if escalator.floor_index == index:
			busy.append(Vector2(escalator.x - clearance, escalator.x + clearance))
		elif escalator.floor_index == index - 1:
			# The 45° flight hangs over this floor from the landing to the upper landing
			# on the floor above (ADR-0043, decision 15): a wall under it would pass
			# through the belt. The gap is at the landing; above the other end there is
			# already the whole slab of the floor above.
			var landing := escalator.landing(rules)
			var low := minf(landing, escalator.x) - (clearance if escalator.towards < 0.0 else 0.0)
			var high := maxf(landing, escalator.x) + (clearance if escalator.towards > 0.0 else 0.0)
			busy.append(Vector2(low, high))

	# A door behind a wall is a door that cannot be entered, and an exit — an impassable building.
	for door in doors:
		if door.floor_index == index:
			busy.append(Vector2(door.x - clearance, door.x + clearance))
	# The car at the gate too: a wall through it would cut off the exit along with it.
	if index == floors - 1:
		busy.append(Vector2(exit_x - clearance, exit_x + clearance))
		var car := ExitCar.parked_span(rules)
		busy.append(Vector2(car.x - clearance, car.y + clearance))
	return busy


## A slot from the set, preferably not [param avoid]. If there is no choice — any:
## the ban is soft, and a band cannot be left without a shaft.
static func _pick_slot(rng: RandomNumberGenerator, free: Array[int], avoid: int) -> int:
	var pool := free.filter(func(slot: int) -> bool: return slot != avoid)
	return pick_any(rng, pool if not pool.is_empty() else free)


## Any slot from the set.
##
## The seed's outcome depends on the order of calls to the generator, so picking is
## one line for the whole project rather than rewritten in each rule. Public for
## [BuildingDecks]: it picks the shaft for the pair by the same draw.
static func pick_any(rng: RandomNumberGenerator, pool: Array[int]) -> int:
	return pool[rng.randi_range(0, pool.size() - 1)]


## All slots free on all the listed levels at once.
##
## A slot beyond the level's silhouette does not count as free: that is the street,
## not a floor.
func _free_slots(rules: BuildingRules, taken: Dictionary, on_floors: Array[int]) -> Array[int]:
	var free: Array[int] = []
	for slot in rules.slots:
		var busy := false
		for index in on_floors:
			if is_taken(taken, index, slot) or not rules.slot_available(slot, index):
				busy = true
				break
		if not busy:
			free.append(slot)
	return free


## Takes a slot on the floor. Public for [BuildingLamps]: occupied is one for all.
static func occupy(taken: Dictionary, floor_index: int, slot: int) -> void:
	if not taken.has(floor_index):
		taken[floor_index] = {}
	taken[floor_index][slot] = true


static func is_taken(taken: Dictionary, floor_index: int, slot: int) -> bool:
	return taken.has(floor_index) and taken[floor_index].has(slot)
