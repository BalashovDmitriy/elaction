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
## Интерфейс и джинглы — мимо шины эффектов, прямо в общую: глушение коридора
## за красной дверью их не трогает — щелчок меню и джингл документа звучат не
## в коридоре. Громкость ведёт тот же ползунок эффектов ([method
## AudioDirector.set_level]).
const INTERFACE_BUS := "Interface"

## Причины, по которым музыка звучит из-за стены.
const MUFFLE_PAUSE := "pause"
const MUFFLE_DOOR := "door"

## События игры. Константы, а не строки по месту: опечатка в строке — это
## тишина, которую не видно ни в логе, ни в кадре. Шаг — свой у каждого пола.
const STEP_CARPET := "step_carpet"
const STEP_CONCRETE := "step_concrete"
const SHOT := "shot"
## Удар в сценке добивания (ADR-0040). Файл — прежний удар ногой.
const BLOW := "kick"
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
## M24b (ADR-0038): вертолёт висит над крышей и пролетает, Otto съезжает по
## тросу; дверца и мотор машины, ворота паркинга; шахта в подвал открылась.
const HELICOPTER := "helicopter"
const HELICOPTER_PASS := "helicopter_pass"
const ROPE_SLIDE := "rope_slide"
## M24k: сдвижная дверь вертолёта, лебёдка и сброс бухты троса (ADR-0052).
const HELI_DOOR := "heli_door"
const WINCH := "winch"
const ROPE_DROP := "rope_drop"
const CAR_DOOR := "car_door"
const CAR_START := "car_start"
const GARAGE_GATE := "garage_gate"
const BASEMENT_OPEN := "basement_open"
## Джингл смерти Otto: звучит поверх самой смерти.
const DEATH_JINGLE := "death_jingle"

## M24k — пробелы, найденные аудитом звука (ADR-0052, решение 7): пуля в
## стену и в металл, выстрел агента, тело о пол, давка, вход в замедление;
## прыжок, приземление, присед, шаг по металлу, возвращение Otto; кабина
## трогается и встаёт; дверца машины, поворотник, проезжающая машина, гудок;
## сирена тревоги, треск неона; тиканье бонуса и новый рекорд.
const BULLET_WALL := "bullet_wall"
const BULLET_METAL := "bullet_metal"
const ENEMY_SHOT := "enemy_shot"
const BODY_FALL := "body_fall"
const CRUSH := "crush"
const SLOWMO := "slowmo"
const JUMP := "jump"
const LAND := "land"
const CROUCH := "crouch"
const STEP_METAL := "step_metal"
const RESPAWN := "respawn"
const ELEVATOR_START := "elevator_start"
const ELEVATOR_STOP := "elevator_stop"
const CAR_DOOR_OPEN := "car_door_open"
const TURN_SIGNAL := "turn_signal"
const CAR_PASS := "car_pass"
const HORN := "horn"
const ALARM := "alarm"
const NEON_FLICKER := "neon_flicker"
const BONUS_TICK := "bonus_tick"
const RECORD := "record"

## Меню (ADR-0035, решение 5): переход по пунктам, выбор и возврат.
const UI_MOVE := "ui_move"
const UI_SELECT := "ui_select"
const UI_BACK := "ui_back"

## Музыка: свой трек на экран (ADR-0036, решение 3). Трек тревоги звучит вместо
## темы здания, пока сирена не снята.
const THEME := "theme"
## Тема здания утром, днём и вечером; ночью — [constant THEME] (ADR-0052,
## решение 1). Тревога — одна на любое время суток.
const THEME_MORNING := "theme_morning"
const THEME_DAY := "theme_day"
const THEME_EVENING := "theme_evening"
const ALARM_THEME := "alarm_theme"
const MENU_THEME := "menu_theme"
const GAME_OVER_THEME := "game_over_theme"

