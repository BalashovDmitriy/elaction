class_name Credits
extends RefCounted

## Authors for the "Credits" page (ADR-0042, decision 6).
##
## The source is `CREDITS.md`, it is edited by hand. It does not go into the build, so the page
## reads [constant PATH], built from it by `tools/build_credits.py`; the `test_credits` test
## compares one with the other.

const PATH := "res://assets/credits.json"
## Between authors in a section line. The dot holds on to the previous author with a non-breaking
## space: the line break comes after it, not before.
const SEPARATOR := "\u00a0·  "
## Non-breaking space: "name (licence)" does not break in the middle.
const NBSP := "\u00a0"


## Section: translation key of the heading and the authors with licences.
class Section:
	extends RefCounted
	var key: String = ""
	## Author name — licences of their works in this section.
	var authors: Array[Dictionary] = []

	## Section line: "Quaternius (CC0 1.0)  ·  Kenney (CC0 1.0)".
	func line() -> String:
		var parts: PackedStringArray = []
		for author: Dictionary in authors:
			var licences: Array = author.get("licences", [])
			# "CC BY", as Creative Commons itself writes it: at the hyphen in "CC-BY" the line broke in the
			# middle of the licence.
			var licence := ", ".join(licences).replace("CC-BY", "CC BY")
			var entry := "%s (%s)" % [author.get("name", ""), licence]
			parts.append(entry.replace(" ", NBSP))
		return SEPARATOR.join(parts)


## Sections from [param path] in file order. No file — empty: a page without authors is better than
## a menu that does not open.
static func load_sections(path: String = PATH) -> Array[Section]:
	var found: Array[Section] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("нет списка авторов: %s" % path)
		return found
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		return found
	for raw: Variant in (data as Dictionary).get("sections", []):
		# A type check, not `as`: a dictionary is never null, and casting a foreign value to it would
		# crash rather than skip the section.
		if not raw is Dictionary:
			continue
		var entry := raw as Dictionary
		var section := Section.new()
		section.key = String(entry.get("key", ""))
		for author: Variant in entry.get("authors", []):
			if author is Dictionary:
				section.authors.append(author as Dictionary)
		found.append(section)
	return found
