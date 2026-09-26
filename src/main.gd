extends Node

## Точка входа: меню, партия и переходы между ними.
##
## Держит три вещи и связывает их: [Menu] — экраны вне игры, [Hud] — то, что
## видно в игре, и само здание. Партия живёт в [GameState], здание — нет:
## оно собирается заново на каждое и выбрасывается целиком.
##
## Корень — голый [Node], а не 2D- или 3D-узел: под ним живут и трёхмерное
## здание, и плоский интерфейс, и ни одному из них родительский трансформ
## не нужен. Пост-обработка 2D ушла вместе с ADR-0002; её 3D-наследник —
## дело вехи света (M17).
##
## Игра начинается с меню, а не со здания (DoD вехи M8b): до неё сюда попадали
## сразу в партию, потому что меню ещё не было.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
## Скрипт автолоада съёмки: имя автолоада при разборе одного файла не видно,
## а статический вопрос «идёт ли съёмка» задать надо.
const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")
## Сколько досчитанный бонус висит на кадре, прежде чем кадр уйдёт в чёрное, с:
## дочитать число.
const BONUS_HOLD: float = 0.8

var _level: GreyboxLevel = null
## Город за главным меню (ADR-0035). Живёт, пока открыто меню, а не партия.
var _stage: MenuStage = null
var _settings: GameSettings = null
var _records: Records = null
## Идёт ли партия. На экранах меню — нет, даже пока здание висит в дереве.
var _playing: bool = false
## Что удерживалось в прошлом кадре: по этому считается фронт нажатия.
var _held: Dictionary = {}
## Страница меню, какой её оставил прошлый кадр. Esc — это и «пауза», и «назад»
## меню: с настроек над паузой меню возвращает на паузу раньше, чем кадр доходит
## до [method _process], и по одной текущей странице то же нажатие тут же снимало
## бы паузу (авторевью M22b).
var _page_before: Menu.Page = Menu.Page.MAIN
## Затемнение между зданиями (ADR-0038, решение 4).
var _curtain: FadeCurtain = null
## Идущее демо (ADR-0041) или null. Сколько главное меню простояло без нажатий и
## с какой точки пойдёт следующее демо.
var _demo: DemoRun = null
var _idle: float = 0.0
var _demo_point: int = DemoPlan.Point.ROOF
## Демо уходит в затемнение: второе нажатие его уже не кончает.
var _demo_ending: bool = false

@onready var _menu: Menu = $Menu
@onready var _hud: Hud = $Hud


func _ready() -> void:
	# Первое, что игра говорит в лог: версия и платформа. Без них сообщение
	# «у меня не работает» не с чем соотнести, а сборка без этой строки
	# считается незапустившейся — tools/smoke.py смотрит именно на неё.
	print(Release.banner())

	# Ввод паузы должен работать на паузе, иначе из неё не выйти. Само здание
	# при этом обязано замирать — см. _enter_building.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_settings = GameSettings.load_from()
	_settings.apply()
	# Виньетка — под HUD и меню, над сценой (ADR-0030, решение 3).
	add_child(Vignette.new())
	_curtain = FadeCurtain.new()
	add_child(_curtain)
	_records = Records.load_from()

	_menu.settings = _settings
	_menu.records = _records
	_menu.play_pressed.connect(_start_game)
	_menu.resume_pressed.connect(_resume)
	_menu.restart_pressed.connect(_start_game)
	_menu.to_menu_pressed.connect(_open_menu)
	_menu.quit_pressed.connect(_quit)

	var game := GameState.instance()
	game.game_over.connect(_on_game_over)
	game.extra_life_awarded.connect(_on_extra_life)

	# Автосъёмка начинает сразу с партии: она водит Otto игровыми действиями,
	# а кнопки меню нажимать не умеет.
	if SCREENSHOTTER.capturing():
		_start_game()
	else:
		_open_menu()


