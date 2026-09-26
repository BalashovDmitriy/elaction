extends GutTest

## Бот умеет драться: встретив агента на своей линии, он его убивает.
##
## Тест про сам инструмент замера, а не про игру, — и всё же самый важный из
## новых. Одиночные действия, выстрел и прыжок, движок отдаёт по фронту
## нажатия: отпустить и нажать их в одном кадре мало, фронта не выйдет. Бот
## делал именно так, и всю веху M11 замеры показывали игру, в которой Otto ни
## разу не выстрелил и ни разу не прыгнул. Цифры в ADR-0016 собраны тем ботом,
## и переписаны они только после этой проверки.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")

## Сколько кадров даётся на дуэль. Пуля летит 6.6 м/с, агент стоит в паре
## метров — это доля секунды; остальное запас на замах и на промах.
const DUEL_FRAMES: int = 300

## Сколько кадров даётся зданию, чтобы встать на места.
const SETTLE_FRAMES: int = 4

## Этаж посередине здания: и не крыша, и не выход.
const FLOOR: int = 5


func before_all() -> void:
	Engine.time_scale = 4.0


func after_all() -> void:
	Engine.time_scale = 1.0
	GameState.instance().reset()


## Здание настоящее, но своих агентов оно не выпускает: в дуэли должен быть
## ровно один противник, иначе непонятно, кого бот достал.
func _build() -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = 1
	level.spawn_agents = false
	add_child_autofree(level)
	return level


func test_the_bot_shoots_the_agent_in_its_way() -> void:
	var level := _build()
	await wait_physics_frames(SETTLE_FRAMES)

	var rules := level.rules
	var spots := level.plan().safe_spots(rules, FLOOR)
	assert_gt(spots.size(), 1, "на этаже есть где стоять обоим")

	# Не первые два места, а два ближайших друг к другу: между соседними местами
	# бывает и занятое — шахта, проём эскалатора, — и первая пара расходилась бы
	# на полэтажа. С того края агент боту уже не цель, и дуэли не вышло бы вовсе.
	var pair := _closest_pair(spots)
	var gap := pair.y - pair.x
	assert_lt(gap, OttoBot.ENGAGE, "агент стоит в поле зрения бота")

	var surface := rules.floor_surface(FLOOR)
	level.otto.global_position = WorldSpace.to_scene(Vector2(pair.x, surface))
	var agent := ENEMY_SCENE.instantiate() as Enemy
	level.add_child(agent)
	agent.global_position = WorldSpace.to_scene(Vector2(pair.y, surface))
	agent.apply_rules(rules)
	agent.setup(level.otto, -1.0)
	await wait_physics_frames(SETTLE_FRAMES)

	var bot := OttoBot.new(level)
	var frames := 0
	# Два кадра на решение, как во всех прогонах ботом: это правило M13, а не
	# недосмотр. Подробно — `tests/test_building_playthrough.gd`, метод `_tick`,
	# и `docs/testing.md`, пункт 4.
	while not agent.is_dead() and frames < DUEL_FRAMES:
		bot.step()
		await wait_physics_frames(1)
		frames += 1
	bot.release()

	assert_true(agent.is_dead(), "бот не достал агента в %.2f м за %d кадров" % [gap, DUEL_FRAMES])
	assert_false(level.otto.is_dead(), "и сам при этом остался жив")
	remove_child(level)


