extends GutTest

## Тесты пребывания Otto за дверью.
##
## Как и поездка на эскалаторе, это состояние снимается только снаружи: дверь
## выпускает Otto сама через пять секунд или раньше (ADR-0005, пункт 3).


func _snapshot(move: float = 0.0, crouch: bool = false, jump: bool = false) -> OttoInput:
	var input := OttoInput.new()
	input.move = move
	input.crouch = crouch
	input.jump_pressed = jump
	return input


func test_input_does_not_work_behind_the_door() -> void:
	var machine := OttoStateMachine.new()
	machine.go_indoors()
	var state := machine.update(_snapshot(1.0, true, true), true, 0.0)
	assert_eq(state, OttoStateMachine.State.INDOORS)


func test_coming_out_returns_control() -> void:
	var machine := OttoStateMachine.new()
	machine.go_indoors()
	machine.come_out()
	assert_eq(machine.update(_snapshot(1.0), true, 0.0), OttoStateMachine.State.WALK)


func test_the_dead_do_not_go_indoors() -> void:
	var machine := OttoStateMachine.new()
	machine.kill()
	machine.go_indoors()
	assert_eq(machine.state, OttoStateMachine.State.DEAD)


func test_coming_out_does_nothing_when_outside() -> void:
	var machine := OttoStateMachine.new()
	machine.update(_snapshot(0.0, true), true, 0.0)
	machine.come_out()
	assert_eq(machine.state, OttoStateMachine.State.CROUCH)


func test_world_driven_covers_door_and_escalator() -> void:
	var machine := OttoStateMachine.new()
	assert_false(machine.is_world_driven(), "на своих ногах Otto ведёт игрок")
	machine.go_indoors()
	assert_true(machine.is_world_driven(), "за дверью Otto распоряжается дверь")
	machine.come_out()
	assert_false(machine.is_world_driven())
	machine.ride()
	assert_true(machine.is_world_driven(), "на эскалаторе — эскалатор")
	machine.stop_riding()
	machine.kill()
	assert_true(machine.is_world_driven(), "мёртвый ввод не разбирает вовсе")
