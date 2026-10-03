extends GutTest

## Otto state machine tests.
##
## They work without a scene and without physics: the machine takes an input snapshot and facts
## about the body, so its behaviour is checked directly.


func _snapshot(move: float = 0.0, crouch: bool = false, jump: bool = false) -> OttoInput:
	var input := OttoInput.new()
	input.move = move
	input.crouch = crouch
	input.jump_pressed = jump
	return input


func test_starts_idle() -> void:
	var machine := OttoStateMachine.new()
	assert_eq(machine.state, OttoStateMachine.State.IDLE)


func test_walks_when_moving_on_floor() -> void:
	var machine := OttoStateMachine.new()
	assert_eq(machine.update(_snapshot(1.0), true, 0.0), OttoStateMachine.State.WALK)


func test_tilt_below_threshold_is_idle() -> void:
	var machine := OttoStateMachine.new()
	var barely := OttoStateMachine.MOVE_THRESHOLD
	assert_eq(machine.update(_snapshot(barely), true, 0.0), OttoStateMachine.State.IDLE)


func test_crouches_when_down_held() -> void:
	var machine := OttoStateMachine.new()
	assert_eq(machine.update(_snapshot(0.0, true), true, 0.0), OttoStateMachine.State.CROUCH)


func test_crouch_beats_walk() -> void:
	var machine := OttoStateMachine.new()
	assert_eq(machine.update(_snapshot(1.0, true), true, 0.0), OttoStateMachine.State.CROUCH)


func test_jumps_from_floor() -> void:
	var machine := OttoStateMachine.new()
	assert_eq(machine.update(_snapshot(0.0, false, true), true, 0.0), OttoStateMachine.State.JUMP)


func test_cannot_jump_while_crouching() -> void:
	var machine := OttoStateMachine.new()
	assert_eq(machine.update(_snapshot(0.0, true, true), true, 0.0), OttoStateMachine.State.CROUCH)


func test_rising_in_air_is_jump() -> void:
	var machine := OttoStateMachine.new()
	machine.update(_snapshot(0.0, false, true), true, 0.0)
	assert_eq(machine.update(_snapshot(), false, -120.0), OttoStateMachine.State.JUMP)


## Walking off a rising cab roof hands Otto upward speed without a jump: that is a fall,
## not the jump pose and sound (ADR-0060).
func test_rising_without_a_jump_is_fall() -> void:
	var machine := OttoStateMachine.new()
	machine.update(_snapshot(1.0), true, 0.0)
	assert_eq(machine.update(_snapshot(1.0), false, -120.0), OttoStateMachine.State.FALL)


## Past the top of the jump the rise does not come back as a jump.
func test_jump_past_the_top_stays_a_fall() -> void:
	var machine := OttoStateMachine.new()
	machine.update(_snapshot(0.0, false, true), true, 0.0)
	machine.update(_snapshot(), false, -120.0)
	machine.update(_snapshot(), false, 10.0)
	assert_eq(machine.update(_snapshot(), false, -5.0), OttoStateMachine.State.FALL)


func test_falling_in_air_is_fall() -> void:
	var machine := OttoStateMachine.new()
	assert_eq(machine.update(_snapshot(), false, 120.0), OttoStateMachine.State.FALL)


func test_input_is_ignored_in_air() -> void:
	var machine := OttoStateMachine.new()
	assert_eq(machine.update(_snapshot(1.0, true, true), false, 120.0), OttoStateMachine.State.FALL)


func test_dead_is_terminal() -> void:
	var machine := OttoStateMachine.new()
	machine.kill()
	assert_eq(machine.update(_snapshot(1.0), true, 0.0), OttoStateMachine.State.DEAD)
	assert_true(machine.is_dead())


func test_reset_returns_to_idle() -> void:
	var machine := OttoStateMachine.new()
	machine.kill()
	machine.reset()
	assert_eq(machine.state, OttoStateMachine.State.IDLE)
	assert_false(machine.is_dead())


func test_just_entered_fires_only_once() -> void:
	var machine := OttoStateMachine.new()
	machine.update(_snapshot(0.0, false, true), true, 0.0)
	assert_true(machine.just_entered(OttoStateMachine.State.JUMP), "the first frame of the jump")

	machine.update(_snapshot(), false, -120.0)
	assert_false(machine.just_entered(OttoStateMachine.State.JUMP), "the second frame of the jump")


func test_state_name_matches_enum() -> void:
	assert_eq(OttoStateMachine.state_name(OttoStateMachine.State.CROUCH), "CROUCH")
	assert_eq(OttoStateMachine.state_name(OttoStateMachine.State.DEAD), "DEAD")
