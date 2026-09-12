extends GutTest

## Тесты тревоги по таймеру.
##
## Главное здесь — то, чего нет: способа снять тревогу смертью. В оригинале она
## держится до конца здания, и это наказание на всё прохождение, а не на попытку
## (ADR-0009, пункт 1).

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
	assert_false(_run(alarm, 0.5), "время ещё есть")


func test_alarm_goes_off_when_the_time_runs_out() -> void:
	var alarm := _alarm()
	assert_true(_run(alarm, 1.5))
	assert_true(alarm.raised)


func test_alarm_goes_off_only_once() -> void:
	var alarm := _alarm()
	_run(alarm, 1.5)
	assert_false(_run(alarm, 1.0), "сирена включается один раз, а не каждый кадр")


func test_new_building_takes_the_alarm_off() -> void:
	var alarm := _alarm()
	_run(alarm, 1.5)
	alarm.enter_building()
	assert_false(alarm.raised, "снять тревогу может только смена здания")


func test_time_left_never_goes_below_zero() -> void:
	var alarm := _alarm()
	_run(alarm, 3.0)
	assert_eq(alarm.time_left(), 0.0)
