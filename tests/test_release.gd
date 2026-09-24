extends GutTest

## Тесты релиза: версия и пресеты экспорта.
##
## Версия живёт в четырёх местах — `project.godot`, два поля пресета Windows,
## имя архива и тег ([ADR-0013](../docs/adr/0013-release-and-versioning.md),
## пункт 3). Разъезжаются они молча: архив назовётся одной версией, игра в углу
## меню покажет другую, и заметит это уже тот, кто скачал.
##
## Пресеты проверяются по той же причине, что и список звуков: правка в них
## не видна ни в кадре, ни в логе. Забытый `exclude_filter` уносит игроку тесты
## и инструменты разработчика, а неверная иконка — дефолтного робота Godot.

const PRESETS_PATH := "res://export_presets.cfg"
const CHANGELOG_PATH := "res://CHANGELOG.md"
const ICON_PATH := "res://icon.ico"
const PACKAGE_PATH := "res://tools/package.py"
const FONTS_DIR := "res://assets/fonts"

## Пресет, который должен быть, и платформа, на которой он собирается.
const WANTED_PRESETS: Dictionary = {
	"Windows Desktop": "Windows Desktop",
	"Linux": "Linux",
}

## Что не должно уехать игроку внутри сборки.
const EXCLUDED: Array[String] = ["tests/", "tools/", "addons/"]


## Разбирает export_presets.cfg. Пустой — если файла нет или он не читается.
func _presets() -> ConfigFile:
	var config := ConfigFile.new()
	var code := config.load(PRESETS_PATH)
	assert_eq(code, OK, "export_presets.cfg читается")
	return config


## Секции пресетов без секций опций: `preset.0`, но не `preset.0.options`.
func _preset_sections(config: ConfigFile) -> Array[String]:
	var sections: Array[String] = []
	for section: String in config.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			sections.append(section)
	return sections


## Секция пресета с таким именем — или пустая строка, если такого нет.
func _section_of(config: ConfigFile, name: String) -> String:
	for section: String in _preset_sections(config):
		if str(config.get_value(section, "name", "")) == name:
			return section
	return ""


func test_the_version_looks_like_a_version() -> void:
	var version := Release.version()
	var parts := version.split(".")
	assert_eq(parts.size(), 3, "версия из трёх чисел: %s" % version)
	for part: String in parts:
		assert_true(part.is_valid_int(), "«%s» в версии %s — число" % [part, version])


func test_the_banner_names_the_version() -> void:
	# По этой строке tools/smoke.py решает, поднялась ли собранная игра.
	assert_string_contains(Release.banner(), Release.version())
	assert_string_contains(Release.banner(), "elaction")


func test_the_tag_is_the_version_with_a_letter() -> void:
	assert_eq(Release.tag(), "v" + Release.version())


func test_both_platforms_are_in_the_presets() -> void:
	var config := _presets()
	var found: Array[String] = []
	for section: String in _preset_sections(config):
		found.append(str(config.get_value(section, "name", "")))

	for name: String in WANTED_PRESETS:
		assert_has(found, name, "пресет «%s» на месте" % name)


func test_every_preset_stands_on_its_own_platform() -> void:
	var config := _presets()
	for section: String in _preset_sections(config):
		var name := str(config.get_value(section, "name", ""))
		if not WANTED_PRESETS.has(name):
			continue
		assert_eq(
			str(config.get_value(section, "platform", "")),
			str(WANTED_PRESETS[name]),
			"пресет «%s» собирается на своей платформе" % name
		)


func test_the_windows_preset_carries_the_project_version() -> void:
	# Пустыми эти поля быть не могут: на пустой версии rcedit падает и экспорт
	# не собирается вовсе (godot#83379). Windows ждёт четыре числа, поэтому
	# к версии проекта добавлен ноль.
	var config := _presets()
	var options := _section_of(config, "Windows Desktop") + ".options"
	var wanted := Release.version() + ".0"
	for key: String in ["application/file_version", "application/product_version"]:
		assert_eq(
			str(config.get_value(options, key, "")), wanted, "%s совпадает с версией проекта" % key
		)


func test_the_windows_preset_points_at_the_icon() -> void:
	var config := _presets()
	var options := _section_of(config, "Windows Desktop") + ".options"
	assert_eq(str(config.get_value(options, "application/icon", "")), ICON_PATH)
	assert_true(FileAccess.file_exists(ICON_PATH), "иконка нарисована: tools/render_icon.py")


func test_resources_live_inside_the_executable() -> void:
	# Иначе рядом с игрой лежит .pck, который теряют при распаковке архива.
	var config := _presets()
	for section: String in _preset_sections(config):
		var options := section + ".options"
		assert_true(
			bool(config.get_value(options, "binary_format/embed_pck", false)),
			"%s собирается одним файлом" % section
		)


func test_the_player_does_not_get_tests_and_tools() -> void:
	var config := _presets()
	for section: String in _preset_sections(config):
		var filter := str(config.get_value(section, "exclude_filter", ""))
		for excluded: String in EXCLUDED:
			assert_string_contains(filter, excluded)


func test_the_changelog_has_a_section_for_this_version() -> void:
	# Релиз без заметок выходит молча, и замечают это после публикации.
	var text := FileAccess.get_file_as_string(CHANGELOG_PATH)
	assert_false(text.is_empty(), "CHANGELOG.md читается")
	assert_string_contains(text, "## [%s]" % Release.version())


func test_every_font_ships_with_its_license() -> void:
	# OFL требует прикладывать лицензию к продукту, а шрифт добавляют одной
	# строкой в тему — список архива в tools/package.py при этом не вспоминают.
	# Так Exo 2 проехал бы без лицензии: HUD на нём с M22, архив о нём не знал.
	var extras := FileAccess.get_file_as_string(PACKAGE_PATH)
	assert_false(extras.is_empty(), "tools/package.py читается")
	var fonts := 0
	for file: String in DirAccess.get_files_at(FONTS_DIR):
		if file.get_extension() != "ttf":
			continue
		fonts += 1
		var license := "assets/fonts/%s.LICENSE.txt" % file.get_basename()
		assert_true(FileAccess.file_exists("res://" + license), "у %s есть лицензия" % file)
		assert_string_contains(extras, '"%s"' % license)
	assert_gt(fonts, 0, "шрифты нашлись")


func test_the_credits_ship_with_the_game() -> void:
	# CC-BY 3.0 моделей обстановки требует назвать авторов там, где модели
	# распространяют, — а распространяет их архив релиза.
	var extras := FileAccess.get_file_as_string(PACKAGE_PATH)
	assert_string_contains(extras, '"CREDITS.md"')
