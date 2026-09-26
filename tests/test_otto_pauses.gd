extends GutTest

## Паузы разворота и приземления на живом Otto (ADR-0039, решение 4).
##
## Правило проверяет test_move_locks.gd; здесь — что Otto его слушается: стоит,
## пока поворачивается, и не идёт и не прыгает, пока восстанавливается после
## прыжка. Сцена — одна плита пола.

const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")

## Паузы меряются временем, а не кадрами: headless-прогон шагает физику
## по нескольку раз за кадр, и счёт кадрами врёт вдвое.


func after_each() -> void:
	for action: StringName in [&"move_left", &"move_right", &"jump"]:
		Input.action_release(action)


func _standing_otto() -> Otto:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 0.4, WorldSpace.CORRIDOR_DEPTH)
	shape.shape = box
	shape.position = Vector3(0.0, -0.2, 0.0)
	ground.add_child(shape)
	add_child_autofree(ground)
	var otto := OTTO_SCENE.instantiate() as Otto
	add_child_autofree(otto)
	otto.global_position = Vector3(0.0, 0.05, WorldSpace.PLAY_Z)
	await wait_physics_frames(6)
	assert_true(otto.is_grounded(), "Otto стоит на плите")
	return otto


func test_a_turn_holds_otto_in_place() -> void:
	var otto := await _standing_otto()
	var start := otto.global_position.x
	Input.action_press(&"move_left")
	await wait_seconds(MoveLocks.TURN_TIME * 0.4)
	assert_almost_eq(otto.global_position.x, start, 0.01, "поворачиваясь, стоит")
	await wait_seconds(MoveLocks.TURN_TIME + 0.15)
	assert_lt(otto.global_position.x, start - 0.05, "развернулся — пошёл влево")


func test_walking_on_ahead_has_no_pause() -> void:
	# Пауза — только на смену стороны: идущий вперёд трогается сразу.
	var otto := await _standing_otto()
	var start := otto.global_position.x
	Input.action_press(&"move_right")
	await wait_physics_frames(3)
	assert_gt(otto.global_position.x, start + 0.01, "вперёд — без паузы")


func test_a_landing_holds_walk_and_jump() -> void:
	var otto := await _standing_otto()
	Input.action_press(&"jump")
	await wait_physics_frames(2)
	Input.action_release(&"jump")
	var left := 120
	while left > 0 and not otto.is_grounded():
		await wait_physics_frames(1)
		left -= 1
	await wait_physics_frames(1)
	while left > 0 and not otto.is_grounded():
		await wait_physics_frames(1)
		left -= 1
	assert_true(otto.is_grounded(), "приземлился")
	var start := otto.global_position
	Input.action_press(&"move_right")
	Input.action_press(&"jump")
	await wait_seconds(MoveLocks.LAND_TIME * 0.4)
	assert_almost_eq(otto.global_position.x, start.x, 0.01, "восстанавливаясь, не идёт")
	assert_almost_eq(otto.global_position.y, start.y, 0.01, "и не прыгает")
	Input.action_release(&"jump")
	await wait_seconds(MoveLocks.LAND_TIME + 0.15)
	assert_gt(otto.global_position.x, start.x + 0.05, "восстановился — идёт")
