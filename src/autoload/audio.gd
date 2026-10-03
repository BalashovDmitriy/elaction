class_name AudioDirector
extends Node

## Game sound: one autoload for everything.
##
## Nodes do not create their own sources: they would have to be kept in every scene, and
## a shot that outlived the shooter's death would be cut off together with him. Here there is
## a pool of sources on the SFX bus, a pair for music and ambience on its own bus (ADR-0012,
## point 7; ADR-0036, decisions 5 and 6).
##
## Sound names are [Sounds] constants; a test makes sure each one has a file,
## and each file has a constant.
##
## It is accessed through [method Sounds.play] and its neighbours: the autoload name
## differs from [code]class_name[/code], as with [GameState] — otherwise
## parsing a single script apart from the project does not find the identifier.

## How many effects can sound at once. More than a dozen in a frame is already mush,
## as with light sources: the original had four chips of three voices for everything.
const VOICES: int = 12

## Crossfade of one track into another, s: the alarm comes in rather than cutting the theme.
const MUSIC_FADE: float = 1.6
## How fast the track fades to silence on [method stop_music], s.
const MUSIC_OUT: float = 0.6
## Quieter than this a source is no longer heard; past it — stop.
const SILENT_DB: float = -60.0

## "Behind the wall" cutoff frequency, Hz: music behind a red door and on pause,
## ambience on floors. Without muffling the filter is off, rather than sitting at 20 kHz.
const MUSIC_MUFFLED_HZ: float = 900.0
const AMBIENCE_MUFFLED_HZ: float = 1600.0
const OPEN_HZ: float = 20000.0
## The corridor from behind a red door: steps, shots and doors are dull and quieter
## (ADR-0038, decision 2).
const SFX_MUFFLED_HZ: float = 700.0
const SFX_MUFFLED_DB: float = -6.0
## How fast sound goes behind the wall and comes back, s.
const MUFFLE_TIME: float = 0.35
## Ambience on floors is quieter than on the roof, dB.
const INDOOR_AMBIENCE_DB: float = -3.0

## How much a jingle ducks the track, dB, and how fast.
const DUCK_DB: float = -12.0
const DUCK_IN: float = 0.12
const DUCK_OUT: float = 0.8

## Speed of sound, m/s: thunder follows the flash with a delay by distance.
const SOUND_SPEED: float = 343.0
## Thunder delay is clamped, s: a distant strike five kilometres away would be waited for
## fifteen seconds, and the connection to the flash could no longer be heard.
const THUNDER_DELAY := Vector2(0.25, 6.0)
## Closer than this — a clap, farther — a roll, m.
const THUNDER_NEAR: float = 1200.0

## Filter effects in [code]buses.tres[/code]: cutoff first, volume second.
const MUFFLE_EFFECT: int = 0
const DUCK_EFFECT: int = 1
## The third effect of the SFX bus is pitch shift: when the world slows down (takedown, last
## death) world sounds play lower (ADR-0052, decision 7). It is enabled only for
## the slowdown — pitch shift is expensive.
const SLOW_EFFECT: int = 2
## Pitch of world sounds at the deepest slowdown and from which world tempo it
## starts to drop.
const SLOWEST_PITCH: float = 0.62
const SLOW_FROM: float = 0.98

static var _instance: AudioDirector = null

## Bus volumes, 0..1. Settings change them.
var _levels: Dictionary = {}

var _sfx: Array[AudioStreamPlayer] = []
var _next: int = 0

## Two music sources: while one fades out, the other fades in.
var _music: Array[AudioStreamPlayer] = []
var _current: int = 0
var _playing_music: String = ""
var _music_fades: Array[Tween] = [null, null]

## Ambience loops by name and one-shot ambience sounds — thunder.
var _ambience: Dictionary = {}
## Loops currently fading to silence. Separate from the playing ones: when called
## again, a fading loop comes back itself rather than a second one starting over it —
## the first one would stay playing at half strength forever (code review M23).
var _leaving: Dictionary = {}
var _ambience_shot: AudioStreamPlayer = null
var _ambience_fades: Dictionary = {}

## Why music is behind the wall now: pause, red door. While there is at least
## one reason — dull; a pause in the middle of a visit does not bring the sound back on exiting it.
var _muffled_by: Dictionary = {}
var _world_muffled: bool = false
var _outdoors: bool = true
var _weather: Weather.Kind = Weather.Kind.CLEAR
var _time: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT
var _building: BuildingIdentity.Kind = BuildingIdentity.Kind.HOTEL
## Ambience of the special floor hall Otto is near ([method set_hall]); empty — none.
var _hall: String = ""
## Which city in sequence is sounding. Thunder is assigned to a city, and to the next one — in
## the menu, in another building — it no longer comes (code review M23).
var _city: int = 0
var _tweens: Dictionary = {}
## When the jingle now ducking the track ends, by the engine clock, s.
var _duck_until: float = 0.0


## The game's sound. Before the autoload enters the tree — null.
static func instance() -> AudioDirector:
	return _instance


