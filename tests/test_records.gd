extends GutTest

## Тесты таблицы рекордов.
##
## Правила таблицы — чистые функции, и проверяются без диска. На диск ходят
## только два теста: рекорд, переживший перезапуск, — единственное, ради чего
## таблица вообще существует.

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
	# Одиннадцатая строка никому не интересна, а файл растёт вечно.
	var many: Array[int] = []
	for index: int in 25:
		many.append(index * 100)
	assert_eq(Records.sorted(_rows(many)).size(), Records.LIMIT)


func test_a_good_score_gets_its_place() -> void:
	var records := Records.new()
	records.rows = _rows([1000, 500])
	assert_eq(records.submit(2000), 0, "лучший счёт встаёт первым")
	assert_eq(records.submit(700), 2, "средний — между соседями")


func test_a_poor_score_does_not_make_the_table() -> void:
	var records := Records.new()
	var many: Array[int] = []
	for index: int in Records.LIMIT:
		many.append(10000 + index)
	records.rows = _rows(many)
	assert_eq(records.submit(5), -1, "в десятку не попал")
	assert_eq(records.rows.size(), Records.LIMIT, "и таблицу не раздул")


func test_a_repeated_score_does_not_fake_a_record() -> void:
	# Тот же счёт в тот же день бывает дважды. Поиск строки по паре «счёт и дата»
	# находил чужую — и счёт, не попавший в десятку, объявлялся рекордом.
	var records := Records.new()
	var many: Array[int] = []
	for _index: int in Records.LIMIT:
		many.append(7000)
	records.rows = _rows(many)
	assert_eq(records.submit(7000, "2026-09-13"), -1, "одиннадцатый такой же — мимо")


func test_the_best_of_an_empty_table_is_zero() -> void:
	# HUD и меню показывают число, и особый случай им ни к чему.
	assert_eq(Records.new().best(), 0)


func test_records_survive_a_restart() -> void:
	var records := Records.new()
	records.submit(4200, "2026-09-13")
	records.save_to(TEMP)

	var loaded := Records.load_from(TEMP)
	assert_eq(loaded.rows.size(), 1, "запись на месте")
	assert_eq(loaded.best(), 4200, "и счёт тот же")
	assert_eq(String(loaded.rows[0][Records.DATE]), "2026-09-13", "и дата тоже")


func test_a_broken_file_does_not_break_the_game() -> void:
	# Файл можно испортить руками или недописать при отключении света. Рекорды
	# не та вещь, ради которой стоит падать на запуске.
	var file := FileAccess.open(TEMP, FileAccess.WRITE)
	file.store_string("{это не таблица}")
	file.close()

	var loaded := Records.load_from(TEMP)
	assert_eq(loaded.rows.size(), 0, "таблица начинается заново")
	# Предупреждение здесь ожидаемое, и тест его засчитывает: молча глотать
	# испорченный файл нельзя, а падать из-за рекордов — тем более.
	assert_push_warning("не читается", "игрок узнает, что таблица потеряна")


func test_a_missing_file_is_an_empty_table() -> void:
	assert_eq(Records.load_from("user://no_such_records.json").rows.size(), 0)
