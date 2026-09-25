extends GutTest

## Тесты микса (ADR-0036): шины, наплыв треков, приглушение, фон по погоде и
## месту, гром за молнией, шаг по полу.


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
	# Отдельная шина у музыки — чтобы её можно было приглушить, не выключая
	# выстрелы; фон — дочерняя шина эффектов, его ведёт тот же ползунок.
	for bus: String in [Sounds.MASTER_BUS, Sounds.MUSIC_BUS, Sounds.SFX_BUS, Sounds.AMBIENCE_BUS]:
		assert_gt(AudioServer.get_bus_index(bus), -1, "шина %s есть" % bus)
	var ambience := AudioServer.get_bus_index(Sounds.AMBIENCE_BUS)
	assert_eq(String(AudioServer.get_bus_send(ambience)), Sounds.SFX_BUS, "фон идёт в эффекты")
	for bus: String in [Sounds.MUSIC_BUS, Sounds.AMBIENCE_BUS]:
		var index := AudioServer.get_bus_index(bus)
		assert_true(
			(
				AudioServer.get_bus_effect(index, AudioDirector.MUFFLE_EFFECT)
				is AudioEffectLowPassFilter
			),
			"у шины %s есть фильтр «из-за стены»" % bus
		)
		assert_true(
			AudioServer.get_bus_effect(index, AudioDirector.DUCK_EFFECT) is AudioEffectAmplify,
			"и ручка громкости для приглушения"
		)


func test_music_starts_and_stops() -> void:
	var director := AudioDirector.instance()
	assert_not_null(director, "автолоад звука поднят")
	if director == null:
		return

	director.play_music(Sounds.THEME)
	assert_eq(director.music_name(), Sounds.THEME, "тема играет")
	director.stop_music()
	assert_eq(director.music_name(), "", "и замолкает")


func test_the_alarm_fades_in_instead_of_cutting_the_theme() -> void:
	var director := AudioDirector.instance()
	if director == null:
		return
	director.play_music(Sounds.THEME)
	director.play_music(Sounds.ALARM_THEME)
	assert_eq(director.music_name(), Sounds.ALARM_THEME, "играет тревога")
	var playing := 0
	for player: Node in director.get_children():
		var music := player as AudioStreamPlayer
		if music != null and music.bus == Sounds.MUSIC_BUS and music.playing:
			playing += 1
	assert_eq(playing, 2, "а тема ещё уходит под неё")
	director.stop_music()


func test_the_same_building_does_not_restart_its_track() -> void:
	var director := AudioDirector.instance()
	if director == null:
		return
	director.play_music(Sounds.THEME, 3)
	var first := director.music_stream()
	director.play_music(Sounds.THEME, 3)
	assert_eq(director.music_stream(), first, "тот же трек не заводится заново")
	director.play_music(Sounds.THEME, 4)
	assert_ne(director.music_stream(), first, "трек другого здания — заводится")
	director.stop_music()


func test_music_stays_behind_the_wall_while_any_reason_holds() -> void:
	# Пауза посреди визита в красную дверь: снятие паузы не возвращает звук,
	# пока Otto за дверью.
	var director := AudioDirector.instance()
	if director == null:
		return
	director.muffle_music(Sounds.MUFFLE_DOOR, true)
	director.muffle_music(Sounds.MUFFLE_PAUSE, true)
	director.muffle_music(Sounds.MUFFLE_PAUSE, false)
	assert_true(director.music_muffled(), "за дверью глухо и после паузы")
	director.muffle_music(Sounds.MUFFLE_DOOR, false)
	assert_false(director.music_muffled(), "вышел — звук вернулся")


