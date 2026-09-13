extends GutTest

## Тесты интерфейса: настройки, переводы, счёт в HUD и жизнь за очки.
##
## Всё, что здесь проверяется, — правила, а не отрисовка: сохранились ли
## настройки, есть ли строка на обоих языках, как выглядит число и когда
## приходит дополнительная жизнь. Кадр для этого поднимать незачем.

const TEMP := "user://test_settings.cfg"

## Откуда берутся ключи переводов: та же таблица, из которой их берёт игра.
const STRINGS := "res://assets/i18n/ui.csv"


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
	settings.fullscreen = true
	settings.save_to(TEMP)

	var loaded := GameSettings.load_from(TEMP)
	assert_almost_eq(loaded.master, 0.4, 0.001)
	assert_almost_eq(loaded.music, 0.1, 0.001)
	assert_almost_eq(loaded.sfx, 0.9, 0.001)
	assert_eq(loaded.locale, "en")
	assert_true(loaded.fullscreen)


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


func test_an_extra_life_comes_once() -> void:
	var game := GameState.instance()
	game.start_game()
	var lives := game.lives

	game.add_score(GameState.EXTRA_LIFE_SCORE)
	assert_eq(game.lives, lives + 1, "за десять тысяч дают жизнь")

	game.add_score(GameState.EXTRA_LIFE_SCORE)
	assert_eq(game.lives, lives + 1, "а за двадцать — уже нет")
	game.start_game()


func test_a_new_game_brings_the_extra_life_back() -> void:
	var game := GameState.instance()
	game.start_game()
	game.add_score(GameState.EXTRA_LIFE_SCORE)
	game.start_game()

	var lives := game.lives
	game.add_score(GameState.EXTRA_LIFE_SCORE)
	assert_eq(game.lives, lives + 1, "в новой партии порог считается заново")
	game.start_game()


func test_the_dead_do_not_get_an_extra_life() -> void:
	# После Game Over очки ещё начисляются — бонус за здание приходит отложенно.
	var game := GameState.instance()
	game.start_game()
	while game.lives > 0:
		game.lose_life()

	game.add_score(GameState.EXTRA_LIFE_SCORE)
	assert_eq(game.lives, 0, "мёртвому жизнь не выдают")
	game.start_game()
