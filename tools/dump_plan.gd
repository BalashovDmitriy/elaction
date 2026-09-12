extends SceneTree

## Печатает раскладку здания: что и где сгенерировалось.
##
## Раскладка случайна по сиду, и глазами по кадру её не проверить — в кадр влезает
## меньше трети этажа. Инструмент отвечает на вопрос «а что там вообще получилось».
##
## Запуск:
##     godot --headless --script res://tools/dump_plan.gd -- 1
## где 1 — сид здания.


func _init() -> void:
	var building_seed := 1
	for argument in OS.get_cmdline_user_args():
		if argument.is_valid_int():
			building_seed = argument.to_int()
			break

	var rules := BuildingRules.new()
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
