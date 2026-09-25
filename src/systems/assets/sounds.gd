class_name Sounds
extends RefCounted

## Звуки игры: имена событий и загрузка файлов.
##
## Устроено как у прежних спрайтов: имя — это имя файла, список один
## на проект, и тест ходит по нему в обе стороны — у каждого имени есть файл,
## у каждого файла есть имя. Иначе ненужный звук копится в репозитории, а
## забытое событие молчит. Файлы — из свободных библиотек, авторы в
## `assets/audio/credits.json` (ADR-0036, решение 1).

const DIR := "res://assets/audio/"

## Расширения, в которых может лежать звук. Короткое и частое — в WAV,
## длинное — в OGG; какое у какого, решает сборка ассетов, а игра берёт то,
## что нашла. Второй список тех же имён разъехался бы с первым молча.
const EXTENSIONS: PackedStringArray = [".wav", ".ogg"]

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const MASTER_BUS := "Master"
## Фон — дочерняя шина эффектов: громкость эффектов в настройках ведёт и его
## (ADR-0036, решение 5).
const AMBIENCE_BUS := "Ambience"

## Причины, по которым музыка звучит из-за стены.
const MUFFLE_PAUSE := "pause"
const MUFFLE_DOOR := "door"

## События игры. Константы, а не строки по месту: опечатка в строке — это
## тишина, которую не видно ни в логе, ни в кадре. Шаг — свой у каждого пола.
const STEP_CARPET := "step_carpet"
const STEP_CONCRETE := "step_concrete"
const SHOT := "shot"
const KICK := "kick"
const LAMP_BREAK := "lamp_break"
const LAMP_CRASH := "lamp_crash"
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
## Джингл смерти Otto: звучит поверх самой смерти.
const DEATH_JINGLE := "death_jingle"

## Меню (ADR-0035, решение 5): переход по пунктам, выбор и возврат.
const UI_MOVE := "ui_move"
const UI_SELECT := "ui_select"
const UI_BACK := "ui_back"

## Музыка: свой трек на экран (ADR-0036, решение 3). Трек тревоги звучит вместо
## темы здания, пока сирена не снята.
const THEME := "theme"
const ALARM_THEME := "alarm_theme"
const MENU_THEME := "menu_theme"
const GAME_OVER_THEME := "game_over_theme"

## Фон: улица, дождь и ветер снаружи; на этажах — дождь за стеклом и тишина
## коридора; гром к молниям; гул шахты и неон вывески — на своём месте.
const CITY := "city"
const RAIN := "rain"
const WIND := "wind"
const RAIN_WINDOW := "rain_window"
const ROOM_TONE := "room_tone"
const THUNDER_NEAR := "thunder_near"
const THUNDER_FAR := "thunder_far"
const SHAFT_HUM := "shaft_hum"
const NEON_BUZZ := "neon_buzz"

const EFFECTS: PackedStringArray = [
	STEP_CARPET,
	STEP_CONCRETE,
	SHOT,
	KICK,
	LAMP_BREAK,
	LAMP_CRASH,
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
	DEATH_JINGLE,
	UI_MOVE,
	UI_SELECT,
	UI_BACK,
]
const MUSIC: PackedStringArray = [THEME, ALARM_THEME, MENU_THEME, GAME_OVER_THEME]
const AMBIENCE: PackedStringArray = [
	CITY, RAIN, WIND, RAIN_WINDOW, ROOM_TONE, THUNDER_NEAR, THUNDER_FAR, SHAFT_HUM, NEON_BUZZ
]

## Джинглы: на время звучания приглушают трек (ADR-0036, решение 6).
const JINGLES: PackedStringArray = [DOCUMENT, EXTRA_LIFE, BUILDING_BONUS, GAME_OVER, DEATH_JINGLE]

## Звуки, которые звучат петлёй, пока длится то, что их вызвало. Трек конца
## партии не зациклен: он доигрывает под экраном рекорда и молкнет.
const LOOPED: PackedStringArray = [
	ELEVATOR_HUM,
	ESCALATOR_HUM,
	THEME,
	ALARM_THEME,
	MENU_THEME,
	CITY,
	RAIN,
	WIND,
	RAIN_WINDOW,
	ROOM_TONE,
	SHAFT_HUM,
	NEON_BUZZ,
]

## Больше стольких вариантов одного имени не бывает: дальше тест не ищет.
const MAX_VARIANTS: int = 9

static var _cache: Dictionary = {}


## Все имена разом: по ним ходит тест.
static func names() -> PackedStringArray:
	var all := PackedStringArray(EFFECTS)
	all.append_array(MUSIC)
	all.append_array(AMBIENCE)
	return all


## Файлы вариантов звука по порядку: `имя`, `имя.2`, `имя.3`… Счёт идёт до
## первого пропуска — вариант за пропуском игра бы не нашла.
static func variant_paths(name: String) -> PackedStringArray:
	var paths := PackedStringArray()
	for index: int in MAX_VARIANTS:
		var path := _existing(variant_stem(name, index))
		if path.is_empty():
			break
		paths.append(path)
	return paths


