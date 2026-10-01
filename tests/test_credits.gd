extends GutTest

## Страница «Авторы» (ADR-0042, решение 6).
##
## Правят `CREDITS.md`, а игра читает собранный из него `assets/credits.json`:
## забытая пересборка молча оставила бы нового автора без строки в игре.
## Поэтому тест разбирает `CREDITS.md` тем же правилом, что
## `tools/build_credits.py`, и сверяет с тем, что прочтёт страница.

const SOURCE := "res://CREDITS.md"
const SECTIONS := {
	"Люди и машины": "UI_CREDITS_ACTORS",
	"Обстановка и крыша": "UI_CREDITS_PROPS",
	"Фактуры": "UI_CREDITS_TEXTURES",
	"Город и небо": "UI_CREDITS_CITY",
	"Звук": "UI_CREDITS_SOUND",
	"Шрифты": "UI_CREDITS_FONTS",
}


## Авторы по разделам из `CREDITS.md`: ключ раздела — имена по порядку.
func _from_markdown() -> Dictionary:
	var found: Dictionary = {}
	var key := ""
	var header: PackedStringArray = []
	for line: String in FileAccess.get_file_as_string(SOURCE).split("\n"):
		line = line.strip_edges()
		if line.begins_with("## "):
			key = String(SECTIONS.get(line.substr(3).strip_edges(), ""))
			if not key.is_empty():
				found[key] = []
			header = []
			continue
		if key.is_empty() or not line.begins_with("|"):
			header = []
			continue
		var cells: PackedStringArray = []
		for cell: String in line.trim_prefix("|").trim_suffix("|").split("|"):
			cells.append(cell.strip_edges())
		if header.is_empty():
			header = cells
			continue
		if cells[0].begins_with("---") or not header.has("Автор"):
			continue
		var name := cells[header.find("Автор")]
		if name != "elaction" and not (found[key] as Array).has(name):
			(found[key] as Array).append(name)
	return found


func test_the_page_list_matches_credits_md() -> void:
	var wanted := _from_markdown()
	assert_eq(wanted.size(), SECTIONS.size(), "в CREDITS.md все разделы")
	var sections := Credits.load_sections()
	assert_eq(sections.size(), wanted.size(), "на странице — все разделы")
	for section: Credits.Section in sections:
		var names: Array = []
		for author: Dictionary in section.authors:
			names.append(author["name"])
		assert_eq(
			names, wanted.get(section.key, []), "%s: python tools/build_credits.py" % section.key
		)


func test_every_author_has_a_licence() -> void:
	for section: Credits.Section in Credits.load_sections():
		for author: Dictionary in section.authors:
			assert_false((author["licences"] as Array).is_empty(), "лицензия у %s" % author["name"])


func test_every_section_is_translated() -> void:
	var before := TranslationServer.get_locale()
	for section: Credits.Section in Credits.load_sections():
		for locale: String in ["en", "ru"]:
			TranslationServer.set_locale(locale)
			assert_ne(tr(section.key), section.key, "%s переведён на %s" % [section.key, locale])
	TranslationServer.set_locale(before)
