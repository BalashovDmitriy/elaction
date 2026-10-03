extends GutTest

## Release tests: version and export presets.
##
## The version lives in four places — `project.godot`, two fields of the Windows preset, the archive
## name and the tag ([ADR-0013](../docs/adr/0013-release-and-versioning.md), item 3). They drift
## apart silently: the archive is named with one version, the game shows another in the menu corner,
## and the one who notices is whoever downloaded it.
##
## Presets are checked for the same reason as the sound list: an edit in them is visible neither in
## the frame nor in the log. A forgotten `exclude_filter` ships tests and developer tools to the
## player, and a wrong icon ships Godot's default robot.

const PRESETS_PATH := "res://export_presets.cfg"
const CHANGELOG_PATH := "res://CHANGELOG.md"
const ICON_PATH := "res://icon.ico"
const PACKAGE_PATH := "res://tools/package.py"
const FONTS_DIR := "res://assets/fonts"

## The preset that must exist, and the platform it is built for.
const WANTED_PRESETS: Dictionary = {
	"Windows Desktop": "Windows Desktop",
	"Linux": "Linux",
}

## What must not end up with the player inside the build.
const EXCLUDED: Array[String] = ["tests/", "tools/", "addons/"]


## Parses export_presets.cfg. Empty if the file is missing or cannot be read.
func _presets() -> ConfigFile:
	var config := ConfigFile.new()
	var code := config.load(PRESETS_PATH)
	assert_eq(code, OK, "export_presets.cfg читается")
	return config


## Preset sections without options sections: `preset.0`, but not `preset.0.options`.
func _preset_sections(config: ConfigFile) -> Array[String]:
	var sections: Array[String] = []
	for section: String in config.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			sections.append(section)
	return sections


## The preset section with this name — or an empty string if there is none.
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
	# By this line tools/smoke.py decides whether the built game came up.
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
	# These fields cannot be empty: on an empty version rcedit crashes and the export does not build at
	# all (godot#83379). Windows expects four numbers, so a zero is appended to the project version.
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
	# Otherwise a .pck lies next to the game, and it gets lost when the archive is unpacked.
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
	# A release without notes goes out silently, and this is noticed after publication.
	var text := FileAccess.get_file_as_string(CHANGELOG_PATH)
	assert_false(text.is_empty(), "CHANGELOG.md читается")
	assert_string_contains(text, "## [%s]" % Release.version())


func test_every_font_ships_with_its_license() -> void:
	# The OFL requires shipping the licence with the product, and a font is added to the theme with one
	# line — the archive list in tools/package.py is not remembered then. That is how Exo 2 would have
	# shipped without a licence: the HUD has used it since M22, the archive did not know about it.
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
	# CC-BY 3.0 of the dressing models requires naming the authors where the models are distributed —
	# and the release archive distributes them.
	var extras := FileAccess.get_file_as_string(PACKAGE_PATH)
	assert_string_contains(extras, '"CREDITS.md"')
