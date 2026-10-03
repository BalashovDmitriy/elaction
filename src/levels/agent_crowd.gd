class_name AgentCrowd
extends RefCounted

## A crowd on a floor (@041F-0458; ADR-0053, decision 5): on Otto's floor, above and
## below, [constant Arcade.CROWD] agents or more stand on the floor — those far from
## Otto leave through doors, the near ones stay. Those coming out of a door and riding a cab do not
## count: the former are still in the doorway, the latter do not stand on the floor. Moved out of
## [GreyboxLevel] — a rule without level nodes.


## Extras in the crowd from [param agents]: a dictionary "agent — true". [param here] —
## Otto's floor, [param otto_x] — where he stands, scene.
##
## [param leaving] — the extras of the previous count: they stay among the extras first, not
## by distance. The count runs every frame, and one walking to a door closer to Otto would
## stop being a far one on the way — he would be recalled and his neighbour sent away instead,
## and the crowd would just stand there, passing the leaving to each other.
static func extras(
	agents: Array[Enemy], rules: BuildingRules, here: int, otto_x: float, leaving: Dictionary = {}
) -> Dictionary:
	var on_floor: Dictionary = {}
	for agent in agents:
		if agent.is_dead() or agent.is_emerging() or Takedown.rides_a_car(agent):
			continue
		var where := rules.floor_index_near(WorldSpace.to_plane(agent.global_position).y)
		if absi(where - here) > 1:
			continue
		if not on_floor.has(where):
			var fresh: Array[Enemy] = []
			on_floor[where] = fresh
		(on_floor[where] as Array[Enemy]).append(agent)
	var crowd: Dictionary = {}
	for where: int in on_floor:
		var standing := on_floor[where] as Array[Enemy]
		var leavers := Arcade.crowd_leavers(Arcade.rom_floor(where, rules.floors), standing.size())
		if leavers == 0:
			continue
		standing.sort_custom(
			func(a: Enemy, b: Enemy) -> bool:
				if leaving.has(a) != leaving.has(b):
					return leaving.has(a)
				return absf(a.global_position.x - otto_x) > absf(b.global_position.x - otto_x)
		)
		for index in leavers:
			crowd[standing[index]] = true
	return crowd
