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

## Сколько кадров даётся на дуэль. Пуля летит 220 px/с, агент стоит в паре сотен
## пикселей — это доля секунды; остальное запас на замах и на промах.
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
	level.otto.global_position = Vector2(pair.x, surface)
	var agent := ENEMY_SCENE.instantiate() as Enemy
	level.add_child(agent)
	agent.global_position = Vector2(pair.y, surface)
	agent.apply_rules(rules)
	agent.setup(level.otto, -1.0)
	await wait_physics_frames(SETTLE_FRAMES)

	var bot := OttoBot.new(level)
	var frames := 0
	while not agent.is_dead() and frames < DUEL_FRAMES:
		bot.step()
		await wait_physics_frames(1)
		frames += 1
	bot.release()

	assert_true(agent.is_dead(), "бот не достал агента в %.0f px за %d кадров" % [gap, DUEL_FRAMES])
	assert_false(level.otto.is_dead(), "и сам при этом остался жив")
	remove_child(level)


## Два ближайших друг к другу места этажа: слева и справа.
func _closest_pair(spots: PackedFloat64Array) -> Vector2:
	var best := Vector2(spots[0], spots[1])
	for index in range(1, spots.size() - 1):
		if spots[index + 1] - spots[index] < best.y - best.x:
			best = Vector2(spots[index], spots[index + 1])
	return best
