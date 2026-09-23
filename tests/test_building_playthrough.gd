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
## M11 (ADR-0016, пункты 7 и 8). Бой меряется числом смертей, а не тем, дожил
## ли бот на трёх жизнях, — жизни ему не ограничены.
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

## Потолок на настоящее здание, **шагов петли бота** — тех самых, что считает
## цикл ниже. Один шаг — два физических кадра, это стережёт
## [method test_a_tick_is_two_physics_frames].
##
## Замер `tools/playthrough.gd` на пяти сидах, 2026-09-22: **1992–3176 шагов**,
## все пять проходят с пятью документами из пяти. Потолок — вдвое от худшего
## сида, округлённо.
##
## Мерить надо в тех же единицах, в каких считает тест. Прежний комментарий
## обещал «около 5500 кадров» — число из инструмента, который тогда ходил одним
## кадром на шаг, тогда как тест ходил двумя. Разошедшиеся единицы и стоили
## вехе трёх коммитов разбора.
const TALL_BUDGET: int = 7000

## Сиды настоящего здания с охраной. Это самый дорогой прогон в проекте: к
## тридцати этажам добавляется бой, и каждая дуэль — это ещё секунды.
const GUARDED_SEEDS: Array[int] = [1, 2, 3]

## Потолок на здание с охраной, шагов петли бота. Тот же, что и без неё: бой
## добавляет к прогону десятки шагов, а не тысячи — дуэль решается за секунду.
## Замер `tools/playthrough.gd --agents` на трёх сидах, 2026-09-22:
## **2756–3176 шагов** против 1992–3176 без боя.
##
## Вдвое больше худшего сида, но не больше: этот прогон — самый дорогой
## в проекте, и провалившийся сид не должен жечь минуты CI, прежде чем сказать
## об этом.
const GUARDED_BUDGET: int = 7000

## Сколько жизней выдаётся боту в прогоне с боем. Не три, а столько, чтобы
## партия дошла до конца при любой мыслимой неудаче: мерой служит число
## смертей, а не факт «дожил» (ADR-0016, пункт 8).
const ENDLESS_LIVES: int = 99

## Во сколько смертей бою позволено обойтись боту на одном здании.
##
## Замер 2026-09-23, после боя по ROM (ADR-0027), навык 0 — первое здание на
## лёгком уровне: **0, 0, 0** на сидах 1–3 и 0, 1, 0 на сидах 4–6
## (`tools/playthrough.gd --agents --endless`). До M18d было 5, 2 и 1: агентов
## было восемь, и стреляли они с шести метров без замаха злости.
##
## Шкала по навыку (`--skill=N`, сиды 1–3): 3 — 1, 3, 5; 6 — 39, 33, 15;
## 10 — 9, 19, 11. Бот проходит здание на любом; пик на шести — свойство бота:
## там агенты уже быстры, но стоят, а на десяти три выстрела из четырёх лёжа,
## и от такой пули бот прыгает лучше, чем выигрывает дуэль.
##
## Поэтому порог с запасом, а не впритык к худшему: подгонять его под
## неустойчивое число — значит закрепить в проверке шум. Ловит он просадку
## в разы, а не на единицу, и этого хватает: за единицами следят напечатанные
## числа каждого сида, они видны и на зелёном прогоне.
##
## Число это — о сложности игры, и правится оно замером, а не подгонкой под
## зелёный тест (ADR-0016). Выросло — значит бой стал злее, и решать надо,
## хотели мы этого или нет.
const DEATHS_ALLOWED: int = 3

## Сколько шагов боту даётся на то, чтобы хоть как-то продвинуться, прежде чем
## прогон признаётся зациклившимся.
##
## Законная причина стоять на месте у бота одна — ждать кабину, и она ограничена
## оборотом самой длинной шахты: четырнадцать этажей, тринадцать пролётов, по
## 2 с хода и [member ElevatorCar.floor_pause] стоянки — около 91 с в оба конца,
## то есть примерно 2730 шагов. Порог взят чуть выше и всё равно вдвое ниже
## бюджета прогона.
##
## Нужен он не ради скорости, хотя и ради неё тоже. На M18a зациклившийся сид
## выжигал весь бюджет и сообщал «не уложился за N кадров» — формулировка,
## которая увела разбор в сторону бюджета на три коммита, тогда как бот стоял
## на одном этаже с 2900-го шага. Сторож говорит «застрял там-то, решал то-то»,
## и это ровно те два факта, по которым причина нашлась.
const STALL_LIMIT: int = 3000


