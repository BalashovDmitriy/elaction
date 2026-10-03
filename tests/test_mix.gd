extends GutTest

## Mix tests (ADR-0036): buses, track crossfade, ducking, ambience by weather and
## place, thunder after lightning, steps on the floor.


func before_each() -> void:
	Sounds.forget()
	var director := AudioDirector.instance()
	if director != null:
		director.reset()


func after_all() -> void:
	var director := AudioDirector.instance()
	if director != null:
		director.stop_music()
		director.reset()


func test_the_mixer_has_its_buses() -> void:
	# Music has a separate bus so that it can be ducked without muting
	# shots; ambience is a child bus of effects, driven by the same slider.
	for bus: String in [Sounds.MASTER_BUS, Sounds.MUSIC_BUS, Sounds.SFX_BUS, Sounds.AMBIENCE_BUS]:
		assert_gt(AudioServer.get_bus_index(bus), -1, "bus %s exists" % bus)
	var ambience := AudioServer.get_bus_index(Sounds.AMBIENCE_BUS)
	assert_eq(
		String(AudioServer.get_bus_send(ambience)), Sounds.SFX_BUS, "ambience goes to the effects"
	)
	for bus: String in [Sounds.MUSIC_BUS, Sounds.AMBIENCE_BUS]:
		var index := AudioServer.get_bus_index(bus)
		assert_true(
			(
				AudioServer.get_bus_effect(index, AudioDirector.MUFFLE_EFFECT)
				is AudioEffectLowPassFilter
			),
			"bus %s has a 'behind the wall' filter" % bus
		)
		assert_true(
			AudioServer.get_bus_effect(index, AudioDirector.DUCK_EFFECT) is AudioEffectAmplify,
			"and a volume knob for ducking"
		)


func test_music_starts_and_stops() -> void:
	var director := AudioDirector.instance()
	assert_not_null(director, "the sound autoload is up")
	if director == null:
		return

	director.play_music(Sounds.THEME)
	assert_eq(director.music_name(), Sounds.THEME, "the theme plays")
	director.stop_music()
	assert_eq(director.music_name(), "", "and goes quiet")


func test_the_alarm_fades_in_instead_of_cutting_the_theme() -> void:
	var director := AudioDirector.instance()
	if director == null:
		return
	director.play_music(Sounds.THEME)
	director.play_music(Sounds.ALARM_THEME)
	assert_eq(director.music_name(), Sounds.ALARM_THEME, "the alarm plays")
	var playing := 0
	for player: Node in director.get_children():
		var music := player as AudioStreamPlayer
		if music != null and music.bus == Sounds.MUSIC_BUS and music.playing:
			playing += 1
	assert_eq(playing, 2, "and the theme still fades out under it")
	director.stop_music()


func test_the_same_building_does_not_restart_its_track() -> void:
	var director := AudioDirector.instance()
	if director == null:
		return
	director.play_music(Sounds.THEME, 3)
	var first := director.music_stream()
	director.play_music(Sounds.THEME, 3)
	assert_eq(director.music_stream(), first, "the same track is not restarted")
	director.play_music(Sounds.THEME, 4)
	assert_ne(director.music_stream(), first, "another building's track does start")
	director.stop_music()


func test_music_stays_behind_the_wall_while_any_reason_holds() -> void:
	# A pause in the middle of a visit to a red door: unpausing does not bring the sound back
	# while Otto is behind the door.
	var director := AudioDirector.instance()
	if director == null:
		return
	director.muffle_music(Sounds.MUFFLE_DOOR, true)
	director.muffle_music(Sounds.MUFFLE_PAUSE, true)
	director.muffle_music(Sounds.MUFFLE_PAUSE, false)
	assert_true(director.music_muffled(), "muffled behind the door, also after a pause")
	director.muffle_music(Sounds.MUFFLE_DOOR, false)
	assert_false(director.music_muffled(), "stepped out - the sound is back")