## Фон: улица, дождь и ветер снаружи; на этажах — дождь за стеклом и тишина
## коридора; гром к молниям; гул шахты и неон вывески — на своём месте.
const CITY := "city"
## Улица утром, днём и вечером (ADR-0052, решение 8); ночь — [constant CITY].
const CITY_MORNING := "city_morning"
const CITY_DAY := "city_day"
const CITY_EVENING := "city_evening"
const RAIN := "rain"
const WIND := "wind"
## Снег (ADR-0054): ветер снаружи, шаг по снегу, шины по каше.
const WIND_SNOW := "wind_snow"
const STEP_SNOW := "step_snow"
const CAR_PASS_SLUSH := "car_pass_slush"
const RAIN_WINDOW := "rain_window"
const ROOM_TONE := "room_tone"
## Свой фон коридора у офиса и жилого дома (ADR-0055, решение 8); у отеля —
## прежний [constant ROOM_TONE].
const ROOM_TONE_OFFICE := "room_tone_office"
const ROOM_TONE_RESIDENTIAL := "room_tone_residential"
## Жизнь за дверью квартиры ([DoorLife]) и шаг по линолеуму жилого дома.
const DOOR_TV := "door_tv"
const DOOR_DOG := "door_dog"
const DOOR_ARGUE := "door_argue"
const STEP_LINO := "step_lino"
const THUNDER_NEAR := "thunder_near"
const THUNDER_FAR := "thunder_far"
const SHAFT_HUM := "shaft_hum"
const NEON_BUZZ := "neon_buzz"

const EFFECTS: PackedStringArray = [
	STEP_CARPET,
	STEP_CONCRETE,
	SHOT,
	BLOW,
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
	HELICOPTER,
	HELICOPTER_PASS,
	ROPE_SLIDE,
	HELI_DOOR,
	WINCH,
	ROPE_DROP,
	CAR_DOOR,
	CAR_START,
	GARAGE_GATE,
	BASEMENT_OPEN,
	BUILDING_BONUS,
	EXTRA_LIFE,
	GAME_OVER,
	DEATH_JINGLE,
	UI_MOVE,
	UI_SELECT,
	UI_BACK,
	BULLET_WALL,
	BULLET_METAL,
	ENEMY_SHOT,
	BODY_FALL,
	CRUSH,
	SLOWMO,
	JUMP,
	LAND,
	CROUCH,
	STEP_METAL,
	STEP_SNOW,
	RESPAWN,
	ELEVATOR_START,
	ELEVATOR_STOP,
	CAR_DOOR_OPEN,
	TURN_SIGNAL,
	CAR_PASS,
	CAR_PASS_SLUSH,
	HORN,
	ALARM,
	NEON_FLICKER,
	BONUS_TICK,
	RECORD,
]
const MUSIC: PackedStringArray = [
	THEME, THEME_MORNING, THEME_DAY, THEME_EVENING, ALARM_THEME, MENU_THEME, GAME_OVER_THEME
]
const AMBIENCE: PackedStringArray = [
	CITY,
	CITY_MORNING,
	CITY_DAY,
	CITY_EVENING,
	RAIN,
	WIND,
	WIND_SNOW,
	RAIN_WINDOW,
	ROOM_TONE,
	ROOM_TONE_OFFICE,
	ROOM_TONE_RESIDENTIAL,
	DOOR_TV,
	DOOR_DOG,
	DOOR_ARGUE,
	STEP_LINO,
	THUNDER_NEAR,
	THUNDER_FAR,
	SHAFT_HUM,
	NEON_BUZZ
]

## Джинглы: на время звучания приглушают трек (ADR-0036, решение 6).
const JINGLES: PackedStringArray = [
	DOCUMENT, EXTRA_LIFE, BUILDING_BONUS, GAME_OVER, DEATH_JINGLE, RECORD
]

## Звуки меню: как и джинглы, идут в [constant INTERFACE_BUS].
const INTERFACE: PackedStringArray = [UI_MOVE, UI_SELECT, UI_BACK, BONUS_TICK]

## Звуки, которые звучат петлёй, пока длится то, что их вызвало. Трек конца
## партии не зациклен: он доигрывает под экраном рекорда и молкнет.
const LOOPED: PackedStringArray = [
	ELEVATOR_HUM,
	HELICOPTER,
	WINCH,
	ESCALATOR_HUM,
	THEME,
	THEME_MORNING,
	THEME_DAY,
	THEME_EVENING,
	ALARM_THEME,
	MENU_THEME,
	CITY,
	RAIN,
	WIND,
	WIND_SNOW,
	RAIN_WINDOW,
	ROOM_TONE,
	ROOM_TONE_OFFICE,
	ROOM_TONE_RESIDENTIAL,
	SHAFT_HUM,
	NEON_BUZZ,
]

