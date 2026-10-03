extends GutTest

## Tests for Otto staying behind a door.
##
## Like an escalator ride, this state is lifted only from outside: the door lets Otto out
## by itself after 70 ROM ticks, you cannot leave earlier (ADR-0038, decision 2).

const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")


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
	assert_false(machine.is_world_driven(), "on his own feet Otto is driven by the player")
	machine.go_indoors()
	assert_true(machine.is_world_driven(), "behind a door the door commands Otto")
	machine.come_out()
	assert_false(machine.is_world_driven())
	machine.ride()
	assert_true(machine.is_world_driven(), "on an escalator the escalator does")
	machine.stop_riding()
	machine.kill()
	assert_true(machine.is_world_driven(), "a dead one does not parse input at all")


## Otto is vulnerable only on his own feet and without a breather: this is how agents
## know to hold their fire instead of sending a bullet through him.
func test_otto_can_be_hit_only_on_foot_and_out_of_grace() -> void:
	var otto := OTTO_SCENE.instantiate() as Otto
	add_child_autofree(otto)
	assert_true(otto.hittable, "vulnerable on his own feet")
	otto.ride(true)
	assert_false(otto.hittable, "not in a doorway or on an escalator")
	otto.ride(false)
	otto.stay_indoors(true)
	assert_false(otto.hittable, "not behind a door")
	otto.stay_indoors(false)
	assert_true(otto.hittable)
	otto.kill()
	assert_false(otto.hittable, "not when dead")
	otto.revive()
	assert_false(otto.hittable, "not in the grace period after returning")
	await wait_seconds(Otto.RESPAWN_GRACE + 0.2)
	assert_true(otto.hittable, "grace period over: vulnerable again")


## The cab calls [method Otto.kill] every physics step while Otto is under it, during a
## breather as well: the crush sounds only as a real death, not as a volley in every
## voice (M24k code review).
func test_a_crush_in_grace_makes_no_sound() -> void:
	var director := AudioDirector.instance()
	assert_not_null(director, "the sound autoload is up")
	if director == null:
		return
	var otto := OTTO_SCENE.instantiate() as Otto
	add_child_autofree(otto)
	otto.kill()
	otto.revive()
	for _step: int in 3:
		otto.kill(true)
	assert_false(otto.is_dead(), "the cab does not kill during the grace period")
	assert_eq(director.voices_playing(Sounds.CRUSH), 0, "and the crush does not sound")
	await wait_seconds(Otto.RESPAWN_GRACE + 0.2)
	otto.kill(true)
	assert_true(otto.is_dead(), "without the grace period it crushes")
	assert_eq(director.voices_playing(Sounds.CRUSH), 1, "and the crush sounds once")
