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

## На сколько заходить в кусок этажа от его края, м. Столько нужно, чтобы стоять
## на нём, а не на самой кромке проёма.
const STEP_INSIDE: float = 0.3

## Допуск на примыкание: на дробную арифметику, и только на неё.
##
## Раньше он был метровым, и на этом граф обещал связь, которой нет: внутренняя
## стена шириной почти метр (ADR-0024, решение 5) укладывалась в допуск целиком,
## и кусок за ней считался доступным прямо из кабины. Здание с таким «переходом»
## проходило проверку, а игрок упирался в стену.
const TOUCHING_SLACK: float = 0.05


## Узлы, куда можно добраться из точки старта. Ключ — «этаж:кусок».
static func reachable(plan: BuildingPlan, rules: BuildingRules) -> Dictionary:
	return reachable_in(plan, rules, _floor_segments(plan, rules))


## Куски всех уровней: уровень -> пары «левый край, правый край».
##
## Отдаются наружу, чтобы считать узлы пачкой: [method node_in] по готовым кускам
## стоит копейки, а сами куски — это перебор всей раскладки.
##
## Словарь, а не список: уровни считаются от [constant BuildingRules.ROOF], то есть
## от −1, а [code]Array[-1][/code] в GDScript отдаёт последний элемент — крыша молча
## притворялась бы первым этажом вместо того, чтобы уронить обход (ADR-0014).
static func segments(plan: BuildingPlan, rules: BuildingRules) -> Dictionary:
	return _floor_segments(plan, rules)


## Узел точки уровня по готовым кускам из [method segments]. По нему проверяют,
## ведёт ли туда маршрут: [method reachable] возвращает набор таких же узлов.
static func node_in(floors: Dictionary, floor_index: int, x: float) -> String:
	return _node(floor_index, _segment_at(floors[floor_index], x))


## Те же узлы, что и у [method reachable], но по готовым кускам из
## [method segments]: кто их уже посчитал, второй раз за перебор не платит.
static func reachable_in(
	plan: BuildingPlan, rules: BuildingRules, floors: Dictionary
) -> Dictionary:
	var links: Dictionary = _graph(plan, rules, floors, false)["links"]

	# Спуск начинается с крыши, а не с верхнего этажа: туда Otto попадает лифтом,
	# и здание, до которого от крыши не добраться, непроходимо.
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


## Готовый к ходьбе граф здания: куски уровней и подписанные переходы между ними.
##
## Считается один раз на здание и отдаётся тому, кто по нему ходит: раскладка за
## партию не меняется, а [method step_toward] зовут каждый кадр.
##
## Отдельно от [method reachable]: тому достаточно знать, связаны ли узлы, а
## идущему нужно знать чем — к какой шахте идти и на каком уровне выходить.
static func walkable(plan: BuildingPlan, rules: BuildingRules) -> Dictionary:
	var pieces := _floor_segments(plan, rules)
	return {
		"pieces": pieces,
		"moves": _graph(plan, rules, pieces, true)["moves"],
		# Докуда дотянется тот, кто стоит в кабине: она перекрывает проём собой,
		# и выйти из неё можно в любой край.
		"reach": rules.shaft_width * 0.5 + TOUCHING_SLACK,
	}


## Первый шаг к цели по готовому графу из [method walkable].
##
## Отдаётся один шаг, а не весь маршрут: идущий пересчитывает решение каждый
## кадр — он промахивается мимо кабины, дерётся, падает и сходит с места, и
## запомненный маршрут устарел бы к следующему кадру.
##
## Ключи ответа: [code]kind[/code] — [code]walk[/code], [code]shaft[/code] или
## [code]escalator[/code]; [code]x[/code] — куда идти; [code]floor[/code] — на
## каком уровне оказаться. Пустой словарь — цель недостижима.
static func step_toward(
	graph: Dictionary, from_floor: int, from_x: float, to_floor: int, to_x: float
) -> Dictionary:
	var pieces: Dictionary = graph["pieces"]
	var moves: Dictionary = graph["moves"]
	var goal := _node(to_floor, _segment_at(pieces[to_floor], to_x))

	# Отправных точек может быть несколько. Стоящий в кабине стоит в проёме, а у
	# проёма куска этажа нет: выйти он волен в любой край, и оба ему открыты.
	# Отдать один — значит запереть его в том, который выпал первым, и он будет
	# ездить туда-сюда, пытаясь попасть в соседний.
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


## Точка внутри куска, ближайшая к [param x]: с отступом от краёв, чтобы в неё
## можно было прийти и на ней устоять.
##
## Кусок уже двух отступов — берётся его середина: это тесная полоска между
## проёмами, и точнее в ней не встанешь.
static func _inside(piece: Vector2, x: float) -> float:
	if piece.y - piece.x <= STEP_INSIDE * 2.0:
		return (piece.x + piece.y) * 0.5
	return clampf(x, piece.x + STEP_INSIDE, piece.y - STEP_INSIDE)


