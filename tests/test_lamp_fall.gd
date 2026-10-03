extends GutTest

## Lamp fall tests.
##
## The second "arming" in the project after the door: the node disappears only at the end of the
## frame, and until then keeps catching bullets. Without a ban on restarting, a second bullet would
## raise an already fallen lamp back.

const STEP: float = 0.1


func _fall() -> LampFall:
	var fall := LampFall.new()
	fall.speed = 100.0
	fall.distance = 40.0
	return fall


func test_hanging_lamp_does_not_move() -> void:
	assert_eq(_fall().advance(STEP), 0.0, "пока не сбита — висит")


func test_shot_lamp_starts_falling() -> void:
	var fall := _fall()
	assert_true(fall.start())
	assert_almost_eq(fall.advance(STEP), 10.0, 0.01)


func test_second_bullet_does_not_restart_the_fall() -> void:
	var fall := _fall()
	fall.start()
	assert_false(fall.start(), "уже падает")


func test_fall_stops_exactly_at_the_floor() -> void:
	var fall := _fall()
	fall.start()
	var travelled := 0.0
	for _frame: int in 10:
		travelled += fall.advance(STEP)
	assert_almost_eq(travelled, fall.distance, 0.01, "пролетела ровно сколько отмерено")
	assert_true(fall.has_landed())


func test_landed_lamp_stays_down() -> void:
	var fall := _fall()
	fall.start()
	for _frame: int in 10:
		fall.advance(STEP)
	assert_false(fall.start(), "вторая пуля в упавшую лампу её не поднимает")
	assert_eq(fall.advance(STEP), 0.0)
