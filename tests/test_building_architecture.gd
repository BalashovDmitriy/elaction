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

## Сколько кадров ждать конца вступления: спуск по тросу занимает меньше секунды.
const LANDING_FRAMES: int = 180

## Сколько кадров дверям даётся на то, чтобы выпустить всех, кого они могут.
##
## Дверь выпускает следующего не раньше чем через свою паузу, а уровень отдаёт
## не больше одного за кадр: чтобы толпа собралась целиком, нужны секунды, а не
## кадр-другой.
const CROWD_FRAMES: int = 240

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
func _build(building_seed: int, agents: bool, rules: BuildingRules = null) -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = rules if rules != null else BuildingRules.new()
	level.building_seed = building_seed
	level.spawn_agents = agents
	add_child_autofree(level)
	return level


func _drop(level: GreyboxLevel) -> void:
	remove_child(level)


## Ждёт, пока двери выпустят хоть кого-нибудь.
##
## Дверь сперва открывается и только потом отдаёт агента (ADR-0020, решение 2),
## и на телеграф уходит заметно больше, чем кадр-другой. Смотреть агентов сразу
## после сборки значит не смотреть ничего: ровно так два теста здесь и стали
## пустыми в первом же прогоне M14.
func _wait_for_agents(level: GreyboxLevel) -> Array[Enemy]:
	for _frame: int in CROWD_FRAMES:
		await wait_physics_frames(1)
		var found := _agents_in(level)
		if not found.is_empty():
			return found
	return []


## Живые агенты здания. Перебор детей — дело самого уровня ([method
## GreyboxLevel.agents]), здесь остаётся только отсев мёртвых.
##
## И тех, кого уже убрали за кромку кадра: [method Node.queue_free] освобождает
## узел лишь в конце кадра, а угрозой он перестал быть сразу — без этого отсева
## потолок живых считался бы с лишним телом и тест падал бы на ровном месте.
func _agents_in(level: GreyboxLevel) -> Array[Enemy]:
	var found: Array[Enemy] = []
	for agent in level.agents():
		if not agent.is_dead() and not agent.is_queued_for_deletion():
			found.append(agent)
	return found


## Тот самый баг, с которого началась веха: Otto стоял макушкой выше края кадра
## и уходил в прыжке на 94 px за него, а камера туда не поднималась.
func test_otto_and_his_jump_fit_in_frame_on_the_roof() -> void:
	var level := _build(1, false)
	await _wait_for_the_landing(level)

	var otto := level.otto
	# Макушка — рост стоячей формы над ногами. Кадр и макушка меряются в
	# плоскости правил, где «выше» — это меньший Y.
	var standing := otto.get_node("StandingShape") as CollisionShape3D
	var height := (standing.shape as BoxShape3D).size.y
	var head := WorldSpace.to_plane(otto.global_position).y - height
	var view := otto.camera_view()

	assert_gt(head, view.position.y, "макушка Otto ниже верхнего края кадра")
	assert_gt(head - otto.jump_height(), view.position.y, "и в верхней точке прыжка тоже")
	_drop(level)


