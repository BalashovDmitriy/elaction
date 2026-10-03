extends GutTest

## Timer alarm tests.
##
## The main thing here is what does not exist: a way to clear the alarm by dying. In the original it
## holds until the end of the building, and it is a punishment for the whole playthrough, not for an
## attempt (ADR-0009, item 1).

const STEP: float = 0.1


func _alarm() -> Alarm:
	var alarm := Alarm.new()
	alarm.time_limit = 1.0
	alarm.enter_building()
	return alarm


func _run(alarm: Alarm, seconds: float) -> bool:
	var raised := false
	for _frame: int in int(roundf(seconds / STEP)):
		raised = alarm.tick(STEP) or raised
	return raised


func test_fresh_building_starts_quiet() -> void:
	var alarm := _alarm()
	assert_false(alarm.raised)
	assert_false(_run(alarm, 0.5), "there is still time")


func test_alarm_goes_off_when_the_time_runs_out() -> void:
	var alarm := _alarm()
	assert_true(_run(alarm, 1.5))
	assert_true(alarm.raised)


func test_alarm_goes_off_only_once() -> void:
	var alarm := _alarm()
	_run(alarm, 1.5)
	assert_false(_run(alarm, 1.0), "the siren turns on once, not every frame")


func test_new_building_takes_the_alarm_off() -> void:
	var alarm := _alarm()
	_run(alarm, 1.5)
	alarm.enter_building()
	assert_false(alarm.raised, "only a building change can clear the alarm")


func test_time_left_never_goes_below_zero() -> void:
	var alarm := _alarm()
	_run(alarm, 3.0)
	assert_eq(alarm.time_left(), 0.0)
