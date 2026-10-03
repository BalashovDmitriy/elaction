extends GutTest

## High score table tests.
##
## The table rules are pure functions and are checked without the disk. Only two tests
## touch the disk: a record that survives a restart is the only reason the
## table exists at all.

const TEMP := "user://test_records.json"


func after_each() -> void:
	if FileAccess.file_exists(TEMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))


func _rows(scores: Array) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for score: int in scores:
		rows.append({Records.SCORE: score, Records.DATE: "2026-09-13"})
	return rows


func test_the_table_is_sorted_from_the_best() -> void:
	var sorted := Records.sorted(_rows([300, 1200, 50]))
	assert_eq(int(sorted[0][Records.SCORE]), 1200)
	assert_eq(int(sorted[2][Records.SCORE]), 50)


func test_the_table_keeps_only_ten_rows() -> void:
	# Nobody is interested in the eleventh line, and the file grows forever.
	var many: Array[int] = []
	for index: int in 25:
		many.append(index * 100)
	assert_eq(Records.sorted(_rows(many)).size(), Records.LIMIT)


func test_a_good_score_gets_its_place() -> void:
	var records := Records.new()
	records.rows = _rows([1000, 500])
	assert_eq(records.submit(2000), 0, "the best score comes first")
	assert_eq(records.submit(700), 2, "a middle one goes between its neighbours")


func test_a_poor_score_does_not_make_the_table() -> void:
	var records := Records.new()
	var many: Array[int] = []
	for index: int in Records.LIMIT:
		many.append(10000 + index)
	records.rows = _rows(many)
	assert_eq(records.submit(5), -1, "did not make the top ten")
	assert_eq(records.rows.size(), Records.LIMIT, "and did not bloat the table")


func test_a_repeated_score_does_not_fake_a_record() -> void:
	# The same score on the same day can happen twice. Looking up a line by the "score and
	# date" pair found someone else's — and a score that did not make the top ten was declared
	# a record.
	var records := Records.new()
	var many: Array[int] = []
	for _index: int in Records.LIMIT:
		many.append(7000)
	records.rows = _rows(many)
	assert_eq(records.submit(7000, "2026-09-13"), -1, "an eleventh equal one - misses")


func test_the_best_of_an_empty_table_is_zero() -> void:
	# The HUD and the menu show a number, and they have no use for a special case.
	assert_eq(Records.new().best(), 0)


func test_records_survive_a_restart() -> void:
	var records := Records.new()
	records.submit(4200, "2026-09-13")
	records.save_to(TEMP)

	var loaded := Records.load_from(TEMP)
	assert_eq(loaded.rows.size(), 1, "the entry is in place")
	assert_eq(loaded.best(), 4200, "and the score is the same")
	assert_eq(String(loaded.rows[0][Records.DATE]), "2026-09-13", "and the date too")


func test_a_broken_file_does_not_break_the_game() -> void:
	# The file can be corrupted by hand or left half-written in a power cut. Records
	# are not the kind of thing worth crashing on startup for.
	var file := FileAccess.open(TEMP, FileAccess.WRITE)
	file.store_string("{this is not a table}")
	file.close()

	var loaded := Records.load_from(TEMP)
	assert_eq(loaded.rows.size(), 0, "the table starts afresh")
	# The warning here is expected, and the test counts it: silently swallowing
	# a corrupted file is not allowed, and crashing because of records even less so.
	assert_push_warning("is unreadable", "the player learns the table was lost")


func test_a_missing_file_is_an_empty_table() -> void:
	assert_eq(Records.load_from("user://no_such_records.json").rows.size(), 0)


## A valid table with a wrongly typed entry: the entry is skipped, the rest is read, and the
## game does not stop on a failed conversion (ADR-0060).
func test_a_wrongly_typed_entry_is_skipped() -> void:
	var file := FileAccess.open(TEMP, FileAccess.WRITE)
	file.store_string(
		'[{"score": null}, {"score": "lots"}, {"score": 900, "date": 7}, 5, {"score": 300}]'
	)
	file.close()

	var loaded := Records.load_from(TEMP)
	assert_eq(loaded.rows.size(), 2, "only the entries with a number for a score")
	assert_eq(loaded.best(), 900)
	assert_eq(String(loaded.rows[0][Records.DATE]), "", "a date that is not text is dropped")


## Zero is no record, even in a table with free rows: the menu would celebrate it (ADR-0060).
func test_a_zero_score_is_no_record() -> void:
	var records := Records.new()
	assert_eq(records.submit(0), -1, "zero in an empty table")
	assert_eq(records.submit(-50), -1, "nor below")
	assert_eq(records.rows.size(), 0, "the table stays empty")


## An equal score goes after the ones already in the table: the older one keeps its place.
## Placed before them by an unstable sort, the new row could even push out its own place.
func test_an_equal_score_goes_after_the_older_one() -> void:
	var records := Records.new()
	var many: Array[int] = []
	for index: int in Records.LIMIT - 1:
		many.append(9000 - index * 100)
	many.append(5000)
	records.rows = _rows(many)
	for row: Dictionary in records.rows:
		row[Records.DATE] = "old"
	assert_eq(records.submit(5000, "new"), -1, "the eleventh equal one misses")
	assert_eq(String(records.rows[-1][Records.DATE]), "old", "the old one stays in the table")

	var ties := Records.new()
	ties.rows = _rows([700, 700, 700, 100])
	for row: Dictionary in ties.rows:
		row[Records.DATE] = "old"
	assert_eq(ties.submit(700, "new"), 3, "after the three equal ones")
	assert_eq(String(ties.rows[3][Records.DATE]), "new", "and the table says the same")
	assert_eq(int(ties.rows[4][Records.SCORE]), 100)