## Sources are created here, not in [method Node._ready], together with publishing
## the instance: between entering the tree and ready [method instance] would hand out
## a director with an empty pool, and the very first [method play] would crash the frame by
## accessing a null voice.
func _enter_tree() -> void:
	if _instance != null:
		return
	_instance = self

	# The autoload lives on pause too: otherwise music would cut off on every Esc.
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
	# A clap lasts about nine seconds, and series come more often: the second thunder does not cut
	# the first.
	_ambience_shot.max_polyphony = 2
	add_child(_ambience_shot)


## World sound pitch follows the world tempo: slowdown — lower. The tempo is set by the takedown
## and last-death scenes ([member Engine.time_scale]); test speed-up
## does not touch the pitch.
func _process(_delta: float) -> void:
	var index := AudioServer.get_bus_index(Sounds.SFX_BUS)
	if index < 0 or AudioServer.get_bus_effect_count(index) <= SLOW_EFFECT:
		return
	var tempo := Engine.time_scale
	var slow := tempo < SLOW_FROM
	if AudioServer.is_bus_effect_enabled(index, SLOW_EFFECT) != slow:
		AudioServer.set_bus_effect_enabled(index, SLOW_EFFECT, slow)
	if slow:
		var shift := AudioServer.get_bus_effect(index, SLOW_EFFECT) as AudioEffectPitchShift
		if shift != null:
			shift.pitch_scale = lerpf(SLOWEST_PITCH, 1.0, clampf(tempo, 0.0, 1.0))


## As with [GameState]: without this the static reference would outlive the node itself, and
## [method Sounds.play] would call a freed object.
func _exit_tree() -> void:
	if _instance == self:
		_instance = null


## Plays an effect. Voices are taken in a round: the oldest is overwritten,
## and simultaneous shooting does not eat the sound of steps for good. A jingle ducks the track
## while it plays (ADR-0036, decision 6).
##
## [param pitch] and [param db] — pitch and volume for this time: the takedown hit
## sounds over itself a tone lower, booming (ADR-0050). Voices are shared, and every
## time pitch and volume are set anew — otherwise a lowered hit would pass
## its pitch to the next step.
func play(name: String, pitch: float = 1.0, db: float = 0.0) -> void:
	var stream := Sounds.stream(name)
	if stream == null:
		return

	var player := _sfx[_next]
	_next = (_next + 1) % _sfx.size()
	# Voices are shared, but a sound has its own bus: menu and jingles bypass the corridor muffling.
	player.bus = Sounds.bus_of(name)
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = db
	player.play()
	if Sounds.JINGLES.has(name):
		_duck(stream.get_length())


## How many shared voices are playing effect [param name] right now. Needed by tests.
func voices_playing(name: String) -> int:
	var stream := Sounds.stream(name)
	var count := 0
	for player: AudioStreamPlayer in _sfx:
		if player.playing and player.stream == stream:
			count += 1
	return count


## Turns music on with a crossfade. The same track is not restarted: otherwise the theme
## would start over on every death. [param pick] — the track variant, the
## building chooses it by seed (ADR-0036). The first track — at full strength right away:
## a fade-in from silence at game start would sound like a delay.
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


## Fades music to silence.
func stop_music() -> void:
	_playing_music = ""
	for index: int in _music.size():
		if _music[index].playing:
			_fade_music(index, SILENT_DB, MUSIC_OUT, true)


## What is playing right now. Needed by tests and debugging.
func music_name() -> String:
	return _playing_music if _music[_current].playing else ""


## The file of the track now fading in or playing. Needed by tests.
func music_stream() -> AudioStream:
	return _music[_current].stream if _music[_current].playing else null


## Music from behind the wall for reason [param reason]: behind a red door and on pause
## (ADR-0036, decision 6).
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


## World sounds from behind the wall — Otto behind a red door. The effects bus with
## ambience is muffled; menu and jingles bypass it ([constant Sounds.INTERFACE_BUS]).
func muffle_world(on: bool) -> void:
	if _world_muffled == on:
		return
	_world_muffled = on
	_sweep(Sounds.SFX_BUS, SFX_MUFFLED_HZ if on else OPEN_HZ)
	_gain(Sounds.SFX_BUS, SFX_MUFFLED_DB if on else 0.0, MUFFLE_TIME)


func world_muffled() -> bool:
	return _world_muffled


## Ambience loops: street, rain, wind. Extra ones fade out, new ones fade in,
## those already playing are not restarted — otherwise rain would be interrupted on
## every building.
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


## Weather around: outside and inside have their own loops. The city calls it when
## it is built — and the previous city's thunder is cancelled with that.
func set_weather(weather: Weather.Kind, time: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT) -> void:
	_weather = weather
	_time = time
	_city += 1
	set_ambience(Sounds.weather_loops(_weather, _outdoors, _time, _building, _hall))


## Building kind: it sets the corridor silence (ADR-0055, decision 8). [param hall] —
## the ambience of the special floor hall Otto is near (ADR-0057, decision 4): it fades
## in over the corridor silence and fades out when Otto has left the floor.
func set_building(building: BuildingIdentity.Kind, hall: String = "") -> void:
	if _building == building and _hall == hall:
		return
	_building = building
	_hall = hall
	set_ambience(Sounds.weather_loops(_weather, _outdoors, _time, _building, _hall))


