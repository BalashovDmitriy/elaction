class_name Sounds
extends RefCounted

## Game sounds: event names and file loading.
##
## Organized like the former sprites: the name is the file name, there is one list
## for the project, and a test walks it both ways: every name has a file,
## every file has a name. Otherwise unused sound piles up in the repository, and a
## forgotten event stays silent. Files come from free libraries, authors are in
## `assets/audio/credits.json` (ADR-0036, decision 1).

const DIR := "res://assets/audio/"

## Extensions a sound can be stored in. Short and frequent ones are WAV,
## long ones OGG; which is which is decided by the asset build, and the game takes what
## it finds. A second list of the same names would silently drift from the first.
const EXTENSIONS: PackedStringArray = [".wav", ".ogg"]

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const MASTER_BUS := "Master"
## Ambience is a child bus of effects: the effects volume in the settings drives it too
## (ADR-0036, decision 5).
const AMBIENCE_BUS := "Ambience"
## The interface and jingles bypass the effects bus and go straight into the master one:
## the corridor muffling behind a red door does not touch them, since a menu click and
## the document jingle do not sound in the corridor. Volume is driven by the same effects
## slider ([method AudioDirector.set_level]).
const INTERFACE_BUS := "Interface"

## Reasons for which the music sounds as if from behind a wall.
const MUFFLE_PAUSE := "pause"
const MUFFLE_DOOR := "door"

## Game events. Constants, not strings in place: a typo in a string is
## silence that shows neither in the log nor in the frame. Each floor has its own step.
const STEP_CARPET := "step_carpet"
const STEP_CONCRETE := "step_concrete"
const SHOT := "shot"
## The blow in the takedown scene (ADR-0040). The file is the former kick.
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
## M24b (ADR-0038): the helicopter hovers above the roof and flies past, Otto slides down
## the rope; the car door and engine, the garage gate; the shaft to the basement opened.
const HELICOPTER := "helicopter"
const HELICOPTER_PASS := "helicopter_pass"
const ROPE_SLIDE := "rope_slide"
## M24k: the helicopter's sliding door, the winch and the rope coil drop (ADR-0052).
const HELI_DOOR := "heli_door"
const WINCH := "winch"
const ROPE_DROP := "rope_drop"
const CAR_DOOR := "car_door"
const CAR_START := "car_start"
const GARAGE_GATE := "garage_gate"
const BASEMENT_OPEN := "basement_open"

## M24k: gaps found by the sound audit (ADR-0052, decision 7): a bullet into a
## wall and into metal, an agent's shot, a body hitting the floor, a crush, entering the
## slowdown; jump, landing, crouch, a step on metal, Otto's return; the cab
## starts and stops; the car door, a turn signal, a passing car, a horn;
## the alarm siren, neon crackle; the bonus ticking and a new high score.
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

## Menu (ADR-0035, decision 5): moving between items, selection and going back.
const UI_MOVE := "ui_move"
const UI_SELECT := "ui_select"
const UI_BACK := "ui_back"

## Music: its own track per screen (ADR-0036, decision 3). The alarm track plays instead
## of the building theme until the siren is lifted.
const THEME := "theme"
## The building theme in the morning, by day and in the evening; at night [constant THEME]
## (ADR-0052, decision 1). The alarm is one for any time of day.
const THEME_MORNING := "theme_morning"
const THEME_DAY := "theme_day"
const THEME_EVENING := "theme_evening"
const ALARM_THEME := "alarm_theme"
## Office and residential building themes (ADR-0057, decision 7): the hotel keeps the
## former names, the other kinds have the kind's name; the time of day is a suffix, as
## for the hotel.
const THEME_OFFICE := "theme_office"
const THEME_RESIDENTIAL := "theme_residential"
const ALARM_OFFICE := "alarm_office"
const ALARM_RESIDENTIAL := "alarm_residential"
## The clang of the freight cab's gate (ADR-0057, decision 6).
const CAB_GATE := "cab_gate"
## Ambience of special-floor halls (ADR-0057, decision 4): it sounds over the corridor
## silence while Otto is on the hall's floor. Halls without their own sound get only
## silence.
const HALL_POOL := "hall_pool"
const HALL_SERVER := "hall_server"
const HALL_BOILER := "hall_boiler"
const HALL_LAUNDRY := "hall_laundry"
const HALL_DINING := "hall_dining"
const HALL_KITCHEN := "hall_kitchen"
const HALL_GYM := "hall_gym"
const HALL_BAR := "hall_bar"
const HALL_MECHANICAL := "hall_mechanical"
const HALL_TONES := {
	FloorRole.Role.POOL: HALL_POOL,
	FloorRole.Role.SERVER: HALL_SERVER,
	FloorRole.Role.BOILER: HALL_BOILER,
	FloorRole.Role.LAUNDRY: HALL_LAUNDRY,
	FloorRole.Role.DINING: HALL_DINING,
	FloorRole.Role.KITCHEN: HALL_KITCHEN,
	FloorRole.Role.GYM: HALL_GYM,
	FloorRole.Role.BAR: HALL_BAR,
	FloorRole.Role.MECHANICAL: HALL_MECHANICAL,
}
const MENU_THEME := "menu_theme"
const GAME_OVER_THEME := "game_over_theme"

