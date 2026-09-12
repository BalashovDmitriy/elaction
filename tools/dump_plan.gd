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

	var rules := BuildingRules.new()
	var plan := BuildingPlan.generate(rules, building_seed)

	print("Здание по сиду %d: %d этажей" % [building_seed, plan.floors])
	print("\nШахты (этажи сверху вниз, x):")
	for shaft in plan.shafts:
		print("  %2d..%2d  x=%.0f" % [shaft.top, shaft.bottom, shaft.x])

	print("\nЭскалаторы (с этажа, x, куда спускается):")
	for escalator in plan.escalators:
		print("  %2d  x=%.0f  %s" % [escalator.floor_index, escalator.x, escalator.towards])

	print("\nДокументы на этажах: %s" % str(plan.document_floors()))
	print("Дверей: %d, ламп: %d" % [plan.doors.size(), plan.lamps.size()])

	quit()
