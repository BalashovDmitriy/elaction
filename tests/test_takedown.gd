extends GutTest

## Добивания вместо удара ногой (ADR-0040): правило, позы сценок и сценка на
## живых Otto и агенте.

const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const AGENT_MODEL := preload("res://assets/models/agent.glb")

## Сколько ждать конца сценки, с — с запасом на самую длинную.
const SCENE_WAIT: float = 3.0


func after_each() -> void:
	Input.action_release(&"shoot")
	Input.action_release(&"jump")
	Engine.time_scale = 1.0
	GameState.instance().reset()


# --- Правило -------------------------------------------------------------------


func test_reach_is_close_ahead_on_the_same_floor() -> void:
	var otto := Vector2(0.0, 0.0)
	assert_true(Takedown.can_reach(otto, 1.0, Vector2(0.6, 0.0)), "рядом впереди — достаёт")
	assert_false(Takedown.can_reach(otto, 1.0, Vector2(-0.6, 0.0)), "за спиной — нет")
	assert_false(Takedown.can_reach(otto, 1.0, Vector2(2.0, 0.0)), "далеко — стреляет")
	assert_false(Takedown.can_reach(otto, 1.0, Vector2(0.6, 3.0)), "этажом выше — нет")
	assert_true(Takedown.can_reach(otto, -1.0, Vector2(-0.6, 0.0)), "смотрит влево — слева")


func test_the_side_is_where_the_agent_looks() -> void:
	assert_eq(Takedown.side_of(0.0, 0.7, -1.0), Takedown.Side.FRONT, "агент смотрит на Otto")
	assert_eq(Takedown.side_of(0.0, 0.7, 1.0), Takedown.Side.BACK, "агент спиной к Otto")


func test_landing_next_to_an_agent_is_a_pounce() -> void:
	# ADR-0042, решение 9: вплотную на том же этаже — с любой стороны, с прыжка
	# или с этажа выше, неважно.
	var agent := Vector2(0.0, 0.0)
	assert_true(Takedown.lands_on(Vector2(0.2, 0.0), agent), "на агента — напрыгнул")
	assert_true(Takedown.lands_on(Vector2(-0.8, 0.05), agent), "вплотную сзади — тоже")
	assert_false(Takedown.lands_on(Vector2(1.5, 0.0), agent), "в стороне — нет")
	assert_false(Takedown.lands_on(Vector2(0.2, 3.6), agent), "этажом выше — нет")


func test_scores_by_side_with_the_dark_bonus() -> void:
	# Решение пользователя (ADR-0040): спереди 200, сзади и сверху 300, в темноте
	# +100. Дороже выстрела (100) при любой стороне.
	assert_eq(Takedown.score(Takedown.Side.FRONT, false), 200)
	assert_eq(Takedown.score(Takedown.Side.BACK, false), 300)
	assert_eq(Takedown.score(Takedown.Side.ABOVE, false), 300)
	assert_eq(Takedown.score(Takedown.Side.FRONT, true), 300)
	for side: int in Takedown.SCORES:
		assert_gt(Takedown.score(side, false), GameState.ENEMY_SHOT_SCORE, "дороже выстрела")


func test_every_side_has_scenes_and_the_front_and_back_vary() -> void:
	assert_eq(Takedown.scenes_for(Takedown.Side.FRONT).size(), 2, "спереди — серия и рукоять")
	assert_eq(Takedown.scenes_for(Takedown.Side.BACK).size(), 2, "сзади — удушение и шея")
	assert_eq(Takedown.scenes_for(Takedown.Side.ABOVE).size(), 1, "сверху — напрыгивание")


func test_a_scene_does_not_repeat_in_a_row() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var last := ""
	for _round in 40:
		var scene := Takedown.pick(Takedown.Side.BACK, last, rng)
		assert_ne(scene.name, last, "та же сценка подряд не повторяется")
		last = scene.name