func test_the_weather_sounds_outside_and_behind_the_glass() -> void:
	var director := AudioDirector.instance()
	if director == null:
		return
	director.set_outdoors(true)
	director.set_weather(Weather.Kind.RAIN)
	assert_eq(_sorted(director.ambience()), _sorted([Sounds.CITY, Sounds.RAIN]), "rain on the roof")
	director.set_outdoors(false)
	assert_eq(
		_sorted(director.ambience()),
		_sorted([Sounds.ROOM_TONE, Sounds.RAIN_WINDOW]),
		"on a floor - rain behind glass"
	)
	director.set_weather(Weather.Kind.CLEAR)
	assert_eq(
		director.ambience(), PackedStringArray([Sounds.ROOM_TONE]), "on a clear night - silence"
	)
	director.set_outdoors(true)
	assert_eq(
		_sorted(director.ambience()), _sorted([Sounds.CITY, Sounds.WIND]), "and wind on the roof"
	)


## Any weather, time of day, building kind and special floor hall: the ambience loop
## is looped. The street's morning, day and evening and the M24o halls played once and went silent.
func test_every_weather_sounds_with_existing_loops() -> void:
	var halls: Array[String] = [""]
	for tone: String in Sounds.HALL_TONES.values():
		halls.append(tone)
	for weather: Weather.Kind in Weather.Kind.values():
		for outdoors: bool in [true, false]:
			for time: TimeOfDay.Kind in TimeOfDay.Kind.values():
				for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
					for hall: String in halls:
						for name: String in Sounds.weather_loops(
							weather, outdoors, time, kind, hall
						):
							assert_true(
								Sounds.LOOPED.has(name), "%s of the ambience is looped" % name
							)
							assert_true(Sounds.AMBIENCE.has(name), "%s is ambience" % name)


func test_thunder_follows_the_flash_by_distance() -> void:
	assert_almost_eq(AudioDirector.thunder_delay(343.0), 1.0, 0.001, "a kilometre in three seconds")
	assert_eq(AudioDirector.thunder_delay(50000.0), AudioDirector.THUNDER_DELAY.y, "not infinite")
	assert_eq(
		AudioDirector.thunder_delay(0.0), AudioDirector.THUNDER_DELAY.x, "and not before the flash"
	)


func test_every_lightning_series_brings_thunder() -> void:
	var lightning: Lightning = add_child_autofree(Lightning.new()) as Lightning
	lightning.setup(3, Vector2(0.0, 30.0), 0.0)
	var seen := 0
	for step: int in 3000:
		var before := lightning.last_distance
		lightning.advance(0.01)
		if lightning.last_distance != before:
			seen += 1
			assert_gt(lightning.last_distance, 0.0, "a bolt struck somewhere")
	assert_gt(seen, 0, "thunder rolled at least once in half a minute")


func test_the_step_sounds_the_floor() -> void:
	var hotel := BuildingIdentity.new()
	hotel.kind = BuildingIdentity.Kind.HOTEL
	var office := BuildingIdentity.new()
	office.kind = BuildingIdentity.Kind.OFFICE
	assert_eq(PlaceSound.step_at(false, hotel), Sounds.STEP_CARPET, "carpet in the hotel")
	assert_eq(PlaceSound.step_at(false, office), Sounds.STEP_CONCRETE, "stone in the office")
	assert_eq(PlaceSound.step_at(true, hotel), Sounds.STEP_CONCRETE, "stone on the roof")


func test_silence_mutes_the_bus_instead_of_going_to_minus_infinity() -> void:
	var director := AudioDirector.instance()
	if director == null:
		return

	director.set_level(Sounds.SFX_BUS, 0.0)
	var index := AudioServer.get_bus_index(Sounds.SFX_BUS)
	assert_true(AudioServer.is_bus_mute(index), "zero is a muted bus")

	director.set_level(Sounds.SFX_BUS, 1.0)
	assert_false(AudioServer.is_bus_mute(index), "and it unmutes again")
	assert_almost_eq(director.level_of(Sounds.SFX_BUS), 1.0, 0.001)


