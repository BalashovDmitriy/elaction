extends GutTest

## Тесты состояния поездки на эскалаторе.
##
## RIDE снимается и ставится снаружи, как и DEAD: пока Otto везут, ввод игрока
## не действует (ADR-0004, пункт 8).


func _snapshot(move: float = 0.0, crouch: bool = false, jump: bool = false) -> OttoInput:
	var input := OttoInput.new()
	input.move = move
	input.crouch = crouch
	input.jump_pressed = jump
	return input


func test_escalator_ride_ignores_input() -> void:
	var machine := OttoStateMachine.new()
	machine.ride()
	var state := machine.update(_snapshot(1.0, true, true), true, 0.0)
	assert_eq(state, OttoStateMachine.State.RIDE, "пока везёт эскалатор, ввод не действует")


func test_stop_riding_returns_control() -> void:
	var machine := OttoStateMachine.new()
	machine.ride()
	machine.stop_riding()
	assert_eq(machine.state, OttoStateMachine.State.IDLE)
	assert_eq(machine.update(_snapshot(1.0), true, 0.0), OttoStateMachine.State.WALK)


func test_stop_riding_does_nothing_when_not_riding() -> void:
	var machine := OttoStateMachine.new()
	machine.update(_snapshot(0.0, true), true, 0.0)
	machine.stop_riding()
	assert_eq(machine.state, OttoStateMachine.State.CROUCH)


func test_escalator_does_not_revive_the_dead() -> void:
	var machine := OttoStateMachine.new()
	machine.kill()
	machine.ride()
	assert_eq(machine.state, OttoStateMachine.State.DEAD, "из DEAD выводит только reset")
