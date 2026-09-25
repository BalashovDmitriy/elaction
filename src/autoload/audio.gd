class_name AudioDirector
extends Node

## Звук игры: один автолоад на всё.
##
## Узлы не заводят себе источников: их пришлось бы держать в каждой сцене, а
## выстрел, переживший смерть стрелявшего, обрывался бы вместе с ним. Здесь
## пул источников на шине SFX, пара на музыку и фон на своей шине (ADR-0012,
## пункт 7; ADR-0036, решения 5 и 6).
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

## Наплыв одного трека в другой, с: тревога входит, а не обрывает тему.
const MUSIC_FADE: float = 1.6
## Как быстро трек уходит в тишину на [method stop_music], с.
const MUSIC_OUT: float = 0.6
## Тише этого источник уже не слышно; дальше — остановка.
const SILENT_DB: float = -60.0

## Частота среза «из-за стены», Гц: музыка за красной дверью и на паузе,
## фон на этажах. Без приглушения фильтр выключен, а не стоит на 20 кГц.
const MUSIC_MUFFLED_HZ: float = 900.0
const AMBIENCE_MUFFLED_HZ: float = 1600.0
const OPEN_HZ: float = 20000.0
## Коридор из-за красной двери: шаги, выстрелы и двери глухо и тише
## (ADR-0038, решение 2).
const SFX_MUFFLED_HZ: float = 700.0
const SFX_MUFFLED_DB: float = -6.0
## Как быстро звук уходит за стену и возвращается, с.
const MUFFLE_TIME: float = 0.35
## Фон на этажах тише, чем на крыше, дБ.
const INDOOR_AMBIENCE_DB: float = -3.0

## Насколько джингл приглушает трек, дБ, и как быстро.
const DUCK_DB: float = -12.0
const DUCK_IN: float = 0.12
const DUCK_OUT: float = 0.8

## Скорость звука, м/с: гром идёт за вспышкой с задержкой по дальности.
const SOUND_SPEED: float = 343.0
## Задержка грома в пределах, с: дальний разряд в пять километров ждали бы
## пятнадцать секунд, и связи со вспышкой было бы уже не услышать.
const THUNDER_DELAY := Vector2(0.25, 6.0)
## Ближе этого — раскат, дальше — перекат, м.
const THUNDER_NEAR: float = 1200.0

## Эффекты фильтров в [code]buses.tres[/code]: срез первым, громкость вторым.
const MUFFLE_EFFECT: int = 0
const DUCK_EFFECT: int = 1

static var _instance: AudioDirector = null

## Громкости шин, 0..1. Их меняют настройки.
var _levels: Dictionary = {}

var _sfx: Array[AudioStreamPlayer] = []
var _next: int = 0

## Два источника музыки: пока один уходит, второй входит.
var _music: Array[AudioStreamPlayer] = []
var _current: int = 0
var _playing_music: String = ""
var _music_fades: Array[Tween] = [null, null]

## Петли фона по имени и разовые звуки фона — гром.
var _ambience: Dictionary = {}
## Петли, которые сейчас уходят в тишину. Отдельно от звучащих: позванная
## снова, уходящая петля возвращается сама, а не заводится второй поверх неё —
## та, первая, осталась бы звучать вполсилы навсегда (авторевью M23).
var _leaving: Dictionary = {}
var _ambience_shot: AudioStreamPlayer = null
var _ambience_fades: Dictionary = {}

