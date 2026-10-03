extends GutTest

## Tests of the cab response delay.
##
## During the alarm the cab "responds worse" — the original describes this directly. The delay
## does not accumulate between presses: released or stepped out — it is counted anew (ADR-0009,
## point 1). Stepping out has a separate test: an empty cab does not enter
## [method ElevatorMotion._drive], and without a reset the delay would work only for the first ride.

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


## The siren mid-ride: Otto holds "down" all the way, and the wait counter
## has long overflowed by this moment. Without a reset the alarm penalty would catch up
## only with the next press, while the started ride would finish the old way.
func test_the_alarm_catches_a_ride_already_under_way() -> void:
	var motion := _shaft()
	# No alarm yet: the cab responds immediately.
	motion.response_delay = 0.0
	var underway := _run(motion, 0.5, ElevatorMotion.DOWN)
	assert_gt(underway, TOP, "поехала сразу: тревоги ещё нет")

	motion.response_delay = 0.5
	motion.forget_command()
	assert_almost_eq(
		_run(motion, 0.4, ElevatorMotion.DOWN), underway, 0.01, "встала и думает заново"
	)
	assert_gt(_run(motion, 0.4, ElevatorMotion.DOWN), underway, "подумала и поехала")


func test_leaving_the_car_makes_it_think_again() -> void:
	var motion := _shaft()
	_run(motion, 1.0, ElevatorMotion.DOWN)
# The passenger stepped out: the cab is empty and still waits out the floor pause, not moving.
	motion.update(STEP, 0.0, false)
	var boarded_at := motion.position
	assert_almost_eq(
		_run(motion, 0.4, ElevatorMotion.DOWN), boarded_at, 0.01, "новый пассажир ждёт так же"
	)
