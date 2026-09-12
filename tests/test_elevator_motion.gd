extends GutTest

## Тесты движения кабины лифта.
##
## Работают без сцены и без физики: [ElevatorMotion] принимает время кадра,
## команду игрока и факт занятости, поэтому проверяется напрямую.

const TOP: float = 0.0
const MIDDLE: float = 100.0
const BOTTOM: float = 200.0

## Кадр теста. При скорости 100 px/с кабина проходит за него ровно 10 px.
const STEP: float = 0.1


func _shaft(start_floor: int = 0) -> ElevatorMotion:
	var motion := ElevatorMotion.new()
	motion.speed = 100.0
	motion.floor_pause = 1.0
	motion.setup(PackedFloat32Array([TOP, MIDDLE, BOTTOM]), start_floor)
	return motion


## Прогоняет несколько кадров и возвращает координату кабины.
func _run(motion: ElevatorMotion, seconds: float, command: float, occupied: bool) -> float:
	for _frame: int in int(roundf(seconds / STEP)):
		motion.update(STEP, command, occupied)
	return motion.position


func test_setup_places_car_on_requested_floor() -> void:
	var motion := _shaft(2)
	assert_eq(motion.position, BOTTOM)
	assert_eq(motion.aligned_floor(), 2)


func test_driven_car_goes_up() -> void:
	var motion := _shaft(2)
	assert_almost_eq(_run(motion, 0.5, ElevatorMotion.UP, true), 150.0, 0.01)


func test_driven_car_goes_down() -> void:
	var motion := _shaft(0)
	assert_almost_eq(_run(motion, 0.5, ElevatorMotion.DOWN, true), 50.0, 0.01)


func test_released_car_stops_between_floors() -> void:
	var motion := _shaft(2)
	_run(motion, 0.3, ElevatorMotion.UP, true)
	assert_almost_eq(_run(motion, 1.0, 0.0, true), 170.0, 0.01)
	assert_false(motion.is_aligned(), "кабина встала между этажами")


func test_released_car_finishes_to_floor_when_free_stop_is_off() -> void:
	var motion := _shaft(2)
	motion.stops_between_floors = false
	_run(motion, 0.3, ElevatorMotion.UP, true)
	assert_almost_eq(_run(motion, 2.0, 0.0, true), MIDDLE, 0.01)
	assert_true(motion.is_aligned(), "кабина довелась до этажа")


func test_car_does_not_leave_shaft_at_the_top() -> void:
	var motion := _shaft(2)
	assert_almost_eq(_run(motion, 10.0, ElevatorMotion.UP, true), TOP, 0.01)


func test_car_does_not_leave_shaft_at_the_bottom() -> void:
	var motion := _shaft(0)
	assert_almost_eq(_run(motion, 10.0, ElevatorMotion.DOWN, true), BOTTOM, 0.01)


func test_car_at_the_limit_stands_still() -> void:
	var motion := _shaft(0)
	motion.update(STEP, ElevatorMotion.UP, true)
	assert_almost_eq(motion.position, TOP, 0.01)
	assert_true(motion.is_stopped(), "выше верхнего этажа кабина не едет")


func test_occupied_car_does_not_move_on_its_own() -> void:
	var motion := _shaft(0)
	assert_almost_eq(_run(motion, 2.0, 0.0, true), TOP, 0.01)


func test_car_waits_on_the_floor_it_starts_from() -> void:
	var motion := _shaft(0)
	assert_almost_eq(_run(motion, 0.5, 0.0, false), TOP, 0.01)
	assert_true(motion.is_stopped(), "кабина стоит на этаже, прежде чем тронуться")


func test_empty_car_travels_by_itself() -> void:
	var motion := _shaft(0)
	# Секунда стартовой паузы на этаже плюс секунда хода до среднего этажа.
	assert_almost_eq(_run(motion, 2.5, 0.0, false), MIDDLE, 0.01)


func test_car_left_by_passenger_waits_before_moving_on() -> void:
	var motion := _shaft(0)
	_run(motion, 0.5, 0.0, true)
	# Пассажир вышел на этаже: кабина сначала стоит паузу, как любая пустая.
	assert_almost_eq(_run(motion, 0.8, 0.0, false), TOP, 0.01)
	assert_gt(_run(motion, 0.8, 0.0, false), TOP, "отстояв паузу, кабина поехала сама")


func test_empty_car_pauses_at_the_floor() -> void:
	var motion := _shaft(0)
	_run(motion, 2.5, 0.0, false)
	assert_almost_eq(_run(motion, 0.3, 0.0, false), MIDDLE, 0.01)


func test_empty_car_reverses_at_the_end_of_the_shaft() -> void:
	var motion := _shaft(0)
	_run(motion, 5.5, 0.0, false)
	assert_eq(motion.direction, ElevatorMotion.UP, "с нижнего этажа кабина поехала вверх")
	assert_lt(motion.position, BOTTOM)


func test_alignment_reports_current_floor() -> void:
	var motion := _shaft(1)
	assert_eq(motion.aligned_floor(), 1)
	motion.update(STEP, ElevatorMotion.DOWN, true)
	assert_false(motion.is_aligned(), "тронувшаяся кабина с этажом не совпадает")
	assert_eq(motion.aligned_floor(), -1)


func test_velocity_reports_real_movement() -> void:
	var motion := _shaft(0)
	motion.update(STEP, ElevatorMotion.DOWN, true)
	assert_almost_eq(motion.velocity, 100.0, 0.5)

	# Отъезжаем подальше: рядом с этажом кабина сама дотянет до него.
	_run(motion, 0.4, ElevatorMotion.DOWN, true)
	motion.update(STEP, 0.0, true)
	assert_true(motion.is_stopped())


func test_shaft_with_one_floor_stays_put() -> void:
	var motion := ElevatorMotion.new()
	motion.speed = 100.0
	motion.setup(PackedFloat32Array([50.0]))
	assert_almost_eq(_run(motion, 2.0, 0.0, false), 50.0, 0.01)


func test_shaft_without_floors_is_harmless() -> void:
	var motion := ElevatorMotion.new()
	assert_eq(motion.update(STEP, ElevatorMotion.DOWN, true), 0.0)