## Почему музыка сейчас из-за стены: пауза, красная дверь. Пока есть хоть
## одна причина — глухо; пауза посреди визита не возвращает звук на выходе из неё.
var _muffled_by: Dictionary = {}
var _world_muffled: bool = false
var _outdoors: bool = true
var _weather: Weather.Kind = Weather.Kind.CLEAR
## Какой по счёту город звучит. Гром назначается городу, и к следующему — в
## меню, в другое здание — он уже не приходит (авторевью M23).
var _city: int = 0
var _tweens: Dictionary = {}
## Когда кончится джингл, который сейчас приглушает трек, по часам движка, с.
var _duck_until: float = 0.0


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

	for index: int in 2:
		var player := AudioStreamPlayer.new()
		player.bus = Sounds.MUSIC_BUS
		add_child(player)
		_music.append(player)

	_ambience_shot = AudioStreamPlayer.new()
	_ambience_shot.bus = Sounds.AMBIENCE_BUS
	# Раскат длится секунд девять, а серии идут чаще: второй гром не обрывает
	# первый.
	_ambience_shot.max_polyphony = 2
	add_child(_ambience_shot)


## Как у [GameState]: без этого статическая ссылка переживала бы сам узел, и
## [method Sounds.play] звал бы освобождённый объект.
func _exit_tree() -> void:
	if _instance == self:
		_instance = null


## Проигрывает эффект. Голоса разбираются по кругу: самый старый затирается,
## и одновременная пальба не съедает звук шагов насовсем. Джингл на время
## звучания приглушает трек (ADR-0036, решение 6).
func play(name: String) -> void:
	var stream := Sounds.stream(name)
	if stream == null:
		return

	var player := _sfx[_next]
	_next = (_next + 1) % _sfx.size()
	player.stream = stream
	player.play()
	if Sounds.JINGLES.has(name):
		_duck(stream.get_length())


## Включает музыку наплывом. Тот же трек не перезапускается: иначе тема
## начиналась бы заново на каждой смерти. [param pick] — вариант трека, его
## выбирает здание по сиду (ADR-0036). Первый трек — сразу в полную силу:
## наплыв из тишины на старте игры звучал бы как задержка.
func play_music(name: String, pick: int = 0) -> void:
	var stream := Sounds.variant(name, pick)
	if stream == null:
		return
	if _playing_music == name and _music[_current].playing and _music[_current].stream == stream:
		return

	var was_playing := _music[_current].playing
	var old := _current
	if was_playing:
		_current = 1 - _current
		_fade_music(old, SILENT_DB, MUSIC_FADE, true)

	_playing_music = name
	var player := _music[_current]
	player.stream = stream
	player.volume_db = SILENT_DB if was_playing else 0.0
	player.play()
	if was_playing:
		_fade_music(_current, 0.0, MUSIC_FADE, false)


## Уводит музыку в тишину.
func stop_music() -> void:
	_playing_music = ""
	for index: int in _music.size():
		if _music[index].playing:
			_fade_music(index, SILENT_DB, MUSIC_OUT, true)


## Что играет прямо сейчас. Нужно тестам и отладке.
func music_name() -> String:
	return _playing_music if _music[_current].playing else ""


## Файл трека, который сейчас входит или звучит. Нужно тестам.
func music_stream() -> AudioStream:
	return _music[_current].stream if _music[_current].playing else null


## Музыка из-за стены по причине [param reason]: за красной дверью и на паузе
## (ADR-0036, решение 6).
func muffle_music(reason: String, on: bool) -> void:
	var was := music_muffled()
	if on:
		_muffled_by[reason] = true
	else:
		_muffled_by.erase(reason)
	if music_muffled() != was:
		_sweep(Sounds.MUSIC_BUS, MUSIC_MUFFLED_HZ if music_muffled() else OPEN_HZ)


func music_muffled() -> bool:
	return not _muffled_by.is_empty()


## Звуки мира из-за стены — Otto за красной дверью.
func muffle_world(on: bool) -> void:
	if _world_muffled == on:
		return
	_world_muffled = on
	_sweep(Sounds.SFX_BUS, SFX_MUFFLED_HZ if on else OPEN_HZ)
	_gain(Sounds.SFX_BUS, SFX_MUFFLED_DB if on else 0.0, MUFFLE_TIME)


func world_muffled() -> bool:
	return _world_muffled


