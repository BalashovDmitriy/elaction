extends GutTest

## Подвал заперт, пока не собраны все документы (M24b): шахта в подвал не везёт
## туда, проём над ним закрыт люком, последний документ открывает и то и другое.
##
## Правило кабины проверяется без сцены — на [ElevatorMotion]; люки — на
## раскладке многих сидов: здание генерируется, и дыра в подвал на одном сиде
## из сорока — это дыра. Сборка с физикой — на маленьком здании: Otto стоит на
## люке и проваливается, только когда подвал открыт.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

const TOP: float = 0.0
const MIDDLE: float = 100.0
const BOTTOM: float = 200.0
const STEP: float = 0.1

## Сколько сидов раскладки проверять.
const SEEDS: int = 40
const SETTLE_FRAMES: int = 5
## Сколько шагов физики дать Otto упасть и встать: падение на этаж — меньше
## секунды, остальное запас.
const FALL_FRAMES: int = 90


func before_each() -> void:
	GameState.instance().start_game()


func after_each() -> void:
	GameState.instance().start_game()


func _shaft(start_floor: int = 0) -> ElevatorMotion:
	var motion := ElevatorMotion.new()
	motion.speed = 100.0
	motion.floor_pause = 1.0
	motion.settle_distance = 12.0
	motion.setup(PackedFloat32Array([TOP, MIDDLE, BOTTOM]), start_floor)
	return motion


func _run(motion: ElevatorMotion, seconds: float, command: float, occupied: bool) -> float:
	for _frame: int in int(roundf(seconds / STEP)):
		motion.update(STEP, command, occupied)
	return motion.position


func test_a_locked_car_does_not_take_its_rider_to_the_bottom() -> void:
	var motion := _shaft(0)
	motion.bottom_locked = true
	assert_almost_eq(_run(motion, 10.0, ElevatorMotion.DOWN, true), MIDDLE, 0.01)
	assert_false(motion.can_go(ElevatorMotion.DOWN), "ниже запертой остановки не пускает")
	assert_true(motion.can_go(ElevatorMotion.UP))


func test_a_locked_car_does_not_go_to_the_bottom_on_its_own() -> void:
	var motion := _shaft(0)
	motion.bottom_locked = true
	var deepest := TOP
	for _frame: int in 200:
		motion.update(STEP, 0.0, false)
		deepest = maxf(deepest, motion.position)
	assert_almost_eq(deepest, MIDDLE, 0.01, "сама разворачивается над подвалом")


func test_the_unlocked_car_reaches_the_bottom() -> void:
	var motion := _shaft(0)
	motion.bottom_locked = true
	_run(motion, 10.0, ElevatorMotion.DOWN, true)
	motion.bottom_locked = false
	assert_almost_eq(_run(motion, 10.0, ElevatorMotion.DOWN, true), BOTTOM, 0.01)


## Кабина, уже стоявшая внизу, когда подвал заперли, не едет «вниз» наверх.
func test_the_lock_does_not_drag_a_car_already_below() -> void:
	var motion := _shaft(2)
	motion.bottom_locked = true
	assert_almost_eq(_run(motion, 1.0, ElevatorMotion.DOWN, true), BOTTOM, 0.01)
	assert_almost_eq(_run(motion, 0.5, ElevatorMotion.UP, true), 150.0, 0.01, "вверх — можно")


func test_a_one_floor_shaft_has_nothing_to_lock() -> void:
	var motion := ElevatorMotion.new()
	motion.setup(PackedFloat32Array([TOP]))
	motion.bottom_locked = true
	assert_almost_eq(_run(motion, 1.0, ElevatorMotion.DOWN, true), TOP, 0.01)


## На любом сиде над подвалом нет открытого проёма шахты: каждый закрыт люком
## ровно по своей ширине, в перекрытии этажа над подвалом.
func test_every_shaft_into_the_basement_is_covered_on_any_seed() -> void:
	var rules := BuildingRules.new()
	var bottom := rules.floors - 1
	var above := bottom - 1
	for building_seed in range(1, SEEDS + 1):
		var plan := BuildingPlan.generate(rules, building_seed)
		var hatches := BasementLock.hatches(rules, plan)
		var into_basement := 0
		for shaft in plan.shafts:
			if shaft.bottom != bottom:
				continue
			into_basement += 1
			var covered := false
			for rect in hatches:
				covered = (
					covered
					or (
						is_equal_approx(rect.get_center().x, shaft.x)
						and is_equal_approx(rect.size.x, rules.shaft_width)
						and is_equal_approx(rect.position.y, rules.floor_surface(above))
					)
				)
			assert_true(covered, "сид %d: шахта на x=%.1f закрыта люком" % [building_seed, shaft.x])
		assert_gt(into_basement, 0, "сид %d: в подвал ведёт шахта" % building_seed)
		assert_eq(
			hatches.size(), into_basement, "сид %d: люков столько же, сколько шахт" % building_seed
		)


