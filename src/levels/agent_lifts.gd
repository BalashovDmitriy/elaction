class_name AgentLifts
extends RefCounted

## Where an agent should go to ride to Otto.
##
## There is one rule — "go to the cab already standing level with your floor" — but
## it has four conditions, and each cost the milestone a separate finding. Hence its own
## file rather than four methods in [GreyboxLevel]: that one has already hit
## the thousand-line ceiling.
##
## The ride design is in [ADR-0025](../../docs/adr/0025-shafts-escalators-and-riders.md),
## decision 6. What the agent does with the answer is known to [method Enemy.set_lift_at]:
## he keeps the chosen cab as long as he is offered a ride at all.


## The axis of the cab the agent should enter to get closer to Otto, or NAN.
##
## [param where] — the agent's floor, [param x] — where he stands, [param here] — Otto's
## Otto.
##
## Only one standing level with his floor is offered: nobody in the original has a cab call, and the
## agent has no way to wait for it at the opening — he would shuffle on the edge, turning around
## every frame.
##
## **Of the suitable ones the nearest is taken.** A podium floor has up to five shafts, and
## some cab stands level almost always; the offer jumped from one
## to another, and the agent darted between them, reaching none in half a minute.
##
## On Otto's floor no cab is offered at all: arrived. So a riding agent
## gets out where Otto is, not on the first floor that comes along — while the cab is moving,
## it is level with nothing, and the offer disappears by itself.
##
## **Only one the agent can reach is offered.** He will not turn around in front of
## an obstacle — a cab behind a solid wall or behind another opening
## would mean an agent frozen at the obstacle until the end of the building instead of patrolling.
static func offer(
	plan: BuildingPlan,
	rules: BuildingRules,
	cars: Array[ElevatorCar],
	where: int,
	x: float,
	here: int
) -> float:
	if where == here:
		return NAN

	# Cabs standing level with the agent's floor: only they carry, and they also
	# cover their openings.
	var standing := _standing_at(rules, cars, where)
	if standing.is_empty():
		return NAN

	var blocks := _walk_blocks(plan, rules, where, standing)
	var towards := signi(here - where)
	var best := NAN
	for axis: float in standing:
		var shaft := _shaft_in_column(plan, rules, axis, where)
		if shaft == null:
			continue
		# The shaft must lead toward Otto: otherwise the agent rides away from him.
		if not _leads_towards(shaft, where, towards):
			continue
		if not _reaches(blocks, x, axis):
			continue
		if is_nan(best) or absf(axis - x) < absf(best - x):
			best = axis
	return best


## Whether the agent's floor [param where] has a shaft that carries toward Otto and
## that he can reach — whether a cab stands there now or not.
##
## Such an agent waits for the cab rather than leaving through a door: otherwise an agent a couple
## of floors behind would leave before the cab managed to come for him, and agent rides (ADR-0025,
## decision 6) would not remain at all.
static func can_ride(
	plan: BuildingPlan, rules: BuildingRules, where: int, x: float, here: int
) -> bool:
	if where == here:
		return false
	var towards := signi(here - where)
	for shaft in plan.shafts:
		if shaft.top > where or shaft.bottom < where:
			continue
		if not _leads_towards(shaft, where, towards):
			continue
		var blocks := _walk_blocks(plan, rules, where, PackedFloat64Array([shaft.x]))
		if _reaches(blocks, x, shaft.x):
			return true
	return false


## The nearest door of floor [param where] that the agent can reach from [param x],
## or NAN. A lagging agent leaves there (ADR-0027, decision 3a); like a cab,
## only a reachable one is offered — behind a wall or an opening he would freeze at the obstacle.
static func nearest_door(
	plan: BuildingPlan, rules: BuildingRules, cars: Array[ElevatorCar], where: int, x: float
) -> float:
	var blocks := _walk_blocks(plan, rules, where, _standing_at(rules, cars, where))
	var best := NAN
	for door in plan.doors:
		if door.floor_index != where or not _reaches(blocks, x, door.x):
			continue
		if is_nan(best) or absf(door.x - x) < absf(best - x):
			best = door.x
	return best


## Axes of the cabs standing level with floor [param where].
static func _standing_at(
	rules: BuildingRules, cars: Array[ElevatorCar], where: int
) -> PackedFloat64Array:
	var standing := PackedFloat64Array()
	for car in cars:
		if car.is_aligned() and rules.floor_index_near(_height_of(car)) == where:
			standing.append(car.position.x)
	return standing


## Whether the shaft carries from floor [param where] toward [param towards]: up — −1,
## down — +1, the way floor numbers grow.
static func _leads_towards(shaft: BuildingPlan.ShaftSpot, where: int, towards: int) -> bool:
	var span := shaft.ride_span()
	return (towards > 0 and span.y > where) or (towards < 0 and span.x < where)


## What cuts the agent's walk along the floor: openings and solid walls, except the openings
## where a cab stands.
##
## A standing cab is walked straight through — both the building graph lives by this
## ([BuildingRoute]) and half of a floor cut by a shaft.
static func _walk_blocks(
	plan: BuildingPlan, rules: BuildingRules, where: int, standing: PackedFloat64Array
) -> Array[Vector2]:
	var blocks: Array[Vector2] = []
	for block: Vector2 in plan.blocks_on(rules, where):
		var bridged := false
		for axis: float in standing:
			if block.x <= axis and axis <= block.y:
				bridged = true
				break
		if not bridged:
			blocks.append(block)
	return blocks


## Whether one walking along the floor gets from [param from_x] to [param to_x] without hitting
## any of the obstacles [param blocks].
static func _reaches(blocks: Array[Vector2], from_x: float, to_x: float) -> bool:
	var low := minf(from_x, to_x)
	var high := maxf(from_x, to_x)
	for block: Vector2 in blocks:
		if block.y > low and block.x < high:
			return false
	return true


## The shaft standing in this column and serving this floor.
##
## A column alone does not identify a shaft: runs do not overlap by floors,
## but the same grid slot is taken by different shafts at different heights.
static func _shaft_in_column(
	plan: BuildingPlan, rules: BuildingRules, x: float, index: int
) -> BuildingPlan.ShaftSpot:
	for shaft in plan.shafts:
		if index < shaft.top or index > shaft.bottom:
			continue
		if absf(shaft.x - x) <= rules.shaft_width * 0.5:
			return shaft
	return null


## Node height in rule coordinates: where Y grows downward.
static func _height_of(node: Node3D) -> float:
	return WorldSpace.to_plane(node.global_position).y
