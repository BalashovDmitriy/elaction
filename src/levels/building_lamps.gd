class_name BuildingLamps
extends RefCounted

## Lamps on the building plan: where a fixture hangs on each floor.
##
## Separate from [BuildingPlan], like [BuildingDecks] and [BuildingBasement]:
## the layout hit the line limit. The count is the same, moved without changes
## (M24b).

## Half-width of a lamp with its hanger, m: the fixture edge must not hang over a hole.
const LAMP_REACH: float = 0.3


## Places lamps: by floor width and at the middles of equal zones.
##
## The roof gets no lamps — there is sky above it, nothing to hang a hanger from. It is not even
## in the range: floors start from zero, the roof lies above (ADR-0014).
##
## Not random, like the rest: a lamp zone is a unit of darkness (ADR-0023), and lamps
## bunched at one edge would leave the other edge of the floor dark with all of them lit.
## The floor is divided into as many zones as there are lamps, and each goes into the free slot
## nearest the middle of its zone.
##
## Lamps yield to shafts, escalators and the mandatory door — doors beyond it
## are placed after the lamps ([method BuildingPlan.generate]) — so there may not be enough
## free slots, and then there are fewer lamps. A dark floor on the map asks for no lamps
## at all ([method BuildingRules.is_unlit]). **Any other — not zero:** a floor
## without a single lamp is not lit and has nothing to darken it with — for the darkness rule it is
## lit forever, though in the frame it is black. When no free slots are
## left, a lamp shares a slot with a door: the door stands at the back wall, the lamp
## hangs under the ceiling, and they get in each other's way only on the plan. With the default
## rules it does not come to this — 12000 floors on 400 seeds got at least
## one — but the margin is needed for rules that do not exist yet.
static func lay(plan: BuildingPlan, rules: BuildingRules, taken: Dictionary) -> void:
	for index in plan.floors:
		var span := rules.slot_range(index)
		var free: Array[int] = []
		for slot in range(span.x, span.y + 1):
			if not BuildingPlan.is_taken(taken, index, slot):
				free.append(slot)
		# Slots without a ceiling are filtered out before the fallback, not after: otherwise a floor
		# whose free slots are all under an escalator opening would be left without
		# a single lamp.
		var ceiling := func(slot: int) -> bool: return _has_a_ceiling(plan, rules, index, slot)
		free = free.filter(ceiling)
		if free.is_empty():
			free = _slots_beside_the_openings(plan, rules, index).filter(ceiling)

		var wanted := rules.lamps_on(index)
		for number in wanted:
			if free.is_empty():
				break
			var ideal := (
				float(span.x)
				+ float(span.y - span.x) * (2.0 * float(number) + 1.0) / (2.0 * float(wanted))
			)
			var slot := _nearest_slot(free, ideal)
			free.erase(slot)

			var lamp := BuildingPlan.LampSpot.new()
			lamp.floor_index = index
			lamp.x = rules.slot_x(slot)
			BuildingPlan.occupy(taken, index, slot)
			plan.lamps.append(lamp)


## Floor slots where a lamp can still be hung when no free ones are left:
## everything except openings — shafts, escalators and the exit. There will never be a lamp
## over an opening: a cab runs there and the lamp has nowhere to fall.
##
## These are the slots where one can stand ([method BuildingPlan.safe_spots]) — the same
## selection, only as grid slots rather than coordinates.
static func _slots_beside_the_openings(
	plan: BuildingPlan, rules: BuildingRules, floor_index: int
) -> Array[int]:
	var clear := plan.safe_spots(rules, floor_index)
	var free: Array[int] = []
	var span := rules.slot_range(floor_index)
	for slot in range(span.x, span.y + 1):
		if clear.has(rules.slot_x(slot)):
			free.append(slot)
	return free


## Whether there is a ceiling over the slot: over the opening of an escalator from the floor above
## there is nothing for a lamp to hang from (ADR-0043, decision 15). A 45° run goes as an opening to
## the floor edge, and under it the floor below has no ceiling for two or three slots.
static func _has_a_ceiling(plan: BuildingPlan, rules: BuildingRules, index: int, slot: int) -> bool:
	var x := rules.slot_x(slot)
	for escalator in plan.escalators:
		if escalator.floor_index != index - 1:
			continue
		var gap := escalator.gap(rules)
		if x + LAMP_REACH > gap.x and x - LAMP_REACH < gap.y:
			return false
	return true


## The free slot nearest the desired one. At equal distance — the left one.
static func _nearest_slot(free: Array[int], ideal: float) -> int:
	var best := free[0]
	for slot in free:
		if absf(float(slot) - ideal) < absf(float(best) - ideal):
			best = slot
	return best
