class_name BuildingRoute
extends RefCounted

## Достижимость по зданию: куда можно попасть из точки старта.
##
## Этаж разрезан проёмами на куски, и пешком ходить можно только внутри куска.
## Между кусками и этажами переносят шахты и эскалаторы — по ним и строится граф.
##
## Падения в граф не входят намеренно: если здание проходимо без них, оно проходимо
## тем более. А падение в шахту вдобавок смертельно.
##
## Всё считается по раскладке, без узлов и физики, поэтому проверяется на десятках
## сидов за доли секунды — а именно на редких сидах и вылезают дыры в генерации.


## Узлы, куда можно добраться из точки старта. Ключ — «этаж:кусок».
static func reachable(plan: BuildingPlan, rules: BuildingRules) -> Dictionary:
	return reachable_in(plan, rules, _floor_segments(plan, rules))


## Куски всех этажей: этаж -> пары «левый край, правый край».
##
## Отдаются наружу, чтобы считать узлы пачкой: [method node_in] по готовым кускам
## стоит копейки, а сами куски — это перебор всей раскладки.
static func segments(plan: BuildingPlan, rules: BuildingRules) -> Array:
	return _floor_segments(plan, rules)


## Узел точки этажа по готовым кускам из [method segments]. По нему проверяют,
## ведёт ли туда маршрут: [method reachable] возвращает набор таких же узлов.
static func node_in(floors: Array, floor_index: int, x: float) -> String:
	return _node(floor_index, _segment_at(floors[floor_index], x))


## Те же узлы, что и у [method reachable], но по готовым кускам из
## [method segments]: кто их уже посчитал, второй раз за перебор не платит.
static func reachable_in(plan: BuildingPlan, rules: BuildingRules, floors: Array) -> Dictionary:
	var links := _links(plan, rules, floors)

	var start := _node(0, _segment_at(floors[0], plan.safe_x(rules, 0)))
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


## Проходимо ли здание: все документы собираются и выход достижим.
static func is_winnable(plan: BuildingPlan, rules: BuildingRules) -> bool:
	return unreachable_spots(plan, rules).is_empty()


## Что недостижимо из точки старта: описания мест, по одному на каждое.
##
## Возвращает описания, а не индексы, чтобы упавший тест сразу говорил, где дыра.
static func unreachable_spots(plan: BuildingPlan, rules: BuildingRules) -> Array[String]:
	var floors := _floor_segments(plan, rules)
	var seen := reachable_in(plan, rules, floors)
	var missing: Array[String] = []

	for door in plan.doors:
		if not door.has_document:
			continue
		var node := _node(door.floor_index, _segment_at(floors[door.floor_index], door.x))
		if not seen.has(node):
			missing.append("документ на этаже %d (x=%.0f)" % [door.floor_index, door.x])

	var bottom := plan.floors - 1
	var exit_node := _node(bottom, _segment_at(floors[bottom], plan.exit_x))
	if not seen.has(exit_node):
		missing.append("выход на этаже %d (x=%.0f)" % [bottom, plan.exit_x])
	return missing


## Куски каждого этажа: пары «левый край, правый край» между проёмами.
static func _floor_segments(plan: BuildingPlan, rules: BuildingRules) -> Array:
	var floors: Array = []
	for index in plan.floors:
		floors.append(BuildingPlan.spans_between(plan.gaps_on(rules, index), rules.width))
	return floors


## Куда можно шагнуть из каждого узла.
static func _links(plan: BuildingPlan, rules: BuildingRules, floors: Array) -> Dictionary:
	var links: Dictionary = {}

	for shaft in plan.shafts:
		# Кабина связывает все этажи своей полосы, а заодно оба края проёма:
		# сквозь стоящую на этаже кабину проходят насквозь.
		var boarding: Array[String] = []
		for index in range(shaft.top, shaft.bottom + 1):
			for segment in _segments_touching(floors[index], shaft.x, rules.shaft_width):
				boarding.append(_node(index, segment))
		_connect_all(links, boarding)

	for escalator in plan.escalators:
		var upper := escalator.floor_index
		var top_segment := _segment_at(floors[upper], escalator.x)
		var landing := escalator.x + escalator.towards * rules.escalator_run
		var bottom_segment := _segment_at(floors[upper + 1], landing)
		# -1 — конец эскалатора попал в проём или за стену. Узла с таким номером
		# на этаже нет, и связывать его нельзя: обход пометил бы его достижимым,
		# а после этого достижимой считалась бы любая точка этажа внутри дыры.
		if top_segment < 0 or bottom_segment < 0:
			push_error("эскалатор на этаже %d упирается в проём" % upper)
			continue
		_connect_all(
			links, [_node(upper, top_segment), _node(upper + 1, bottom_segment)] as Array[String]
		)

	return links


## Куски этажа, примыкающие к столбцу шириной [param width] вокруг [param x].
static func _segments_touching(pieces: Array, x: float, width: float) -> Array[int]:
	var half := width * 0.5
	var found: Array[int] = []
	for index in pieces.size():
		var piece: Vector2 = pieces[index]
		# Либо кусок доходит до края столбца, либо столбец целиком внутри него.
		if piece.y >= x - half - 1.0 and piece.x <= x + half + 1.0:
			found.append(index)
	return found


static func _segment_at(pieces: Array, x: float) -> int:
	for index in pieces.size():
		var piece: Vector2 = pieces[index]
		if x >= piece.x and x <= piece.y:
			return index
	return -1


static func _connect_all(links: Dictionary, nodes: Array[String]) -> void:
	for from_node in nodes:
		for to_node in nodes:
			if from_node == to_node:
				continue
			if not links.has(from_node):
				links[from_node] = [] as Array[String]
			if not links[from_node].has(to_node):
				links[from_node].append(to_node)


static func _node(floor_index: int, segment: int) -> String:
	return "%d:%d" % [floor_index, segment]
