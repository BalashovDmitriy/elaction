extends GutTest

## Кабина, в которую вошли на ходу (ADR-0037, решение 1).
##
## Otto садится в кабину вровень с этажом или шагнув на её пол, пока она
## подъезжает. Во втором случае он её ещё не вёл, и встать между этажами ей не
## с чего: невровень с этажом из неё не выйти, и оба застыли бы навсегда. Работает
## без сцены, как и [code]test_elevator_motion.gd[/code].

const TOP: float = 0.0
const MIDDLE: float = 100.0
const BOTTOM: float = 200.0

## Кадр теста. При скорости 100 px/с кабина проходит за него ровно 10 px.
const STEP: float = 0.1


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


func test_car_boarded_on_the_way_carries_on_to_its_floor() -> void:
	var motion := _shaft(2)
	_run(motion, 1.5, 0.0, false)
	assert_between(motion.position, MIDDLE + 20.0, BOTTOM - 20.0, "пустая кабина на пути вверх")
	assert_almost_eq(_run(motion, 1.0, 0.0, true), MIDDLE, 0.01)
	assert_true(motion.is_aligned(), "доехала до этажа, куда шла")


func test_car_boarded_on_the_way_obeys_and_then_stops_between_floors() -> void:
	# Повёл — значит и остановил сам: дальше кабина снова встаёт по отпусканию.
	var motion := _shaft(2)
	_run(motion, 1.2, 0.0, false)
	var stopped := _run(motion, 0.3, ElevatorMotion.UP, true)
	assert_almost_eq(_run(motion, 1.0, 0.0, true), stopped, 0.01)
	assert_false(motion.is_aligned(), "остановленная пассажиром — между этажами")


func test_the_next_passenger_starts_unsteered() -> void:
	# Пассажир повёл и вышел; следующий входит на ходу — кабина снова доезжает.
	var motion := _shaft(2)
	_run(motion, 0.6, ElevatorMotion.UP, true)
	_run(motion, 0.8, 0.0, true)
	_run(motion, 1.2, 0.0, false)
	assert_false(motion.is_aligned(), "пустая кабина снова в пути")
	_run(motion, 1.0, 0.0, true)
	assert_true(motion.is_aligned(), "вошедший на ходу её не вёл — доехала")
