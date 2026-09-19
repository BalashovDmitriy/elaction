class_name Hud
extends CanvasLayer

## Игровой HUD: только то, без чего не сыграть.
##
## Современный, а не аркадный (ADR-0012, пункт 8): очки и документы слева
## сверху, жизни справа, место в здании — справа снизу, тревога — по центру.
## Строки сверху с рекордом и жизнями-иконками нет: это язык автомата, а игра
## ремейк — интерфейс на той же стороне, что картинка и звук.
##
## Отладочный оверлей из M1 сюда не переехал: ему место за клавишей, а не в кадре.

## Как часто мигает надпись тревоги, раз в секунду.
const ALARM_BLINKS: float = 1.6

## Насколько тускнеет надпись тревоги в нижней точке мигания.
const ALARM_DIM: float = 0.35

@onready var _score: Label = %Score
@onready var _documents: Label = %Documents
@onready var _lives: Label = %Lives
@onready var _place: Label = %Place
@onready var _alarm: Label = %Alarm


func _ready() -> void:
	var game := GameState.instance()
	game.score_changed.connect(_on_score_changed)
	game.documents_changed.connect(_on_documents_changed)
	game.lives_changed.connect(_on_lives_changed)
	game.building_changed.connect(_on_building_changed)
	game.alarm_raised.connect(_on_alarm_raised)
	refresh()


func _process(_delta: float) -> void:
	if not _alarm.visible:
		return
	# Мигание считается от времени, а не накопителем: HUD живёт и на паузе,
	# а под паузой delta не приходит вовсе.
	var phase := sin(Time.get_ticks_msec() / 1000.0 * ALARM_BLINKS * TAU) * 0.5 + 0.5
	_alarm.modulate.a = ALARM_DIM + (1.0 - ALARM_DIM) * phase


## Перерисовывает всё разом. Зовётся на входе в здание и при смене состояния:
## сигналов у партии много, а полей мало, и разбирать их по одному незачем.
func refresh() -> void:
	var game := GameState.instance()
	_score.text = "%s %s" % [tr("UI_SCORE"), format_score(game.score)]
	_documents.text = (
		"%s %d / %d" % [tr("UI_DOCUMENTS"), game.documents_collected, game.documents_total]
	)
	_lives.text = "%s %d" % [tr("UI_LIVES"), game.lives]
	# «Раунд», а не «здание»: так счётчик называется и в аркаде, и в порте
	# (ADR-0017, решение 5).
	_place.text = "%s %d" % [tr("UI_ROUND"), game.building]
	_alarm.text = tr("UI_ALARM")
	_alarm.visible = game.alarm.raised


## Счёт с пробелами по три цифры: 12 400 читается с одного взгляда, 12400 — нет.
static func format_score(score: int) -> String:
	var digits := str(absi(score))
	var grouped := ""
	for index: int in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0:
			grouped += " "
		grouped += digits[index]
	return ("-" if score < 0 else "") + grouped


func _on_score_changed(_value: int) -> void:
	refresh()


func _on_documents_changed(_collected: int, _total: int) -> void:
	refresh()


func _on_lives_changed(_value: int) -> void:
	refresh()


func _on_building_changed(_number: int) -> void:
	refresh()


func _on_alarm_raised() -> void:
	refresh()
