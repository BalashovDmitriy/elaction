extends GutTest

## Бот проходит здание целиком.
##
## Самая честная проверка уровня: собирается настоящая сцена с физикой, и Otto
## действительно спускается, забирает документы и уходит в выход. Ловит то, чего
## не видят ни раскладка, ни дымовой тест, — например, кабину, чьи остановки не
## совпадают с полами, или коврик двери, до которого не дойти.
##
## Здание маленькое и без охраны: проверяется проходимость, а не бой.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const SEEDS: Array[int] = [1, 2, 3, 4, 5]

## Потолок на прохождение, физических кадров. При 60 кадрах в секунду это минута
## игрового времени на четыре этажа — с запасом даже на ожидание кабины.
const FRAME_BUDGET: int = 900


func _rules() -> BuildingRules:
	var rules := BuildingRules.new()
	rules.floors = 4
	rules.documents = 1
	rules.shaft_span = 2
	return rules


func _build(building_seed: int) -> GreyboxLevel:
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = _rules()
	level.building_seed = building_seed
	level.spawn_agents = false
	add_child_autofree(level)
	return level


## Убирает здание из дерева сразу, не дожидаясь конца теста.
##
## [method GutTest.add_child_autofree] освобождает только после всего теста, а сиды
## перебираются внутри одного: без этого пять зданий стоят друг в друге в одном
## физическом мире. Бот жмёт действия глобально, значит идут все пять Otto разом,
## и красные двери прошлых зданий по-прежнему шлют документы в общий [GameState] —
## проверка «документы собраны» проходила бы чужим трудом. Освободит их GUT.
func _drop(level: GreyboxLevel) -> void:
	remove_child(level)


func before_all() -> void:
	# Кадров у прогона мало, поэтому игровое время идёт быстрее реального.
	Engine.time_scale = 4.0


func after_all() -> void:
	Engine.time_scale = 1.0
	# Автолоад один на весь прогон: оставленная «в игре» партия досчитывала бы
	# тревогу в чужих тестах. Возвращаем его в исходное.
	GameState.instance().reset()


func test_bot_finishes_every_building() -> void:
	for building_seed: int in SEEDS:
		GameState.instance().start_game()
		var level := _build(building_seed)
		var cleared := [false]
		level.building_cleared.connect(func() -> void: cleared[0] = true)

		var bot := OttoBot.new(level)
		var frames := 0
		while not cleared[0] and frames < FRAME_BUDGET:
			bot.step()
			await wait_physics_frames(1)
			frames += 1
		bot.release()

		var game := GameState.instance()
		assert_eq(
			game.documents_collected,
			game.documents_total,
			"сид %d: выход сработал, но документы не собраны" % building_seed
		)

		assert_true(
			cleared[0],
			(
				"сид %d: бот не прошёл за %d кадров. Этаж %d, жизней %d, мёртв: %s"
				% [
					building_seed,
					FRAME_BUDGET,
					level.rules.floor_index_near(level.otto.global_position.y),
					GameState.instance().lives,
					level.otto.is_dead()
				]
			)
		)

		_drop(level)
