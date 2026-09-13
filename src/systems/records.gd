class_name Records
extends RefCounted

## Таблица рекордов: десять строк со счётом и датой.
##
## Без ввода инициалов (ADR-0012, пункт 9): ритуал зала, где за автоматом стоит
## очередь, дома превращается в лишний экран между смертью и следующей партией.
##
## Правила таблицы — чистые функции над массивом, и проверяются они без диска:
## сортировка, обрезка до десяти и место нового счёта. На диск ходят только
## [method load_from] и [method save_to].

const PATH := "user://records.json"

## Сколько строк держим. Одиннадцатая никому не интересна.
const LIMIT: int = 10

## Счёт и дата одной записи.
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

	# Разбор через экземпляр, а не [method JSON.parse_string]: статический
	# помощник на кривом файле сам пишет ошибку в лог движка, и испорченная
	# таблица выглядела бы как поломка игры.
	var json := JSON.new()
	var failed := json.parse(file.get_as_text()) != OK
	file.close()

	var parsed: Variant = json.data
	if failed or parsed is not Array:
		# Файл испорчен или дописан руками: таблица начинается заново, но игра
		# из-за этого не падает — рекорды не та вещь, ради которой стоит падать.
		push_warning("Таблица рекордов не читается, начинаем заново: %s" % path)
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
		push_warning("Таблица рекордов не сохранилась: %s" % path)
		return
	file.store_string(JSON.stringify(rows))
	file.close()


## Добавляет счёт и возвращает его место в таблице, считая с нуля.
## Не попал в десятку — вернётся -1.
func submit(score: int, date: String = "") -> int:
	var stamp := date if not date.is_empty() else today()
	rows = sorted(rows + [{SCORE: score, DATE: stamp}])
	for index: int in rows.size():
		if rows[index][SCORE] == score and rows[index][DATE] == stamp:
			return index if index < LIMIT else -1
	return -1


## Лучший счёт таблицы. Пустая таблица — ноль, а не отсутствие значения:
## HUD и меню показывают число, и особый случай им ни к чему.
func best() -> int:
	return int(rows[0][SCORE]) if not rows.is_empty() else 0


## Сортировка по убыванию с обрезкой до [constant LIMIT].
##
## Статическая и без состояния: правило таблицы проверяется тестом прямо так,
## без файлов и без экземпляра.
static func sorted(entries: Array) -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for entry: Variant in entries:
		copy.append(entry as Dictionary)
	copy.sort_custom(
		func(first: Dictionary, second: Dictionary) -> bool:
			return int(first[SCORE]) > int(second[SCORE])
	)
	return copy.slice(0, LIMIT)


## Сегодняшняя дата в виде «2026-09-13».
static func today() -> String:
	var now := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [now["year"], now["month"], now["day"]]