## На крыше нет дверей, а значит и агентов. Раньше их там стояло двое, ближе
## дальности своего огня, и партия кончалась, не начавшись.
func test_the_roof_is_empty_when_the_game_starts() -> void:
	for building_seed: int in [1, 2, 3]:
		var level := _build(building_seed, true)
		var agents := await _wait_for_agents(level)
		assert_false(agents.is_empty(), "сид %d: двери никого не выпустили" % building_seed)

		var rules := level.rules
		for agent in agents:
			assert_gt(
				_floor_of(rules, agent),
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
	var agents := await _wait_for_agents(level)
	assert_false(agents.is_empty(), "двери никого не выпустили")

	var rules := level.rules
	var here := _floor_of(rules, level.otto)
	for agent in agents:
		var floor_index := _floor_of(rules, agent)
		assert_lt(
			absi(floor_index - here), 10, "агент на этаже %d, Otto на %d" % [floor_index, here]
		)
	_drop(level)


## Возвращение в игру — не на то же место, где убили: агент оттуда никуда не
## делся, и три жизни сгорали на одном пятачке.
##
## Агент стоит неподвижно ([code]walk_speed[/code] = 0), и это не удобство, а
## условие проверки. Ходящий успевает уйти за те 60 кадров, пока Otto лежит, и
## «вернулся не туда, где убили» начинает зависеть от того, куда он ушёл: на
## M18b кусок этажа стал короче, агент развернулся раньше — и проверка,
## поставленная в M10 на настоящую поломку, стала мерить совпадение.
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
	agent.walk_speed = 0.0
	level.add_child(agent)
	agent.global_position = WorldSpace.to_scene(Vector2(spots[0], surface))
	agent.setup(level.otto, 1.0)
	await wait_physics_frames(SETTLE_FRAMES)

	level.otto.global_position = WorldSpace.to_scene(Vector2(spots[0], surface))
	level.otto.kill()
	await wait_physics_frames(60)

	var back := WorldSpace.to_plane(level.otto.global_position).x
	assert_gt(absf(back - spots[0]), 0.01, "Otto вернулся под тот же ствол")
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


## Внизу здания тесно: там на каждом этаже по две двери, а полоса выпуска — девять
## этажей. Без потолка живых набиралось до восемнадцати, и нижние этажи выходили
## тиром, где стреляют со всех сторон разом (ADR-0016, пункт 6).
func test_no_more_live_agents_than_the_rules_allow() -> void:
	for building_seed: int in [1, 2, 3]:
		var level := _build(building_seed, true)
		var rules := level.rules
		_stand_on(level, rules.floors - 2)

		var most := 0
		for _frame in CROWD_FRAMES:
			await wait_physics_frames(1)
			most = maxi(most, _agents_in(level).size())

		assert_gt(most, 0, "сид %d: двери на нижних этажах никого не выпустили" % building_seed)
		# Потолок ROM — три, а поздно в здании четыре (ADR-0027, решение 2).
		var ceiling := rules.agents_at_once(GameState.instance().alarm.elapsed())
		assert_lte(
			most,
			ceiling,
			"сид %d: живых агентов разом %d при потолке %d" % [building_seed, most, ceiling]
		)
		_drop(level)


## Правила доезжают из здания до самого агента.
##
## Проверяется переключателем «не стрелять»: с ним агент не стреляет вовсе, и
## это видно по пулям и по тому, что Otto жив.
func test_agents_take_their_combat_numbers_from_the_rules() -> void:
	var toothless := BuildingRules.new()
	toothless.agents_hold_fire = true
	var harmless := _build(1, true, toothless)
	_stand_on(harmless, harmless.rules.floors - 2)
	var quiet := await _worst_moment(harmless)
	assert_gt(_agents_in(harmless).size(), 0, "агенты вышли")
	assert_eq(quiet, 0, "но им велено не стрелять")
	assert_false(harmless.otto.is_dead(), "и Otto цел, простояв среди них столбом")
	_drop(harmless)

	var armed := _build(1, true)
	_stand_on(armed, armed.rules.floors - 2)
	var shots := await _worst_moment(armed)
	assert_gt(shots, 0, "без запрета те же агенты стреляют")
	_drop(armed)


## Ставит Otto посреди этажа: туда, где стоял бы игрок, а не в проём.
func _stand_on(level: GreyboxLevel, index: int) -> void:
	var rules := level.rules
	level.otto.global_position = WorldSpace.to_scene(
		Vector2(level.plan().safe_x(rules, index), rules.floor_surface(index))
	)


## Этаж, на котором стоит узел, по правилам здания.
func _floor_of(rules: BuildingRules, node: Node3D) -> int:
	return rules.floor_index_near(WorldSpace.to_plane(node.global_position).y)


## Сколько вражеских пуль оказалось в воздухе разом за [constant CROWD_FRAMES].
##
## Не «сколько их сейчас»: пуля живёт доли секунды, и один замер попал бы
## в промежуток между выстрелами.
func _worst_moment(level: GreyboxLevel) -> int:
	var most := 0
	for _frame in CROWD_FRAMES:
		await wait_physics_frames(1)
		var flying := 0
		for node in level.get_tree().get_nodes_in_group(Bullet.GROUP):
			var bullet := node as Bullet
			if bullet != null and bullet.collision_mask == Bullet.FROM_ENEMY:
				flying += 1
		most = maxi(most, flying)
	return most


## Ждёт, пока Otto съедет по тросу на крышу.
##
## Здание с M12 начинается вступлением: Otto приезжает сверху, и первые полсекунды
## он не на полу и не слушается ввода (ADR-0017, решение 4). Ждать его надо по
## состоянию, а не выдержкой: под [member Engine.time_scale] выдержка врёт.
func _wait_for_the_landing(level: GreyboxLevel) -> void:
	var left := LANDING_FRAMES
	while not level.otto.is_grounded() and left > 0:
		await wait_physics_frames(1)
		left -= 1
	assert_true(level.otto.is_grounded(), "Otto съехал по тросу и встал на крышу")