## Сторож простоя: следит, что бот продвигается, и обрывает зациклившийся прогон.
##
## Продвижением считается любой рост меры, которую передаёт прогон, — этаж
## глубже прежнего, собранный документ, потраченная жизнь. Ожидание кабины
## продвижением не считается, поэтому порог и взят по обороту шахты.
class _Watchdog:
	extends RefCounted

	## Сработал ли сторож: прогон оборван как зациклившийся.
	var tripped: bool = false

	var _best: int = -1
	var _idle: int = 0

	## Принимает меру продвижения и говорит, пора ли обрывать прогон.
	func stalled(depth: int, done: int) -> bool:
		var measure := depth * 100 + done
		if measure > _best:
			_best = measure
			_idle = 0
			return false
		_idle += 1
		tripped = _idle > STALL_LIMIT
		return tripped

	## Чем именно бот занят в месте, где встал. Решение бота здесь важнее
	## координат: по «жмёт [] на 21-м этаже» причина не видна, а по «ждёт кабину
	## шахты x=6.6, чтобы уехать на 27-й» — видна сразу.
	func report(level: GreyboxLevel, bot: OttoBot, depth: int) -> String:
		var at := WorldSpace.to_plane(level.otto.global_position)
		return (
			"бот зациклился: %d шагов без продвижения, этаж %d, Otto %s, решение: %s"
			% [_idle, depth, at, bot.decision()]
		)


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


## Шаг петли управления ботом: **два физических кадра, и это нарочно**.
##
## [method GutTest.wait_physics_frames] ждёт, пока счётчик станет *больше*
## запрошенного ([code]addons/gut/awaiter.gd[/code]), поэтому
## `wait_physics_frames(1)` пропускает два кадра, а не один. На M13 это заметили
## и оставили как правило: бот — самая грубая петля управления, какая случится
## с игрой, и допуск в мире не должен быть меньше пути за два кадра под
## [member Engine.time_scale] (`docs/testing.md`, пункт 4). Тем правилом поймали
## кабину, которая замирала в 24 единицах от этажа.
##
## Менять на один кадр нельзя — это отменит правило. Менять на два кадра
## в одном месте и на один в другом нельзя тем более: на M18a тест и
## [code]tools/playthrough.gd[/code] разошлись именно так, и сид 2 «не проходил
## здание» в тесте, проходя в инструменте за 6377 кадров. Поломку успели списать
## сперва на длину маршрута по графу, потом на баланс боя. Инструмент и тест
## обязаны водить Otto одинаково, иначе они меряют разные игры.
func _tick() -> void:
	await wait_physics_frames(1)


## Шаг петли бота длится два физических кадра — на этом стоят и бюджеты выше,
## и правило M13 про допуски (`docs/testing.md`, пункт 4).
##
## Проверка дешёвая, а стережёт дорогое: единица, в которой считают бюджеты,
## задана поведением чужого кода — [method GutTest.wait_physics_frames] ждёт,
## пока счётчик станет *больше* запрошенного. Обновление GUT может это
## поменять молча, и тогда бюджеты станут значить вдвое больше или меньше,
## а бот — вдвое отзывчивее или грубее. На M18a такое расхождение между
## тестом и инструментом замера обошлось в три коммита разбора.
func test_a_tick_is_two_physics_frames() -> void:
	# Считает движок, а не свой обработчик [signal SceneTree.physics_frame]:
	# обработчики идут в порядке подключения, аваитер GUT подключён раньше и
	# будит корутину прямо внутри эмиссии — до того, как подсчёт успеет
	# сработать. Такой счётчик занижает ответ ровно на один кадр.
	var before := Engine.get_physics_frames()
	await _tick()
	assert_eq(int(Engine.get_physics_frames() - before), 2, "шаг петли бота — два физических кадра")


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
			await _tick()
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
func test_bot_finishes_the_real_building_seed_1() -> void:
	await _play_tall(TALL_SEEDS[0])


func test_bot_finishes_the_real_building_seed_2() -> void:
	await _play_tall(TALL_SEEDS[1])


## Один прогон настоящего здания без охраны.
##
## Сид приходит снаружи, а не перебирается циклом: прогон стоит полторы минуты,
## и раскидать сиды по процессам можно, только если у каждого свой тест
## (`tools/run_tests.py`, раскладка по шардам).
func _play_tall(building_seed: int) -> void:
	GameState.instance().start_game()
	var level := _build(building_seed, BuildingRules.new())
	var cleared := [false]
	level.building_cleared.connect(func() -> void: cleared[0] = true)

	var bot := OttoBot.new(level)
	var game := GameState.instance()
	var frames := 0
	var deepest := 0
	var watchdog := _Watchdog.new()
	while not cleared[0] and frames < TALL_BUDGET:
		bot.step()
		await _tick()
		frames += 1
		deepest = maxi(
			deepest, level.rules.floor_index_near(WorldSpace.to_plane(level.otto.global_position).y)
		)
		if watchdog.stalled(deepest, game.documents_collected):
			break
	bot.release()

	assert_false(
		watchdog.tripped, "сид %d: %s" % [building_seed, watchdog.report(level, bot, deepest)]
	)
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


