extends GutTest

## Interface tests: settings, translations, the score in the HUD and a life for points.
##
## Everything checked here is rules, not drawing: whether the settings were saved,
## whether a string exists in both languages, what a number looks like and when an
## extra life arrives. There is no point bringing up a frame for that.

const TEMP := "user://test_settings.cfg"

## Where translation keys come from: the same table the game takes them from.
const STRINGS := "res://assets/i18n/ui.csv"

const HUD_SCENE := preload("res://src/ui/hud.tscn")


func after_each() -> void:
	if FileAccess.file_exists(TEMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))


# --- Settings ----------------------------------------------------------------


func test_settings_survive_a_restart() -> void:
	var settings := GameSettings.new()
	settings.master = 0.4
	settings.music = 0.1
	settings.sfx = 0.9
	settings.locale = "en"
	settings.window_mode = DisplayModes.Mode.BORDERLESS
	settings.resolution = Vector2i(2560, 1440)
	settings.save_to(TEMP)

	var loaded := GameSettings.load_from(TEMP)
	assert_almost_eq(loaded.master, 0.4, 0.001)
	assert_almost_eq(loaded.music, 0.1, 0.001)
	assert_almost_eq(loaded.sfx, 0.9, 0.001)
	assert_eq(loaded.locale, "en")
	assert_eq(loaded.window_mode, DisplayModes.Mode.BORDERLESS)
	assert_eq(loaded.resolution, Vector2i(2560, 1440))


## Settings before M22 stored a "full screen" flag: it becomes a window mode.
func test_the_old_fullscreen_flag_becomes_a_window_mode() -> void:
	var old := ConfigFile.new()
	old.set_value(GameSettings.SECTION, "fullscreen", true)
	old.save(TEMP)
	assert_eq(GameSettings.load_from(TEMP).window_mode, DisplayModes.Mode.FULLSCREEN)


## Window sizes — only those that fit on the monitor; 4K — on a 4K screen.
func test_window_sizes_fit_the_screen() -> void:
	var full_hd := DisplayModes.available(Vector2i(1920, 1080))
	assert_eq(full_hd[-1], Vector2i(1920, 1080), "on FullHD nothing above FullHD is offered")
	assert_has(
		DisplayModes.available(Vector2i(3840, 2160)), Vector2i(3840, 2160), "4K is offered on 4K"
	)
	assert_eq(DisplayModes.available(Vector2i(800, 600)).size(), 1, "on a tiny one — at least one")
	assert_eq(
		DisplayModes.nearest(Vector2i(3840, 2160), Vector2i(1920, 1080)),
		Vector2i(1920, 1080),
		"the monitor changed — the size shrinks to the new one"
	)


## A 4K monitor with a taskbar: the work area is below 2160, yet 4K is in the list and
## goes full screen without a border. The list used to be built from the work area,
## and 4K disappeared (user's remark, M24b).
func test_4k_window_on_a_4k_screen_with_a_taskbar() -> void:
	var screen := Rect2i(0, 0, 3840, 2160)
	var usable := Rect2i(0, 0, 3840, 2112)
	assert_has(DisplayModes.available(screen.size), Vector2i(3840, 2160), "4K in the list")
	var frame := DisplayModes.windowed_rect(Vector2i(3840, 2160), screen, usable)
	assert_eq(frame, screen, "a 4K window — full screen")
	assert_false(
		DisplayModes.framed(frame, usable), "no frame: with it the title would go off the edge"
	)
	var small := DisplayModes.windowed_rect(Vector2i(1920, 1080), screen, usable)
	assert_true(DisplayModes.framed(small, usable), "a smaller window — with a frame")
	assert_eq(small.position, Vector2i(960, 516), "in the middle of the work area")


func test_the_language_is_always_a_known_one() -> void:
	# Without a file — the system language, from the list of known ones.
	var settings := GameSettings.load_from("user://no_such_settings.cfg")
	assert_true(
		GameSettings.LOCALES.has(settings.locale), "the language is from the list of known ones"
	)

	# The file can be edited by hand, and any language can be written in it. Showing the
	# interface in a nonexistent language is not allowed, so the fallback is used.
	var file := ConfigFile.new()
	file.set_value(GameSettings.SECTION, "locale", "klingon")
	file.save(TEMP)

	var loaded := GameSettings.load_from(TEMP)
	assert_true(GameSettings.LOCALES.has(loaded.locale), "the language is known anyway")