func test_every_scene_is_playable() -> void:
	# Позы сценок — из таблицы рига: неизвестная встала бы стойкой, и сценка
	# играла бы сама себя без движения.
	for scene: Takedown.Scene in Takedown.all_scenes():
		assert_gt(scene.kill_at, 0.0, "%s: агент гибнет не в первый кадр" % scene.name)
		assert_lt(scene.kill_at, scene.duration, "%s: и до конца сценки" % scene.name)
		assert_lte(scene.duration, 1.5, "%s: сценка короткая" % scene.name)
		assert_true(FigurePoses.knows(scene.corpse), "%s: труп %s" % [scene.name, scene.corpse])
		assert_true(ActorPose.is_down(scene.corpse), "%s: труп лежит" % scene.name)
		for track: Array[Array] in [scene.otto, scene.agent]:
			var previous := -1.0
			for key: Array in track:
				assert_true(FigurePoses.knows(String(key[1])), "%s: поза %s" % [scene.name, key[1]])
				assert_gt(float(key[0]), previous, "%s: ключи по времени" % scene.name)
				previous = float(key[0])


func test_a_snapped_neck_turns_the_head_aside() -> void:
	var rig := FigureRig.new()
	rig.model = AGENT_MODEL
	add_child_autofree(rig)
	rig.show_pose("snap_held")
	rig.snap()
	var held := rig.bone_rotation(FigureRig.HEAD)
	rig.show_pose("snap_broken")
	rig.snap()
	assert_gt(
		held.angle_to(rig.bone_rotation(FigureRig.HEAD)),
		deg_to_rad(30.0),
		"голова повёрнута вбок, а не кивнула"
	)


# --- Сценка на живых -------------------------------------------------------------


func _floor() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30.0, 0.4, WorldSpace.CORRIDOR_DEPTH)
	shape.shape = box
	shape.position = Vector3(0.0, -0.2, 0.0)
	ground.add_child(shape)
	add_child_autofree(ground)


func _wall(x: float) -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 0.8, WorldSpace.CORRIDOR_DEPTH)
	shape.shape = box
	shape.position = Vector3(x, 0.4, 0.0)
	wall.add_child(shape)
	add_child_autofree(wall)


func _otto_at(x: float, y: float = 0.05) -> Otto:
	var otto := OTTO_SCENE.instantiate() as Otto
	add_child_autofree(otto)
	otto.global_position = Vector3(x, y, WorldSpace.PLAY_Z)
	return otto


## Агент, вышедший сразу и не стреляющий: сценку проверяют, а не дуэль.
func _agent_at(otto: Otto, x: float, facing: float) -> Enemy:
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.emerge_time = 0.0
	var rules := BuildingRules.new()
	rules.agents_hold_fire = true
	add_child_autofree(agent)
	agent.apply_rules(rules)
	agent.global_position = Vector3(x, 0.05, WorldSpace.PLAY_Z)
	agent.setup(otto, facing)
	return agent


func _director() -> TakedownScene:
	for child: Node in get_children():
		if child is TakedownScene:
			return child
	return null


func _press_shoot() -> void:
	Input.action_press(&"shoot")
	await wait_physics_frames(2)
	Input.action_release(&"shoot")


func _wait_for_the_end(agent: Enemy) -> void:
	var left := SCENE_WAIT
	while left > 0.0 and _director() != null:
		await wait_seconds(0.1)
		left -= 0.1
	assert_null(_director(), "сценка кончилась")
	assert_true(agent.is_dead(), "агент добит")


func test_shooting_close_up_takes_the_agent_down_from_the_front() -> void:
	_floor()
	var otto := _otto_at(0.0)
	await wait_physics_frames(4)
	var agent := _agent_at(otto, 0.7, -1.0)
	await wait_physics_frames(3)
	var before := GameState.instance().score
	await _press_shoot()
	var director := _director()
	assert_not_null(director, "выстрел вплотную — добивание, а не выстрел")
	if director == null:
		return
	assert_eq(director.scene().side, Takedown.Side.FRONT, "агент лицом к Otto — спереди")
	# Замедление неровное (ADR-0050): заход быстрее, к удару — [constant
	# TakedownScene.SLOW], на ударе — стоп-кадр.
	assert_between(
		Engine.time_scale,
		TakedownScene.SLOW - 0.001,
		TakedownScene.APPROACH + 0.001,
		"мир замедлен"
	)
	assert_true(otto.takedown != null, "Otto в сценке")
	var froze := false
	for _frame: int in 600:
		await wait_physics_frames(1)
		if not is_instance_valid(director):
			break
		if director.is_frozen():
			froze = froze or Engine.time_scale < TakedownScene.SLOW * 0.5
		if director.killed() and not director.is_frozen():
			break
	assert_true(froze, "на ударе — стоп-кадр: мир почти встал")
	assert_true(agent.is_dead(), "агент погиб на ударе")
	assert_false(agent.held, "погибший отпущен — падает рэгдоллом, а не позой")
	var hat := agent.figure.find_child("hat", true, false) as MeshInstance3D
	assert_not_null(hat, "у агента шляпа — своим мешем")
	if hat != null:
		assert_false(hat.visible, "шляпа слетела с головы")
	assert_not_null(agent.get_parent().find_child("Hat", false, false), "и улетела телом")
	await _wait_for_the_end(agent)
	assert_eq(GameState.instance().score - before, 200, "спереди — 200")
	assert_almost_eq(Engine.time_scale, 1.0, 0.001, "мир снова в своём темпе")
	assert_null(otto.takedown, "Otto отпущен")