## Ambience: the street, rain and wind outside; on the floors, rain behind the glass and
## the corridor silence; thunder for lightning; the shaft hum and the sign neon in their
## own places.
const CITY := "city"
## The street in the morning, by day and in the evening (ADR-0052, decision 8); night is
## [constant CITY].
const CITY_MORNING := "city_morning"
const CITY_DAY := "city_day"
const CITY_EVENING := "city_evening"
const RAIN := "rain"
const WIND := "wind"
## Snow (ADR-0054): wind outside, a step in snow, tires in slush.
const WIND_SNOW := "wind_snow"
const STEP_SNOW := "step_snow"
const CAR_PASS_SLUSH := "car_pass_slush"
const RAIN_WINDOW := "rain_window"
const ROOM_TONE := "room_tone"
## Own corridor ambience for the office and the residential building (ADR-0055, decision
## 8); the hotel keeps the former [constant ROOM_TONE].
const ROOM_TONE_OFFICE := "room_tone_office"
const ROOM_TONE_RESIDENTIAL := "room_tone_residential"
## Life behind an apartment door ([DoorLife]) and a step on residential building
## linoleum.
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
	STEP_LINO,
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
	CAB_GATE,
]
const MUSIC: PackedStringArray = [
	THEME,
	THEME_MORNING,
	THEME_DAY,
	THEME_EVENING,
	ALARM_THEME,
	THEME_OFFICE,
	THEME_OFFICE + "_morning",
	THEME_OFFICE + "_day",
	THEME_OFFICE + "_evening",
	ALARM_OFFICE,
	THEME_RESIDENTIAL,
	THEME_RESIDENTIAL + "_morning",
	THEME_RESIDENTIAL + "_day",
	THEME_RESIDENTIAL + "_evening",
	ALARM_RESIDENTIAL,
	MENU_THEME,
	GAME_OVER_THEME,
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
	THUNDER_NEAR,
	THUNDER_FAR,
	SHAFT_HUM,
	NEON_BUZZ,
	HALL_POOL,
	HALL_SERVER,
	HALL_BOILER,
	HALL_LAUNDRY,
	HALL_DINING,
	HALL_KITCHEN,
	HALL_GYM,
	HALL_BAR,
	HALL_MECHANICAL,
]

## Jingles: they duck the track while they play (ADR-0036, decision 6).
const JINGLES: PackedStringArray = [DOCUMENT, EXTRA_LIFE, BUILDING_BONUS, GAME_OVER, RECORD]

## Menu sounds: like jingles, they go to [constant INTERFACE_BUS].
const INTERFACE: PackedStringArray = [UI_MOVE, UI_SELECT, UI_BACK, BONUS_TICK]

## Sounds that play as a loop while whatever triggered them lasts. The game-over track
## is not looped: it plays out under the high-score screen and falls silent.
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
	# Office and residential building themes and alarms (ADR-0057, decision 7): without a
	# loop the building track played once and was silent until the end of the building
	# (M24o code review).
	THEME_OFFICE,
	THEME_OFFICE + "_morning",
	THEME_OFFICE + "_day",
	THEME_OFFICE + "_evening",
	ALARM_OFFICE,
	THEME_RESIDENTIAL,
	THEME_RESIDENTIAL + "_morning",
	THEME_RESIDENTIAL + "_day",
	THEME_RESIDENTIAL + "_evening",
	ALARM_RESIDENTIAL,
	MENU_THEME,
	CITY,
	# The street in the morning, by day and in the evening loops, like the night one
	# (ADR-0052, decision 8).
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
	SHAFT_HUM,
	NEON_BUZZ,
	# Special-floor hall ambience (ADR-0057, decision 4) plays while Otto is on the floor.
	HALL_POOL,
	HALL_SERVER,
	HALL_BOILER,
	HALL_LAUNDRY,
	HALL_DINING,
	HALL_KITCHEN,
	HALL_GYM,
	HALL_BAR,
	HALL_MECHANICAL,
]

