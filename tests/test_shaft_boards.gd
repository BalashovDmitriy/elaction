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
	var down := Intent.DOWN
	var up := Intent.UP
	assert_eq(BuildingShafts.coming(down, 5, 9), down, "едет вниз к этажу ниже")
	assert_eq(BuildingShafts.coming(down, 5, 2), 0.0, "уехала вниз от этажа выше")
	assert_eq(BuildingShafts.coming(up, 5, 2), up, "едет вверх к этажу выше")
	assert_eq(BuildingShafts.coming(up, 5, 9), 0.0, "уехала вверх от этажа ниже")
	assert_eq(BuildingShafts.coming(0.0, 5, 9), 0.0, "стоит — не зовёт никого")


## Ход табло берётся из настоящей скорости кабины. У неё y растёт вниз, и до
## авторевью M21b табло читало едущую вниз кабину как едущую вверх: зажигало
## «▲» на этажах, от которых она уезжала.
func test_the_heading_follows_the_real_speed_of_the_car() -> void:
	var motion := ElevatorMotion.new()
	motion.setup(PackedFloat32Array([10.0, 13.6, 17.2]), 1)
	motion.update(0.1, ElevatorMotion.DOWN, true)
	assert_eq(BuildingShafts.heading_of(motion.velocity), Intent.DOWN, "едет вниз")
	motion.setup(PackedFloat32Array([10.0, 13.6, 17.2]), 1)
	motion.update(0.1, ElevatorMotion.UP, true)
	assert_eq(BuildingShafts.heading_of(motion.velocity), Intent.UP, "едет вверх")
	assert_eq(BuildingShafts.heading_of(0.0), 0.0, "стоит")


## Табло на всех порталах шахты показывают этаж, где её кабина, — номер
## таблички этажа, а не индекс; на крыше — R. Сначала обновляются все кабины,
## потом проверяются все табло: в одном столбце бывает несколько шахт (на сиде 1
## — шахта с крыши и шахта 15..22), и табло не должны показывать чужую кабину.
##
## Кабина встаёт на свой этаж только с первым шагом физики: у тела с
## sync_to_physics позиция до него откатывается к нулю, и все кабины читались
## бы стоящими на крыше.
func test_every_board_of_a_shaft_shows_where_its_car_is() -> void:
	var level := _level()
	var shafts := _shafts(level)
	assert_not_null(shafts, "шахт нет")
	if shafts == null:
		return
	await wait_physics_frames(3)
	var watched: Array[ElevatorCar] = []
	for car: ElevatorCar in level._cars:
		if shafts.watches(car):
			shafts.refresh(car)
			watched.append(car)
	var checked := 0
	var shared := 0
	for car in watched:
		var shaft := shafts._watched[car] as BuildingPlan.ShaftSpot
		if _column_is_shared(level, shaft):
			shared += 1
		var where := shafts._nearest_floor(car)
		var height := WorldSpace.to_plane(car.global_position).y
		assert_eq(where, level.rules.floor_index_near(height), "кабина не на своём этаже")
		var label := BuildingShafts.floor_label(level.rules, where)
		for index in range(maxi(shaft.top, 0), shaft.bottom + 1):
			var text := shafts.board_text(shaft.x, index)
			assert_true(
				text.ends_with(label),
				"шахта x=%.1f, этаж %d: «%s» вместо %s" % [shaft.x, index, text, label]
			)
			checked += 1
	assert_gt(checked, 0, "ни одного табло")
	assert_gt(shared, 0, "на сиде 1 нет шахт в общем столбце — тест ничего не ловит")
	remove_child(level)


## Кабина на крыше — на табло R, а не номер на единицу больше верхнего этажа.
func test_the_roof_is_not_a_floor_number() -> void:
	var rules := BuildingRules.new()
	assert_eq(BuildingShafts.floor_label(rules, BuildingRules.ROOF), BuildingShafts.ROOF_LABEL)
	assert_eq(BuildingShafts.floor_label(rules, 0), str(rules.floors))


## Нижний этаж — паркинг: табло шахт пишет «P», как табличка этажа и колонны
## паркинга, а этаж над ним остаётся вторым (ADR-0038, решение 3).
func test_the_parking_is_p_on_the_boards() -> void:
	var rules := BuildingRules.new()
	var bottom := rules.floors - 1
	assert_eq(BuildingShafts.floor_label(rules, bottom), "P")
	assert_eq(BuildingShafts.floor_label(rules, bottom - 1), "2")
	assert_eq(Garage.LEVEL_MARK, "P", "колонны паркинга — P-01, P-02…")


## Панель кнопок не встаёт на наличник двери соседнего места и на её табличку —
## на любом здании. Проёма выхода в задней стене с M24b нет: выход — ворота
## паркинга в торце ([GarageGate]).
func test_the_call_panel_keeps_off_doors() -> void:
	var door_left := Door.LEAF_SIZE.x * 0.5 + Door.FRAME_WIDTH
	var door_right := Door.LEAF_SIZE.x * 0.5 + BuildingProps.PLATE_GAP + BuildingProps.PLATE.x
	var panels := 0
	for skill: int in [0, 5]:
		var rules := BuildingRules.new()
		rules.skill = skill
		for building_seed: int in [1, 2, 3, 5, 8, 13, 21, 34]:
			var plan := BuildingPlan.generate(rules, building_seed)
			for shaft in plan.shafts:
				for index in range(maxi(shaft.top, 0), shaft.bottom + 1):
					var panel := BuildingShafts.call_panel_span(rules, plan, shaft.x, index)
					if panel.y <= panel.x:
						continue
					panels += 1
					var busy: Array[Vector2] = []
					for door in plan.doors:
						if door.floor_index == index:
							busy.append(Vector2(door.x - door_left, door.x + door_right))
					for zone in busy:
						assert_true(
							panel.y <= zone.x or panel.x >= zone.y,
							(
								"сид %d, этаж %d: панель %s на двери %s"
								% [building_seed, index, panel, zone]
							)
						)
	assert_gt(panels, 0, "ни одной панели — проверять нечего")


func _column_is_shared(level: GreyboxLevel, shaft: BuildingPlan.ShaftSpot) -> bool:
	for other in level.plan().shafts:
		if other != shaft and absf(other.x - shaft.x) < 0.01:
			return true
	return false


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