func _process(delta: float) -> void:
	_count_idle(delta)
	if _just_pressed(&"pause"):
		# Пауза во вступлении его пропускает, а не открывает меню (ADR-0038).
		if _playing and _level != null and _level.skip_the_intro():
			pass
		elif _playing:
			_pause()
		elif _page_before == Menu.Page.PAUSE and _menu.current_page() == Menu.Page.PAUSE:
			_resume()
	_page_before = _menu.current_page()


## Любое нажатие: в меню сбрасывает отсчёт до демо, в демо — кончает его
## (ADR-0041, решение 5). Нажатие, кончившее демо, в игру и меню не проходит.
func _input(event: InputEvent) -> void:
	var pressed := (
		(event is InputEventKey and event.is_pressed() and not event.is_echo())
		or (event is InputEventJoypadButton and event.is_pressed())
		or (event is InputEventMouseButton and event.is_pressed())
	)
	if _demo != null:
		# Кадр F12 снимается и с демо: main слышит ввод раньше автолоада съёмки, и
		# нажатие, кончившее демо, до него бы уже не дошло (авторевью M24e).
		if pressed and not event.is_action(&"screenshot"):
			get_viewport().set_input_as_handled()
			_end_demo()
		return
	# Стик — тоже ход по меню: стрелками меню ходят и им (авторевью M24e).
	var stick := event as InputEventJoypadMotion
	if (
		pressed
		or event is InputEventMouseMotion
		or (stick != null and absf(stick.axis_value) > 0.5)
	):
		_idle = 0.0


## Главное меню без нажатий [constant DemoPlan.IDLE_TIME] секунд — демо. Только
## главное: на паузе, в настройках и в партии отсчёта нет.
func _count_idle(delta: float) -> void:
	var waiting := (
		_demo == null
		and not _playing
		and _menu.visible
		and _menu.current_page() == Menu.Page.MAIN
		and not SCREENSHOTTER.capturing()
	)
	if not waiting:
		_idle = 0.0
		return
	_idle += delta
	if _idle >= DemoPlan.IDLE_TIME:
		_start_demo()


## Демо (ADR-0041): здание своей солью, бот за Otto, точка — следующая по кругу.
func _start_demo() -> void:
	_idle = 0.0
	_demo_ending = false
	_drop_the_curtain()
	_drop_stage()
	_menu.close()
	_hud.visible = true
	GameState.instance().start_game(_new_salt())
	_enter_building(true)
	_demo = DemoRun.start(_level, _demo_point)
	_demo.finished.connect(_end_demo)
	_demo_point = DemoPlan.next(_demo_point)


## Конец демо: здание замирает, кадр уходит в чёрное, из чёрного — главное меню.
func _end_demo() -> void:
	if _demo == null or _demo_ending:
		return
	_demo_ending = true
	_demo.stop()
	_level.process_mode = Node.PROCESS_MODE_DISABLED
	# Сценка добивания держит свой режим PAUSABLE и под выключенным зданием шла бы
	# дальше: добивала агента со звуком, водила камеру и держала мир замедленным —
	# с ним и затемнение (авторевью M24e). Уход из дерева возвращает миру ход.
	var director := _level.otto.takedown
	if director != null:
		_level.otto.takedown = null
		director.get_parent().remove_child(director)
		director.queue_free()
	_curtain.cover(0.0, _open_menu.bind(true))


## Нажато ли действие именно в этом кадре.
##
## Своё отслеживание фронта вместо [method Input.is_action_just_pressed]: тот
## верен лишь в кадр самого нажатия, а автосценарий съёмки нажимает действия
## из своего кадра — кадр main успевает пройти раньше, и нажатие теряется.
func _just_pressed(action: StringName) -> bool:
	var pressed := Input.is_action_pressed(action)
	var was: bool = _held.get(action, false)
	_held[action] = pressed
	return pressed and not was


