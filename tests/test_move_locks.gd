extends GutTest

## Паузы разворота и приземления (ADR-0039, решение 4).


func test_a_fresh_actor_walks_and_jumps() -> void:
	var locks := MoveLocks.new()
	assert_true(locks.can_walk(), "без пауз идёт")
	assert_true(locks.can_jump(), "и прыгает")


func test_a_turn_holds_the_feet_but_not_the_jump() -> void:
	var locks := MoveLocks.new()
	locks.turn()
	assert_false(locks.can_walk(), "разворачиваясь, не идёт")
	assert_true(locks.can_jump(), "прыгнуть с разворота можно")
	locks.tick(MoveLocks.TURN_TIME * 0.5)
	assert_false(locks.can_walk(), "полразворота — ещё стоит")
	locks.tick(MoveLocks.TURN_TIME * 0.5 + 0.001)
	assert_true(locks.can_walk(), "развернулся — идёт")


func test_a_landing_holds_walk_and_jump() -> void:
	var locks := MoveLocks.new()
	locks.land()
	assert_false(locks.can_walk(), "приземлившись, не идёт")
	assert_false(locks.can_jump(), "и не прыгает")
	locks.tick(MoveLocks.LAND_TIME + 0.001)
	assert_true(locks.can_walk(), "восстановился — идёт")
	assert_true(locks.can_jump(), "и прыгает")


func test_the_pauses_end_on_their_frame() -> void:
	# Физика шагает по 1/60: пауза в 0.1 с — это шесть кадров, а не семь из-за
	# остатка float, и 0.15 с — девять.
	var locks := MoveLocks.new()
	locks.turn()
	for _frame in roundi(MoveLocks.TURN_TIME * 60.0):
		locks.tick(1.0 / 60.0)
	assert_true(locks.can_walk(), "разворот кончился на своём кадре")
	locks.land()
	for _frame in roundi(MoveLocks.LAND_TIME * 60.0):
		locks.tick(1.0 / 60.0)
	assert_true(locks.can_jump(), "восстановление — тоже")


func test_a_repeated_turn_restarts_the_pause() -> void:
	var locks := MoveLocks.new()
	locks.turn()
	locks.tick(MoveLocks.TURN_TIME * 0.9)
	locks.turn()
	locks.tick(MoveLocks.TURN_TIME * 0.5)
	assert_false(locks.can_walk(), "новый разворот — новая пауза")


func test_clear_drops_both_pauses() -> void:
	var locks := MoveLocks.new()
	locks.turn()
	locks.land()
	locks.clear()
	assert_true(locks.can_walk() and locks.can_jump(), "после возвращения в игру пауз нет")


func test_the_pauses_stay_short() -> void:
	# Паузы — вес движения, а не новая механика: дольше пятой доли секунды
	# они уже спорят с пулями втрое быстрее ROM (ADR-0037).
	assert_lt(MoveLocks.TURN_TIME, 0.2, "разворот короче 0.2 с")
	assert_lt(MoveLocks.LAND_TIME, 0.2, "восстановление короче 0.2 с")