## Граф здания: кто с кем связан и, по запросу, чем именно.
##
## Один обход на оба ответа. Раньше их было два — [code]_moves[/code] и
## [code]_links[/code], — и они считали одно и то же по-разному: правка под
## двухэтажную пару (ADR-0025, решение 1) прошла бы в одном и не прошла
## в другом, а расходились они уже на вырожденном конце эскалатора.
##
## [param detailed] — нужна ли подпись каждого перехода. Обходу достижимости
## довольно соседей, а идущему нужно знать, чем воспользоваться и где он
## окажется. Словарь на ребро стоит дорого, а [method is_winnable] зовётся
## около десяти раз на здание — поэтому подпись считается по запросу, но
## правило, кто с кем связан, остаётся одно на оба ответа.
static func _graph(
	plan: BuildingPlan, rules: BuildingRules, pieces: Dictionary, detailed: bool
) -> Dictionary:
	var links: Dictionary = {}
	var moves: Dictionary = {}

	for shaft in plan.shafts:
		# Кабина связывает уровни своей шахты, а заодно оба края проёма на одном
		# уровне: сквозь стоящую кабину проходят насквозь. Ход на тот же уровень
		# выглядит пустым, но он и есть переход через проём — без него половины
		# этажа, разрезанного шахтой, друг для друга недостижимы.
		#
		# Узлы посадки — тремя параллельными массивами, а не словарём на узел.
		# Словарь здесь стоил вдвое всей генерации: шахт дюжина, узлов у каждой
		# десятки, а перебор их попарно — квадрат. Замер: 24.5 мс на здание
		# против 12.2 после.
		var nodes: Array[String] = []
		var on_floor := PackedInt32Array()
		# Выходят не на ось шахты, а в сам кусок: иначе переход через проём
		# кончался бы ровно в кабине, и «дошёл» наступало, не сходя с места.
		var inside := PackedFloat64Array()
		# Возит ли кабина с этого узла. Считается заранее, а не в переборе:
		# [method BuildingPlan.ShaftSpot.ride_span] заводит [Vector2i], а
		# перебор идёт квадратом от числа узлов.
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
				# Переход через проём — на своём этаже, и его даёт любая стоящая
				# кабина. Поездка — только туда, куда довезёт любой из ярусов
				# пары: вошедший не выбирает, какой ярус его встретит.
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
		var landing := escalator.x + escalator.towards * rules.escalator_run
		var bottom_segment := _segment_at(pieces[upper + 1], landing)
		# -1 — конец эскалатора попал в проём или за стену. Узла с таким номером
		# на этаже нет, и связывать его нельзя: обход пометил бы его достижимым,
		# а после этого достижимой считалась бы любая точка этажа внутри дыры.
		if top_segment < 0 or bottom_segment < 0:
			push_error("эскалатор на этаже %d упирается в проём" % upper)
			continue
		# Эскалатор ходит в обе стороны: с площадки внизу на нём поднимаются.
		var above := _node(upper, top_segment)
		var below := _node(upper + 1, bottom_segment)
		_join(links, above, below)
		_join(links, below, above)
		if detailed:
			_offer(moves, above, "escalator", escalator.x, landing, upper + 1, below)
			_offer(moves, below, "escalator", landing, escalator.x, upper, above)

	return {"links": links, "moves": moves}


## Отмечает, что из одного узла можно попасть в другой.
static func _join(links: Dictionary, from_node: String, to_node: String) -> void:
	if not links.has(from_node):
		links[from_node] = [] as Array[String]
	if not links[from_node].has(to_node):
		links[from_node].append(to_node)


## [param x] — куда идти, чтобы воспользоваться переходом; [param to_x] — где
## окажешься. У шахты это одно и то же, у эскалатора — разные концы полотна.
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


## Куски каждого уровня: пары «левый край, правый край» между тем, что ходьбу
## прерывает.
##
## Режут и проёмы, и внутренние стены ([method BuildingPlan.blocks_on]): сквозь
## стену не пройти, хотя пол под ней есть. Перекрытие при этом остаётся целым —
## его считают по одним проёмам, ADR-0024, решение 5.
##
## Границы берутся у самого уровня: здание расширяется книзу, и кусок во всю
## ширину здания вёл бы на узком этаже сквозь стену на улицу.
static func _floor_segments(plan: BuildingPlan, rules: BuildingRules) -> Dictionary:
	var floors: Dictionary = {}
	for index in rules.levels():
		var blocks := plan.blocks_on(rules, index)
		floors[index] = BuildingPlan.spans_between(blocks, rules.floor_span(index))
	return floors


## Куски этажа, примыкающие к столбцу шириной [param width] вокруг [param x].
static func _segments_touching(pieces: Array, x: float, width: float) -> Array[int]:
	var half := width * 0.5
	var found: Array[int] = []
	for index in pieces.size():
		var piece: Vector2 = pieces[index]
		# Либо кусок доходит до края столбца, либо столбец целиком внутри него.
		if piece.y >= x - half - TOUCHING_SLACK and piece.x <= x + half + TOUCHING_SLACK:
			found.append(index)
	return found


## Куски, из которых точка достижима пешком: тот, в котором она лежит, а если
## она в проёме — все, чей край к ней примыкает.
##
## Отдельно от [method _segment_at]: тому «нигде» — законный ответ, по которому
## достижимость отказывается связывать узел. А идущему нужен ответ всегда: он
## бывает и в проёме — стоя в кабине лифта, — и выйти оттуда может в любую
## сторону, потому что кабина перекрывает проём собой.
static func _segments_near(pieces: Array, x: float, reach: float) -> Array[int]:
	var here := _segment_at(pieces, x)
	if here >= 0:
		return [here] as Array[int]

	# Дальше кабины тянуться некуда: в проёме шире неё пола нет, и стоять там
	# некому. Не нашлось ни одного края — отдаётся ближайший: лучше неточный
	# ответ, чем застрявший навсегда.
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