func test_the_weather_sounds_outside_and_behind_the_glass() -> void:
	var director := AudioDirector.instance()
	if director == null:
		return
	director.set_outdoors(true)
	director.set_weather(Weather.Kind.RAIN)
	assert_eq(_sorted(director.ambience()), _sorted([Sounds.CITY, Sounds.RAIN]), "на крыше дождь")
	director.set_outdoors(false)
	assert_eq(
		_sorted(director.ambience()),
		_sorted([Sounds.ROOM_TONE, Sounds.RAIN_WINDOW]),
		"на этаже — дождь за стеклом"
	)
	director.set_weather(Weather.Kind.CLEAR)
	assert_eq(director.ambience(), PackedStringArray([Sounds.ROOM_TONE]), "в ясную ночь — тишина")
	director.set_outdoors(true)
	assert_eq(_sorted(director.ambience()), _sorted([Sounds.CITY, Sounds.WIND]), "а на крыше ветер")


func test_every_weather_sounds_with_existing_loops() -> void:
	for weather: Weather.Kind in Weather.Kind.values():
		for outdoors: bool in [true, false]:
			for name: String in Sounds.weather_loops(weather, outdoors):
				assert_true(Sounds.LOOPED.has(name), "%s фона зациклен" % name)
				assert_true(Sounds.AMBIENCE.has(name), "%s — фон" % name)


func test_thunder_follows_the_flash_by_distance() -> void:
	assert_almost_eq(AudioDirector.thunder_delay(343.0), 1.0, 0.001, "километр за три секунды")
	assert_eq(AudioDirector.thunder_delay(50000.0), AudioDirector.THUNDER_DELAY.y, "не бесконечно")
	assert_eq(
		AudioDirector.thunder_delay(0.0), AudioDirector.THUNDER_DELAY.x, "и не раньше вспышки"
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
			assert_gt(lightning.last_distance, 0.0, "разряд где-то ударил")
	assert_gt(seen, 0, "за полминуты грянуло хоть раз")


func test_the_step_sounds_the_floor() -> void:
	var hotel := BuildingIdentity.new()
	hotel.kind = BuildingIdentity.Kind.HOTEL
	var office := BuildingIdentity.new()
	office.kind = BuildingIdentity.Kind.OFFICE
	assert_eq(GreyboxLevel.step_sound_at(false, hotel), Sounds.STEP_CARPET, "в отеле ковёр")
	assert_eq(GreyboxLevel.step_sound_at(false, office), Sounds.STEP_CONCRETE, "в конторе камень")
	assert_eq(GreyboxLevel.step_sound_at(true, hotel), Sounds.STEP_CONCRETE, "на крыше камень")


func test_silence_mutes_the_bus_instead_of_going_to_minus_infinity() -> void:
	var director := AudioDirector.instance()
	if director == null:
		return

	director.set_level(Sounds.SFX_BUS, 0.0)
	var index := AudioServer.get_bus_index(Sounds.SFX_BUS)
	assert_true(AudioServer.is_bus_mute(index), "ноль — это выключенная шина")

	director.set_level(Sounds.SFX_BUS, 1.0)
	assert_false(AudioServer.is_bus_mute(index), "и она включается обратно")
	assert_almost_eq(director.level_of(Sounds.SFX_BUS), 1.0, 0.001)


## Зациклен ли поток. Форматов два, и у каждого свой способ об этом сказать.


func test_the_shaft_hum_rides_the_shaft_with_otto() -> void:
	# Источник стоит вровень с Otto, но не выходит за этажи своей шахты.
	var hums: ShaftHums = add_child_autofree(ShaftHums.new()) as ShaftHums
	var shaft := BuildingPlan.ShaftSpot.new()
	shaft.x = 4.0
	hums.add(shaft, 30.0, 10.0)
	hums.follow(20.0)
	assert_almost_eq(hums.height_of(0), 20.0, 0.001, "вровень с Otto")
	hums.follow(50.0)
	assert_almost_eq(hums.height_of(0), 30.0, 0.001, "не выше шахты")
	hums.follow(-5.0)
	assert_almost_eq(hums.height_of(0), 10.0, 0.001, "и не ниже")


func _sorted(names: Variant) -> PackedStringArray:
	var list := PackedStringArray(names)
	list.sort()
	return list