## Больше стольких вариантов одного имени не бывает: дальше тест не ищет.
const MAX_VARIANTS: int = 9

static var _cache: Dictionary = {}


## Шина, в которую идёт эффект [param name]: меню и джинглы — в
## [constant INTERFACE_BUS], всё остальное, звуки мира, — в [constant SFX_BUS].
static func bus_of(name: String) -> String:
	return INTERFACE_BUS if INTERFACE.has(name) or JINGLES.has(name) else SFX_BUS


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


## Эффект с тоном [param pitch] и громкостью [param db] этого раза.
static func play_tuned(name: String, pitch: float, db: float = 0.0) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.play(name, pitch, db)


## Приглушает музыку на [param seconds] секунд.
static func duck_music(seconds: float) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.duck(seconds)


## Тема здания во время суток [param time]: ночью — нуар [constant THEME],
## в остальное время — своя (ADR-0052, решение 1).
static func theme_for(time: TimeOfDay.Kind) -> String:
	match time:
		TimeOfDay.Kind.MORNING:
			return THEME_MORNING
		TimeOfDay.Kind.DAY:
			return THEME_DAY
		TimeOfDay.Kind.EVENING:
			return THEME_EVENING
	return THEME


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


## Звуки мира из-за стены: Otto за красной дверью слышит коридор глухо.
static func muffle_world(on: bool) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.muffle_world(on)


## Погода и время суток вокруг: по ним директор выбирает петли фона снаружи и
## внутри.
static func set_weather(weather: Weather.Kind, time: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.set_weather(weather, time)


## Петли фона под погоду [param weather]. Снаружи — улица и дождь или ветер;
## на этажах — тишина коридора и, в дождь, дождь за стеклом. Гром сюда не
## входит: он приходит от молний.
##
## Улица — своя на время суток [param time] (ADR-0052, решение 8), тишина
## коридора — своя у типа здания [param building] (ADR-0055, решение 8).
static func weather_loops(
	weather: Weather.Kind,
	outdoors: bool,
	time: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT,
	building: BuildingIdentity.Kind = BuildingIdentity.Kind.HOTEL
) -> PackedStringArray:
	var raining := Weather.is_raining(weather)
	if outdoors:
		var outside := WIND_SNOW if Weather.is_snowing(weather) else WIND
		return PackedStringArray([city_for(time), RAIN if raining else outside])
	if raining:
		return PackedStringArray([room_tone_of(building), RAIN_WINDOW])
	return PackedStringArray([room_tone_of(building)])


## Тишина коридора здания типа [param building].
static func room_tone_of(building: BuildingIdentity.Kind) -> String:
	match building:
		BuildingIdentity.Kind.OFFICE:
			return ROOM_TONE_OFFICE
		BuildingIdentity.Kind.RESIDENTIAL:
			return ROOM_TONE_RESIDENTIAL
	return ROOM_TONE


## Тип здания, в котором партия: по нему тишина коридора.
static func set_building(building: BuildingIdentity.Kind) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.set_building(building)


## Улица во время суток [param time]: утром птицы, днём плотный гул, вечером
## тише, ночью — прежний ночной город.
static func city_for(time: TimeOfDay.Kind) -> String:
	match time:
		TimeOfDay.Kind.MORNING:
			return CITY_MORNING
		TimeOfDay.Kind.DAY:
			return CITY_DAY
		TimeOfDay.Kind.EVENING:
			return CITY_EVENING
	return CITY


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


## Разовый звук на месте [param at] (координаты сцены): его слышно рядом, а
## не везде. Источник — на [param host], поверх его движения, и убирает себя
## сам, когда отзвучал. [param pitch] и [param db] — тон и громкость этого раза.
static func play_at(
	host: Node, name: String, at: Vector3, reach: float = 24.0, db: float = 0.0, pitch: float = 1.0
) -> void:
	if host == null or not host.is_inside_tree() or stream(name) == null:
		return
	var player := source(host, name, reach)
	player.top_level = true
	player.global_position = at
	player.volume_db = db
	player.pitch_scale = pitch
	player.finished.connect(player.queue_free)
	player.play()


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
