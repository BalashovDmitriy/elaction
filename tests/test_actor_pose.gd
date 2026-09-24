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
			ActorPose.OTTO_POSES.has(pose),
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

	for pose: String in ActorPose.OTTO_POSES:
		assert_true(shown.has(pose), "поза %s кому-то нужна" % pose)
	# И наоборот — как у агента: показать можно только нарисованное. Без этого
	# опечатка в [ActorPose] дошла бы до игрока розовым квадратом заглушки.
	for pose: String in shown:
		assert_true(ActorPose.OTTO_POSES.has(pose), "поза %s нарисована" % pose)


func test_every_pose_of_the_agent_is_reachable() -> void:
	var shown: Array[String] = []
	for dead: bool in [false, true]:
		for walking: bool in [false, true]:
			for crushed: bool in [false, true]:
				for falling: bool in [false, true]:
					for shooting: bool in [false, true]:
						for phase: int in ActorPose.WALK_FRAMES:
							# Стойки перебираются наравне с остальным: с M11 агент
							# уклоняется, и у колена с положением лёжа свои позы.
							for stance: EnemyBrain.Stance in _stances():
								var pose := ActorPose.of_agent(
									dead, walking, crushed, falling, shooting, float(phase), stance
								)
								if not shown.has(pose):
									shown.append(pose)

	for pose: String in ActorPose.AGENT_POSES:
		assert_true(shown.has(pose), "поза %s кому-то нужна" % pose)
	for pose: String in shown:
		assert_true(ActorPose.AGENT_POSES.has(pose), "поза %s нарисована" % pose)


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
	# Фаза растёт дробно, кадр меняется на целых: цикл обязан замыкаться.
	assert_eq(ActorPose.walk_frame(0.0), "walk_0")
	assert_eq(ActorPose.walk_frame(0.9), "walk_0", "дробная часть кадр не меняет")
	assert_eq(ActorPose.walk_frame(1.0), "walk_1")
	assert_eq(ActorPose.walk_frame(2.9), "walk_2")
	assert_eq(ActorPose.walk_frame(3.0), "walk_0", "цикл замыкается")


func test_the_phase_never_skips_a_frame_of_the_cycle() -> void:
	# Длину цикла знает один WALK_FRAMES, и продвижение фазы обязано считать её
	# так же, как выбор кадра. Разойдутся — последний кадр ходьбы не покажется
	# никогда, и заметить это на глаз нельзя: шаг просто станет короче.
	var phase := 0.0
	var seen: Array[String] = []
	for _step: int in 120:
		phase = ActorPose.advance(phase, 1.0 / 60.0)
		assert_between(phase, 0.0, float(ActorPose.WALK_FRAMES), "фаза не уходит из цикла")
		var frame := ActorPose.walk_frame(phase)
		if not seen.has(frame):
			seen.append(frame)
	assert_eq(seen.size(), ActorPose.WALK_FRAMES, "за две секунды показаны все кадры")


func test_a_broken_phase_does_not_break_the_frame() -> void:
	# Фаза приходит из накопителя времени, и отрицательной ей быть незачем —
	# но кадр всё равно обязан остаться кадром, а не «walk_-1».
	assert_eq(ActorPose.walk_frame(-1.0), "walk_0")


## Все стойки агента. Перечислены руками: enum в GDScript не перебирается
## значениями, а список из трёх строк честнее, чем обход Stance.keys().
func _stances() -> Array[EnemyBrain.Stance]:
	return [EnemyBrain.Stance.STAND, EnemyBrain.Stance.KNEEL, EnemyBrain.Stance.PRONE]


func test_every_way_of_dying_counts_as_down() -> void:
	# Промах здесь оставит труп стоять — у того, кто когда-нибудь спросит.
	for crushed: bool in [true, false]:
		for falling: bool in [true, false]:
			var pose := ActorPose.of_otto(OttoStateMachine.State.DEAD, crushed, falling, false, 0.0)
			assert_true(ActorPose.is_down(pose), "%s — это лежащий" % pose)


func test_an_agent_dodging_prone_counts_as_down() -> void:
	var pose := ActorPose.of_agent(false, false, false, false, false, 0.0, EnemyBrain.Stance.PRONE)
	assert_true(ActorPose.is_down(pose))


func test_the_living_and_upright_are_not_down() -> void:
	for pose: String in [
		"idle", "walk_0", "walk_1", "walk_2", "jump", "kick", "shoot", ActorPose.CROUCH
	]:
		assert_false(ActorPose.is_down(pose), "%s — это не лежащий" % pose)


func test_the_knee_and_the_crouch_are_one_pose() -> void:
	# Агент на колене и присевший Otto показываются одинаково — так было и в 2D.
	var kneeling := ActorPose.of_agent(
		false, false, false, false, false, 0.0, EnemyBrain.Stance.KNEEL
	)
	var crouching := ActorPose.of_otto(OttoStateMachine.State.CROUCH, false, false, false, 0.0)
	assert_eq(kneeling, crouching)
	assert_eq(kneeling, ActorPose.CROUCH)