## Which ambience loops are playing. Needed by tests.
func ambience() -> PackedStringArray:
	return PackedStringArray(_ambience.keys())


## Under the open sky ambience is at full strength, on floors — dull, as if through glass
## (ADR-0036, decision 5).
func set_outdoors(on: bool) -> void:
	if _outdoors == on:
		return
	_outdoors = on
	set_ambience(Sounds.weather_loops(_weather, _outdoors, _time, _building, _hall))
	# Thunder on floors is dull: the inside loops are recorded through glass anyway, and
	# the bus filter muffles what comes from outside.
	_sweep(Sounds.AMBIENCE_BUS, OPEN_HZ if on else AMBIENCE_MUFFLED_HZ)
	_gain(Sounds.AMBIENCE_BUS, 0.0 if on else INDOOR_AMBIENCE_DB, MUFFLE_TIME)


## Thunder from a strike [param distance] metres away: with a delay, like a real one.
## The timer stops on game pause — thunder does not arrive to a frozen flash.
func thunder(distance: float) -> void:
	var name := Sounds.THUNDER_NEAR if distance < THUNDER_NEAR else Sounds.THUNDER_FAR
	var timer := get_tree().create_timer(thunder_delay(distance), false)
	timer.timeout.connect(_rumble.bind(name, _city))


## Thunder delay for a strike [param distance] metres away, s.
static func thunder_delay(distance: float) -> float:
	return clampf(distance / SOUND_SPEED, THUNDER_DELAY.x, THUNDER_DELAY.y)


## A thunderclap assigned to city number [param city]. If the city has
## changed since — the lightning it came from is gone.
func _rumble(name: String, city: int) -> void:
	if city != _city:
		return
	var stream := Sounds.stream(name)
	if stream == null:
		return
	_ambience_shot.stream = stream
	_ambience_shot.play()


## Bus volume, 0..1. Zero — silence, one — as recorded.
func set_level(bus: String, level: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	# Only an applied level is remembered: otherwise [method level_of] would give
	# the settings a bus volume that does not exist.
	var value := clampf(level, 0.0, 1.0)
	_levels[bus] = value
	_apply_level(index, value)
	# Interface and jingles bypass the effects bus, but are under its slider: in
	# the settings their volume has always been the effects volume, and they got their own bus
	# for muffling behind the door, not for one more slider.
	if bus == Sounds.SFX_BUS:
		var interface := AudioServer.get_bus_index(Sounds.INTERFACE_BUS)
		if interface >= 0:
			_apply_level(interface, value)


## Silence is not "minus eighty decibels" but a disabled bus: at low
## volumes the logarithm goes to minus infinity and crackles along the way.
static func _apply_level(index: int, value: float) -> void:
	AudioServer.set_bus_mute(index, is_zero_approx(value))
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.0001)))


func level_of(bus: String) -> float:
	return float(_levels.get(bus, 1.0))


## Resets ducking, ambience and assigned thunder. Needed by tests: the autoload is one
## for all files.
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
	_building = BuildingIdentity.Kind.HOTEL
	_hall = ""
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


## Starts ambience loop [param name] from silence; null — no file.
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


## The loop has faded to silence — the source is no longer needed.
func _drop_loop(name: String, player: AudioStreamPlayer) -> void:
	if _leaving.get(name) == player:
		_leaving.erase(name)
	player.queue_free()


## Moves the bus filter cutoff toward [param hz]. With open sound the filter turns off:
## at 20 kHz it is inaudible, but it costs mixer time.
func _sweep(bus: String, hz: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	var muffle := _muffle_of(bus)
	AudioServer.set_bus_effect_enabled(index, MUFFLE_EFFECT, true)
	var sweep := _restart(bus + "/muffle")
	# Cutoff is heard by octaves, not by hertz: a linear sweep from 20 kHz to
	# 900 Hz would spend almost all its time where no difference is heard.
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


## Ducks the track for [param seconds] seconds from outside: music drops on
## the takedown hit (ADR-0050).
func duck(seconds: float) -> void:
	_duck(seconds)


## Ducks the track for [param seconds] seconds. A jingle over a jingle extends
## the ducking rather than bringing the track back in the middle of the second.
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


## The "behind the wall" filter of bus [param bus] — the first effect in [code]buses.tres[/code].
static func _muffle_of(bus: String) -> AudioEffectLowPassFilter:
	var index := AudioServer.get_bus_index(bus)
	return AudioServer.get_bus_effect(index, MUFFLE_EFFECT) as AudioEffectLowPassFilter


## Volume knob of bus [param bus] — the second effect: ducking and ambience on floors.
static func _gain_of(bus: String) -> AudioEffectAmplify:
	var index := AudioServer.get_bus_index(bus)
	return AudioServer.get_bus_effect(index, DUCK_EFFECT) as AudioEffectAmplify
