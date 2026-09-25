extends GutTest

## Тесты интерфейса: настройки, переводы, счёт в HUD и жизнь за очки.
##
## Всё, что здесь проверяется, — правила, а не отрисовка: сохранились ли
## настройки, есть ли строка на обоих языках, как выглядит число и когда
## приходит дополнительная жизнь. Кадр для этого поднимать незачем.

const TEMP := "user://test_settings.cfg"

## Откуда берутся ключи переводов: та же таблица, из которой их берёт игра.
const STRINGS := "res://assets/i18n/ui.csv"

const HUD_SCENE := preload("res://src/ui/hud.tscn")


func after_each() -> void:
	if FileAccess.file_exists(TEMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))


# --- Настройки ---------------------------------------------------------------


func test_settings_survive_a_restart() -> void:
	var settings := GameSettings.new()
	settings.master = 0.4
	settings.music = 0.1
	settings.sfx = 0.9
	settings.locale = "en"
	settings.window_mode = DisplayModes.Mode.BORDERLESS
	settings.resolution = Vector2i(2560, 1440)
	settings.render_scale = 0.67
	settings.save_to(TEMP)

	var loaded := GameSettings.load_from(TEMP)
	assert_almost_eq(loaded.master, 0.4, 0.001)
	assert_almost_eq(loaded.music, 0.1, 0.001)
	assert_almost_eq(loaded.sfx, 0.9, 0.001)
	assert_eq(loaded.locale, "en")
	assert_eq(loaded.window_mode, DisplayModes.Mode.BORDERLESS)
	assert_eq(loaded.resolution, Vector2i(2560, 1440))
	assert_almost_eq(loaded.render_scale, 0.67, 0.001)


## Настройки до M22 хранили флажок «полный экран»: он становится режимом окна.
func test_the_old_fullscreen_flag_becomes_a_window_mode() -> void:
	var old := ConfigFile.new()
	old.set_value(GameSettings.SECTION, "fullscreen", true)
	old.save(TEMP)
	assert_eq(GameSettings.load_from(TEMP).window_mode, DisplayModes.Mode.FULLSCREEN)


## Размеры окна — только те, что влезают на монитор; 4K — на экране 4K.
func test_window_sizes_fit_the_screen() -> void:
	var full_hd := DisplayModes.available(Vector2i(1920, 1080))
	assert_eq(full_hd[-1], Vector2i(1920, 1080), "на FullHD больше FullHD не предлагается")
	assert_has(DisplayModes.available(Vector2i(3840, 2160)), Vector2i(3840, 2160), "4K есть на 4K")
	assert_eq(DisplayModes.available(Vector2i(800, 600)).size(), 1, "на крошечном — хоть один")
	assert_eq(
		DisplayModes.nearest(Vector2i(3840, 2160), Vector2i(1920, 1080)),
		Vector2i(1920, 1080),
		"сменили монитор — размер ужимается под новый"
	)


## 4K-монитор с панелью задач: рабочая область ниже 2160, а 4K в списке есть
## и встаёт во весь экран без рамки. Раньше список строился по рабочей области,
## и 4K пропадал (замечание пользователя, M24b).
func test_4k_window_on_a_4k_screen_with_a_taskbar() -> void:
	var screen := Rect2i(0, 0, 3840, 2160)
	var usable := Rect2i(0, 0, 3840, 2112)
	assert_has(DisplayModes.available(screen.size), Vector2i(3840, 2160), "4K в списке")
	var frame := DisplayModes.windowed_rect(Vector2i(3840, 2160), screen, usable)
	assert_eq(frame, screen, "окно 4K — во весь экран")
	assert_false(DisplayModes.framed(frame, usable), "без рамки: с ней заголовок ушёл бы за край")
	var small := DisplayModes.windowed_rect(Vector2i(1920, 1080), screen, usable)
	assert_true(DisplayModes.framed(small, usable), "меньшее окно — с рамкой")
	assert_eq(small.position, Vector2i(960, 516), "по середине рабочей области")


