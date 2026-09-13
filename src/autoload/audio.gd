class_name AudioDirector
extends Node

## Звук игры: один автолоад на всё.
##
## Узлы не заводят себе источников: их пришлось бы держать в каждой сцене, а
## выстрел, переживший смерть стрелявшего, обрывался бы вместе с ним. Здесь
## пул источников на шине SFX и один на музыку (ADR-0012, пункт 7).
##
## Имена звуков — константы [Sounds]; тест следит, чтобы у каждой был файл,
## а у каждого файла — константа.
##
## Обращаются к нему через [method Sounds.play] и соседей: имя автолоада
## отличается от [code]class_name[/code], как и у [GameState], — иначе
## разбор одного скрипта в отрыве от проекта не находит идентификатор.

## Сколько эффектов может звучать разом. Больше дюжины в кадре — это уже каша,
## как и с источниками света: у оригинала на всё было четыре чипа по три голоса.
const VOICES: int = 12

static var _instance: AudioDirector = null

## Громкости шин, 0..1. Настройки их и будут менять в M8b.
var _levels: Dictionary = {}

var _sfx: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer = null
var _next: int = 0
var _playing_music: String = ""


## Звук партии. До входа автолоада в дерево — null.
static func instance() -> AudioDirector:
	return _instance


## Источники заводятся здесь, а не в [method Node._ready], вместе с публикацией
## экземпляра: между входом в дерево и готовностью [method instance] отдавал бы
## директора с пустым пулом, и первый же [method play] уронил бы кадр обращением
## за нулевым голосом.
func _enter_tree() -> void:
	if _instance != null:
		return
	_instance = self

	# Автолоад живёт и на паузе: иначе музыка обрывалась бы на каждом Esc.
	process_mode = Node.PROCESS_MODE_ALWAYS

	for index: int in VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = Sounds.SFX_BUS
		add_child(player)
		_sfx.append(player)

	_music = AudioStreamPlayer.new()
	_music.bus = Sounds.MUSIC_BUS
	add_child(_music)


## Как у [GameState]: без этого статическая ссылка переживала бы сам узел, и
## [method Sounds.play] звал бы освобождённый объект.
func _exit_tree() -> void:
	if _instance == self:
		_instance = null


## Проигрывает эффект. Голоса разбираются по кругу: самый старый затирается,
## и одновременная пальба не съедает звук шагов насовсем.
func play(name: String) -> void:
	var stream := Sounds.stream(name)
	if stream == null:
		return

	var player := _sfx[_next]
	_next = (_next + 1) % _sfx.size()
	player.stream = stream
	player.play()


## Включает музыку. Та же самая не перезапускается: иначе тема начиналась бы
## заново на каждом здании.
func play_music(name: String) -> void:
	if _playing_music == name and _music.playing:
		return

	var stream := Sounds.stream(name)
	if stream == null:
		return

	_playing_music = name
	_music.stream = stream
	_music.play()


func stop_music() -> void:
	_playing_music = ""
	_music.stop()


## Что играет прямо сейчас. Нужно тестам и отладке.
func music_name() -> String:
	return _playing_music if _music.playing else ""


## Громкость шины, 0..1. Ноль — тишина, единица — как записано.
func set_level(bus: String, level: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	# Уровень запоминается только применённый: иначе [method level_of] отдавал бы
	# настройкам громкость шины, которой нет.
	var value := clampf(level, 0.0, 1.0)
	_levels[bus] = value
	# Тишина — это не «минус восемьдесят децибел», а выключенная шина: на малых
	# громкостях логарифм уходит в минус бесконечность и трещит по дороге.
	AudioServer.set_bus_mute(index, is_zero_approx(value))
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.0001)))


func level_of(bus: String) -> float:
	return float(_levels.get(bus, 1.0))
