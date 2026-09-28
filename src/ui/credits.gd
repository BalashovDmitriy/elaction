class_name Credits
extends RefCounted

## Авторы для страницы «Авторы» (ADR-0042, решение 6).
##
## Источник — `CREDITS.md`, его правят руками. В сборку он не идёт, поэтому
## страница читает [constant PATH], собранный из него `tools/build_credits.py`;
## тест `test_credits` сверяет одно с другим.

const PATH := "res://assets/credits.json"
## Между авторами в строке раздела. Точка держится за предыдущего автора
## неразрывным пробелом: перенос строки — после неё, а не перед.
const SEPARATOR := "\u00a0·  "
## Неразрывный пробел: «имя (лицензия)» не рвётся переносом посередине.
const NBSP := "\u00a0"


## Раздел: ключ перевода заголовка и авторы с лицензиями.
class Section:
	extends RefCounted
	var key: String = ""
	## Имя автора — лицензии его работ в этом разделе.
	var authors: Array[Dictionary] = []

	## Строка раздела: «Quaternius (CC0 1.0)  ·  Kenney (CC0 1.0)».
	func line() -> String:
		var parts: PackedStringArray = []
		for author: Dictionary in authors:
			var licences: Array = author.get("licences", [])
			# «CC BY», как пишет сама Creative Commons: по дефису «CC-BY» строка
			# переносилась посередине лицензии.
			var licence := ", ".join(licences).replace("CC-BY", "CC BY")
			var entry := "%s (%s)" % [author.get("name", ""), licence]
			parts.append(entry.replace(" ", NBSP))
		return SEPARATOR.join(parts)


## Разделы из [param path] в порядке файла. Нет файла — пусто: страница без
## авторов лучше, чем меню, которое не открывается.
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
		var entry := raw as Dictionary
		if entry == null:
			continue
		var section := Section.new()
		section.key = String(entry.get("key", ""))
		for author: Variant in entry.get("authors", []):
			if author is Dictionary:
				section.authors.append(author as Dictionary)
		found.append(section)
	return found