## Петли фона: улица, дождь, ветер. Лишние уходят, новые входят наплывом,
## те, что уже звучат, не перезапускаются — иначе дождь прерывался бы на
## каждом здании.
func set_ambience(names: PackedStringArray) -> void:
	for name: String in _ambience.keys():
		if not names.has(name):
			_leaving[name] = _ambience[name]
			_ambience.erase(name)
			_fade_ambience(name, _leaving[name] as AudioStreamPlayer, SILENT_DB, true)
	for name: String in names:
		var player := _ambience.get(name) as AudioStreamPlayer
		if player == null:
			player = _leaving.get(name) as AudioStreamPlayer
			_leaving.erase(name)
		if player == null:
			player = _loop(name)
		if player == null:
			continue
		_ambience[name] = player
		_fade_ambience(name, player, 0.0, false)


## Погода вокруг: снаружи и внутри звучат свои петли. Зовёт её город, когда
## строится, — и гром прежнего города с этим отменяется.
func set_weather(weather: Weather.Kind) -> void:
	_weather = weather
	_city += 1
	set_ambience(Sounds.weather_loops(_weather, _outdoors))


## Какие петли фона звучат. Нужно тестам.
func ambience() -> PackedStringArray:
	return PackedStringArray(_ambience.keys())


## Под открытым небом фон в полную силу, на этажах — глухо, как из-за стекла
## (ADR-0036, решение 5).
func set_outdoors(on: bool) -> void:
	if _outdoors == on:
		return
	_outdoors = on
	set_ambience(Sounds.weather_loops(_weather, _outdoors))
	# Гром на этажах глухой: петли внутри и так записаны из-за стекла, а
	# фильтр шины приглушает то, что приходит снаружи.
	_sweep(Sounds.AMBIENCE_BUS, OPEN_HZ if on else AMBIENCE_MUFFLED_HZ)
	_gain(Sounds.AMBIENCE_BUS, 0.0 if on else INDOOR_AMBIENCE_DB, MUFFLE_TIME)


## Гром от разряда в [param distance] метрах: с задержкой, как от настоящего.
## Таймер встаёт на паузе игры — гром не приходит к замершей вспышке.
func thunder(distance: float) -> void:
	var name := Sounds.THUNDER_NEAR if distance < THUNDER_NEAR else Sounds.THUNDER_FAR
	var timer := get_tree().create_timer(thunder_delay(distance), false)
	timer.timeout.connect(_rumble.bind(name, _city))


## Задержка грома для разряда в [param distance] метрах, с.
static func thunder_delay(distance: float) -> float:
	return clampf(distance / SOUND_SPEED, THUNDER_DELAY.x, THUNDER_DELAY.y)


## Раскат грома, назначенный городу номер [param city]. Город с тех пор
## сменился — молнии, от которой он шёл, уже нет.
func _rumble(name: String, city: int) -> void:
	if city != _city:
		return
	var stream := Sounds.stream(name)
	if stream == null:
		return
	_ambience_shot.stream = stream
	_ambience_shot.play()


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


## Сбрасывает приглушения, фон и назначенный гром. Нужен тестам: автолоад один
## на все файлы.
func reset() -> void:
	for player: AudioStreamPlayer in _ambience.values() + _leaving.values():
		player.queue_free()
	_ambience.clear()
	_leaving.clear()
	for fade: Tween in _ambience_fades.values():
		fade.kill()
	_ambience_fades.clear()
	for key: String in _tweens.keys():
		(_tweens[key] as Tween).kill()
	_tweens.clear()
	_muffled_by.clear()
	_world_muffled = false
	_outdoors = true
	_weather = Weather.Kind.CLEAR
	_duck_until = 0.0
	_city += 1
	_ambience_shot.stop()
	for bus: String in [Sounds.MUSIC_BUS, Sounds.AMBIENCE_BUS, Sounds.SFX_BUS]:
		_muffle_of(bus).cutoff_hz = OPEN_HZ
		AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index(bus), MUFFLE_EFFECT, false)
		_gain_of(bus).volume_db = 0.0


