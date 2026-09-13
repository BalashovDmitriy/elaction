extends GutTest

## Тесты звука.
##
## Проверяется то же правило, что у спрайтов: список имён и папка обязаны
## совпадать в обе стороны. Забытое событие молчит, а синтезированный, но
## никому не нужный звук копится в репозитории — и ни то, ни другое не видно
## ни в кадре, ни в логе (ADR-0012, пункт 1).


func before_each() -> void:
	Sounds.forget()


func test_every_sound_has_a_file() -> void:
	for name: String in Sounds.names():
		var path := Sounds.path_of(name)
		assert_true(ResourceLoader.exists(path), "синтезирован звук %s" % path)


func test_every_sound_loads() -> void:
	for name: String in Sounds.names():
		var stream := Sounds.stream(name)
		assert_not_null(stream, "звук %s читается" % name)
		if stream == null:
			continue
		assert_gt(stream.get_length(), 0.0, "звук %s не пустой" % name)


func test_the_folder_holds_nothing_but_the_listed_sounds() -> void:
	var known := Sounds.names()
	var folder := DirAccess.open(Sounds.DIR)
	assert_not_null(folder, "папка звуков на месте")
	if folder == null:
		return

	for file: String in folder.get_files():
		# Godot в экспортированной сборке видит .import, в проекте — исходник.
		if not file.ends_with(".wav"):
			continue
		var name := file.get_basename()
		assert_true(known.has(name), "звук %s кому-то нужен" % name)


func test_sounds_that_should_loop_do_loop() -> void:
	# Тема, оборвавшаяся через пять секунд, — это не «музыка тихая», это тишина
	# до конца партии, и заметить её можно только на слух.
	for name: String in Sounds.LOOPED:
		var stream := Sounds.stream(name) as AudioStreamWAV
		assert_not_null(stream, "звук %s читается как WAV" % name)
		if stream == null:
			continue
		assert_ne(stream.loop_mode, AudioStreamWAV.LOOP_DISABLED, "%s зациклен" % name)


func test_one_shot_sounds_do_not_loop() -> void:
	for name: String in Sounds.EFFECTS:
		if Sounds.LOOPED.has(name):
			continue
		var stream := Sounds.stream(name) as AudioStreamWAV
		if stream == null:
			continue
		assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_DISABLED, "%s звучит один раз" % name)


func test_the_mixer_has_its_three_buses() -> void:
	# Отдельная шина у музыки нужна затем, чтобы её можно было приглушить,
	# не выключая выстрелы (ADR-0012, пункт 7).
	for bus: String in [Sounds.MASTER_BUS, Sounds.MUSIC_BUS, Sounds.SFX_BUS]:
		assert_gt(AudioServer.get_bus_index(bus), -1, "шина %s есть" % bus)


func test_music_starts_and_stops() -> void:
	var director := AudioDirector.instance()
	assert_not_null(director, "автолоад звука поднят")
	if director == null:
		return

	director.play_music(Sounds.THEME)
	assert_eq(director.music_name(), Sounds.THEME, "тема играет")
	director.stop_music()
	assert_eq(director.music_name(), "", "и замолкает")


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