func test_from_behind_scores_more() -> void:
	_floor()
	var otto := _otto_at(0.0)
	await wait_physics_frames(4)
	var agent := _agent_at(otto, 0.7, 1.0)
	await wait_physics_frames(3)
	var before := GameState.instance().score
	await _press_shoot()
	var director := _director()
	assert_not_null(director, "сзади — тоже добивание")
	if director == null:
		return
	assert_eq(director.scene().side, Takedown.Side.BACK, "агент спиной — сзади")
	await _wait_for_the_end(agent)
	assert_eq(GameState.instance().score - before, 300, "сзади — 300")


func test_a_far_agent_is_shot_not_taken_down() -> void:
	_floor()
	var otto := _otto_at(0.0)
	await wait_physics_frames(4)
	_agent_at(otto, 4.0, -1.0)
	await wait_physics_frames(3)
	await _press_shoot()
	assert_null(_director(), "далеко — сценки нет")
	assert_gt(get_tree().get_nodes_in_group(Bullet.GROUP).size(), 0, "а пуля летит")


func test_otto_killed_mid_scene_lets_the_agent_live() -> void:
	# Otto в сценке уязвим (ADR-0040, решение 5): погиб до ключевого кадра —
	# агент жив и снова в бою, мир в своём темпе.
	_floor()
	var otto := _otto_at(0.0)
	await wait_physics_frames(4)
	var agent := _agent_at(otto, 0.7, -1.0)
	await wait_physics_frames(3)
	await _press_shoot()
	assert_not_null(_director(), "сценка началась")
	otto.kill()
	await wait_physics_frames(2)
	assert_null(_director(), "сценка оборвалась")
	assert_false(agent.is_dead(), "агент жив")
	assert_false(agent.held, "и снова в бою")
	assert_almost_eq(Engine.time_scale, 1.0, 0.001, "мир в своём темпе")


func test_falling_onto_an_agent_pounces_by_itself() -> void:
	_floor()
	# Загон из двух низких стенок: агент ходит быстрее, чем Otto падает, и из-под
	# падающего уходит — в игре так и надо, а в тесте он разворачивается на месте.
	_wall(-0.9)
	_wall(0.9)
	var otto := _otto_at(-6.0)
	var agent := _agent_at(otto, 0.0, -1.0)
	# Сверху напрыгивают на вышедшего: в проёме агент неуязвим.
	var wait := 120
	while wait > 0 and not agent.takedown_ready:
		await wait_physics_frames(1)
		wait -= 1
	assert_true(agent.takedown_ready, "агент вышел из двери")
	otto.global_position = Vector3(agent.global_position.x, 2.6, WorldSpace.PLAY_Z)
	var left := 120
	while left > 0 and _director() == null:
		await wait_physics_frames(1)
		left -= 1
	var director := _director()
	assert_not_null(director, "упал на агента — напрыгнул без кнопки")
	if director == null:
		return
	assert_eq(director.scene().side, Takedown.Side.ABOVE, "сверху")
	await _wait_for_the_end(agent)


