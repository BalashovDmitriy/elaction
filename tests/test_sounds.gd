extends GutTest

## Тесты звука.
##
## Список имён и папка обязаны совпадать в обе стороны: забытое событие молчит,
## а файл, который никто не зовёт, копится в репозитории, — и ни то, ни другое
## не видно ни в кадре, ни в логе. У каждого файла — автор (ADR-0036).

const CREDITS_JSON := "res://assets/audio/credits.json"
const CREDITS_MD := "res://CREDITS.md"


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


func test_every_sound_has_a_file_and_each_variant_exactly_one() -> void:
	# Вариант может лежать в WAV или OGG — формат выбирает сборка. Два файла с
	# одним именем означали бы, что игра берёт один, а правят другой.
	for name: String in Sounds.names():
		var count := Sounds.variant_paths(name).size()
		assert_gt(count, 0, "у звука %s есть файл" % name)
		for index: int in count:
			var found := 0
			for path: String in Sounds.candidates(Sounds.variant_stem(name, index)):
				if ResourceLoader.exists(path):
					found += 1
			assert_eq(found, 1, "вариант %d звука %s лежит в одном файле" % [index + 1, name])


func test_every_variant_loads() -> void:
	for name: String in Sounds.names():
		var streams := Sounds.variants(name)
		assert_eq(streams.size(), Sounds.variant_paths(name).size(), "%s читается весь" % name)
		for each: AudioStream in streams:
			assert_gt(each.get_length(), 0.0, "звук %s не пустой" % name)


func test_the_folder_holds_nothing_but_the_listed_sounds() -> void:
	var known := Sounds.names()
	var files := _audio_files()
	assert_gt(files.size(), 0, "папка звуков на месте")
	for file: String in files:
		var stem := file.get_basename()
		var name := stem.get_slice(".", 0)
		assert_true(known.has(name), "звук %s кому-то нужен" % stem)
		# Вариант за пропуском игра бы не нашла: `имя.3` без `имя.2` — мёртвый файл.
		if known.has(name):
			var stems := PackedStringArray()
			for index: int in Sounds.variant_paths(name).size():
				stems.append(Sounds.variant_stem(name, index))
			assert_true(stems.has(stem), "вариант %s виден игре" % stem)


func test_every_file_has_its_author() -> void:
	# CC-BY требует указать автора, и указан он должен быть там, где его увидят:
	# в credits.json для сборки и в CREDITS.md, который едет с игрой.
	var credits := JSON.parse_string(FileAccess.get_file_as_string(CREDITS_JSON)) as Dictionary
	assert_not_null(credits, "credits.json читается")
	if credits == null:
		return
	var page := FileAccess.get_file_as_string(CREDITS_MD)
	for file: String in _audio_files():
		var stem := file.get_basename()
		assert_true(credits.has(stem), "%s: нет в credits.json" % stem)
		if not credits.has(stem):
			continue
		var entry := credits[stem] as Dictionary
		for key: String in ["title", "author", "licence", "url"]:
			assert_false(str(entry.get(key, "")).is_empty(), "%s: есть %s" % [stem, key])
		var licence := str(entry.get("licence", ""))
		assert_true(
			licence.begins_with("CC0") or licence.begins_with("CC-BY"),
			"%s: лицензия CC0 или CC-BY, а не %s" % [stem, licence]
		)
		assert_true(page.contains("`%s`" % stem), "%s: есть строка в CREDITS.md" % stem)


func test_sounds_that_should_loop_do_loop() -> void:
	# Тема, оборвавшаяся через двадцать секунд, — это не «музыка тихая», это
	# тишина до конца партии, и заметить её можно только на слух.
	for name: String in Sounds.LOOPED:
		for each: AudioStream in Sounds.variants(name):
			assert_true(_loops(each), "%s зациклен" % name)


func test_one_shot_sounds_do_not_loop() -> void:
	for name: String in Sounds.names():
		if Sounds.LOOPED.has(name):
			continue
		for each: AudioStream in Sounds.variants(name):
			assert_false(_loops(each), "%s звучит один раз" % name)


func test_several_variants_are_drawn_on_every_play() -> void:
	# Пять шагов по бетону — пять файлов: шаги подряд не звучат одним.
	assert_gt(Sounds.variant_paths(Sounds.STEP_CONCRETE).size(), 1, "у шага по бетону варианты")
	assert_true(
		Sounds.stream(Sounds.STEP_CONCRETE) is AudioStreamRandomizer, "и жребий на каждый шаг"
	)
	assert_false(Sounds.stream(Sounds.SHOT) is AudioStreamRandomizer, "один файл — без жребия")


func test_the_building_track_is_picked_by_the_building() -> void:
	# Треков здания несколько (решение пользователя): одно и то же здание звучит
	# одним треком, соседние — разными.
	var count := Sounds.variants(Sounds.THEME).size()
	assert_gt(count, 1, "треков здания несколько")
	assert_eq(
		Sounds.variant(Sounds.THEME, 7), Sounds.variant(Sounds.THEME, 7), "то же здание — тот же"
	)
	assert_ne(Sounds.variant(Sounds.THEME, 0), Sounds.variant(Sounds.THEME, 1), "соседние — разные")
	assert_eq(
		Sounds.variant(Sounds.THEME, -1),
		Sounds.variant(Sounds.THEME, count - 1),
		"сид бывает любым"
	)


func test_a_loop_is_not_restarted_while_it_plays() -> void:
	# Присваивание `playing = true` каждый физический кадр зовёт `play()` заново,
	# и от двухсекундного гула кабины слышно первые три миллисекунды. Второй вызов
	# [method Sounds.keep_playing] обязан оставить идущую петлю в покое — видно это
	# по объекту воспроизведения: заведённая заново петля получила бы новый.
	var host: Node3D = add_child_autofree(Node3D.new()) as Node3D
	var player := Sounds.source(host, Sounds.ELEVATOR_HUM, 360.0)

	Sounds.keep_playing(player, true)
	assert_true(player.playing, "петля пошла")
	var playback := player.get_stream_playback()
	assert_not_null(playback, "воспроизведение началось")

	Sounds.keep_playing(player, true)
	assert_eq(player.get_stream_playback(), playback, "и не завелась заново")

	Sounds.keep_playing(player, false)
	assert_false(player.playing, "а выключается с одного слова")


func test_an_always_on_source_starts_by_itself() -> void:
	var host: Node3D = add_child_autofree(Node3D.new()) as Node3D
	var player := Sounds.source(host, Sounds.NEON_BUZZ, 9.0, true)
	assert_true(player.playing, "неон гудит без приглашения")


func _loops(stream: AudioStream) -> bool:
	var wav := stream as AudioStreamWAV
	if wav != null:
		return wav.loop_mode != AudioStreamWAV.LOOP_DISABLED
	var vorbis := stream as AudioStreamOggVorbis
	return vorbis != null and vorbis.loop


func _audio_files() -> PackedStringArray:
	var files := PackedStringArray()
	var folder := DirAccess.open(Sounds.DIR)
	if folder == null:
		return files
	for file: String in folder.get_files():
		# Godot в экспортированной сборке видит .import, в проекте — исходник.
		if file.ends_with(".wav") or file.ends_with(".ogg"):
			files.append(file)
	return files
