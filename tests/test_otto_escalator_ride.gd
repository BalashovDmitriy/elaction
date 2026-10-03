extends GutTest

## Tests of the escalator ride state.
##
## RIDE is cleared and set from outside, like DEAD: while Otto is being carried, the
## player's input has no effect (ADR-0004, point 8).

const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")
const ESCALATOR_SCENE := preload("res://src/systems/escalators/escalator.tscn")

## Otto standing on the escalator in the scene tests.
var _rider: Otto = null


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
	assert_eq(
		state, OttoStateMachine.State.RIDE, "while the escalator carries him, input has no effect"
	)


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
	assert_eq(machine.state, OttoStateMachine.State.DEAD, "only reset leaves DEAD")


## An escalator with Otto on its upper landing: a slab under him, the flight down to the
## right. Returns the escalator; Otto is in [member _rider].
func _escalator_with_otto() -> Escalator:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 0.4, WorldSpace.CORRIDOR_DEPTH)
	shape.shape = box
	shape.position = Vector3(0.0, -0.2, 0.0)
	ground.add_child(shape)
	add_child_autofree(ground)
	var escalator := ESCALATOR_SCENE.instantiate() as Escalator
	add_child_autofree(escalator)
	escalator.setup(Vector2(3.0, 3.0), Vector2(1.5, 1.5), Vector2(0.6, 3.0), 0.3)
	_rider = OTTO_SCENE.instantiate() as Otto
	add_child_autofree(_rider)
	_rider.global_position = Vector3(0.0, 0.05, WorldSpace.PLAY_Z)
	return escalator


## Presses "down" until the escalator takes Otto. Returns whether it took him.
func _board(escalator: Escalator) -> bool:
	await wait_physics_frames(4)
	Input.action_press(&"move_down")
	for step: int in 30:
		await wait_physics_frames(1)
		if escalator.is_busy():
			break
	Input.action_release(&"move_down")
	return escalator.is_busy()


## A bullet that reaches Otto in the step the escalator takes him does not kill him: he
## would ride on dead (ADR-0060).
func test_otto_on_the_escalator_cannot_be_killed() -> void:
	var escalator := _escalator_with_otto()
	assert_true(await _board(escalator), "the escalator took Otto")
	_rider.kill()
	assert_false(_rider.is_dead(), "not killed on the escalator")


## A rider who is dead all the same is dropped, not carried on (ADR-0060).
func test_the_escalator_drops_a_dead_rider() -> void:
	var escalator := _escalator_with_otto()
	assert_true(await _board(escalator), "the escalator took Otto")
	(_rider.get(&"_states") as OttoStateMachine).kill()
	await wait_physics_frames(2)
	assert_false(escalator.is_busy(), "the escalator let go of the dead one")
