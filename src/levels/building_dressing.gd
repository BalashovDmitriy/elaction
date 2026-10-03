class_name BuildingDressing
extends RefCounted

## Floor dressing: what stands at the corridor's back wall and what hangs on it
## (ADR-0029, decision 3; since M21b — pack models, ADR-0033, decision 3).
##
## Decor only. In the arcade a floor has nothing but doors, lamps and shafts, and
## our furniture serves as neither cover nor obstacle: the items have no bodies,
## bullets and people pass by. So the layout has one rule — do not hurt
## readability: an item does not take the place of a door, lamp, shaft, escalator or
## exit and does not press against a solid wall. Layout without a scene, by plan and seed —
## tests check it on any building; [BuildingProps] builds the items.
##
## What to place is decided by the building kind ([BuildingIdentity]): hotel and office take
## their own items and the shared ones from [PropCatalog].


## A floor item: catalogue name, floor and middle along x.
class PropSpot:
	extends RefCounted
	var name: String = ""
	var floor_index: int = 0
	var x: float = 0.0
	## Width the item takes at the wall, m.
	var width: float = 0.0


## The chance a free slot gets floor furniture (user's
## decision: "rich but readable" — every second one; since M24i — more often: in the
## shots the floor stayed empty, ADR-0048).
const FLOOR_CHANCE: float = 0.7

## Fractions of the slot pitch an item fits into: a narrow one — its own slot, a wide one —
## three slots if the neighbours are free. Wider than its slot, an item would touch
## the neighbour's door or sign.
const NARROW: float = 0.8
const WIDE: float = 2.4

## A wall item is no wider than this, m: it hangs between pilasters. The number is shared with
## the catalogue — it scales the models to it.
const WALL_WIDTH: float = PropCatalog.WALL_MAX_WIDTH

## Furniture taller than this covers the wall: nothing is hung above it. Height includes
## what stands on top: a lamp on a chest of drawers overlapped the bottom of a picture.
const TALL: float = 1.25

## Mixed with the seed so the dressing does not repeat the layout draw.
const SALT: int = 0x0DEC_0A7E

var props: Array[PropSpot] = []
## Items on the wall.
var decor: Array[PropSpot] = []
## Floors with a pipe running under the ceiling.
var pipes: Array[int] = []


## Building dressing by its plan, seed and kind.
static func lay(
	rules: BuildingRules,
	plan: BuildingPlan,
	building_seed: int,
	identity: BuildingIdentity = BuildingIdentity.new()
) -> BuildingDressing:
	var dressing := BuildingDressing.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, SALT])
	var step := rules.slot_x(1) - rules.slot_x(0)
	var floor_items := PropCatalog.pick(PropCatalog.Place.FLOOR, identity.fit())
	var wall_items := PropCatalog.pick(PropCatalog.Place.WALL, identity.fit())
	var style := BuildingStyle.of(identity)
	# An office's back wall is glass (ADR-0056, decision 4): nothing hangs on it.
	if style.glass_wall:
		wall_items.clear()
	# The exit floor is a garage: empty, with one car (ADR-0031, decision 4).
	for index in rules.floors - 1:
		# A special floor is furnished by its own hall ([FloorHall], ADR-0057, decision 3):
		# there is no wall, and corridor furniture would stand in front of the hall in the void.
		if FloorRole.hall_at(rules, index):
			continue
		var spots := free_spots(rules, plan, index)
		var zones := blocked_zones(rules, plan, index)
		var taken := {}
		var on_floor: Array[PropSpot] = []
		for slot in spots.size():
			if taken.has(slot) or rng.randf() >= FLOOR_CHANCE:
				continue
			var roomy := _neighbour_free(spots, slot, -1, step, taken)
			roomy = roomy and _neighbour_free(spots, slot, 1, step, taken)
			var room := step * (WIDE if roomy else NARROW)
			room = minf(room, _room_between(zones, spots[slot]))
			var item := _draw(rng, floor_items, room)
			if item == null:
				continue
			var prop := _spot(item.name, index, spots[slot])
			on_floor.append(prop)
			dressing.props.append(prop)
			taken[slot] = true
			if prop.width > step * NARROW:
				taken[slot - 1] = true
				taken[slot + 1] = true
		var last := ""
		for x: float in wall_spots(rules, plan, index):
			if _under_tall(on_floor, x) or _beside_shaft(rules, plan, index, x):
				continue
			if rng.randf() >= style.decor_share:
				continue
			var hung := _draw(rng, wall_items, WALL_WIDTH, last)
			if hung == null:
				continue
			last = hung.name
			dressing.decor.append(_spot(hung.name, index, x))
		if rng.randf() < style.pipe_share:
			dressing.pipes.append(index)
	return dressing


## Floor slots where an item may stand: where people stand
## ([method BuildingPlan.safe_spots] — not a shaft, an escalator or the exit), and not
## in the place of a door or lamp, not at an escalator's lower landing or under the bottom of its
## run, not right against a solid wall.
static func free_spots(
	rules: BuildingRules, plan: BuildingPlan, floor_index: int
) -> PackedFloat64Array:
	var step := rules.slot_x(1) - rules.slot_x(0)
	var near_wall := step * 0.5 + rules.inner_wall_width * 0.5
	var busy := PackedFloat64Array()
	for door in plan.doors:
		if door.floor_index == floor_index:
			busy.append(door.x)
	for lamp in plan.lamps:
		if lamp.floor_index == floor_index:
			busy.append(lamp.x)
	# The bottom of the run from the floor above: the belt at 45° is below head height there
	# (ADR-0043, decision 15), and an item would stand through it.
	var low_flights: Array[Vector2] = []
	for escalator in plan.escalators:
		if escalator.floor_index + 1 == floor_index:
			var landing := escalator.landing(rules)
			busy.append(landing)
			var start := landing - escalator.towards * rules.escalator_low_span
			low_flights.append(Vector2(minf(landing, start), maxf(landing, start)))

	var free := PackedFloat64Array()
	for x: float in plan.safe_spots(rules, floor_index):
		var taken := false
		for other: float in busy:
			if absf(other - x) < step * 0.5:
				taken = true
				break
		for flight: Vector2 in low_flights:
			if x > flight.x and x < flight.y:
				taken = true
		for wall in plan.walls:
			if wall.floor_index == floor_index and absf(wall.x - x) < near_wall:
				taken = true
		if not taken:
			free.append(x)
	return free


