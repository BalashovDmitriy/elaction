extends GutTest

## Elevator cab motion tests.
##
## They work without a scene and without physics: [ElevatorMotion] takes the frame time,
## the player's command and the occupancy fact, so it is checked directly.

const TOP: float = 0.0
const MIDDLE: float = 100.0
const BOTTOM: float = 200.0

## Test frame. At a speed of 100 px/s the cab covers exactly 10 px in it.
const STEP: float = 0.1


func _shaft(start_floor: int = 0) -> ElevatorMotion:
	var motion := ElevatorMotion.new()
	motion.speed = 100.0
	motion.floor_pause = 1.0
	# The test shaft is its own little world: floors a hundred units apart.
	# Settling onto a floor is set explicitly, otherwise the test depends on the
	# scale the game is drawn at: since M13 the world is three times larger, and the class default
	# (36) would cover the whole run between floors of this test.
	motion.settle_distance = 12.0
	motion.setup(PackedFloat32Array([TOP, MIDDLE, BOTTOM]), start_floor)
	return motion


## Runs several frames and returns the cab coordinate.
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


## A released cab does not stop between floors but runs on to the next floor in its travel,
## as in ROM (@5E1E), and stands there: it does not move further by itself (ADR-0053, decision 1).
func test_released_car_runs_on_to_the_floor_ahead() -> void:
	var motion := _shaft(2)
	_run(motion, 0.3, ElevatorMotion.UP, true)
	assert_almost_eq(_run(motion, 2.0, 0.0, true), MIDDLE, 0.01)
	assert_true(motion.is_aligned(), "the cab was brought to the floor")
	assert_almost_eq(
		_run(motion, 5.0, 0.0, true), MIDDLE, 0.01, "does not move by itself with a passenger"
	)


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
	assert_true(motion.is_stopped(), "the cab does not go above the top floor")


func test_occupied_car_does_not_move_on_its_own() -> void:
	var motion := _shaft(0)
	assert_almost_eq(_run(motion, 2.0, 0.0, true), TOP, 0.01)


func test_car_waits_on_the_floor_it_starts_from() -> void:
	var motion := _shaft(0)
	assert_almost_eq(_run(motion, 0.5, 0.0, false), TOP, 0.01)
	assert_true(motion.is_stopped(), "the cab stands at the floor before starting")


func test_empty_car_travels_by_itself() -> void:
	var motion := _shaft(0)
	# A second of starting pause on the floor plus a second of travel to the middle floor.
	assert_almost_eq(_run(motion, 2.5, 0.0, false), MIDDLE, 0.01)


func test_car_left_by_passenger_waits_before_moving_on() -> void:
	var motion := _shaft(0)
	_run(motion, 0.5, 0.0, true)
	# The passenger got out on the floor: the cab first stands its pause, like any empty one.
	assert_almost_eq(_run(motion, 0.8, 0.0, false), TOP, 0.01)
	assert_gt(_run(motion, 0.8, 0.0, false), TOP, "after the pause the cab set off by itself")


func test_empty_car_pauses_at_the_floor() -> void:
	var motion := _shaft(0)
	_run(motion, 2.5, 0.0, false)
	assert_almost_eq(_run(motion, 0.3, 0.0, false), MIDDLE, 0.01)


func test_empty_car_reverses_at_the_end_of_the_shaft() -> void:
	var motion := _shaft(0)
	_run(motion, 5.5, 0.0, false)
	assert_eq(motion.direction, ElevatorMotion.UP, "from the bottom floor the cab went up")
	assert_lt(motion.position, BOTTOM)


func test_alignment_reports_current_floor() -> void:
	var motion := _shaft(1)
	assert_eq(motion.aligned_floor(), 1)
	motion.update(STEP, ElevatorMotion.DOWN, true)
	assert_false(motion.is_aligned(), "a started cab does not match the floor")
	assert_eq(motion.aligned_floor(), -1)


func test_velocity_reports_real_movement() -> void:
	var motion := _shaft(0)
	motion.update(STEP, ElevatorMotion.DOWN, true)
	assert_almost_eq(motion.velocity, 100.0, 0.5)

	# A released cab runs on to the floor in its travel and only there stops.
	_run(motion, 0.4, ElevatorMotion.DOWN, true)
	motion.update(STEP, 0.0, true)
	assert_false(motion.is_stopped(), "released between floors it keeps going")
	_run(motion, 2.0, 0.0, true)
	assert_true(motion.is_stopped(), "stopped at the floor")


func test_shaft_with_one_floor_stays_put() -> void:
	var motion := ElevatorMotion.new()
	motion.speed = 100.0
	motion.setup(PackedFloat32Array([50.0]))
	assert_almost_eq(_run(motion, 2.0, 0.0, false), 50.0, 0.01)


func test_shaft_without_floors_is_harmless() -> void:
	var motion := ElevatorMotion.new()
	assert_eq(motion.update(STEP, ElevatorMotion.DOWN, true), 0.0)


## Arrival is not lost on fractions: a remainder of a step plus an extra millionth still
## counts, and the cab pauses on the floor rather than touching it and leaving.
##
## Found by the bot in M15: with metres and float32 stops the remainder to the top
## stop came out larger than a step by the last bit, the cab stopped a micron from
## it — "aligned" by FLOOR_EPSILON — and turned back without a pause. Otto
## waited for it on the roof forever. Here the same is done by hand and in test units.
func test_arrival_is_not_lost_to_float_noise() -> void:
	var motion := _shaft(2)
	# The start pause has passed with margin, the cab is already moving by itself — up, toward
	# MIDDLE. The margin is needed: a one-second pause is subtracted in tenths, and on fractions the
	# last frame may leave a hundred-trillionth of it — the cab would stand one more frame, and the
	# position rigged below would never move.
	_run(motion, 1.5, 0.0, false)
	motion.direction = ElevatorMotion.UP
	# One step and a millionth past the floor: without a tolerance the step falls short.
	motion.position = MIDDLE + motion.speed * STEP + 0.000001

	motion.update(STEP, 0.0, false)
	assert_eq(motion.aligned_floor(), 1, "the cab arrived at the floor")

	motion.update(STEP, 0.0, false)
	assert_eq(
		motion.aligned_floor(), 1, "and stands there for the pause rather than touching and leaving"
	)
	assert_true(motion.is_stopped(), "stands, not moving")


## The demo from the roof holds an empty cab on the floor (ADR-0041): it stands as long as
## told, and leaves on schedule afterwards.
func test_a_held_car_waits_then_goes() -> void:
	var motion := _shaft()
	motion.hold(3.0)
	assert_eq(_run(motion, 2.5, 0.0, false), TOP, "a held one stands longer than the usual pause")
	assert_gt(_run(motion, 1.5, 0.0, false), TOP, "and leaves when the time is up")
