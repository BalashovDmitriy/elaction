class_name RespawnSpot
extends RefCounted

## Куда Otto возвращается после гибели: на тот же этаж, но подальше от тех,
## кто его там убил. Вынесено из [GreyboxLevel] — правило без узлов.

## Кусок этажа уже этого, м, — тупик, а не своя сторона: возвращение в игру
## ищет место на всём этаже.
const POCKET: float = 3.0


## Место на этаже [param index] плана [param plan]: своя сторона от
## [param from_x], где погиб, — и дальше всех живых из [param agents].
static func choose(
	plan: BuildingPlan, rules: BuildingRules, index: int, from_x: float, agents: Array[Enemy]
) -> float:
	var spots := plan.safe_spots(rules, index)
	if spots.is_empty():
		return plan.safe_x(rules, index)
	# Своя сторона этажа, а не та, что за стеной или проёмом. Но не карман:
	# между стеной и шахтой бывает тупик в полтора метра, и вернувшийся туда Otto
	# уходил бы из него только кабиной, под огнём из-за шахты, — и погибал там
	# раз за разом (M24g, сид 3). Тогда — весь этаж.
	var own := plan.spots_on_the_same_piece(rules, index, from_x, spots)
	var sorted := own.duplicate()
	sorted.sort()
	if not own.is_empty() and sorted[sorted.size() - 1] - sorted[0] >= POCKET:
		spots = own

	var best := spots[0]
	var best_gap := -1.0
	for x: float in spots:
		var gap := INF
		for agent in agents:
			if agent.is_dead():
				continue
			gap = minf(gap, absf(agent.global_position.x - x))
		if gap > best_gap:
			best_gap = gap
			best = x
	return best