func test_settings_without_a_file_take_the_system_language() -> void:
	var settings := GameSettings.load_from("user://no_such_settings.cfg")
	assert_true(GameSettings.LOCALES.has(settings.locale), "язык из списка известных")


func test_an_unknown_language_falls_back() -> void:
	# Файл можно поправить руками, а язык — написать любой. Показывать
	# интерфейс на несуществующем языке нельзя, поэтому берётся запасной.
	var file := ConfigFile.new()
	file.set_value(GameSettings.SECTION, "locale", "klingon")
	file.save(TEMP)

	var loaded := GameSettings.load_from(TEMP)
	assert_true(GameSettings.LOCALES.has(loaded.locale), "язык всё равно известный")


func test_volumes_are_clamped() -> void:
	var file := ConfigFile.new()
	file.set_value(GameSettings.SECTION, "master", 40.0)
	file.set_value(GameSettings.SECTION, "music", -3.0)
	file.save(TEMP)

	var loaded := GameSettings.load_from(TEMP)
	assert_almost_eq(loaded.master, 1.0, 0.001, "громче единицы не бывает")
	assert_almost_eq(loaded.music, 0.0, 0.001, "и тише нуля тоже")


func test_a_bus_level_goes_where_it_belongs() -> void:
	var settings := GameSettings.new()
	settings.set_level(Sounds.MUSIC_BUS, 0.25)
	assert_almost_eq(settings.music, 0.25, 0.001)
	assert_almost_eq(settings.level_of(Sounds.MUSIC_BUS), 0.25, 0.001)
	assert_almost_eq(settings.master, 1.0, 0.001, "соседние шины не тронуты")


# --- Переводы ----------------------------------------------------------------


func _keys() -> PackedStringArray:
	var file := FileAccess.open(STRINGS, FileAccess.READ)
	assert_not_null(file, "таблица строк на месте")
	var keys := PackedStringArray()
	if file == null:
		return keys

	file.get_csv_line()  # заголовок
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() >= 3 and not row[0].is_empty():
			keys.append(row[0])
	file.close()
	return keys


func test_every_string_exists_in_both_languages() -> void:
	# Непереведённая строка показывается ключом — «UI_PLAY» вместо «Играть»,
	# и заметить это можно только глазами на нужном языке.
	var was := TranslationServer.get_locale()
	for locale: String in GameSettings.LOCALES:
		TranslationServer.set_locale(locale)
		for key: String in _keys():
			var line := TranslationServer.translate(key)
			assert_ne(line, key, "%s переведён на %s" % [key, locale])
	TranslationServer.set_locale(was)


func test_the_table_is_not_empty() -> void:
	assert_gt(_keys().size(), 10, "строк в таблице больше десятка")


# --- HUD ---------------------------------------------------------------------


func test_a_score_is_split_into_threes() -> void:
	# 12 400 читается с одного взгляда, 12400 — нет.
	assert_eq(Hud.format_score(0), "0")
	assert_eq(Hud.format_score(999), "999")
	assert_eq(Hud.format_score(1000), "1 000")
	assert_eq(Hud.format_score(1234567), "1 234 567")


# --- Дополнительная жизнь ----------------------------------------------------


## Своя партия на тест, а не автолоад: глобальную трогать нельзя — её же смотрят
## соседние тесты, и оставленные в ней жизни и очки утекли бы к ним.
func _game() -> GameState:
	var game := autofree(GameState.new()) as GameState
	game.start_game()
	return game


func test_an_extra_life_comes_once() -> void:
	var game := _game()
	var lives := game.lives

	game.add_score(GameState.EXTRA_LIFE_SCORE)
	assert_eq(game.lives, lives + 1, "за десять тысяч дают жизнь")

	game.add_score(GameState.EXTRA_LIFE_SCORE)
	assert_eq(game.lives, lives + 1, "а за двадцать — уже нет")


