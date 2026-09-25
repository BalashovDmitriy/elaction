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
	assert_eq(PlaceSound.step_at(false, hotel), Sounds.STEP_CARPET, "в отеле ковёр")
	assert_eq(PlaceSound.step_at(false, office), Sounds.STEP_CONCRETE, "в конторе камень")
	assert_eq(PlaceSound.step_at(true, hotel), Sounds.STEP_CONCRETE, "на крыше камень")


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


func test_a_loop_called_back_while_leaving_is_not_doubled() -> void:
	# Otto съехал с крыши и тут же вернулся: улица ещё уходила, а новая петля
	# заводилась поверх неё — старая, с убитым наплывом, звучала вполсилы до
	# конца игры, и на каждом таком возвращении их становилось больше.
	var director := AudioDirector.instance()
	if director == null:
		return
	director.set_weather(Weather.Kind.RAIN)
	director.set_outdoors(false)
	director.set_outdoors(true)
	director.set_outdoors(false)
	director.set_outdoors(true)
	assert_eq(_players_of(director, Sounds.CITY), 1, "улица звучит одна")
	assert_eq(_players_of(director, Sounds.ROOM_TONE), 1, "и тишина коридора, уходя, одна")


func test_the_street_is_heard_on_the_roof_and_at_the_exit() -> void:
	# ADR-0036, решение 5: на крыше, у выхода и в меню — улица в полную силу.
	var rules := BuildingRules.new()
	var bottom := rules.floors - 1
	var exit_x := 20.0
	var near := exit_x + PlaceSound.STREET_REACH * 0.5
	var far := exit_x + PlaceSound.STREET_REACH * 2.0
	assert_true(PlaceSound.hears_street(rules, BuildingRules.ROOF, far, exit_x), "на крыше")
	assert_true(PlaceSound.hears_street(rules, bottom, near, exit_x), "у выхода")
	assert_false(PlaceSound.hears_street(rules, bottom, far, exit_x), "в глубине нижнего этажа")
	assert_false(PlaceSound.hears_street(rules, 0, exit_x, exit_x), "на этаже — из-за стекла")


func test_the_thunder_of_a_gone_city_does_not_arrive() -> void:
	# Гром ждёт своей задержки на таймере дерева, а не у молнии: из меню или
	# прежнего здания он приходил в следующее, хоть там и ясная ночь.
	var director := AudioDirector.instance()
	if director == null:
		return
	director.set_weather(Weather.Kind.RAIN)
	director.thunder(0.0)
	await wait_seconds(AudioDirector.THUNDER_DELAY.x + 0.2)
	assert_true(_rumbling(director), "гром пришёл за вспышкой")
	director.reset()
	director.thunder(0.0)
	director.set_weather(Weather.Kind.CLEAR)
	await wait_seconds(AudioDirector.THUNDER_DELAY.x + 0.2)
	assert_false(_rumbling(director), "а к новому городу — нет")


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


## Сколько живых источников директора играют петлю [param name].
func _players_of(director: AudioDirector, name: String) -> int:
	var stream := Sounds.stream(name)
	var count := 0
	for child: Node in director.get_children():
		var player := child as AudioStreamPlayer
		if player != null and player.stream == stream and not player.is_queued_for_deletion():
			count += 1
	return count


## Звучит ли сейчас ближний раскат.
func _rumbling(director: AudioDirector) -> bool:
	var near := Sounds.stream(Sounds.THUNDER_NEAR)
	for child: Node in director.get_children():
		var player := child as AudioStreamPlayer
		if player != null and player.stream == near and player.playing:
			return true
	return false
