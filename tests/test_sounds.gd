extends GutTest

## Sound tests.
##
## The name list and the folder must match both ways: a forgotten event is silent,
## and a file nobody calls piles up in the repository — and neither one nor the other
## is visible in a frame or in the log. Every file has an author (ADR-0036).

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
	# A variant may be in WAV or OGG — the build chooses the format. Two files with
	# one name would mean the game takes one while the other is edited.
	for name: String in Sounds.names():
		var count := Sounds.variant_paths(name).size()
		assert_gt(count, 0, "sound %s has a file" % name)
		for index: int in count:
			var found := 0
			for path: String in Sounds.candidates(Sounds.variant_stem(name, index)):
				if ResourceLoader.exists(path):
					found += 1
			assert_eq(found, 1, "variant %d of sound %s is in one file" % [index + 1, name])


func test_every_variant_loads() -> void:
	for name: String in Sounds.names():
		var streams := Sounds.variants(name)
		assert_eq(streams.size(), Sounds.variant_paths(name).size(), "%s is fully readable" % name)
		for each: AudioStream in streams:
			assert_gt(each.get_length(), 0.0, "sound %s is not empty" % name)


func test_the_folder_holds_nothing_but_the_listed_sounds() -> void:
	var known := Sounds.names()
	var files := _audio_files()
	assert_gt(files.size(), 0, "the sounds folder is in place")
	for file: String in files:
		var stem := file.get_basename()
		var name := stem.get_slice(".", 0)
		assert_true(known.has(name), "sound %s is needed by someone" % stem)
		# The game would not find a variant after a gap: `name.3` without `name.2` is a dead file.
		if known.has(name):
			var stems := PackedStringArray()
			for index: int in Sounds.variant_paths(name).size():
				stems.append(Sounds.variant_stem(name, index))
			assert_true(stems.has(stem), "variant %s is visible to the game" % stem)


func test_every_file_has_its_author() -> void:
	# CC-BY requires crediting the author, and it must be done where it will be seen:
	# in credits.json for the build and in CREDITS.md, which ships with the game.
	# Parsing via Variant: `as Dictionary` on a broken file does not give null,
	# and the "is readable" check would never fire.
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CREDITS_JSON))
	assert_true(parsed is Dictionary, "credits.json is readable")
	if not parsed is Dictionary:
		return
	var credits: Dictionary = parsed
	var page := FileAccess.get_file_as_string(CREDITS_MD)
	for file: String in _audio_files():
		var stem := file.get_basename()
		assert_true(credits.has(stem), "%s: not in credits.json" % stem)
		if not credits.has(stem):
			continue
		var entry := credits[stem] as Dictionary
		for key: String in ["title", "author", "licence", "url"]:
			assert_false(str(entry.get(key, "")).is_empty(), "%s: has %s" % [stem, key])
		var licence := str(entry.get("licence", ""))
		assert_true(
			licence.begins_with("CC0") or licence.begins_with("CC-BY"),
			"%s: licence is CC0 or CC-BY, not %s" % [stem, licence]
		)
		assert_true(page.contains("`%s`" % stem), "%s: has a line in CREDITS.md" % stem)


func test_sounds_that_should_loop_do_loop() -> void:
	# A theme that cut off after twenty seconds is not "the music is quiet", it is
	# silence until the end of the game, and it can only be noticed by ear.
	for name: String in Sounds.LOOPED:
		for each: AudioStream in Sounds.variants(name):
			assert_true(_loops(each), "%s is looped" % name)


func test_one_shot_sounds_do_not_loop() -> void:
	for name: String in Sounds.names():
		if Sounds.LOOPED.has(name):
			continue
		for each: AudioStream in Sounds.variants(name):
			assert_false(_loops(each), "%s sounds once" % name)


func test_several_variants_are_drawn_on_every_play() -> void:
	# Five steps on concrete — five files: consecutive steps do not sound as one.
	assert_gt(
		Sounds.variant_paths(Sounds.STEP_CONCRETE).size(), 1, "the concrete step has variants"
	)
	assert_true(
		Sounds.stream(Sounds.STEP_CONCRETE) is AudioStreamRandomizer, "and a draw for every step"
	)
	assert_false(Sounds.stream(Sounds.SHOT) is AudioStreamRandomizer, "one file — no draw")


func test_the_building_track_is_picked_by_the_building() -> void:
	# There are several building tracks (the user's decision): the same building sounds
	# with one track, neighbouring ones with different ones.
	var count := Sounds.variants(Sounds.THEME).size()
	assert_gt(count, 1, "there are several building tracks")
	assert_eq(
		Sounds.variant(Sounds.THEME, 7),
		Sounds.variant(Sounds.THEME, 7),
		"the same building — the same one"
	)
	assert_ne(
		Sounds.variant(Sounds.THEME, 0), Sounds.variant(Sounds.THEME, 1), "neighbours — different"
	)
	assert_eq(
		Sounds.variant(Sounds.THEME, -1),
		Sounds.variant(Sounds.THEME, count - 1),
		"a seed can be anything"
	)


func test_a_loop_is_not_restarted_while_it_plays() -> void:
	# Assigning `playing = true` every physics frame calls `play()` anew,
	# and of the two-second cab hum only the first three milliseconds are heard. A second call
	# of [method Sounds.keep_playing] must leave a running loop alone — this is visible
	# in the playback object: a loop started anew would get a new one.
	var host: Node3D = add_child_autofree(Node3D.new()) as Node3D
	var player := Sounds.source(host, Sounds.ELEVATOR_HUM, 360.0)

	Sounds.keep_playing(player, true)
	assert_true(player.playing, "the loop started")
	var playback := player.get_stream_playback()
	assert_not_null(playback, "playback started")

	Sounds.keep_playing(player, true)
	assert_eq(player.get_stream_playback(), playback, "and did not restart")

	Sounds.keep_playing(player, false)
	assert_false(player.playing, "and switches off with one word")


func test_an_always_on_source_starts_by_itself() -> void:
	var host: Node3D = add_child_autofree(Node3D.new()) as Node3D
	var player := Sounds.source(host, Sounds.NEON_BUZZ, 9.0, true)
	assert_true(player.playing, "the neon hums uninvited")


## Whether the stream loops. There are two formats, and each has its own way of saying so.
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
		# In an exported build Godot sees .import, in the project — the source.
		if file.ends_with(".wav") or file.ends_with(".ogg"):
			files.append(file)
	return files