## There are never more variants of one name than this: the test does not look further.
const MAX_VARIANTS: int = 9

static var _cache: Dictionary = {}


## The bus effect [param name] goes to: menu and jingles to
## [constant INTERFACE_BUS], everything else, world sounds, to [constant SFX_BUS].
static func bus_of(name: String) -> String:
	return INTERFACE_BUS if INTERFACE.has(name) or JINGLES.has(name) else SFX_BUS


## All names at once: the test walks them.
static func names() -> PackedStringArray:
	var all := PackedStringArray(EFFECTS)
	all.append_array(MUSIC)
	all.append_array(AMBIENCE)
	return all


## Sound variant files in order: `name`, `name.2`, `name.3`... Counting goes up to
## the first gap: the game would not find a variant beyond a gap.
static func variant_paths(name: String) -> PackedStringArray:
	var paths := PackedStringArray()
	for index: int in MAX_VARIANTS:
		var path := _existing(variant_stem(name, index))
		if path.is_empty():
			break
		paths.append(path)
	return paths


## Variant file name without the extension.
static func variant_stem(name: String, index: int) -> String:
	return name if index == 0 else "%s.%d" % [name, index + 1]


## All places where a file named [param stem] could be. The test needs them: it
## makes sure a variant is in exactly one file, not in WAV and OGG at once.
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


## The sound stream, or null if there is no file. The cache is shared: the same shot
## sounds thousands of times per game. If there are several variants, the stream itself
## draws one for every playback: consecutive steps do not sound with the same file.
static func stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name] as AudioStream

	var streams := variants(name)
	var loaded: AudioStream = null
	if streams.is_empty():
		push_error("No sound %s — run tools/build_audio.py" % name)
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


## Variant number [param pick] wrapping around, for music and ambience, which are chosen
## by a draw per building, not per playback (ADR-0036).
static func variant(name: String, pick: int) -> AudioStream:
	var streams := variants(name)
	if streams.is_empty():
		return stream(name)
	return streams[posmod(pick, streams.size())]


## All sound variants, loaded and looped according to [constant LOOPED].
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


## Looping is set here, not in the import settings.
##
## The import settings are a second copy of the same list, and they drift silently:
## a theme whose loop is reset in `.import` plays for twenty seconds and goes silent
## until the end of the game. The [constant LOOPED] list is single, and the test checks it.
static func _set_looping(stream: AudioStream, looping: bool) -> void:
	var wav := stream as AudioStreamWAV
	if wav != null:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if looping else AudioStreamWAV.LOOP_DISABLED
		if looping:
			wav.loop_begin = 0
			# The loop end is the last frame, and it is computed from length and rate:
			# dividing data size by frame bytes is not possible, the format can be compressed.
			wav.loop_end = int(round(wav.get_length() * float(wav.mix_rate)))
		return

	var vorbis := stream as AudioStreamOggVorbis
	if vorbis != null:
		vorbis.loop = looping
		vorbis.loop_offset = 0.0


## Plays an effect. Silently does nothing if the autoload does not exist yet:
## tests bring up classes even without a scene tree.
static func play(name: String) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.play(name)


## An effect with pitch [param pitch] and volume [param db] for this playback.
static func play_tuned(name: String, pitch: float, db: float = 0.0) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.play(name, pitch, db)


## Ducks the music for [param seconds] seconds.
static func duck_music(seconds: float) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.duck(seconds)


## The theme of a building of kind [param building] at time of day [param time]
## (ADR-0057, decision 7; ADR-0052, decision 1): the set follows the kind, the variant
## the time of day. At night the hotel has the noir [constant THEME].
static func theme_for(
	time: TimeOfDay.Kind, building: BuildingIdentity.Kind = BuildingIdentity.Kind.HOTEL
) -> String:
	var base := THEME
	match building:
		BuildingIdentity.Kind.OFFICE:
			base = THEME_OFFICE
		BuildingIdentity.Kind.RESIDENTIAL:
			base = THEME_RESIDENTIAL
	match time:
		TimeOfDay.Kind.MORNING:
			return base + "_morning"
		TimeOfDay.Kind.DAY:
			return base + "_day"
		TimeOfDay.Kind.EVENING:
			return base + "_evening"
	return base


## Alarm motif for a building of kind [param building], specific to the kind (ADR-0057,
## decision 7), for any time of day.
static func alarm_for(building: BuildingIdentity.Kind = BuildingIdentity.Kind.HOTEL) -> String:
	match building:
		BuildingIdentity.Kind.OFFICE:
			return ALARM_OFFICE
		BuildingIdentity.Kind.RESIDENTIAL:
			return ALARM_RESIDENTIAL
	return ALARM_THEME