## Главное меню: здание выбрасывается, за меню встаёт город, музыка остаётся.
## [param from_demo] — из затемнения конца демо: оно само выведет кадр из чёрного,
## и снимать его здесь нельзя.
func _open_menu(from_demo: bool = false) -> void:
	_playing = false
	_demo = null
	_demo_ending = false
	_idle = 0.0
	_unpause()
	if from_demo:
		_hud.hide_bonus()
	else:
		_drop_the_curtain()
	# Партия останавливается, а не просто прячется: без этого таймер сирены
	# продолжал бы идти под главным меню, куда вышли с паузы.
	GameState.instance().stop_game()
	# Здание уходит вместе с Otto за дверью — глухоту двери снимает сама дверь.
	_drop_level()
	_raise_stage()
	_hud.visible = false
	_menu.show_page(Menu.Page.MAIN)
	Sounds.play_music(Sounds.MENU_THEME)


func _start_game() -> void:
	_demo = null
	_playing = true
	_unpause()
	_drop_the_curtain()
	_drop_stage()
	_menu.close()
	_hud.visible = true
	GameState.instance().start_game(_new_salt())
	# HUD перерисовывать не надо: start_game и start_building внутри здания
	# шлют все сигналы, на которые он подписан.
	_enter_building()
	# Первое здание запуска открывается из чёрного: под ним один раз греются
	# шейдеры редких эффектов, и первый выстрел не дёргает кадр (ADR-0039).
	if ShaderWarmup.run(_level):
		_curtain.reveal(ShaderWarmup.HOLD)


## Соль новой партии: случайная, не ноль — ноль значит «без соли» (ADR-0028,
## решение 6). Аргумент `-- --salt=N` задаёт её руками: так партию можно
## повторить, а кадры снять на известном здании. Автосъёмка вехи идёт без соли:
## её сценарий рассчитан на здание по номеру, и по чужой раскладке он прошёл
## бы мимо шахты.
func _new_salt() -> int:
	if SCREENSHOTTER.capturing():
		return 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--salt="):
			return argument.trim_prefix("--salt=").to_int()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(1, 0x7FFFFFFF)


func _pause() -> void:
	_playing = false
	get_tree().paused = true
	_menu.show_page(Menu.Page.PAUSE)
	Sounds.muffle_music(Sounds.MUFFLE_PAUSE, true)


func _resume() -> void:
	_playing = true
	_unpause()
	_menu.close()


## Снимает паузу, а с ней и глухую музыку паузы. Из паузы выходят не только
## «продолжить»: «заново» и «в меню» оставляли музыку глухой на всю новую
## партию (авторевью M23).
func _unpause() -> void:
	get_tree().paused = false
	Sounds.muffle_music(Sounds.MUFFLE_PAUSE, false)


func _quit() -> void:
	_settings.save_to()
	get_tree().quit()


## Собирает очередное здание. Старое выбрасывается целиком вместе с Otto:
## партия живёт в [GameState], уровень — нет. [param demo] — здание демо: замер
## качества оно не заводит (ADR-0041, решение 6).
func _enter_building(demo: bool = false) -> void:
	_drop_level()

	var game := GameState.instance()
	_level = LEVEL_SCENE.instantiate() as GreyboxLevel
	_level.rules = BuildingRules.for_building(game.building, _settings.difficulty)
	_level.building_seed = game.building_seed()
	# Режим наследуется от родителя, а он тут ALWAYS: без этой строки пауза
	# не останавливала бы ничего — игра шла бы дальше с надписью «пауза».
	_level.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_level)
	_level.car_started.connect(_on_car_started)
	_level.building_cleared.connect(_on_building_cleared)
	# HUD берёт у здания имя, цвет вывески и этаж Otto (M22).
	_hud.follow(_level)
	# Первый запуск: уровень качества выбирается замером на вступлении здания
	# (ADR-0034, решение 3). Автосъёмка вехи снимает на уровне из настроек.
	# Замер — под зданием, а не под main: здание выбросили посреди замера (новая
	# партия, выход в меню) — замер уходит с ним, не мерит меню и не пишет его
	# уровень, а следующее здание заводит свой, один (авторевью M22).
	if QualityProbe.needed(_settings) and not SCREENSHOTTER.capturing() and not demo:
		var probe := QualityProbe.new()
		_level.add_child(probe)
		probe.start(_settings)
	# Тема заводится на здание, а не на партию: после тревоги её надо вернуть,
	# а сирена снимается только сменой здания (ADR-0009).
	# Трек здания и тревоги — жребием по сиду здания (ADR-0036, решение 3).
	Sounds.play_music(
		Sounds.ALARM_THEME if game.alarm.raised else Sounds.THEME, game.building_seed()
	)


