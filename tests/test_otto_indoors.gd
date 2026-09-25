extends GutTest

## Тесты пребывания Otto за дверью.
##
## Как и поездка на эскалаторе, это состояние снимается только снаружи: дверь
## выпускает Otto сама через 70 тиков ROM, раньше не выйти (ADR-0038, решение 2).


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


## Уязвим Otto только на своих ногах и без передышки: по этому агенты
## придерживают выстрел, а не пускают пулю сквозь него.
func test_otto_can_be_hit_only_on_foot_and_out_of_grace() -> void:
	var otto := preload("res://src/actors/otto/otto.tscn").instantiate() as Otto
	add_child_autofree(otto)
	assert_true(otto.hittable, "на своих ногах уязвим")
	otto.ride(true)
	assert_false(otto.hittable, "в проёме двери и на эскалаторе — нет")
	otto.ride(false)
	otto.stay_indoors(true)
	assert_false(otto.hittable, "за дверью — нет")
	otto.stay_indoors(false)
	assert_true(otto.hittable)
	otto.kill()
	assert_false(otto.hittable, "мёртвый — нет")
	otto.revive()
	assert_false(otto.hittable, "в передышку после возвращения — нет")
	await wait_seconds(Otto.RESPAWN_GRACE + 0.2)
	assert_true(otto.hittable, "передышка кончилась — снова уязвим")
