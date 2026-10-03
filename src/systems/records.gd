class_name Records
extends RefCounted

## High score table: ten rows with score and date.
##
## No initials entry (ADR-0012, point 9): the ritual of an arcade hall with a queue at the
## cabinet turns at home into an extra screen between death and the next game.
##
## The table rules are pure functions over an array, and they are tested without disk:
## sorting, trimming to ten and the place of a new score. Only [method load_from] and
## [method save_to] go to disk.

const PATH := "user://records.json"

## How many rows we keep. Nobody cares about the eleventh.
const LIMIT: int = 10

## Score and date of one entry.
const SCORE := "score"
const DATE := "date"

var rows: Array[Dictionary] = []


static func load_from(path: String = PATH) -> Records:
	var records := Records.new()
	if not FileAccess.file_exists(path):
		return records

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return records

	# Parsing through an instance, not [method JSON.parse_string]: the static
	# helper writes an error to the engine log by itself on a broken file, and a corrupted
	# table would look like a game failure.
	var json := JSON.new()
	var failed := json.parse(file.get_as_text()) != OK
	file.close()

	var parsed: Variant = json.data
	if failed or parsed is not Array:
		# The file is corrupted or edited by hand: the table starts anew, but the game
		# does not crash because of it — high scores are not something worth crashing over.
		push_warning("High score table is unreadable, starting afresh: %s" % path)
		return records

	for entry: Variant in parsed as Array:
		if entry is Dictionary and (entry as Dictionary).has(SCORE):
			records.rows.append(
				{
					SCORE: int((entry as Dictionary)[SCORE]),
					DATE: String((entry as Dictionary).get(DATE, ""))
				}
			)
	records.rows = sorted(records.rows)
	return records


func save_to(path: String = PATH) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("High score table was not saved: %s" % path)
		return
	file.store_string(JSON.stringify(rows))
	file.close()


## Adds a score and returns its place in the table, counting from zero.
## Did not make the top ten — returns -1.
##
## The place is computed before insertion, not by searching for the row after it: the same score on
## the same day happens twice, and searching by the "score and date" pair found someone else's row —
## a score that did not make the top ten would be announced as a record.
func submit(score: int, date: String = "") -> int:
	var stamp := date if not date.is_empty() else today()
	var place := 0
	for row: Dictionary in rows:
		if int(row[SCORE]) >= score:
			place += 1
	rows = sorted(rows + [{SCORE: score, DATE: stamp}])
	return place if place < LIMIT else -1


## The table's best score. An empty table is zero, not a missing value:
## whoever displays it does not need a special case.
func best() -> int:
	return int(rows[0][SCORE]) if not rows.is_empty() else 0


## Descending sort with trimming to [constant LIMIT].
##
## Static and stateless: the table rule is tested by a test directly like this,
## without files and without an instance.
static func sorted(entries: Array) -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for entry: Variant in entries:
		copy.append(entry as Dictionary)
	copy.sort_custom(
		func(first: Dictionary, second: Dictionary) -> bool:
			return int(first[SCORE]) > int(second[SCORE])
	)
	return copy.slice(0, LIMIT)


## Today's date in the form "2026-09-13".
static func today() -> String:
	var now := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [now["year"], now["month"], now["day"]]