## Город за меню. Погода — жребием на каждый выход в меню: ясная ночь, туман
## или дождь с молниями.
func _raise_stage() -> void:
	if _stage != null:
		return
	_stage = MenuStage.new()
	_stage.name = "Stage"
	add_child(_stage)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_stage.build(rng.randi())


func _drop_stage() -> void:
	if _stage == null:
		return
	remove_child(_stage)
	_stage.queue_free()
	_stage = null


func _drop_level() -> void:
	if _level == null:
		return
	# Сначала из дерева, потом в утиль: [method Node.queue_free] убирает узел
	# лишь в конце кадра, и старое здание досматривало бы его рядом с новым —
	# два Otto, две кабины и вся геометрия дважды в одном физическом мире.
	remove_child(_level)
	_level.queue_free()
	_level = null


## Otto сел в машину, она тронулась: бонус здания набегает поверх сцены.
func _on_car_started() -> void:
	Sounds.play(Sounds.BUILDING_BONUS)
	_hud.count_bonus(Arcade.building_bonus(GameState.instance().building))


## Машина ушла из кадра: бонус досчитывается на плашке, висит [constant
## BONUS_HOLD], кадр уходит в чёрное, и только под чёрным бонус идёт в счёт,
## раунд — дальше и собирается следующее здание.
##
## Раньше счёт и раунд менялись в тот же кадр, что уходила машина: старое здание
## ещё на экране, а HUD уже пишет «РАУНД 2» и счёт с бонусом, пока плашка
## бонуса только набегает.
func _on_building_cleared() -> void:
	# Демо, доехавшее до выхода, кончается, а не собирает следующее здание.
	if _demo != null:
		_end_demo()
		return
	if not _hud.bonus_shown():
		_on_car_started()
	# Здание меняется под чёрным, из твина затемнения, — не из шага физики
	# уходящего здания, в котором пришёл сигнал.
	_curtain.cover(_hud.bonus_time_left() + BONUS_HOLD, _next_building)


## Под чёрным: бонус в счёт, следующий раунд и его здание.
func _next_building() -> void:
	_hud.hide_bonus()
	GameState.instance().finish_building()
	_enter_building()


## Бросает смену здания на полпути: меню, новая партия, конец игры.
func _drop_the_curtain() -> void:
	_curtain.cancel()
	_hud.hide_bonus()


func _on_extra_life() -> void:
	Sounds.play(Sounds.EXTRA_LIFE)


func _on_game_over() -> void:
	# Демо рекордов не пишет и конца партии не показывает (ADR-0041, решение 6).
	if _demo != null:
		_end_demo()
		return
	_playing = false
	_drop_the_curtain()
	# Джингл приглушает трек на время звучания, и трек конца партии входит
	# из-под него (ADR-0036, решение 6).
	Sounds.play(Sounds.GAME_OVER)
	Sounds.play_music(Sounds.GAME_OVER_THEME)

	var score := GameState.instance().score
	var place := _records.submit(score)
	if place >= 0:
		_records.save_to()
	_menu.remember(score, place)

	# Партия окончена — здание замирает, как на паузе. Иначе агенты продолжают
	# приходить и стрелять под надписью «игра окончена».
	get_tree().paused = true
	_menu.show_page(Menu.Page.GAME_OVER)