## A hand-edited file with a value of the wrong type: the default instead of it, not a script
## error that would stop the game at startup (ADR-0060).
func test_a_wrongly_typed_value_falls_back_to_the_default() -> void:
	var file := ConfigFile.new()
	file.set_value(GameSettings.SECTION, "vsync", "yes")
	file.set_value(GameSettings.SECTION, "blood", 1.5)
	file.set_value(GameSettings.SECTION, "show_fps", [true])
	file.set_value(GameSettings.SECTION, "master", "loud")
	file.set_value(GameSettings.SECTION, "music", 0)
	file.set_value(GameSettings.SECTION, "window_mode", "full")
	file.set_value(GameSettings.SECTION, "frame_limit", {})
	file.set_value(GameSettings.SECTION, "difficulty", 2.0)
	file.set_value(GameSettings.SECTION, "quality", Vector2(1, 2))
	file.set_value(GameSettings.SECTION, "quality_measured", "true")
	file.set_value(GameSettings.SECTION, "locale", 7)
	file.save(TEMP)

	var loaded := GameSettings.load_from(TEMP)
	var fresh := GameSettings.new()
	assert_not_null(loaded, "the file is read anyway")
	assert_eq(loaded.vsync, fresh.vsync, "a word is not a flag")
	assert_eq(loaded.blood, fresh.blood, "nor is a number")
	assert_eq(loaded.show_fps, fresh.show_fps)
	assert_almost_eq(loaded.master, fresh.master, 0.001, "a word is not a volume")
	assert_almost_eq(loaded.music, 0.0, 0.001, "a whole number is a volume")
	assert_eq(loaded.window_mode, fresh.window_mode)
	assert_eq(loaded.frame_limit, fresh.frame_limit)
	assert_eq(loaded.difficulty, 2, "a float stands for a whole number")
	assert_eq(loaded.quality, fresh.quality)
	assert_false(loaded.quality_measured, "a word is not a flag")
	assert_true(GameSettings.LOCALES.has(loaded.locale), "the language is known anyway")


func test_volumes_are_clamped() -> void:
	var file := ConfigFile.new()
	file.set_value(GameSettings.SECTION, "master", 40.0)
	file.set_value(GameSettings.SECTION, "music", -3.0)
	file.save(TEMP)

	var loaded := GameSettings.load_from(TEMP)
	assert_almost_eq(loaded.master, 1.0, 0.001, "there is nothing louder than one")
	assert_almost_eq(loaded.music, 0.0, 0.001, "and nothing quieter than zero")


func test_a_bus_level_goes_where_it_belongs() -> void:
	var settings := GameSettings.new()
	settings.set_level(Sounds.MUSIC_BUS, 0.25)
	assert_almost_eq(settings.music, 0.25, 0.001)
	assert_almost_eq(settings.level_of(Sounds.MUSIC_BUS), 0.25, 0.001)
	assert_almost_eq(settings.master, 1.0, 0.001, "neighbouring buses are untouched")


# --- Translations ------------------------------------------------------------


func _keys() -> PackedStringArray:
	var file := FileAccess.open(STRINGS, FileAccess.READ)
	assert_not_null(file, "the string table is in place")
	var keys := PackedStringArray()
	if file == null:
		return keys

	file.get_csv_line()  # header
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() >= 3 and not row[0].is_empty():
			keys.append(row[0])
	file.close()
	return keys


func test_every_string_exists_in_both_languages() -> void:
	# An untranslated string is shown as its key — "UI_PLAY" instead of the text of UI_PLAY,
	# and it can only be noticed by eye in the right language.
	var was := TranslationServer.get_locale()
	for locale: String in GameSettings.LOCALES:
		TranslationServer.set_locale(locale)
		for key: String in _keys():
			var line := TranslationServer.translate(key)
			assert_ne(line, key, "%s is translated into %s" % [key, locale])
	TranslationServer.set_locale(was)


func test_the_table_is_not_empty() -> void:
	assert_gt(_keys().size(), 10, "more than ten strings in the table")


# --- HUD ---------------------------------------------------------------------


func test_a_score_is_split_into_threes() -> void:
	# 12 400 reads at a glance, 12400 does not.
	assert_eq(Hud.format_score(0), "0")
	assert_eq(Hud.format_score(999), "999")
	assert_eq(Hud.format_score(1000), "1 000")
	assert_eq(Hud.format_score(1234567), "1 234 567")


# --- Extra life --------------------------------------------------------------


## A game of its own per test, not the autoload: the global one must not be touched —
## neighbouring tests look at it too, and lives and points left in it would leak to them.
func _game() -> GameState:
	var game := autofree(GameState.new()) as GameState
	game.start_game()
	return game


func test_an_extra_life_comes_once() -> void:
	var game := _game()
	var lives := game.lives

	game.add_score(GameState.EXTRA_LIFE_SCORE)
	assert_eq(game.lives, lives + 1, "a life is given for ten thousand")

	game.add_score(GameState.EXTRA_LIFE_SCORE)
	assert_eq(game.lives, lives + 1, "and for twenty — no longer")


func test_a_new_game_brings_the_extra_life_back() -> void:
	var game := _game()
	game.add_score(GameState.EXTRA_LIFE_SCORE)
	game.start_game()

	var lives := game.lives
	game.add_score(GameState.EXTRA_LIFE_SCORE)
	assert_eq(game.lives, lives + 1, "in a new game the threshold is counted anew")


