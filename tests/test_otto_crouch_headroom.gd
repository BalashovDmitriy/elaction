extends GutTest

## Тесты вставания из приседа.
##
## Место над головой машина состояний не измеряет — ей его сообщают фактом
## can_stand, как и опору под ногами. Долг M1, закрыт в M2.


func _snapshot(move: float = 0.0, crouch: bool = false, jump: bool = false) -> OttoInput:
	var input := OttoInput.new()
	input.move = move
	input.crouch = crouch
	input.jump_pressed = jump
	return input


func test_crouch_holds_while_there_is_no_headroom() -> void:
	var machine := OttoStateMachine.new()
	machine.update(_snapshot(0.0, true), true, 0.0)
	var blocked := machine.update(_snapshot(), true, 0.0, false)
	assert_eq(blocked, OttoStateMachine.State.CROUCH, "встать некуда — остаёмся в приседе")


func test_stands_up_once_headroom_appears() -> void:
	var machine := OttoStateMachine.new()
	machine.update(_snapshot(0.0, true), true, 0.0)
	machine.update(_snapshot(), true, 0.0, false)
	assert_eq(machine.update(_snapshot(), true, 0.0, true), OttoStateMachine.State.IDLE)


func test_cannot_jump_out_of_a_blocked_crouch() -> void:
	var machine := OttoStateMachine.new()
	machine.update(_snapshot(0.0, true), true, 0.0)
	var jumped := machine.update(_snapshot(0.0, false, true), true, 0.0, false)
	assert_eq(jumped, OttoStateMachine.State.CROUCH)


func test_headroom_does_not_hold_a_standing_otto() -> void:
	var machine := OttoStateMachine.new()
	# Низкий потолок мешает только тому, кто сидит.
	assert_eq(machine.update(_snapshot(1.0), true, 0.0, false), OttoStateMachine.State.WALK)
