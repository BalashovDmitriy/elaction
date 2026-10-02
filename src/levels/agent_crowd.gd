class_name AgentCrowd
extends RefCounted

## Толпа на этаже (@041F-0458; ADR-0053, решение 5): на этаже Otto, выше и
## ниже стоят на полу [constant Arcade.CROWD] агентов или больше — дальние от
## Otto уходят в двери, ближние остаются. Вышедшие из двери и едущие в кабине не
## в счёт: первые ещё в проёме, вторые на этаже не стоят. Вынесено из
## [GreyboxLevel] — правило без узлов уровня.


## Лишние в толпе из [param agents]: словарь «агент — true». [param here] —
## этаж Otto, [param otto_x] — где он стоит, сцена.
##
## [param leaving] — лишние прошлого счёта: они остаются в лишних первыми, а не
## по дальности. Счёт идёт каждый кадр, и ушедший к двери, что ближе к Otto, по
## дороге переставал бы быть дальним — его отзывали бы, а уходить посылали
## соседа, и толпа так и стояла бы, передавая уход друг другу.
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