## Floor slots for a wall item: where people stand, except doors and
## slots right against a solid wall. A lamp does not get in the wall's way — it hangs under
## the ceiling — and the slot under it is fine too: otherwise on a narrow tower floor the walls
## stayed bare.
static func wall_spots(
	rules: BuildingRules, plan: BuildingPlan, floor_index: int
) -> PackedFloat64Array:
	var step := rules.slot_x(1) - rules.slot_x(0)
	var near_wall := step * 0.5 + rules.inner_wall_width * 0.5
	var free := PackedFloat64Array()
	for x: float in plan.safe_spots(rules, floor_index):
		var taken := false
		for door in plan.doors:
			if door.floor_index == floor_index and absf(door.x - x) < step * 0.5:
				taken = true
		for wall in plan.walls:
			if wall.floor_index == floor_index and absf(wall.x - x) < near_wall:
				taken = true
		if not taken:
			free.append(x)
	return free


## What furniture on a floor must not touch, as "left edge, right edge" segments:
## door openings, shafts with their trims and call button panel, solid walls and
## the escalator run from the floor above — it comes down here as a sloping strip almost
## two metres long.
static func blocked_zones(
	rules: BuildingRules, plan: BuildingPlan, floor_index: int
) -> Array[Vector2]:
	var zones: Array[Vector2] = []
	var door_half := Door.LEAF_SIZE.x * 0.5
	for door in plan.doors:
		if door.floor_index == floor_index:
			zones.append(Vector2(door.x - door_half, door.x + door_half))
	var shaft_half := rules.shaft_width * 0.5 + BuildingShafts.PORTAL_JAMB
	for shaft in plan.shafts:
		if shaft.top <= floor_index and floor_index <= shaft.bottom:
			zones.append(Vector2(shaft.x - shaft_half, shaft.x + shaft_half))
			if floor_index > BuildingRules.ROOF:
				# Furniture stands in front of the wall and would cover the buttons.
				var panel := BuildingShafts.call_panel_span(rules, plan, shaft.x, floor_index)
				if panel.y > panel.x:
					zones.append(panel)
	for wall in plan.walls:
		if wall.floor_index == floor_index:
			zones.append(wall.band(rules))
	for escalator in plan.escalators:
		if escalator.floor_index + 1 == floor_index:
			zones.append(escalator.gap(rules))
	return zones


## How much width the slot [param x] has to the nearest occupied zone — doubled, because
## an item stands with its middle on the slot.
static func _room_between(zones: Array[Vector2], x: float) -> float:
	var half := INF
	for zone in zones:
		if x >= zone.x and x <= zone.y:
			return 0.0
		half = minf(half, minf(absf(zone.x - x), absf(x - zone.y)))
	return half * 2.0 - 0.02


## Whether the neighbouring slot is free: it is among the free ones exactly one pitch from this one
## and no one has taken it yet.
static func _neighbour_free(
	spots: PackedFloat64Array, slot: int, side: int, step: float, taken: Dictionary
) -> bool:
	var other := slot + side
	if other < 0 or other >= spots.size() or taken.has(other):
		return false
	return absf(absf(spots[other] - spots[slot]) - step) < 0.01


## An item by draw from those that fit [param room] in width; not the same as
## [param avoid], if there is a choice.
static func _draw(
	rng: RandomNumberGenerator, items: Array[PropCatalog.Entry], room: float, avoid: String = ""
) -> PropCatalog.Entry:
	var fitting: Array[PropCatalog.Entry] = []
	for item in items:
		if PropCatalog.footprint(item.name).x <= room and item.name != avoid:
			fitting.append(item)
	if fitting.is_empty():
		return null
	return fitting[rng.randi_range(0, fitting.size() - 1)]


static func _spot(prop_name: String, floor_index: int, x: float) -> PropSpot:
	var spot := PropSpot.new()
	spot.name = prop_name
	spot.floor_index = floor_index
	spot.x = x
	spot.width = PropCatalog.footprint(prop_name).x
	return spot


## Whether the slot is next to a shaft: on the wall at the portal is the call button panel
## ([BuildingShafts], ADR-0033, decision 7), and a picture would overlap it.
static func _beside_shaft(
	rules: BuildingRules, plan: BuildingPlan, floor_index: int, x: float
) -> bool:
	var step := rules.slot_x(1) - rules.slot_x(0)
	for shaft in plan.shafts:
		if shaft.top <= floor_index and floor_index <= shaft.bottom:
			if absf(shaft.x - x) < step * 1.5:
				return true
	return false


## Whether tall furniture covering the wall stands at [param x].
static func _under_tall(on_floor: Array[PropSpot], x: float) -> bool:
	for prop in on_floor:
		var tall := PropCatalog.footprint(prop.name).y > TALL
		if tall and absf(prop.x - x) < prop.width * 0.5 + WALL_WIDTH * 0.5:
			return true
	return false
