extends GutTest

## Улёгшееся тело застывает (ADR-0044, решение 11).
##
## Замер M24h: двадцать трупов с рэгдоллом не засыпали — в стопке соседи будили
## друг друга. Застывшее тело статично: физика его не считает, но на него
## по-прежнему ложатся другие, и выглядит оно так же. Опора ушла — тело снова
## живёт физикой ([method Ragdoll.wake]). Выпавшее из мира — пропадает.

const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
## Сколько шагов дать телу лечь и застыть.
const SETTLE_FRAMES: int = 480


func before_all() -> void:
	# Как в test_enemy_corpse: мир быстрее, шаг физики мельче — иначе суставы
	# рэгдолла на длинном шаге разлетаются.
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240


func after_all() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Ragdoll.abyss = -INF
	GameState.instance().reset()


func _floor_at(height: float) -> StaticBody3D:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 0.4, WorldSpace.CORRIDOR_DEPTH)
	shape.shape = box
	shape.position = Vector3(0.0, -0.2, 0.0)
	ground.add_child(shape)
	add_child_autofree(ground)
	ground.global_position = Vector3(0.0, height, 0.0)
	return ground


func _corpse_at(at: Vector3) -> Enemy:
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.walk_speed = 0.0
	add_child_autofree(agent)
	agent.global_position = at
	agent.setup(null, 1.0)
	while agent.is_emerging():
		await wait_physics_frames(1)
	agent.kill()
	return agent


func _wait_frozen(agent: Enemy) -> bool:
	for _frame: int in SETTLE_FRAMES:
		await wait_physics_frames(1)
		if agent.corpse.ragdoll.is_frozen():
			return true
	return false


func test_a_body_at_rest_freezes_where_it_lies() -> void:
	_floor_at(0.0)
	var agent: Enemy = await _corpse_at(Vector3.ZERO)
	assert_true(await _wait_frozen(agent), "улёгшееся тело застыло")
	var before := agent.corpse.ragdoll.bounds()
	await wait_physics_frames(60)
	var after := agent.corpse.ragdoll.bounds()
	assert_almost_eq(
		after.get_center().distance_to(before.get_center()), 0.0, 0.01, "и не двигается"
	)
	assert_gt(after.position.y, -0.1, "лежит на полу, а не под ним")


func test_another_body_lies_on_a_frozen_one() -> void:
	_floor_at(0.0)
	var first: Enemy = await _corpse_at(Vector3.ZERO)
	assert_true(await _wait_frozen(first), "первое застыло")
	var top := first.corpse.ragdoll.bounds().end.y
	var second: Enemy = await _corpse_at(Vector3(0.0, top + 0.3, 0.0))
	await wait_physics_frames(SETTLE_FRAMES / 2)
	assert_gt(
		second.corpse.ragdoll.bounds().end.y,
		top + 0.05,
		"второе легло сверху, а не провалилось сквозь застывшее"
	)


func test_a_frozen_body_wakes_when_its_floor_goes() -> void:
	var ground := _floor_at(0.0)
	var agent: Enemy = await _corpse_at(Vector3.ZERO)
	assert_true(await _wait_frozen(agent), "застыло")
	ground.queue_free()
	await wait_physics_frames(2)
	agent.corpse.ragdoll.wake()
	assert_false(agent.corpse.ragdoll.is_frozen(), "проснулось")
	var before := agent.corpse.ragdoll.bounds().position.y
	await wait_physics_frames(60)
	assert_lt(agent.corpse.ragdoll.bounds().position.y, before - 0.5, "и падает")


func test_a_body_fallen_out_of_the_world_is_gone() -> void:
	Ragdoll.abyss = -5.0
	var agent: Enemy = await _corpse_at(Vector3.ZERO)
	for _frame: int in SETTLE_FRAMES:
		await wait_physics_frames(1)
		if agent.corpse.gone:
			break
	assert_true(agent.corpse.gone, "упавшее ниже мира тело пропало")
	Ragdoll.abyss = -INF
