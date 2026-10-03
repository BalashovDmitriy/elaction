extends GutTest

## The "Credits" page (ADR-0042, decision 6).
##
## `CREDITS.md` is edited, while the game reads `assets/credits.json` built from it:
## a forgotten rebuild would silently leave a new author without a line in the game.
## So the test parses `CREDITS.md` by the same rule as
## `tools/build_credits.py`, and compares with what the page will read.

const SOURCE := "res://CREDITS.md"
const SECTIONS := {
	"People and cars": "UI_CREDITS_ACTORS",
	"Props and roof": "UI_CREDITS_PROPS",
	"Textures": "UI_CREDITS_TEXTURES",
	"City and sky": "UI_CREDITS_CITY",
	"Sound": "UI_CREDITS_SOUND",
	"Fonts": "UI_CREDITS_FONTS",
}


## Authors by section from `CREDITS.md`: section key — names in order.
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
		if cells[0].begins_with("---") or not header.has("Author"):
			continue
		var name := cells[header.find("Author")]
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