## На любом сиде ни одна кабина в подвал не спускается, пока он заперт: ни сама,
## ни под пассажиром. Кабины — по остановкам раскладки, как их ставит уровень;
## у двухэтажной пары в подвал спускается нижний ярус, этажом ниже ведущего.
func test_no_car_reaches_the_basement_on_any_seed() -> void:
	var rules := BuildingRules.new()
	var bottom := rules.floors - 1
	var ceiling := rules.floor_surface(bottom - 1) + ElevatorMotion.FLOOR_EPSILON
	for building_seed in range(1, SEEDS + 1):
		var plan := BuildingPlan.generate(rules, building_seed)
		for shaft in plan.shafts:
			if shaft.bottom != bottom:
				continue
			var deck := rules.floor_height if shaft.double_deck else 0.0
			var lowest := shaft.bottom - 1 if shaft.double_deck else shaft.bottom
			var stops := PackedFloat32Array()
			for index in range(shaft.top, lowest + 1):
				stops.append(rules.floor_surface(index))
			var motion := ElevatorMotion.new()
			# Быстрая кабина и короткие паузы: за прогон она обходит шахту
			# туда и обратно не раз.
			motion.speed = 40.0
			motion.floor_pause = 0.1
			motion.setup(stops)
			motion.bottom_locked = true
			var deepest := -INF
			for frame: int in 1200:
				var driven := frame >= 600
				motion.update(1.0 / 60.0, ElevatorMotion.DOWN if driven else 0.0, driven)
				deepest = maxf(deepest, motion.position + deck)
			assert_lte(
				deepest,
				ceiling,
				"сид %d: кабина на x=%.1f не спускается в подвал" % [building_seed, shaft.x]
			)


func _building(documents: int) -> GreyboxLevel:
	var rules := BuildingRules.new()
	rules.floors = 4
	rules.documents_cap = documents
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = rules
	level.building_seed = 1
	level.spawn_agents = false
	add_child_autofree(level)
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	return level


func _lock_of(level: GreyboxLevel) -> BasementLock:
	return level.get_node_or_null("BasementLock") as BasementLock


## Кабины здания, спускающиеся в подвал.
func _basement_cars(level: GreyboxLevel) -> Array[ElevatorCar]:
	var found: Array[ElevatorCar] = []
	var basement := level.rules.floor_surface(level.rules.floors - 1)
	for child in level.get_children():
		var car := child as ElevatorCar
		if car != null and not car.is_deck() and is_equal_approx(car.bottom_reach(), basement):
			found.append(car)
	return found


func test_the_building_without_documents_leaves_the_basement_open() -> void:
	var level := await _building(0)
	var lock := _lock_of(level)
	assert_not_null(lock)
	assert_false(lock.is_locked(), "запирать не за чем")
	for car in _basement_cars(level):
		assert_false(car.is_bottom_locked())


## Otto на люке над подвалом стоит, а не падает; последний документ открывает
## люк и кабины — и тот же Otto проваливается в подвал живым: падение на этаж.
func test_the_hatch_holds_until_the_last_document() -> void:
	var level := await _building(1)
	var lock := _lock_of(level)
	assert_true(lock.is_locked(), "документ не собран — подвал заперт")
	var cars := _basement_cars(level)
	assert_gt(cars.size(), 0, "в подвал ведёт кабина")
	for car in cars:
		assert_true(car.is_bottom_locked(), "кабина в подвал не везёт")

	var rules := level.rules
	var above := rules.floors - 2
	var hatch := BasementLock.hatches(rules, level.plan())[0]
	var feet := Vector2(hatch.get_center().x, rules.floor_surface(above))
	level.otto.global_position = WorldSpace.to_scene(feet - Vector2(0.0, 0.3))
	for _frame: int in FALL_FRAMES:
		await get_tree().physics_frame
	var at := WorldSpace.to_plane(level.otto.global_position)
	assert_true(level.otto.is_grounded(), "стоит на створках")
	assert_eq(rules.floor_index_near(at.y), above, "над подвалом, а не в нём")

	# Прыжок на месте: приземляется на те же створки.
	Input.action_press(&"jump")
	await get_tree().physics_frame
	Input.action_release(&"jump")
	for _frame: int in FALL_FRAMES:
		await get_tree().physics_frame
	at = WorldSpace.to_plane(level.otto.global_position)
	assert_true(level.otto.is_grounded(), "после прыжка — снова на створках")
	assert_eq(rules.floor_index_near(at.y), above, "прыжок в подвал не пускает")

	assert_gt(lock.closed_hatches(), 0)
	GameState.instance().collect_document()
	assert_false(lock.is_locked(), "последний документ открыл подвал")
	assert_eq(lock.closed_hatches(), 0, "створки больше не держат")
	for car in cars:
		assert_false(car.is_bottom_locked(), "кабина снова возит в подвал")
	for _frame: int in FALL_FRAMES:
		await get_tree().physics_frame
	at = WorldSpace.to_plane(level.otto.global_position)
	assert_eq(rules.floor_index_near(at.y), rules.floors - 1, "провалился в подвал")
	assert_false(level.otto.is_dead(), "этаж падения не убивает")
	assert_eq(lock.find_children("Hatch", "", false, false).size(), 0, "створки разошлись и убраны")


