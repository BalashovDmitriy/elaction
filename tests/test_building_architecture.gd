extends GutTest

## Тесты архитектуры здания: крыша, силуэт и выпуск агентов.
##
## Всё, что здесь проверяется, собирается **по настоящим правилам игры**, а не по
## уменьшенным. Прежние тесты уровня строили здания на 4–8 этажей и все до одного
## выключали агентов, поэтому здание, в которое играет игрок, не проверял никто:
## 241 тест был зелёным, пока партия кончалась на крыше за полторы секунды
## (ADR-0014, «Почему это дожило до релиза»).

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

## Сколько кадров даётся геометрии и агентам, чтобы встать на места.
const SETTLE_FRAMES: int = 4

## Сколько кадров Otto стоит на крыше, ничего не делая.
##
## Именно так игрок и начинает партию: кадр появился, он ещё не взялся за
## управление. Раньше за это время он успевал потерять все три жизни.
const IDLE_FRAMES: int = 180


func before_all() -> void:
	Engine.time_scale = 4.0


func after_all() -> void:
	Engine.time_scale = 1.0
	GameState.instance().reset()


## Правила настоящие: тридцать этажей, пять документов, агенты на месте.
func _build(building_seed: int, agents: bool) -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = building_seed
	level.spawn_agents = agents
	add_child_autofree(level)
	return level


func _drop(level: GreyboxLevel) -> void:
	remove_child(level)


func _agents_in(level: GreyboxLevel) -> Array[Enemy]:
	var found: Array[Enemy] = []
	for child in level.get_children():
		var agent := child as Enemy
		if agent != null and not agent.is_dead():
			found.append(agent)
	return found


## Тот самый баг, с которого началась веха: Otto стоял макушкой выше края кадра
## и уходил в прыжке на 94 px за него, а камера туда не поднималась.
func test_otto_and_his_jump_fit_in_frame_on_the_roof() -> void:
	var level := _build(1, false)
	await wait_physics_frames(SETTLE_FRAMES)

	var otto := level.otto
	var body := otto.get_node("Body") as Sprite2D
	var head := otto.global_position.y + body.offset.y
	var view := otto.camera_view()

	assert_gt(head, view.position.y, "макушка Otto ниже верхнего края кадра")
	assert_gt(head - otto.jump_height(), view.position.y, "и в верхней точке прыжка тоже")
	_drop(level)


## На крыше нет дверей, а значит и агентов. Раньше их там стояло двое, ближе
## дальности своего огня, и партия кончалась, не начавшись.
func test_the_roof_is_empty_when_the_game_starts() -> void:
	for building_seed: int in [1, 2, 3]:
		var level := _build(building_seed, true)
		await wait_physics_frames(SETTLE_FRAMES)

		var rules := level.rules
		for agent in _agents_in(level):
			assert_gt(
				rules.floor_index_near(agent.global_position.y),
				BuildingRules.ROOF,
				"сид %d: агент на крыше" % building_seed
			)
		_drop(level)


## Игрок должен успеть осмотреться. Проверка идёт бездействием нарочно: бот,
## который отстреливается, скрыл бы ровно ту беду, которую тест стережёт.
func test_otto_survives_doing_nothing_at_the_start() -> void:
	for building_seed: int in [1, 2, 3]:
		var level := _build(building_seed, true)
		await wait_physics_frames(IDLE_FRAMES)

		assert_false(level.otto.is_dead(), "сид %d: Otto погиб, не сделав хода" % building_seed)
		assert_eq(
			GameState.instance().lives,
			GameState.STARTING_LIVES,
			"сид %d: жизни уходят на старте" % building_seed
		)
		_drop(level)


## Двери выпускают агентов рядом с игроком, а не все разом. Раньше в здании
## жило 55 тел с физикой и ИИ от первого кадра до конца партии.
func test_only_the_doors_near_otto_let_agents_out() -> void:
	var level := _build(1, true)
	await wait_physics_frames(SETTLE_FRAMES)

	var agent_doors := 0
	for spot in level.plan().doors:
		if not spot.has_document:
			agent_doors += 1

	var alive := _agents_in(level).size()
	assert_gt(agent_doors, 30, "в здании и правда много агентских дверей")
	assert_lt(alive, 10, "а в кадре — единицы")
	_drop(level)


## Агент далеко внизу не нужен ни игроку, ни физике: этаж уехал из кадра.
func test_no_agent_walks_a_floor_far_from_otto() -> void:
	var level := _build(1, true)
	await wait_physics_frames(SETTLE_FRAMES)

	var rules := level.rules
	var here := rules.floor_index_near(level.otto.global_position.y)
	for agent in _agents_in(level):
		var floor_index := rules.floor_index_near(agent.global_position.y)
		assert_lt(
			absi(floor_index - here), 10, "агент на этаже %d, Otto на %d" % [floor_index, here]
		)
	_drop(level)


## Возвращение в игру — не на то же место, где убили: агент оттуда никуда не
## делся, и три жизни сгорали на одном пятачке.
func test_otto_comes_back_away_from_the_agent_that_killed_him() -> void:
	var level := _build(1, false)
	await wait_physics_frames(SETTLE_FRAMES)

	var rules := level.rules
	var floor_index := 3
	var surface := rules.floor_surface(floor_index)
	var spots := level.plan().safe_spots(rules, floor_index)
	assert_gt(spots.size(), 1, "на этаже есть из чего выбирать")

	# Агент ставится вплотную к первому свободному месту: раньше именно туда
	# Otto и возвращался, потому что оно было первым по порядку.
	var agent := preload("res://src/actors/enemy/enemy.tscn").instantiate() as Enemy
	level.add_child(agent)
	agent.global_position = Vector2(spots[0], surface)
	agent.setup(level.otto, 1.0)
	await wait_physics_frames(SETTLE_FRAMES)

	level.otto.global_position = Vector2(spots[0], surface)
	level.otto.kill()
	await wait_physics_frames(60)

	var back := level.otto.global_position.x
	assert_gt(absf(back - spots[0]), 1.0, "Otto вернулся под тот же ствол")
	_drop(level)


## Передышка после возвращения в игру: без неё вторая смерть приходит раньше,
## чем игрок успевает нажать хоть что-нибудь.
func test_otto_is_untouchable_right_after_coming_back() -> void:
	var level := _build(1, false)
	await wait_physics_frames(SETTLE_FRAMES)

	level.otto.kill()
	# Ждём ровно возвращения, а не «с запасом»: передышка короткая, и лишние
	# кадры съели бы её раньше, чем тест успел бы её проверить.
	var waited := 0
	while level.otto.is_dead() and waited < 120:
		await wait_physics_frames(1)
		waited += 1
	assert_false(level.otto.is_dead(), "Otto вернулся в игру")

	level.otto.kill()
	assert_false(level.otto.is_dead(), "и сразу второй раз его не убить")
	_drop(level)