## Бот уходит от выстрела по лучу прицела, а не по пуле (ADR-0037, решение 5):
## под высоким приседает сразу, через низкий прыгает, только когда пуля вот-вот
## придёт, — прыгнув раньше, он приземлился бы прямо на неё.
##
## Луч зажигается руками, а агент заморожен: проверяется, как бот читает луч, а
## не жребий позы выстрела.
func test_the_bot_answers_the_aiming_laser() -> void:
	var level := _build()
	await wait_physics_frames(SETTLE_FRAMES)
	var rules := level.rules
	var pair := _closest_pair(level.plan().safe_spots(rules, FLOOR))
	var surface := rules.floor_surface(FLOOR)
	level.otto.global_position = WorldSpace.to_scene(Vector2(pair.x, surface))
	# Агент стоит и не стреляет, пока тест не заморозит его: иначе он подошёл бы
	# вплотную или выстрелил бы сам.
	rules.agents_hold_fire = true
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.walk_speed = 0.0
	level.add_child(agent)
	agent.global_position = WorldSpace.to_scene(Vector2(pair.y, surface))
	agent.apply_rules(rules)
	agent.setup(level.otto, -1.0)
	await wait_physics_frames(SETTLE_FRAMES * 4)
	# Замёрзший агент луч не гасит: его зажигает тест.
	agent.process_mode = Node.PROCESS_MODE_DISABLED
	var bot := OttoBot.new(level)

	_aim(agent, Proportions.SHOT_HIGH, 1.0)
	bot.step()
	assert_true(Input.is_action_pressed(&"move_down"), "под высоким лучом — присесть")
	assert_false(Input.is_action_pressed(&"move_right"), "а не драться, повернувшись")
	bot.release()
	await wait_physics_frames(2)

	_aim(agent, Proportions.SHOT_LOW, 2.0)
	bot.step()
	assert_false(Input.is_action_pressed(&"jump"), "низкий луч, пуля не скоро — рано прыгать")
	bot.release()
	await wait_physics_frames(2)

	_aim(agent, Proportions.SHOT_LOW, 0.2)
	bot.step()
	assert_true(Input.is_action_pressed(&"jump"), "пуля вот-вот — прыжок")
	bot.release()
	remove_child(level)


## Зажигает луч агента на высоте [param height] над полом: пуля уйдёт через
## [param shot_in] секунд.
func _aim(agent: Enemy, height: float, shot_in: float) -> void:
	agent.laser.position = Vector3(-Proportions.MUZZLE, height, 0.0)
	agent.laser.shot_in = shot_in
	agent.laser.shot_speed = Arcade.agent_shot_speed(0, false)
	agent.laser.aim(-1.0)


## Агента спиной к себе бот не расстреливает, а подкрадывается и добивает сзади
## (ADR-0040): так дороже, и так он показывает добивания в демо (ADR-0041).
func test_the_bot_takes_down_an_agent_from_behind() -> void:
	var level := _build()
	await wait_physics_frames(SETTLE_FRAMES)
	var rules := level.rules
	var pair := _closest_pair(level.plan().safe_spots(rules, FLOOR))
	var surface := rules.floor_surface(FLOOR)
	level.otto.global_position = WorldSpace.to_scene(Vector2(pair.x, surface))
	rules.agents_hold_fire = true
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.walk_speed = 0.0
	level.add_child(agent)
	agent.global_position = WorldSpace.to_scene(
		Vector2(minf(pair.y, pair.x + OttoBot.TAKEDOWN_SNEAK * 0.6), surface)
	)
	agent.apply_rules(rules)
	# Спиной к Otto: смотрит от него, вправо.
	agent.setup(level.otto, 1.0)
	await wait_physics_frames(SETTLE_FRAMES * 4)
	var before := GameState.instance().score
	var bot := OttoBot.new(level)
	var frames := 0
	var took := false
	while not agent.is_dead() and frames < DUEL_FRAMES:
		bot.step()
		took = took or level.otto.takedown != null
		await wait_physics_frames(1)
		frames += 1
	bot.release()
	assert_true(took, "бот добил, а не застрелил")
	assert_true(agent.is_dead(), "агент добит")
	assert_eq(
		GameState.instance().score - before,
		Takedown.score(Takedown.Side.BACK, agent.is_in_the_dark()),
		"сзади"
	)
	remove_child(level)


## Два ближайших друг к другу места этажа: слева и справа.
func _closest_pair(spots: PackedFloat64Array) -> Vector2:
	var best := Vector2(spots[0], spots[1])
	for index in range(1, spots.size() - 1):
		if spots[index + 1] - spots[index] < best.y - best.x:
			best = Vector2(spots[index], spots[index + 1])
	return best