func test_a_loop_called_back_while_leaving_is_not_doubled() -> void:
	# Otto rode off the roof and came right back: the street was still fading out, and a new loop
	# started over it — the old one, with its fade killed, played at half strength until the
	# end of the game, and with every such return there were more of them.
	var director := AudioDirector.instance()
	if director == null:
		return
	director.set_weather(Weather.Kind.RAIN)
	director.set_outdoors(false)
	director.set_outdoors(true)
	director.set_outdoors(false)
	director.set_outdoors(true)
	assert_eq(_players_of(director, Sounds.CITY), 1, "the street plays once")
	assert_eq(
		_players_of(director, Sounds.ROOM_TONE),
		1,
		"and the corridor silence, leaving, is a single one"
	)


func test_the_street_is_heard_on_the_roof_and_at_the_exit() -> void:
	# ADR-0036, decision 5: on the roof, at the exit and in the menu — the street at full strength.
	var rules := BuildingRules.new()
	var bottom := rules.floors - 1
	var exit_x := 20.0
	var near := exit_x + PlaceSound.STREET_REACH * 0.5
	var far := exit_x + PlaceSound.STREET_REACH * 2.0
	assert_true(PlaceSound.hears_street(rules, BuildingRules.ROOF, far, exit_x), "on the roof")
	assert_true(PlaceSound.hears_street(rules, bottom, near, exit_x), "at the exit")
	assert_false(PlaceSound.hears_street(rules, bottom, far, exit_x), "deep in the bottom floor")
	assert_false(PlaceSound.hears_street(rules, 0, exit_x, exit_x), "on a floor - through glass")


func test_the_thunder_of_a_gone_city_does_not_arrive() -> void:
	# Thunder waits for its delay on a tree timer, not at the lightning: from the menu or
	# a previous building it came into the next one, even though it is a clear night there.
	var director := AudioDirector.instance()
	if director == null:
		return
	director.set_weather(Weather.Kind.RAIN)
	director.thunder(0.0)
	await wait_seconds(AudioDirector.THUNDER_DELAY.x + 0.2)
	assert_true(_rumbling(director), "thunder followed the flash")
	director.reset()
	director.thunder(0.0)
	director.set_weather(Weather.Kind.CLEAR)
	await wait_seconds(AudioDirector.THUNDER_DELAY.x + 0.2)
	assert_false(_rumbling(director), "but not for a new city")


func test_the_shaft_hum_rides_the_shaft_with_otto() -> void:
	# The source stays level with Otto, but does not go beyond the floors of its shaft.
	var hums: ShaftHums = add_child_autofree(ShaftHums.new()) as ShaftHums
	var shaft := BuildingPlan.ShaftSpot.new()
	shaft.x = 4.0
	hums.add(shaft, 30.0, 10.0)
	hums.follow(20.0)
	assert_almost_eq(hums.height_of(0), 20.0, 0.001, "level with Otto")
	hums.follow(50.0)
	assert_almost_eq(hums.height_of(0), 30.0, 0.001, "not above the shaft")
	hums.follow(-5.0)
	assert_almost_eq(hums.height_of(0), 10.0, 0.001, "and not below")


func _sorted(names: Variant) -> PackedStringArray:
	var list := PackedStringArray(names)
	list.sort()
	return list


## How many live director sources are playing loop [param name].
func _players_of(director: AudioDirector, name: String) -> int:
	var stream := Sounds.stream(name)
	var count := 0
	for child: Node in director.get_children():
		var player := child as AudioStreamPlayer
		if player != null and player.stream == stream and not player.is_queued_for_deletion():
			count += 1
	return count


