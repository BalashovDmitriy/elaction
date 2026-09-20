extends GutTest

## Бот проходит здание целиком.
##
## Самая честная проверка уровня: собирается настоящая сцена с физикой, и Otto
## действительно спускается, забирает документы и уходит в выход. Ловит то, чего
## не видят ни раскладка, ни дымовой тест, — например, кабину, чьи остановки не
## совпадают с полами, или коврик двери, до которого не дойти.
##
## Зданий три вида: маленькое без охраны, настоящее без охраны и настоящее
## с агентами. Первые два проверяют проходимость, третий — бой: это DoD вехи
## M11 (ADR-0016, пункт 7).
##
## Маленькое ловит вырожденные раскладки и стоит копейки, поэтому сидов у него
## много. Настоящее — то самое, в которое играет игрок: пока его не гонял никто,
## здание собиралось с крышей в 20 px просвета, и этого не видел ни один тест
## (ADR-0014, пункт 5).

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const SEEDS: Array[int] = [1, 2, 3, 4, 5]

## Сиды настоящего здания. Их меньше: каждое — это тридцать этажей и пять
## документов, то есть полторы минуты игрового времени на прогон.
const TALL_SEEDS: Array[int] = [1, 2]

## Потолок на прохождение, физических кадров. При 60 кадрах в секунду это минута
## игрового времени на четыре этажа — с запасом даже на ожидание кабины.
const FRAME_BUDGET: int = 900

## Потолок на настоящее здание. Прогон занимает около 5500 кадров, остальное —
## запас на ожидание кабин.
const TALL_BUDGET: int = 12000

## Сиды настоящего здания с охраной. Это самый дорогой прогон в проекте: к
## тридцати этажам добавляется бой, и каждая дуэль — это ещё секунды.
const GUARDED_SEEDS: Array[int] = [1, 2, 3]

## Потолок на здание с охраной. Тот же, что и без неё: бой добавляет к прогону
## сотни кадров, а не тысячи — дуэль решается за секунду.
##
## Вдвое больше, чем уходит на самом деле (5000–5600 кадров на сид), но не
## больше: этот прогон — самый дорогой в проекте, и провалившийся сид не должен
## жечь минуты CI, прежде чем сказать об этом.
const GUARDED_BUDGET: int = 12000


func _rules() -> BuildingRules:
	var rules := BuildingRules.new()
	rules.floors = 4
	rules.documents = 1
	rules.shaft_span = 2
	return rules


func _build(building_seed: int, rules: BuildingRules = null, agents: bool = false) -> GreyboxLevel:
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = rules if rules != null else _rules()
	level.building_seed = building_seed
	level.spawn_agents = agents
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
					level.rules.floor_index_near(WorldSpace.to_plane(level.otto.global_position).y),
					GameState.instance().lives,
					level.otto.is_dead()
				]
			)
		)

		_drop(level)


## Бот проходит то самое здание, в которое играет игрок: тридцать этажей, пять
## документов, крыша сверху и ступенчатый силуэт.
##
## Здание на четыре этажа не ловит ничего из этого: у него одна полоса шахт,
## один документ и ширина, которая не меняется.
func test_bot_finishes_the_real_building() -> void:
	for building_seed: int in TALL_SEEDS:
		GameState.instance().start_game()
		var level := _build(building_seed, BuildingRules.new())
		var cleared := [false]
		level.building_cleared.connect(func() -> void: cleared[0] = true)

		var bot := OttoBot.new(level)
		var frames := 0
		var deepest := 0
		while not cleared[0] and frames < TALL_BUDGET:
			bot.step()
			await wait_physics_frames(1)
			frames += 1
			deepest = maxi(
				deepest,
				level.rules.floor_index_near(WorldSpace.to_plane(level.otto.global_position).y)
			)
		bot.release()

		var game := GameState.instance()
		assert_true(
			cleared[0],
			(
				"сид %d: бот не прошёл за %d кадров, ниже всего этаж %d из %d"
				% [building_seed, TALL_BUDGET, deepest, level.rules.floors - 1]
			)
		)
		assert_eq(
			game.documents_collected,
			game.documents_total,
			"сид %d: документы собраны не все" % building_seed
		)
		_drop(level)


## DoD вехи M11: бот проходит настоящее здание с агентами, не исчерпав трёх жизней.
##
## Самый дорогой тест проекта и единственный, который меряет баланс боя, а не
## геометрию. Числа боя подбирались под него: пока он красный, веха не закрыта
## (ADR-0016, пункт 7).
##
## Бот играет хуже человека — он не отступает, не пользуется дверями как укрытием
## и не считает наперёд. Поэтому это нижняя планка играбельности: здание, которое
## он не проходит, живому игроку тем более не по зубам.
func test_bot_survives_the_real_building_with_agents() -> void:
	for building_seed: int in GUARDED_SEEDS:
		GameState.instance().start_game()
		var level := _build(building_seed, BuildingRules.new(), true)
		var cleared := [false]
		level.building_cleared.connect(func() -> void: cleared[0] = true)

		var bot := OttoBot.new(level)
		var game := GameState.instance()
		var frames := 0
		var deepest := 0
		var deaths := 0
		var was_dead := false
		while not cleared[0] and frames < GUARDED_BUDGET and game.lives > 0:
			bot.step()
			await wait_physics_frames(1)
			frames += 1
			deepest = maxi(
				deepest,
				level.rules.floor_index_near(WorldSpace.to_plane(level.otto.global_position).y)
			)
			if level.otto.is_dead() and not was_dead:
				deaths += 1
			was_dead = level.otto.is_dead()
		bot.release()

		assert_true(
			cleared[0],
			(
				"сид %d: бой не пройден за %d кадров. Этаж %d из %d, жизней %d, смертей %d"
				% [building_seed, frames, deepest, level.rules.floors - 1, game.lives, deaths]
			)
		)
		assert_eq(
			game.documents_collected,
			game.documents_total,
			"сид %d: документы собраны не все" % building_seed
		)
		_drop(level)
