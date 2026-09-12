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
		print("  %2d..%2d  x=%.0f" % [shaft.top, shaft.bottom, shaft.x])

	print("\nЭскалаторы (с этажа, x, куда спускается, проём):")
	for escalator in plan.escalators:
		var gap := escalator.gap(rules)
		var side := "вправо" if escalator.towards > 0.0 else "влево"
		var mark := [escalator.floor_index, escalator.x, side, gap.x, gap.y]
		print("  %2d  x=%.0f  %s  проём %.0f..%.0f" % mark)

	print("\nДокументы на этажах: %s" % str(plan.document_floors()))
	print("Выход: x=%.0f" % plan.exit_x)
	print("Дверей: %d, ламп: %d" % [plan.doors.size(), plan.lamps.size()])

	quit()