## Имя файла варианта без расширения.
static func variant_stem(name: String, index: int) -> String:
	return name if index == 0 else "%s.%d" % [name, index + 1]


## Все места, где мог бы лежать файл с именем [param stem]. Нужны тесту: он
## следит, чтобы вариант лежал ровно в одном файле, а не в WAV и OGG разом.
static func candidates(stem: String) -> PackedStringArray:
	var paths := PackedStringArray()
	for extension: String in EXTENSIONS:
		paths.append(DIR + stem + extension)
	return paths


static func _existing(stem: String) -> String:
	for path: String in candidates(stem):
		if ResourceLoader.exists(path):
			return path
	return ""


## Поток звука или null, если файла нет. Кэш общий: один и тот же выстрел
## звучит в партии тысячи раз. Вариантов несколько — поток сам тянет жребий на
## каждое звучание: шаги подряд не звучат одним файлом.
static func stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name] as AudioStream

	var streams := variants(name)
	var loaded: AudioStream = null
	if streams.is_empty():
		push_error("Нет звука %s — запустите tools/build_audio.py" % name)
	elif streams.size() == 1:
		loaded = streams[0]
	else:
		var shuffle := AudioStreamRandomizer.new()
		shuffle.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
		shuffle.random_pitch = 1.0
		shuffle.random_volume_offset_db = 0.0
		for each: AudioStream in streams:
			shuffle.add_stream(-1, each)
		loaded = shuffle

	_cache[name] = loaded
	return loaded


## Вариант номер [param pick] по кругу — для музыки и фона, которые выбираются
## жребием по зданию, а не на каждое звучание (ADR-0036).
static func variant(name: String, pick: int) -> AudioStream:
	var streams := variants(name)
	if streams.is_empty():
		return stream(name)
	return streams[posmod(pick, streams.size())]


## Все варианты звука, загруженные и с петлёй по [constant LOOPED].
static func variants(name: String) -> Array[AudioStream]:
	var key := name + "#variants"
	if _cache.has(key):
		return _cache[key] as Array[AudioStream]
	var streams: Array[AudioStream] = []
	for path: String in variant_paths(name):
		var loaded := load(path) as AudioStream
		if loaded != null:
			_set_looping(loaded, LOOPED.has(name))
			streams.append(loaded)
	_cache[key] = streams
	return streams


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


## Включает музыку, если она ещё не та же самая. [param pick] — какой из
## вариантов трека: здание берёт его по своему сиду.
static func play_music(name: String, pick: int = 0) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.play_music(name, pick)


static func stop_music() -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.stop_music()


## Музыка из-за стены: за красной дверью и на паузе.
static func muffle_music(reason: String, on: bool) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.muffle_music(reason, on)


## Погода вокруг: по ней директор выбирает петли фона снаружи и внутри.
static func set_weather(weather: Weather.Kind) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.set_weather(weather)


## Петли фона под погоду [param weather]. Снаружи — улица и дождь или ветер;
## на этажах — тишина коридора и, в дождь, дождь за стеклом. Гром сюда не
## входит: он приходит от молний.
static func weather_loops(weather: Weather.Kind, outdoors: bool) -> PackedStringArray:
	var raining := Weather.is_raining(weather)
	if outdoors:
		return PackedStringArray([CITY, RAIN if raining else WIND])
	if raining:
		return PackedStringArray([ROOM_TONE, RAIN_WINDOW])
	return PackedStringArray([ROOM_TONE])


## Фон снаружи или из-за стекла.
static func set_outdoors(on: bool) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.set_outdoors(on)


## Гром от разряда в [param distance] метрах.
static func thunder(distance: float) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.thunder(distance)


## Ставит громкость шины, 0..1. Настройки зовут её на каждый ползунок.
static func set_level(bus: String, level: float) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.set_level(bus, level)


## Позиционный источник на узле: его слышно только рядом с ним.
##
## Нужен тому, что звучит на своём месте, а не в партии целиком: шахт в здании
## пять, и гудеть в ухо должна та, рядом с которой стоишь. Заводится здесь, а не
## в узлах: лифт и эскалатор собирали его одинаково, слово в слово.
## [param reach] — докуда слышно, м.
## [param always] — петля звучит с первого кадра и не выключается: гул шахты,
## неон. Ставится до входа в дерево: вошедший источник автозапуск уже не видит.
static func source(
	host: Node, name: String, reach: float, always: bool = false
) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream(name)
	player.bus = SFX_BUS
	player.max_distance = reach
	player.autoplay = always
	host.add_child(player)
	return player


## Держит петлю включённой или выключенной.
##
## Присваивать [member AudioStreamPlayer3D.playing] каждый кадр нельзя: сеттер
## зовёт [method AudioStreamPlayer3D.play] заново, и от двухсекундного гула
## слышно только первые три миллисекунды — вместо мотора выходит треск на
## частоте кадров (проверено: позиция воспроизведения стоит на 0.003 с).
static func keep_playing(player: AudioStreamPlayer3D, on: bool) -> void:
	if on == player.playing:
		return
	if on:
		player.play()
	else:
		player.stop()


## Сбрасывает кэш. Нужен тестам: они грузят звуки в своём порядке.
static func forget() -> void:
	_cache.clear()
