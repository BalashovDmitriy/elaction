extends GutTest

## Тесты задержки отклика кабины.
##
## По тревоге кабина «слушается хуже» — это прямо описано в оригинале. Задержка
## не копится между нажатиями: отпустил или вышел — считается заново (ADR-0009,
## пункт 1). Про выход отдельный тест: пустая кабина в [method ElevatorMotion._drive]
## не заходит, и без сброса задержка работала бы только на первую поездку.

const TOP: float = 0.0
const STEP: float = 0.1


func _shaft() -> ElevatorMotion:
	var motion := ElevatorMotion.new()
	motion.speed = 100.0
	motion.response_delay = 0.5
	motion.setup(PackedFloat32Array([TOP, 100.0, 200.0]))
	return motion


func _run(motion: ElevatorMotion, seconds: float, command: float) -> float:
	for _frame: int in int(roundf(seconds / STEP)):
		motion.update(STEP, command, true)
	return motion.position


func test_car_does_not_start_at_once() -> void:
	assert_almost_eq(_run(_shaft(), 0.4, ElevatorMotion.DOWN), TOP, 0.01)


func test_car_starts_once_it_has_thought() -> void:
	assert_gt(_run(_shaft(), 1.0, ElevatorMotion.DOWN), TOP, "дождалась и поехала")


func test_letting_go_makes_the_car_think_again() -> void:
	var motion := _shaft()
	_run(motion, 0.4, ElevatorMotion.DOWN)
	_run(motion, 0.2, 0.0)
	assert_almost_eq(_run(motion, 0.4, ElevatorMotion.DOWN), TOP, 0.01, "отсчёт заново")


func test_leaving_the_car_makes_it_think_again() -> void:
	var motion := _shaft()
	_run(motion, 1.0, ElevatorMotion.DOWN)
	# Пассажир вышел: кабина пустая и ещё стоит паузу этажа, то есть не едет сама.
	motion.update(STEP, 0.0, false)
	var boarded_at := motion.position
	assert_almost_eq(
		_run(motion, 0.4, ElevatorMotion.DOWN), boarded_at, 0.01, "новый пассажир ждёт так же"
	)