func _fade_music(index: int, target_db: float, seconds: float, stop_after: bool) -> void:
	var previous := _music_fades[index]
	if previous != null:
		previous.kill()
	var player := _music[index]
	var fade := create_tween()
	fade.tween_property(player, "volume_db", target_db, seconds)
	if stop_after:
		fade.tween_callback(player.stop)
	_music_fades[index] = fade


## Заводит петлю фона [param name] из тишины; null — файла нет.
func _loop(name: String) -> AudioStreamPlayer:
	var stream := Sounds.stream(name)
	if stream == null:
		return null
	var player := AudioStreamPlayer.new()
	player.bus = Sounds.AMBIENCE_BUS
	player.stream = stream
	player.volume_db = SILENT_DB
	add_child(player)
	player.play()
	return player


func _fade_ambience(
	name: String, player: AudioStreamPlayer, target_db: float, drop_after: bool
) -> void:
	var previous := _ambience_fades.get(name) as Tween
	if previous != null:
		previous.kill()
	var fade := create_tween()
	fade.tween_property(player, "volume_db", target_db, MUSIC_FADE)
	if drop_after:
		fade.tween_callback(_drop_loop.bind(name, player))
	_ambience_fades[name] = fade


## Петля ушла в тишину — источник больше не нужен.
func _drop_loop(name: String, player: AudioStreamPlayer) -> void:
	if _leaving.get(name) == player:
		_leaving.erase(name)
	player.queue_free()


## Ведёт срез фильтра шины к [param hz]. На открытом звуке фильтр выключается:
## на 20 кГц он не слышен, но стоит времени микшера.
func _sweep(bus: String, hz: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	var muffle := _muffle_of(bus)
	AudioServer.set_bus_effect_enabled(index, MUFFLE_EFFECT, true)
	var sweep := _restart(bus + "/muffle")
	# Срез слышится по октавам, а не по герцам: линейный ход от 20 кГц до
	# 900 Гц просидел бы почти всё время там, где разницы не слышно.
	sweep.tween_method(
		func(octave: float) -> void: muffle.cutoff_hz = pow(2.0, octave),
		log(muffle.cutoff_hz) / log(2.0),
		log(hz) / log(2.0),
		MUFFLE_TIME
	)
	if is_equal_approx(hz, OPEN_HZ):
		sweep.tween_callback(AudioServer.set_bus_effect_enabled.bind(index, MUFFLE_EFFECT, false))


func _gain(bus: String, target_db: float, seconds: float) -> void:
	_restart(bus + "/gain").tween_property(_gain_of(bus), "volume_db", target_db, seconds)


## Приглушает трек на [param seconds] секунд. Джингл поверх джингла продлевает
## приглушение, а не возвращает трек посреди второго.
func _duck(seconds: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_duck_until = maxf(_duck_until, now + seconds)
	var gain := _gain_of(Sounds.MUSIC_BUS)
	var duck := _restart(Sounds.MUSIC_BUS + "/gain")
	duck.tween_property(gain, "volume_db", DUCK_DB, DUCK_IN)
	duck.tween_interval(maxf(_duck_until - now - DUCK_IN, 0.0))
	duck.tween_property(gain, "volume_db", 0.0, DUCK_OUT)


func _restart(key: String) -> Tween:
	var previous := _tweens.get(key) as Tween
	if previous != null:
		previous.kill()
	var tween := create_tween()
	_tweens[key] = tween
	return tween


## Фильтр «из-за стены» шины [param bus] — первый эффект в [code]buses.tres[/code].
static func _muffle_of(bus: String) -> AudioEffectLowPassFilter:
	var index := AudioServer.get_bus_index(bus)
	return AudioServer.get_bus_effect(index, MUFFLE_EFFECT) as AudioEffectLowPassFilter


## Ручка громкости шины [param bus] — второй эффект: приглушение и фон на этажах.
static func _gain_of(bus: String) -> AudioEffectAmplify:
	var index := AudioServer.get_bus_index(bus)
	return AudioServer.get_bus_effect(index, DUCK_EFFECT) as AudioEffectAmplify
