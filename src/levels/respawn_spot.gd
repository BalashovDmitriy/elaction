class_name RespawnSpot
extends RefCounted

## Where Otto returns after dying — by the ROM rule (@7633, @2FAA;
## ADR-0053, decision 2): no lower than the fifth ROM floor, at the floor's red door if
## the document behind it has not been taken yet, and without one — at the floor's fixed
## point. Where Otto died and where the agents stand does not matter: the agents leave the
## floors, and they are released again with a delay. Moved out of [GreyboxLevel] — a rule
## without nodes.

## A floor piece narrower than this, m, is a dead end: between a wall and a shaft there can be
## a pocket a metre and a half wide, and Otto returned there would get out of it only by cab
## (M24g, seed 3). The return point is searched for outside such pockets.
const POCKET: float = 3.0


## The return floor for one who died on [param index]: the same, but no lower than the fifth
## ROM floor. Below that the arcade building has the first floors with doors at the edges,
## and one who returned there right by the exit would pass them for free.
static func floor_for(rules: BuildingRules, index: int) -> int:
	var at := index
	while (
		at > BuildingRules.ROOF and Arcade.rom_floor(at, rules.floors) < Arcade.RESPAWN_FROM_FLOOR
	):
		at -= 1
	return at


## The spot on floor [param index]: at red door [param red_x] if there is one
## (NAN — none), and without it — the ROM point at floor fraction
## [constant Arcade.RESPAWN_SHARE]. Otto stands at the nearest spot to it where
## one can stand. Only the ROM point avoids pockets, while the floor has something
## besides them: a red door in a pocket is still the goal, and Otto stands by it.
static func choose(plan: BuildingPlan, rules: BuildingRules, index: int, red_x: float) -> float:
	var spots := plan.safe_spots(rules, index)
	if spots.is_empty():
		return plan.safe_x(rules, index)
	var target := red_x
	if is_nan(target):
		var span := rules.floor_span(index)
		target = lerpf(span.x, span.y, Arcade.RESPAWN_SHARE)
		var open := _off_pockets(plan, rules, index, spots)
		if not open.is_empty():
			spots = open

	var best := spots[0]
	for x: float in spots:
		if absf(x - target) < absf(best - target):
			best = x
	return best


## Where on floor [param index] the red door with a document from [param doors] is, or
## NAN: the document behind it was taken or there is no red door on the floor.
static func red_door_x(doors: Array[Door], rules: BuildingRules, index: int) -> float:
	for door in doors:
		if door.is_pending() and rules.floor_index_near(door.mat_position().y) == index:
			return door.mat_position().x
	return NAN


## Spots from [param spots] that stand on floor pieces wider than [constant POCKET].
static func _off_pockets(
	plan: BuildingPlan, rules: BuildingRules, index: int, spots: PackedFloat64Array
) -> PackedFloat64Array:
	var open := PackedFloat64Array()
	var pieces := BuildingPlan.spans_between(plan.blocks_on(rules, index), rules.floor_span(index))
	for piece: Vector2 in pieces:
		var same := PackedFloat64Array()
		for x: float in spots:
			if x >= piece.x and x <= piece.y:
				same.append(x)
		if same.size() > 0 and same[same.size() - 1] - same[0] >= POCKET:
			open.append_array(same)
	return open