## Шахта в подвал этого здания и её кабина.
func _basement_shaft(level: GreyboxLevel) -> BuildingPlan.ShaftSpot:
	for shaft in level.plan().shafts:
		if shaft.bottom == level.rules.floors - 1:
			return shaft
	return null


## Ставит кабину шахты [param shaft] на остановку этажа над подвалом.
func _park_above_the_basement(
	level: GreyboxLevel, car: ElevatorCar, shaft: BuildingPlan.ShaftSpot
) -> void:
	var lowest := shaft.bottom - 1 if shaft.double_deck else shaft.bottom
	var stops := PackedFloat32Array()
	for index in range(shaft.top, lowest + 1):
		stops.append(level.rules.floor_surface(index))
	# Запертая остановка — последняя; кабина встаёт на предпоследнюю.
	car.setup(stops, stops.size() - 2)


## Пассажир жмёт «вниз» в кабине над подвалом — кабина стоит, пока подвал
## заперт, и едет до дна, когда открыт.
func test_the_rider_goes_down_only_after_the_last_document() -> void:
	var level := await _building(1)
	var shaft := _basement_shaft(level)
	var car := _basement_cars(level)[0]
	if shaft.double_deck:
		pass_test("пара: нижний ярус стоит над подвалом, проверяется раскладкой")
		return
	_park_above_the_basement(level, car, shaft)
	var rules := level.rules
	var above := rules.floor_surface(rules.floors - 2)
	level.otto.global_position = WorldSpace.to_scene(Vector2(shaft.x, above - 0.05))
	Input.action_press(&"move_down")
	for _frame: int in FALL_FRAMES * 2:
		await get_tree().physics_frame
	assert_true(level.otto.is_riding(), "Otto в кабине")
	assert_almost_eq(WorldSpace.to_plane(car.global_position).y, above, 0.02, "кабина стоит")

	GameState.instance().collect_document()
	var basement := rules.floor_surface(rules.floors - 1)
	for _frame: int in FALL_FRAMES * 3:
		await get_tree().physics_frame
		if absf(WorldSpace.to_plane(car.global_position).y - basement) < 0.02:
			break
	Input.action_release(&"move_down")
	assert_almost_eq(
		WorldSpace.to_plane(car.global_position).y, basement, 0.02, "кабина доехала до подвала"
	)
	var at := WorldSpace.to_plane(level.otto.global_position)
	assert_eq(rules.floor_index_near(at.y), rules.floors - 1, "и Otto с ней")


## Стоящий на крыше кабины над подвалом вниз не уезжает: кабина разворачивается.
func test_the_car_roof_does_not_carry_otto_into_the_basement() -> void:
	var level := await _building(1)
	var shaft := _basement_shaft(level)
	var car := _basement_cars(level)[0]
	_park_above_the_basement(level, car, shaft)
	var rules := level.rules
	var above := rules.floor_surface(rules.floors - 2)
	var roof := (
		WorldSpace.to_plane(car.global_position).y - (rules.floor_height - rules.slab_height)
	)
	level.otto.global_position = WorldSpace.to_scene(Vector2(shaft.x, roof - 0.05))
	var deepest := -INF
	# Пауза на этаже и попытка поехать вниз — пустая кабина разворачивается.
	for _frame: int in FALL_FRAMES * 4:
		await get_tree().physics_frame
		deepest = maxf(deepest, WorldSpace.to_plane(level.otto.global_position).y)
	assert_lte(deepest, above + 0.02, "Otto не ниже этажа над подвалом")
	assert_lte(WorldSpace.to_plane(car.global_position).y, above + 0.02, "кабина — тоже")