## DoD вехи M11: здание с агентами проходимо, и бой стоит боту не дороже
## [constant DEATHS_ALLOWED] смертей.
##
## Самый дорогой тест проекта и единственный, который меряет баланс боя, а не
## геометрию (ADR-0016, пункты 7 и 8).
##
## **Жизни боту не ограничены нарочно.** Прежняя проверка — «прошёл на трёх
## жизнях» — стояла на обрыве: сид с одной смертью и сид с тремя давали один
## ответ, а между ними вся разница сложности. Живой игрок всё равно играет
## иначе, чем бот, и переносить на него ровно три жизни бессмысленно. Поэтому
## прогон всегда доходит до конца, а мерой служит **число смертей** — величина
## непрерывная, по которой видно направление, а не только факт. На неё же
## лягут будущие уровни сложности.
##
## Бот играет хуже человека — он не отступает, не пользуется дверями как укрытием
## и не считает наперёд. Поэтому это нижняя планка играбельности: здание, которое
## он не проходит, живому игроку тем более не по зубам.
func test_bot_survives_the_real_building_with_agents_seed_1() -> void:
	await _play_guarded(GUARDED_SEEDS[0])


func test_bot_survives_the_real_building_with_agents_seed_2() -> void:
	await _play_guarded(GUARDED_SEEDS[1])


func test_bot_survives_the_real_building_with_agents_seed_3() -> void:
	await _play_guarded(GUARDED_SEEDS[2])


## Один прогон здания с охраной. Сид приходит снаружи по той же причине, что
## и у [method _play_tall]: тремя сидами подряд это 328 с — сорок процентов
## всего набора и его пол, ниже которого не опускается никакая раскладка.
func _play_guarded(building_seed: int) -> void:
	GameState.instance().start_game()
	var level := _build(building_seed, BuildingRules.new(), true)
	var cleared := [false]
	level.building_cleared.connect(func() -> void: cleared[0] = true)

	var bot := OttoBot.new(level)
	var game := GameState.instance()
	# Жизни выдаются разом и с запасом, а не подливаются на нуле: подливание
	# меняло бы ход партии в самый острый её момент, и замер мерил бы уже
	# другую игру. На нуле уровень вообще не назначает возвращение в игру,
	# и Otto остался бы лежать.
	game.lives = ENDLESS_LIVES
	game.lives_changed.emit(game.lives)
	var frames := 0
	var deepest := 0
	var deaths := 0
	var was_dead := false
	var watchdog := _Watchdog.new()
	while not cleared[0] and frames < GUARDED_BUDGET and game.lives > 0:
		bot.step()
		await _tick()
		frames += 1
		deepest = maxi(
			deepest, level.rules.floor_index_near(WorldSpace.to_plane(level.otto.global_position).y)
		)
		if level.otto.is_dead() and not was_dead:
			deaths += 1
		was_dead = level.otto.is_dead()
		# Смерть тоже считается движением: воскресший Otto начинает заново
		# и стоять на месте ему уже не дают.
		if watchdog.stalled(deepest, game.documents_collected + deaths):
			break
	bot.release()

	assert_false(
		watchdog.tripped, "сид %d: %s" % [building_seed, watchdog.report(level, bot, deepest)]
	)

	# Числа печатаются всегда, а не только на провале: по ним видно, куда
	# ползёт сложность от вехи к вехе, — а это и есть то, ради чего прогон
	# с боем держат. Зелёный тест без чисел рассказал бы только, что порог
	# ещё не перейдён.
	gut.p(
		(
			"сид %d: смертей %d, шагов %d, документы %d/%d"
			% [building_seed, deaths, frames, game.documents_collected, game.documents_total]
		)
	)

	assert_true(
		cleared[0],
		(
			"сид %d: бой не пройден за %d шагов. Этаж %d из %d, смертей %d"
			% [building_seed, frames, deepest, level.rules.floors - 1, deaths]
		)
	)
	assert_eq(
		game.documents_collected,
		game.documents_total,
		"сид %d: документы собраны не все" % building_seed
	)
	assert_lte(
		deaths,
		DEATHS_ALLOWED,
		"сид %d: бой стоил %d смертей при пороге %d" % [building_seed, deaths, DEATHS_ALLOWED]
	)
	_drop(level)
