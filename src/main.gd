extends Node2D

## Точка входа: меню, партия и переходы между ними.
##
## Держит три вещи и связывает их: [Menu] — экраны вне игры, [Hud] — то, что
## видно в игре, и само здание. Партия живёт в [GameState], здание — нет:
## оно собирается заново на каждое и выбрасывается целиком.
##
## Игра начинается с меню, а не со здания (DoD вехи M8b): до неё сюда попадали
## сразу в партию, потому что меню ещё не было.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
## Скрипт автолоада съёмки: имя автолоада при разборе одного файла не видно,
## а статический вопрос «идёт ли съёмка» задать надо.
const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")

var _level: GreyboxLevel = null
var _settings: GameSettings = null
var _records: Records = null
## Идёт ли партия. На экранах меню — нет, даже пока здание висит в дереве.
var _playing: bool = false
## Что удерживалось в прошлом кадре: по этому считается фронт нажатия.
var _held: Dictionary = {}

@onready var _menu: Menu = $Menu
@onready var _hud: Hud = $Hud


func _ready() -> void:
	# Ввод паузы должен работать на паузе, иначе из неё не выйти. Само здание
	# при этом обязано замирать — см. _enter_building.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_settings = GameSettings.load_from()
	_settings.apply()
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


func _process(_delta: float) -> void:
	if not _just_pressed(&"pause"):
		return
	if _playing:
		_pause()
	elif _menu.current_page() == Menu.Page.PAUSE:
		_resume()


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


## Главное меню: здание выбрасывается, музыка остаётся.
func _open_menu() -> void:
	_playing = false
	get_tree().paused = false
	_drop_level()
	_hud.visible = false
	_menu.show_page(Menu.Page.MAIN)
	Sounds.play_music(Sounds.THEME)


func _start_game() -> void:
	_playing = true
	get_tree().paused = false
	_menu.close()
	_hud.visible = true
	GameState.instance().start_game()
	_enter_building()
	_hud.refresh()


func _pause() -> void:
	_playing = false
	get_tree().paused = true
	_menu.show_page(Menu.Page.PAUSE)


func _resume() -> void:
	_playing = true
	get_tree().paused = false
	_menu.close()


func _quit() -> void:
	_settings.save_to()
	get_tree().quit()


## Собирает очередное здание. Старое выбрасывается целиком вместе с Otto:
## партия живёт в [GameState], уровень — нет.
func _enter_building() -> void:
	_drop_level()

	var game := GameState.instance()
	_level = LEVEL_SCENE.instantiate() as GreyboxLevel
	_level.rules = BuildingRules.for_building(game.building)
	_level.building_seed = game.building
	# Режим наследуется от родителя, а он тут ALWAYS: без этой строки пауза
	# не останавливала бы ничего — игра шла бы дальше с надписью «пауза».
	_level.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_level)
	_level.building_cleared.connect(_on_building_cleared)
	# Тема заводится на здание, а не на партию: после тревоги её надо вернуть,
	# а сирена снимается только сменой здания (ADR-0009).
	Sounds.play_music(Sounds.ALARM_THEME if game.alarm.raised else Sounds.THEME)


func _drop_level() -> void:
	if _level == null:
		return
	# Сначала из дерева, потом в утиль: [method Node.queue_free] убирает узел
	# лишь в конце кадра, и старое здание досматривало бы его рядом с новым —
	# два Otto, две кабины и вся геометрия дважды в одном физическом мире.
	remove_child(_level)
	_level.queue_free()
	_level = null


func _on_building_cleared() -> void:
	Sounds.play(Sounds.BUILDING_BONUS)
	GameState.instance().finish_building()
	# Отложенно: сигнал приходит из зоны выхода, посреди разбора перекрытий.
	_enter_building.call_deferred()


func _on_extra_life() -> void:
	Sounds.play(Sounds.EXTRA_LIFE)


func _on_game_over() -> void:
	_playing = false
	Sounds.stop_music()
	Sounds.play(Sounds.GAME_OVER)

	var score := GameState.instance().score
	var place := _records.submit(score)
	if place >= 0:
		_records.save_to()
	_menu.remember(score, place)

	# Партия окончена — здание замирает, как на паузе. Иначе агенты продолжают
	# приходить и стрелять под надписью «игра окончена».
	get_tree().paused = true
	_menu.show_page(Menu.Page.GAME_OVER)
