extends SceneTree

## Печатает раскладку здания: что и где сгенерировалось.
##
## Раскладка случайна по сиду, и глазами по кадру её не проверить — в кадр влезает
## меньше трети этажа. Инструмент отвечает на вопрос «а что там вообще получилось».
##
## Запуск:
##     godot --headless --script res://tools/dump_plan.gd -- 1
##     godot --headless --script res://tools/dump_plan.gd -- 3 --floors=4 --span=2
##
## Первое число — сид. Размеры здания можно переопределить: так смотрят те же
## маленькие здания, на которых гоняются тесты прохождения.


func _init() -> void:
	var building_seed := 1
	for argument in OS.get_cmdline_user_args():
		if argument.is_valid_int():
			building_seed = argument.to_int()
			break

	var rules := BuildingRules.new()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--floors="):
			rules.floors = argument.trim_prefix("--floors=").to_int()
		elif argument.begins_with("--documents="):
			rules.documents = argument.trim_prefix("--documents=").to_int()
		elif argument.begins_with("--span="):
			rules.shaft_span = argument.trim_prefix("--span=").to_int()
	var plan := BuildingPlan.generate(rules, building_seed)

	print("Здание по сиду %d: %d этажей" % [building_seed, plan.floors])
	print("\nШахты (этажи сверху вниз, x):")
	for shaft in plan.shafts:
		var pair := ""
		if shaft.double_deck:
			var span := shaft.ride_span()
			pair = "  двухэтажная, возит %d..%d" % [span.x, span.y]
		print("  %2d..%2d  x=%.0f%s" % [shaft.top, shaft.bottom, shaft.x, pair])

	print("\nЭскалаторы (с этажа, x, куда спускается, проём):")
	for escalator in plan.escalators:
		var gap := escalator.gap(rules)
		var side := "вправо" if escalator.towards > 0.0 else "влево"
		var mark := [escalator.floor_index, escalator.x, side, gap.x, gap.y]
		print("  %2d  x=%.0f  %s  проём %.0f..%.0f" % mark)

	print("\nВнутренние стены (этаж, x):")
	for wall in plan.walls:
		print("  %2d  x=%.1f" % [wall.floor_index, wall.x])

	print("\nШахт на этаже (цель правил / вышло):")
	for index in rules.levels():
		var serving := 0
		for shaft in plan.shafts:
			if shaft.top <= index and shaft.bottom >= index:
				serving += 1
		print("  %2d  %d / %d" % [index, rules.shafts_on(index), serving])

	_trace_route(plan, rules)

	print("\nДокументы на этажах: %s" % str(plan.document_floors()))
	print("Выход: x=%.0f" % plan.exit_x)
	print("Дверей: %d, ламп: %d" % [plan.doors.size(), plan.lamps.size()])
	print("Проходимо: %s" % str(BuildingRoute.is_winnable(plan, rules)))

	quit()


## Маршрут, каким его видит бот: шаг за шагом от крыши к выходу.
##
## По этому следу ищут, где спуск встаёт: «бот не прошёл» говорит только этаж,
## а здесь видно, чем он собирался воспользоваться и куда это ведёт.
func _trace_route(plan: BuildingPlan, rules: BuildingRules) -> void:
	print("\nМаршрут по графу: документы сверху вниз, затем выход")
	var graph := BuildingRoute.walkable(plan, rules)
	var here := BuildingRules.ROOF
	var x := plan.safe_x(rules, here)

	# Цели те же, что у бота: верхний несобранный документ, а когда все собраны —
	# выход. Иначе след показывал бы дорогу, которой бот не идёт.
	var goals: Array[Dictionary] = []
	for spot in plan.doors:
		if spot.has_document:
			goals.append({"floor": spot.floor_index, "x": spot.x, "what": "документ"})
	goals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["floor"] < b["floor"])
	goals.append({"floor": rules.floors - 1, "x": plan.exit_x, "what": "выход"})

	for goal: Dictionary in goals:
		print("  → %s на этаже %d, x=%.1f" % [goal["what"], int(goal["floor"]), float(goal["x"])])
		var reached := false
		for _step in rules.floors * 3:
			var move := BuildingRoute.step_toward(
				graph, here, x, int(goal["floor"]), float(goal["x"])
			)
			if move.is_empty():
				print("     этаж %2d, x=%5.1f — дальше хода нет" % [here, x])
				return
			if String(move["kind"]) == "walk":
				print("     этаж %2d, x=%5.1f: дойти" % [here, x])
				here = int(goal["floor"])
				x = float(goal["x"])
				reached = true
				break
			print(
				(
					"     этаж %2d, x=%5.1f: %s к x=%.1f → этаж %d"
					% [here, x, move["kind"], float(move["x"]), int(move["floor"])]
				)
			)
			here = int(move["floor"])
			x = float(move["to_x"])
		if not reached:
			print("     след оборван: маршрут длиннее, чем этажей втрое")
			return
