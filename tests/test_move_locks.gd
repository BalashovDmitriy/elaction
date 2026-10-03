extends GutTest

## Turnaround and landing pauses (ADR-0039, decision 4).


func test_a_fresh_actor_walks_and_jumps() -> void:
	var locks := MoveLocks.new()
	assert_true(locks.can_walk(), "walks without pauses")
	assert_true(locks.can_jump(), "and jumps")


func test_a_turn_holds_the_feet_but_not_the_jump() -> void:
	var locks := MoveLocks.new()
	locks.turn()
	assert_false(locks.can_walk(), "turning, does not walk")
	assert_true(locks.can_jump(), "can jump out of a turn")
	locks.tick(MoveLocks.TURN_TIME * 0.5)
	assert_false(locks.can_walk(), "half a turn - still standing")
	locks.tick(MoveLocks.TURN_TIME * 0.5 + 0.001)
	assert_true(locks.can_walk(), "turned - walks")


func test_a_landing_holds_walk_and_jump() -> void:
	var locks := MoveLocks.new()
	locks.land()
	assert_false(locks.can_walk(), "landing, does not walk")
	assert_false(locks.can_jump(), "and does not jump")
	locks.tick(MoveLocks.LAND_TIME + 0.001)
	assert_true(locks.can_walk(), "recovered - walks")
	assert_true(locks.can_jump(), "and jumps")


func test_the_pauses_end_on_their_frame() -> void:
	# Physics steps at 1/60: a 0.1 s pause is six frames, not seven due to a float
	# remainder, and 0.15 s is nine.
	var locks := MoveLocks.new()
	locks.turn()
	for _frame in roundi(MoveLocks.TURN_TIME * 60.0):
		locks.tick(1.0 / 60.0)
	assert_true(locks.can_walk(), "the turn ended on its own frame")
	locks.land()
	for _frame in roundi(MoveLocks.LAND_TIME * 60.0):
		locks.tick(1.0 / 60.0)
	assert_true(locks.can_jump(), "recovery - also")


func test_a_repeated_turn_restarts_the_pause() -> void:
	var locks := MoveLocks.new()
	locks.turn()
	locks.tick(MoveLocks.TURN_TIME * 0.9)
	locks.turn()
	locks.tick(MoveLocks.TURN_TIME * 0.5)
	assert_false(locks.can_walk(), "a new turn - a new pause")


func test_clear_drops_both_pauses() -> void:
	var locks := MoveLocks.new()
	locks.turn()
	locks.land()
	locks.clear()
	assert_true(locks.can_walk() and locks.can_jump(), "no pauses after returning to the game")


func test_the_pauses_stay_short() -> void:
	# Pauses are the weight of movement, not a new mechanic: longer than a fifth of a
	# second they already compete with bullets three times faster than the ROM (ADR-0037).
	assert_lt(MoveLocks.TURN_TIME, 0.2, "turn is shorter than 0.2 s")
	assert_lt(MoveLocks.LAND_TIME, 0.2, "recovery is shorter than 0.2 s")
