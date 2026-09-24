extends GutTest

## Табло кабины и кнопки у порталов (ADR-0033, решение 7) и вертикальная
## вывеска здания (решение 2): что они показывают, а не как выглядят.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")


func after_all() -> void:
	GameState.instance().reset()


func _level(building: int = 1) -> GreyboxLevel:
	GameState.instance().start_game()
	GameState.instance().building = building
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = 1
	add_child_autofree(level)
	return level


func _shafts(level: GreyboxLevel) -> BuildingShafts:
	for child in level.get_children():
		if child is BuildingShafts:
			return child as BuildingShafts
	return null


## Кабина едет вниз — кнопка «вниз» горит на этажах под ней, «вверх» — на этажах
## над ней, если едет вверх. Стоит — не горит ничего. Индексы растут вниз.
func test_the_button_lights_where_the_car_is_heading() -> void:
	assert_eq(BuildingShafts.coming(-1.0, 5, 9), -1.0, "едет вниз к этажу ниже")
	assert_eq(BuildingShafts.coming(-1.0, 5, 2), 0.0, "уехала вниз от этажа выше")
	assert_eq(BuildingShafts.coming(1.0, 5, 2), 1.0, "едет вверх к этажу выше")
	assert_eq(BuildingShafts.coming(1.0, 5, 9), 0.0, "уехала вверх от этажа ниже")
	assert_eq(BuildingShafts.coming(0.0, 5, 9), 0.0, "стоит — не зовёт никого")


## Табло на всех порталах шахты показывают этаж, где кабина сейчас, — номер
## таблички этажа, а не индекс.
func test_every_board_of_a_shaft_shows_where_its_car_is() -> void:
	var level := _level()
	var shafts := _shafts(level)
	assert_not_null(shafts, "шахт нет")
	if shafts == null:
		return
	var checked := 0
	for car: ElevatorCar in level._cars:
		if not shafts.watches(car):
			continue
		shafts.refresh(car)
		var x := car.global_position.x
		var shaft := _shaft_at(level, x)
		if shaft == null:
			continue
		var where := shafts._nearest_floor(car)
		var number := str(FloorSigns.number_of(level.rules, where))
		for index in range(maxi(shaft.top, 0), shaft.bottom + 1):
			var text := shafts.board_text(shaft.x, index)
			assert_true(
				text.ends_with(number),
				"шахта x=%.1f, этаж %d: «%s» вместо %s" % [x, index, text, number]
			)
			checked += 1
	assert_gt(checked, 0, "ни одного табло")
	remove_child(level)


func _shaft_at(level: GreyboxLevel, x: float) -> BuildingPlan.ShaftSpot:
	for shaft in level.plan().shafts:
		if absf(shaft.x - x) < 0.01:
			return shaft
	return null


## Вывеска висит снаружи здания, над верхними этажами, и пишет имя здания.
func test_the_sign_spells_the_building_and_hangs_outside() -> void:
	for building: int in [1, 2, 3, 4]:
		var level := _level(building)
		var sign_board := level.get_node_or_null("Scenery/VerticalSign") as VerticalSign
		assert_not_null(sign_board, "вывески нет")
		if sign_board == null:
			remove_child(level)
			continue
		var identity := BuildingIdentity.of(building, 1)
		assert_eq(sign_board.text(), "".join(identity.sign_lines()), "здание %d" % building)
		var outer := level.rules.floor_span(0).y
		for label in sign_board.find_children("*", "Label3D", true, false):
			assert_gt((label as Node3D).global_position.x, outer, "буква внутри здания")
		remove_child(level)