## Turns on the music unless it is already the same. [param pick] is which of the
## track variants: the building picks it by its seed.
static func play_music(name: String, pick: int = 0) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.play_music(name, pick)


static func stop_music() -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.stop_music()


## Music from behind a wall: behind a red door and on pause.
static func muffle_music(reason: String, on: bool) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.muffle_music(reason, on)


## World sounds from behind a wall: Otto behind a red door hears the corridor muffled.
static func muffle_world(on: bool) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.muffle_world(on)


## Weather and time of day around: the director picks the ambience loops outside and
## inside by them.
static func set_weather(weather: Weather.Kind, time: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.set_weather(weather, time)


## Ambience loops for weather [param weather]. Outside, the street and rain or wind;
## on the floors, the corridor silence and, in rain, rain behind the glass. Thunder is
## not included: it comes from lightning.
##
## The street is specific to time of day [param time] (ADR-0052, decision 8), the
## corridor silence to building kind [param building] (ADR-0055, decision 8).
static func weather_loops(
	weather: Weather.Kind,
	outdoors: bool,
	time: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT,
	building: BuildingIdentity.Kind = BuildingIdentity.Kind.HOTEL,
	hall: String = ""
) -> PackedStringArray:
	var raining := Weather.is_raining(weather)
	if outdoors:
		var outside := WIND_SNOW if Weather.is_snowing(weather) else WIND
		return PackedStringArray([city_for(time), RAIN if raining else outside])
	var inside := PackedStringArray([room_tone_of(building)])
	if raining:
		inside.append(RAIN_WINDOW)
	# The special-floor hall ambience is inside only (ADR-0057, decision 4).
	if not hall.is_empty():
		inside.append(hall)
	return inside


## Ambience of a hall with role [param role], or empty if the hall has no sound of its own.
static func hall_tone_of(role: FloorRole.Role) -> String:
	return String(HALL_TONES.get(role, ""))


## Corridor silence for a building of kind [param building].
static func room_tone_of(building: BuildingIdentity.Kind) -> String:
	match building:
		BuildingIdentity.Kind.OFFICE:
			return ROOM_TONE_OFFICE
		BuildingIdentity.Kind.RESIDENTIAL:
			return ROOM_TONE_RESIDENTIAL
	return ROOM_TONE


## The kind of building the game is in: the corridor silence follows it. [param hall] is
## the ambience of the special-floor hall Otto is at ([method hall_tone_of]).
static func set_building(building: BuildingIdentity.Kind, hall: String = "") -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.set_building(building, hall)


## The street at time of day [param time]: birds in the morning, a dense hum by day,
## quieter in the evening, the former night city at night.
static func city_for(time: TimeOfDay.Kind) -> String:
	match time:
		TimeOfDay.Kind.MORNING:
			return CITY_MORNING
		TimeOfDay.Kind.DAY:
			return CITY_DAY
		TimeOfDay.Kind.EVENING:
			return CITY_EVENING
	return CITY


## Ambience outside or from behind the glass.
static func set_outdoors(on: bool) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.set_outdoors(on)


## Thunder from a strike [param distance] meters away.
static func thunder(distance: float) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.thunder(distance)


## Sets the bus volume, 0..1. The settings call it on every slider.
static func set_level(bus: String, level: float) -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.set_level(bus, level)


## A positional source on a node: it is audible only near it.
##
## Needed by whatever sounds in its own place rather than across the whole game: there
## are five shafts in a building, and the one you stand next to should hum in your ear.
## It is created here, not in the nodes: the elevator and the escalator built it the same
## way, word for word.
## [param reach] is how far it can be heard, m.
## [param always]: the loop plays from the first frame and is never turned off: the shaft
## hum, neon. Set before entering the tree: a source that has entered no longer sees
## autoplay.
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


## A one-shot sound at [param at] (scene coordinates): audible nearby, not
## everywhere. The source is on [param host], on top of its movement, and removes itself
## when it has finished. [param pitch] and [param db] are the pitch and volume this time.
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


## Keeps a loop on or off.
##
## Assigning [member AudioStreamPlayer3D.playing] every frame is not possible: the setter
## calls [method AudioStreamPlayer3D.play] again, and of a two-second hum only the first
## three milliseconds are heard: instead of an engine you get a crackle at the
## frame rate (verified: the playback position stays at 0.003 s).
static func keep_playing(player: AudioStreamPlayer3D, on: bool) -> void:
	if on == player.playing:
		return
	if on:
		player.play()
	else:
		player.stop()


## Resets the cache. Needed by tests: they load sounds in their own order.
static func forget() -> void:
	_cache.clear()
