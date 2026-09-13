extends GutTest

## Тесты выбора позы актёра.
##
## Проверяется правило, а не отдельная поза: **каждое** состояние машины
## состояний обязано попадать в нарисованную позу. Иначе новое состояние
## однажды покажет розовый квадрат заглушки — и покажет его игроку, а не тесту.


func _every_state() -> Array[OttoStateMachine.State]:
	var states: Array[OttoStateMachine.State] = []
	for value: int in OttoStateMachine.State.values():
		states.append(value as OttoStateMachine.State)
	return states


func test_every_state_of_otto_has_a_pose() -> void:
	for state: OttoStateMachine.State in _every_state():
		var pose := ActorPose.of_otto(state, false, false, false, 0.0)
		assert_true(
			SpriteTextures.OTTO_POSES.has(pose),
			"состояние %s показывается позой %s" % [OttoStateMachine.state_name(state), pose]
		)


func test_every_pose_of_otto_is_reachable() -> void:
	# Обратная проверка: нарисованное должно быть кому показать. Иначе ассеты
	# копятся в репозитории мёртвым грузом, а веха считает их работой.
	var shown: Array[String] = []
	for state: OttoStateMachine.State in _every_state():
		for crushed: bool in [false, true]:
			for falling: bool in [false, true]:
				for shooting: bool in [false, true]:
					for phase: int in ActorPose.WALK_FRAMES:
						var pose := ActorPose.of_otto(
							state, crushed, falling, shooting, float(phase)
						)
						if not shown.has(pose):
							shown.append(pose)

	for pose: String in SpriteTextures.OTTO_POSES:
		assert_true(shown.has(pose), "поза %s кому-то нужна" % pose)


func test_every_pose_of_the_agent_is_reachable() -> void:
	var shown: Array[String] = []
	for dead: bool in [false, true]:
		for walking: bool in [false, true]:
			for crushed: bool in [false, true]:
				for falling: bool in [false, true]:
					for shooting: bool in [false, true]:
						for phase: int in ActorPose.WALK_FRAMES:
							var pose := ActorPose.of_agent(
								dead, walking, crushed, falling, shooting, float(phase)
							)
							if not shown.has(pose):
								shown.append(pose)

	for pose: String in SpriteTextures.AGENT_POSES:
		assert_true(shown.has(pose), "поза %s кому-то нужна" % pose)
	for pose: String in shown:
		assert_true(SpriteTextures.AGENT_POSES.has(pose), "поза %s нарисована" % pose)


func test_death_tells_how_it_happened() -> void:
	# Раздавленный показан своей картинкой — это и есть находка сверки перед
	# вехой (ADR-0011, пункт 12).
	var dead := OttoStateMachine.State.DEAD
	assert_eq(ActorPose.of_otto(dead, false, true, false, 0.0), "dead_0", "падает")
	assert_eq(ActorPose.of_otto(dead, false, false, false, 0.0), "dead_1", "лежит")
	assert_eq(ActorPose.of_otto(dead, true, true, false, 0.0), "crushed", "раздавлен")


func test_the_dead_do_not_shoot() -> void:
	var pose := ActorPose.of_otto(OttoStateMachine.State.DEAD, false, false, true, 0.0)
	assert_eq(pose, "dead_1", "смерть важнее выстрела")


func test_walking_cycles_three_frames() -> void:
	var frames: Array[String] = []
	for step: int in 6:
		frames.append(ActorPose.walk_frame(float(step) * 0.6))
	# Фаза растёт дробно, кадр меняется на целых: цикл обязан замыкаться.
	assert_eq(ActorPose.walk_frame(0.0), "walk_0")
	assert_eq(ActorPose.walk_frame(2.9), "walk_2")
	assert_eq(ActorPose.walk_frame(3.0), "walk_0", "цикл замыкается")
	assert_gt(frames.size(), 0)


func test_a_broken_phase_does_not_break_the_frame() -> void:
	# Фаза приходит из накопителя времени, и отрицательной ей быть незачем —
	# но кадр всё равно обязан остаться кадром, а не «walk_-1».
	assert_eq(ActorPose.walk_frame(-1.0), "walk_0")