## Whether a near clap is playing now.
func _rumbling(director: AudioDirector) -> bool:
	var near := Sounds.stream(Sounds.THUNDER_NEAR)
	for child: Node in director.get_children():
		var player := child as AudioStreamPlayer
		if player != null and player.stream == near and player.playing:
			return true
	return false


## The bus effect [param name] plays into: the voice that got it
## last. Voices are taken in a round, so the search goes from the end of the round.
func _bus_of_voice(director: AudioDirector, name: String) -> String:
	var stream := Sounds.stream(name)
	for child: Node in director.get_children():
		var voice := child as AudioStreamPlayer
		if voice != null and voice.stream == stream:
			return String(voice.bus)
	return ""


## Whether bus [param bus] is heard from behind the wall: whether the "behind the wall" filter is on
## it or on any bus it feeds into, up to the master.
func _behind_the_wall(bus: String) -> bool:
	var index := AudioServer.get_bus_index(bus)
	while index > 0:
		for effect: int in AudioServer.get_bus_effect_count(index):
			var filter := AudioServer.get_bus_effect(index, effect) as AudioEffectLowPassFilter
			if filter != null and AudioServer.is_bus_effect_enabled(index, effect):
				return true
		index = AudioServer.get_bus_index(AudioServer.get_bus_send(index))
	return false


## Otto behind a red door: the corridor is dull, but the menu and the document jingle are not.
## A menu click on pause and a jingle that plays right at the exit are not
## corridor sounds, and muffling them along with it would mean muffling the interface itself.
func test_the_red_door_muffles_the_corridor_but_not_the_interface() -> void:
	var director := AudioDirector.instance()
	if director == null:
		return
	director.muffle_world(true)
	for name: String in [Sounds.UI_SELECT, Sounds.UI_MOVE, Sounds.DOCUMENT, Sounds.SHOT]:
		director.play(name)

	for name: String in [Sounds.UI_SELECT, Sounds.UI_MOVE, Sounds.DOCUMENT]:
		var bus := _bus_of_voice(director, name)
		assert_eq(bus, Sounds.INTERFACE_BUS, "%s goes to the interface bus" % name)
		assert_false(_behind_the_wall(bus), "%s is not muffled behind the door" % name)
	var shot := _bus_of_voice(director, Sounds.SHOT)
	assert_eq(shot, Sounds.SFX_BUS, "a shot is a world sound")
	assert_true(_behind_the_wall(shot), "the corridor behind the door is muffled")
	assert_true(_behind_the_wall(Sounds.AMBIENCE_BUS), "and the ambience - it goes to the effects")

	director.muffle_world(false)
	await wait_seconds(AudioDirector.MUFFLE_TIME + 0.2)
	assert_false(_behind_the_wall(shot), "stepped out - the corridor is audible")


## The interface got its own bus for the door, not for a slider: its volume
## is still set by the effects slider, and it goes into the master bypassing effects.
func test_the_interface_follows_the_effects_volume() -> void:
	var director := AudioDirector.instance()
	if director == null:
		return
	var interface := AudioServer.get_bus_index(Sounds.INTERFACE_BUS)
	assert_gt(interface, -1, "the interface bus exists")
	assert_eq(String(AudioServer.get_bus_send(interface)), Sounds.MASTER_BUS, "goes to the master")
	director.set_level(Sounds.SFX_BUS, 0.5)
	assert_almost_eq(
		AudioServer.get_bus_volume_db(interface), linear_to_db(0.5), 0.01, "effects volume"
	)
	director.set_level(Sounds.SFX_BUS, 0.0)
	assert_true(AudioServer.is_bus_mute(interface), "effects are off - and so is the interface")
	director.set_level(Sounds.SFX_BUS, 1.0)
	assert_false(AudioServer.is_bus_mute(interface))
	assert_almost_eq(AudioServer.get_bus_volume_db(interface), 0.0, 0.01)