func test_a_new_game_brings_the_extra_life_back() -> void:
	var game := _game()
	game.add_score(GameState.EXTRA_LIFE_SCORE)
	game.start_game()

	var lives := game.lives
	game.add_score(GameState.EXTRA_LIFE_SCORE)
	assert_eq(game.lives, lives + 1, "в новой партии порог считается заново")


func test_the_dead_do_not_get_an_extra_life() -> void:
	# После Game Over очки ещё начисляются — бонус за здание приходит отложенно.
	var game := _game()
	while game.lives > 0:
		game.lose_life()

	game.add_score(GameState.EXTRA_LIFE_SCORE)
	assert_eq(game.lives, 0, "мёртвому жизнь не выдают")


## Язык сменили посреди партии — подписи HUD, собранные кодом, переводятся.
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
	assert_has(captions, russian, "подпись очков перевелась")
	assert_does_not_have(captions, english, "подпись очков осталась на прежнем языке")


## Папок документов в HUD столько, сколько документов в здании: по ROM их от 5
## до 10 по навыку, и HUD на пять папок врал бы на высоком навыке.
func test_the_hud_draws_a_folder_per_document() -> void:
	assert_gte(Hud.DOCUMENT_ICONS, Arcade.red_doors(99), "папок меньше, чем бывает документов")
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
		assert_eq(shown, total, "документов %d — столько и папок" % total)
	game.reset()


## Раунд — в центре HUD, первой строкой: в углу его не находили (ADR-0037).
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
	assert_not_null(shown, "номер раунда показан")
	if shown != null:
		var box := shown.get_parent()
		assert_eq(shown.get_index(), 0, "первой строкой")
		assert_eq(box.get_child_count(), 3, "в плашке раунд, здание и этаж")
	game.reset()


## Нижний этаж — паркинг: HUD пишет «ПАРКИНГ», а не «ЭТАЖ 1», как колонны и
## табло там пишут «P» (ADR-0038, решение 3). Этаж над ним — по-прежнему второй.
func test_the_hud_calls_the_bottom_floor_parking() -> void:
	var was := TranslationServer.get_locale()
	var rules := BuildingRules.new()
	var bottom := rules.floors - 1
	for locale: String in GameSettings.LOCALES:
		TranslationServer.set_locale(locale)
		var parking := TranslationServer.translate("UI_PARKING").to_upper()
		var floor_word := TranslationServer.translate("UI_FLOOR").to_upper()
		assert_eq(Hud.floor_text(rules, bottom), parking, "паркинг на %s" % locale)
		assert_eq(Hud.floor_text(rules, bottom - 1), "%s 2" % floor_word, "над ним — второй")
	TranslationServer.set_locale(was)


## Кадры в секунду — по флажку настроек, в углу HUD; флажок переживает перезапуск.
func test_the_fps_counter_follows_the_setting() -> void:
	var settings := GameSettings.new()
	settings.show_fps = true
	var path := "user://test_fps.cfg"
	settings.save_to(path)
	var loaded := GameSettings.load_from(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_true(loaded.show_fps, "флажок сохраняется")
	var hud := HUD_SCENE.instantiate() as Hud
	add_child_autofree(hud)
	Hud.show_fps = loaded.show_fps
	await _hud_frame()
	assert_true(_fps_label_visible(hud), "включили — счётчик виден")
	Hud.show_fps = false
	await _hud_frame()
	assert_false(_fps_label_visible(hud), "выключили — пропал")


## Ждёт, пока `_process` HUD гарантированно отработает хотя бы раз.
## `process_frame` дерево шлёт до `_process` узлов того же кадра, и после одного
## `await` HUD может ещё не обновиться — на CI тест из-за этого падал.
func _hud_frame() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _fps_label_visible(hud: Hud) -> bool:
	for label: Node in hud.find_children("*", "Label", true, false):
		if (label as Label).text.ends_with("FPS"):
			return (label as Label).is_visible_in_tree()
	return false
