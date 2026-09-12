extends Node2D

## Точка входа и игровой цикл.
##
## Держит партию целиком: заводит здание, при сдаче начисляет бонус и собирает
## следующее, показывает счёт и ведёт паузу. Настоящее меню придёт в M8 — здесь
## только механика, чтобы не плодить UI, который будет выброшен (ADR-0009).

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

var _level: GreyboxLevel = null
var _paused: bool = false
var _game_over: bool = false
## Что удерживалось в прошлом кадре: по этому считается фронт нажатия.
var _held: Dictionary = {}

@onready var _debug_label: Label = %DebugLabel
@onready var _hud_label: Label = %HudLabel


func _ready() -> void:
	# Ввод паузы должен работать на паузе, иначе из неё не выйти. Само здание
	# при этом обязано замирать — см. _enter_building.
	process_mode = Node.PROCESS_MODE_ALWAYS

	var game := GameState.instance()
	game.score_changed.connect(_on_score_changed)
	game.documents_changed.connect(_on_documents_changed)
	game.lives_changed.connect(_on_lives_changed)
	game.building_changed.connect(_on_building_changed)
	game.alarm_raised.connect(_on_alarm_raised)
	game.game_over.connect(_on_game_over)

	game.start_game()
	_enter_building()
	_render_hud()


func _process(_delta: float) -> void:
	_read_commands()
	_debug_label.text = _debug_text()


## Ввод партии читается опросом, а не событиями: так его видит и автосценарий
## съёмки, который нажимает действия через [Input], не порождая событий.
func _read_commands() -> void:
	# Фронты считаются все сразу: иначе ранний выход оставил бы остальные
	# действия «свежими» и они сработали бы позже сами собой.
	var pause_pressed := _just_pressed(&"pause")
	var restart_pressed := _just_pressed(&"restart")
	var quit_pressed := _just_pressed(&"quit_game")

	if pause_pressed:
		_toggle_pause()

	# Заново и выход — только из паузы или с экрана «игра окончена». Проверяется
	# после переключения, а не вместо него: нажатые в один кадр Esc и R должны
	# сработать оба, а не потеряться вместе с фронтом.
	if not _paused and not _game_over:
		return
	if restart_pressed:
		_restart()
	elif quit_pressed:
		get_tree().quit()


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


## Собирает очередное здание. Старое выбрасывается целиком вместе с Otto:
## партия живёт в [GameState], уровень — нет.
func _enter_building() -> void:
	if _level != null:
		# Сначала из дерева, потом в утиль: [method Node.queue_free] убирает узел
		# лишь в конце кадра, и старое здание досматривало бы его рядом с новым —
		# два Otto, две кабины и вся геометрия дважды в одном физическом мире.
		remove_child(_level)
		_level.queue_free()

	var game := GameState.instance()
	_level = LEVEL_SCENE.instantiate() as GreyboxLevel
	_level.rules = BuildingRules.for_building(game.building)
	_level.building_seed = game.building
	# Режим наследуется от родителя, а он тут ALWAYS: без этой строки пауза
	# не останавливала бы ничего — игра шла бы дальше с надписью «пауза».
	_level.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_level)
	_level.building_cleared.connect(_on_building_cleared)


func _on_building_cleared() -> void:
	GameState.instance().finish_building()
	# Отложенно: сигнал приходит из зоны выхода, посреди разбора перекрытий.
	_enter_building.call_deferred()


func _toggle_pause() -> void:
	if _game_over:
		return
	_paused = not _paused
	get_tree().paused = _paused
	_render_hud()


func _restart() -> void:
	_paused = false
	_game_over = false
	get_tree().paused = false
	GameState.instance().start_game()
	_enter_building()
	_render_hud()


func _on_score_changed(_value: int) -> void:
	_render_hud()


func _on_documents_changed(_collected: int, _total: int) -> void:
	_render_hud()


func _on_lives_changed(_value: int) -> void:
	_render_hud()


func _on_building_changed(_number: int) -> void:
	_render_hud()


func _on_alarm_raised() -> void:
	_render_hud()


func _on_game_over() -> void:
	_game_over = true
	# Партия окончена — здание замирает, как на паузе. Иначе агенты продолжают
	# приходить и стрелять под надписью «игра окончена». Снимает это только рестарт.
	get_tree().paused = true
	_render_hud()


func _render_hud() -> void:
	var game := GameState.instance()
	var text := (
		"здание: %d\nочки: %d\nжизни: %d\nдокументы: %d / %d"
		% [game.building, game.score, game.lives, game.documents_collected, game.documents_total]
	)
	if game.alarm.raised:
		text += "\nТРЕВОГА"
	if _game_over:
		text += "\nигра окончена\nR — заново, Q — выход"
	elif _paused:
		text += "\nпауза\nEsc — продолжить\nR — заново, Q — выход"
	_hud_label.text = text


## Сколько осталось до сирены. Только для отладки: в оригинале таймер игроку
## не показывают, и в HUD ему делать нечего.
func _alarm_countdown() -> String:
	var alarm := GameState.instance().alarm
	return "сработала" if alarm.raised else "%.0f с" % alarm.time_left()


func _debug_text() -> String:
	if _level == null:
		return ""

	var otto := _level.otto
	var motion := otto.motion()
	return (
		(
			"состояние: %s\nскорость: %.0f / %.0f\nна полу: %s\n"
			+ "в кабине: %s\nпауза: %s\nдо тревоги: %s\nFPS: %d"
		)
		% [
			OttoStateMachine.state_name(otto.current_state()),
			motion.x,
			motion.y,
			"да" if otto.is_grounded() else "нет",
			"да" if otto.is_riding() else "нет",
			"да" if get_tree().paused else "нет",
			_alarm_countdown(),
			Engine.get_frames_per_second(),
		]
	)