func test_a_dead_otto_does_not_pounce() -> void:
	# Убитый в полёте падает телом: напрыгивает только живой.
	_floor()
	_wall(-0.9)
	_wall(0.9)
	var otto := _otto_at(-6.0)
	var agent := _agent_at(otto, 0.0, -1.0)
	var wait := 120
	while wait > 0 and not agent.takedown_ready:
		await wait_physics_frames(1)
		wait -= 1
	otto.global_position = Vector3(agent.global_position.x, 2.6, WorldSpace.PLAY_Z)
	await wait_physics_frames(3)
	otto.kill()
	await wait_seconds(1.0)
	assert_true(otto.is_grounded(), "тело упало")
	assert_null(_director(), "мёртвый не напрыгивает")
	assert_false(agent.is_dead(), "агент жив")


func test_a_jump_onto_an_agent_pounces() -> void:
	# Отзыв после M24e: прыжок с приземлением на агента не добивал никогда —
	# напрыгивание ждало опоры выше этажа агента. С M24f приземлился вплотную —
	# напрыгнул (ADR-0042, решение 9).
	_floor()
	_wall(-0.9)
	_wall(0.9)
	var otto := _otto_at(0.0)
	var agent := _agent_at(otto, 0.0, -1.0)
	# Прыгают с пола: поставленный Otto сперва долетает до него.
	var wait := 120
	while wait > 0 and not (agent.takedown_ready and otto.is_grounded()):
		await wait_physics_frames(1)
		wait -= 1
	Input.action_press(&"jump")
	await wait_physics_frames(2)
	Input.action_release(&"jump")
	var left := 120
	while left > 0 and _director() == null:
		await wait_physics_frames(1)
		left -= 1
	var director := _director()
	assert_not_null(director, "прыгнул на агента — напрыгнул")
	if director == null:
		return
	assert_eq(director.scene().side, Takedown.Side.ABOVE, "сверху")
	await _wait_for_the_end(agent)


func test_the_director_does_not_push_the_agent_into_a_wall() -> void:
	# Агента, прижатого к стене, режиссёр ставит у стены, а не в неё (авторевью
	# M24d): сценка спереди просит 0.62–0.72 м, а до стены меньше.
	_floor()
	_wall(0.75)
	var otto := _otto_at(0.0)
	await wait_physics_frames(4)
	var agent := _agent_at(otto, 0.45, -1.0)
	var wait := 120
	while wait > 0 and not agent.takedown_ready:
		await wait_physics_frames(1)
		wait -= 1
	agent.global_position.x = 0.45
	await _press_shoot()
	assert_not_null(_director(), "сценка началась")
	await wait_seconds(0.2)
	assert_lt(agent.global_position.x, 0.75 - 0.3, "агент у стены, а не в ней")


func test_a_freed_agent_ends_the_scene_quietly() -> void:
	# Агента выбросили посреди сценки — сценка снимается, мир в своём темпе, и
	# никто не обращается к освобождённому узлу.
	_floor()
	var otto := _otto_at(0.0)
	await wait_physics_frames(4)
	var agent := _agent_at(otto, 0.7, -1.0)
	await wait_physics_frames(3)
	await _press_shoot()
	assert_not_null(_director(), "сценка началась")
	agent.free()
	await wait_physics_frames(3)
	assert_null(_director(), "сценка снята")
	assert_null(otto.takedown, "Otto отпущен")
	assert_almost_eq(Engine.time_scale, 1.0, 0.001, "мир в своём темпе")


## Толчок камеры на ударе (ADR-0050): кадр сдвинут и накренён, а за
## [constant SideCamera.KICK_FADE] настоящего времени встаёт на место.
func test_the_camera_kicks_on_the_blow_and_settles() -> void:
	var target := Node3D.new()
	add_child_autofree(target)
	var camera := SideCamera.new()
	add_child_autofree(camera)
	camera.follow(target)
	await get_tree().process_frame
	var calm := camera.global_position
	camera.kick(1.0)
	var moved := false
	var rolled := false
	for _frame: int in 6:
		await get_tree().process_frame
		moved = moved or not camera.global_position.is_equal_approx(calm)
		rolled = rolled or not is_zero_approx(camera.rotation.z)
	assert_true(moved and rolled, "кадр толкнуло и накренило")
	await get_tree().create_timer(SideCamera.KICK_FADE + 0.1, true, false, true).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(camera.is_kicked(), "толчок погас")
	assert_almost_eq(camera.rotation.z, 0.0, 0.0001, "крен снят")
