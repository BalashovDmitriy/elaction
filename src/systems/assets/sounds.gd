class_name Sounds
extends RefCounted

## Звуки игры: имена событий и загрузка файлов.
##
## Устроено как [SpriteTextures] у картинок: имя — это имя файла, список один
## на проект, и тест ходит по нему в обе стороны — у каждого имени есть файл,
## у каждого файла есть имя. Иначе синтезированный, но никому не нужный звук
## копится в репозитории, а забытое событие молчит (ADR-0012, пункт 1).

const DIR := "res://assets/audio/"

## Расширения, в которых может лежать звук. Короткое и частое пишется в WAV,
## длинное и редкое — в OGG (`tools/render_audio.py`); какое именно у какого,
## решает генератор, а игра просто берёт то, что нашла. Второй список тех же
## имён разъехался бы с первым молча.
const EXTENSIONS: PackedStringArray = [".wav", ".ogg"]

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
const EXTRA_LIFE := "extra_life"
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
	EXTRA_LIFE,
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


## Путь к файлу звука или пустая строка, если его нет.
static func path_of(name: String) -> String:
	for path: String in candidates(name):
		if ResourceLoader.exists(path):
			return path
	return ""


## Все места, где звук мог бы лежать. Нужны тесту: он следит, чтобы имя
## находилось ровно в одном файле, а не в двух сразу и не ни в одном.
static func candidates(name: String) -> PackedStringArray:
	var paths := PackedStringArray()
	for extension: String in EXTENSIONS:
		paths.append(DIR + name + extension)
	return paths


## Поток звука или null, если файла нет. Кэш общий: один и тот же выстрел
## звучит в партии тысячи раз.
static func stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name] as AudioStream

	var path := path_of(name)
	var loaded: AudioStream = null
	if path.is_empty():
		push_error("Нет звука %s — запустите tools/render_audio.py" % name)
	else:
		loaded = load(path) as AudioStream
		_set_looping(loaded, LOOPED.has(name))

	_cache[name] = loaded
	return loaded


## Зацикливание задаётся здесь, а не в настройках импорта.
##
## Настройки импорта — вторая копия того же списка, и разъезжаются они молча:
## тема, у которой в `.import` сброшен цикл, играет двадцать секунд и замолкает
## до конца партии. Список [constant LOOPED] один, и он же проверяется тестом.
static func _set_looping(stream: AudioStream, looping: bool) -> void:
	var wav := stream as AudioStreamWAV
	if wav != null:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if looping else AudioStreamWAV.LOOP_DISABLED
		if looping:
			wav.loop_begin = 0
			# Конец петли — последний кадр, а он считается из длины и частоты:
			# делить размер данных на байты кадра нельзя, формат бывает сжатым.
			wav.loop_end = int(round(wav.get_length() * float(wav.mix_rate)))
		return

	var vorbis := stream as AudioStreamOggVorbis
	if vorbis != null:
		vorbis.loop = looping
		vorbis.loop_offset = 0.0


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


## Ставит громкость шины, 0..1. Настройки зовут её на каждый ползунок.
static func set_level(bus: String, level: float) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.set_level(bus, level)


## Текущая громкость шины. Без автолоада — единица: тесты поднимают классы
## и без дерева сцены, и молчаливый ноль там сбивал бы с толку.
static func level_of(bus: String) -> float:
	var director := AudioDirector.instance()
	return director.level_of(bus) if director != null else 1.0


## Позиционный источник на узле: его слышно только рядом с ним.
##
## Нужен тому, что звучит на своём месте, а не в партии целиком: шахт в здании
## пять, и гудеть в ухо должна та, рядом с которой стоишь. Заводится здесь, а не
## в узлах: лифт и эскалатор собирали его одинаково, слово в слово.
## [param reach] — докуда слышно, px.
static func source(host: Node, name: String, reach: float) -> AudioStreamPlayer2D:
	var player := AudioStreamPlayer2D.new()
	player.stream = stream(name)
	player.bus = SFX_BUS
	player.max_distance = reach
	host.add_child(player)
	return player


## Держит петлю включённой или выключенной.
##
## Присваивать [member AudioStreamPlayer2D.playing] каждый кадр нельзя: сеттер
## зовёт [method AudioStreamPlayer2D.play] заново, и от двухсекундного гула
## слышно только первые три миллисекунды — вместо мотора выходит треск на
## частоте кадров (проверено: позиция воспроизведения стоит на 0.003 с).
static func keep_playing(player: AudioStreamPlayer2D, on: bool) -> void:
	if on == player.playing:
		return
	if on:
		player.play()
	else:
		player.stop()


## Сбрасывает кэш. Нужен тестам: они грузят звуки в своём порядке.
static func forget() -> void:
	_cache.clear()