func test_the_dead_do_not_get_an_extra_life() -> void:
	# After Game Over points are still awarded — the building bonus arrives with a delay.
	var game := _game()
	while game.lives > 0:
		game.lose_life()

	game.add_score(GameState.EXTRA_LIFE_SCORE)
	assert_eq(game.lives, 0, "no life is given to the dead")


## The language changed mid-game — HUD labels assembled by code get translated.
func test_the_hud_follows_a_language_change() -> void:
	var was := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var hud := HUD_SCENE.instantiate() as Hud
	add_child_autofree(hud)
	var english := TranslationServer.translate("UI_SCORE").to_upper()
	TranslationServer.set_locale("ru")
	var russian := TranslationServer.translate("UI_SCORE").to_upper()
	var captions: Array[String] = []
	for label in hud.find_children("*", "Label", true, false):
		captions.append((label as Label).text)
	TranslationServer.set_locale(was)
	assert_has(captions, russian, "the score caption was translated")
	assert_does_not_have(captions, english, "the score caption stayed in the old language")


## The HUD has as many document folders as the building has documents: per the ROM
## there are 5 to 10 depending on skill, and a five-folder HUD would lie at high skill.
func test_the_hud_draws_a_folder_per_document() -> void:
	assert_gte(
		Hud.DOCUMENT_ICONS, Arcade.red_doors(99), "fewer folders than documents there can be"
	)
	var hud := HUD_SCENE.instantiate() as Hud
	add_child_autofree(hud)
	var game := GameState.instance()
	for total: int in [Arcade.red_doors(0), Arcade.red_doors(99)]:
		game.start_building(total)
		hud.refresh()
		var shown := 0
		for icon in hud.find_children("*", "HudIcon", true, false):
			if (icon as HudIcon).kind == HudIcon.Kind.DOCUMENT and (icon as Control).visible:
				shown += 1
		assert_eq(shown, total, "%d documents — as many folders" % total)
	game.reset()


## The round — in the centre of the HUD, on the first line: in the corner nobody found
## it (ADR-0037).
func test_the_round_sits_in_the_middle_plate() -> void:
	var hud := HUD_SCENE.instantiate() as Hud
	add_child_autofree(hud)
	var game := GameState.instance()
	game.start_game(0)
	hud.refresh()
	var wanted := "%s %d" % [tr("UI_ROUND").to_upper(), game.building]
	var shown: Label = null
	for label: Node in hud.find_children("*", "Label", true, false):
		if (label as Label).text == wanted:
			shown = label as Label
	assert_not_null(shown, "the round number is shown")
	if shown != null:
		var box := shown.get_parent()
		assert_eq(shown.get_index(), 0, "on the first line")
		assert_eq(box.get_child_count(), 3, "the plate has the round, building and floor")
	game.reset()


## "FLOOR 1", just as the columns and indicator boards there write "P" (ADR-0038, decision 3).
## The floor above it is still the second.
## above it is still the second.
func test_the_hud_calls_the_bottom_floor_parking() -> void:
	var was := TranslationServer.get_locale()
	var rules := BuildingRules.new()
	var bottom := rules.floors - 1
	for locale: String in GameSettings.LOCALES:
		TranslationServer.set_locale(locale)
		var parking := TranslationServer.translate("UI_PARKING").to_upper()
		var floor_word := TranslationServer.translate("UI_FLOOR").to_upper()
		assert_eq(Hud.floor_text(rules, bottom), parking, "parking in %s" % locale)
		assert_eq(Hud.floor_text(rules, bottom - 1), "%s 2" % floor_word, "above it, the second")
	TranslationServer.set_locale(was)


## Frames per second — by a settings flag, in the HUD corner; the flag survives a restart.
func test_the_fps_counter_follows_the_setting() -> void:
	var settings := GameSettings.new()
	settings.show_fps = true
	var path := "user://test_fps.cfg"
	settings.save_to(path)
	var loaded := GameSettings.load_from(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_true(loaded.show_fps, "the flag is saved")
	var hud := HUD_SCENE.instantiate() as Hud
	add_child_autofree(hud)
	Hud.show_fps = loaded.show_fps
	await _hud_frame()
	assert_true(_fps_label_visible(hud), "switched on — the counter is visible")
	Hud.show_fps = false
	await _hud_frame()
	assert_false(_fps_label_visible(hud), "switched off — it is gone")


## Waits until the HUD's `_process` is guaranteed to have run at least once.
## The tree sends `process_frame` before the nodes' `_process` of the same frame, and
## after one `await` the HUD may not have updated yet — the test failed on CI because
## of this.
func _hud_frame() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _fps_label_visible(hud: Hud) -> bool:
	for label: Node in hud.find_children("*", "Label", true, false):
		if (label as Label).text.ends_with("FPS"):
			return (label as Label).is_visible_in_tree()
	return false
