class_name Sounds
extends RefCounted

## Звуки игры: имена событий и загрузка файлов.
##
## Устроено как [SpriteTextures] у картинок: имя — это имя файла, список один
## на проект, и тест ходит по нему в обе стороны — у каждого имени есть файл,
## у каждого файла есть имя. Иначе синтезированный, но никому не нужный звук
## копится в репозитории, а забытое событие молчит (ADR-0012, пункт 1).

const DIR := "res://assets/audio/"

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const MASTER_BUS := "Master"

## События игры. Константы, а не строки по месту: опечатка в строке — это
## тишина, которую не видно ни в логе, ни в кадре.
const STEP := "step"
const SHOT := "shot"
const HIT := "hit"
const KICK := "kick"
const LAMP_BREAK := "lamp_break"
const LAMP_CRASH := "lamp_crash"
const ELEVATOR_DING := "elevator_ding"
const ELEVATOR_HUM := "elevator_hum"
const ESCALATOR_HUM := "escalator_hum"
const DOOR_OPEN := "door_open"
const DOOR_CLOSE := "door_close"
const DOCUMENT := "document"
const OTTO_DEATH := "otto_death"
const AGENT_DEATH := "agent_death"
const CAR_AWAY := "car_away"
const BUILDING_BONUS := "building_bonus"
const GAME_OVER := "game_over"

## Музыка. Тема своя, а не из оригинала (ADR-0012, пункт 2); мотив тревоги
## звучит вместо неё, пока сирена не снята.
const THEME := "theme"
const ALARM_THEME := "alarm_theme"

const EFFECTS: PackedStringArray = [
	STEP,
	SHOT,
	HIT,
	KICK,
	LAMP_BREAK,
	LAMP_CRASH,
	ELEVATOR_DING,
	ELEVATOR_HUM,
	ESCALATOR_HUM,
	DOOR_OPEN,
	DOOR_CLOSE,
	DOCUMENT,
	OTTO_DEATH,
	AGENT_DEATH,
	CAR_AWAY,
	BUILDING_BONUS,
	GAME_OVER,
]
const MUSIC: PackedStringArray = [THEME, ALARM_THEME]

## Звуки, которые звучат петлёй, пока длится то, что их вызвало.
const LOOPED: PackedStringArray = [ELEVATOR_HUM, ESCALATOR_HUM, THEME, ALARM_THEME]

static var _cache: Dictionary = {}


## Все имена разом: по ним ходит тест.
static func names() -> PackedStringArray:
	var all := PackedStringArray(EFFECTS)
	all.append_array(MUSIC)
	return all


## Путь к файлу звука.
static func path_of(name: String) -> String:
	return DIR + name + ".wav"


## Поток звука или null, если файла нет. Кэш общий: один и тот же выстрел
## звучит в партии тысячи раз.
static func stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name] as AudioStream

	var path := path_of(name)
	var loaded: AudioStream = null
	if ResourceLoader.exists(path):
		loaded = load(path) as AudioStream
		_set_looping(loaded, LOOPED.has(name))
	else:
		push_error("Нет звука %s — запустите tools/render_audio.py" % name)

	_cache[name] = loaded
	return loaded


## Зацикливание задаётся здесь, а не в настройках импорта.
##
## Настройки импорта — вторая копия того же списка, и разъезжаются они молча:
## тема, у которой в `.import` сброшен цикл, играет пять секунд и замолкает
## до конца партии. Список [constant LOOPED] один, и он же проверяется тестом.
static func _set_looping(stream: AudioStream, looping: bool) -> void:
	var wav := stream as AudioStreamWAV
	if wav == null:
		return
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if looping else AudioStreamWAV.LOOP_DISABLED
	if looping:
		wav.loop_begin = 0
		wav.loop_end = wav.data.size() / _bytes_per_frame(wav)


## Сколько байт занимает один кадр звука: от этого зависит, где конец петли.
static func _bytes_per_frame(wav: AudioStreamWAV) -> int:
	var channels := 2 if wav.stereo else 1
	var width := 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1
	return maxi(channels * width, 1)


## Проигрывает эффект. Тихо ничего не делает, если автолоада ещё нет:
## тесты поднимают классы и без дерева сцены.
static func play(name: String) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.play(name)


## Включает музыку, если она ещё не та же самая.
static func play_music(name: String) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.play_music(name)


static func stop_music() -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.stop_music()


## Сбрасывает кэш. Нужен тестам: они грузят звуки в своём порядке.
static func forget() -> void:
	_cache.clear()
