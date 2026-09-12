class_name GameState
extends Node

## Состояние партии: счёт и прогресс по документам.
##
## Первый синглтон игрового состояния в проекте. Двери, HUD и выход не знают друг
## о друге и связываются через него сигналами — как предписывают соглашения.
## В M4 сюда приедут жизни, в M5 — номер здания.
##
## В дерево его ставит автолоад `Game`, а код обращается через [method instance].
## Имя автолоада само по себе идентификатором не является: `--check-only` разбирает
## каждый скрипт по отдельности и таких имён не знает, а имя класса знает. Побочная
## выгода — тесты создают свой экземпляр и глобального не трогают.

signal score_changed(value: int)
signal documents_changed(collected: int, total: int)

## Очки за документ — по таблице оригинала (ADR-0005, пункт 1).
const DOCUMENT_SCORE: int = 500

static var _instance: GameState = null

var score: int = 0
var documents_collected: int = 0
var documents_total: int = 0


## Состояние партии. До входа автолоада в дерево — null.
static func instance() -> GameState:
	return _instance


func _enter_tree() -> void:
	# Экземпляр из автолоада входит в дерево первым и становится общим.
	if _instance == null:
		_instance = self


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


## Начинает партию в здании с известным числом красных дверей.
func start_building(total_documents: int) -> void:
	documents_total = maxi(total_documents, 0)
	documents_collected = 0
	documents_changed.emit(documents_collected, documents_total)


## Обнуляет всё, включая счёт.
func reset() -> void:
	score = 0
	documents_collected = 0
	documents_total = 0
	score_changed.emit(score)
	documents_changed.emit(documents_collected, documents_total)


## Засчитывает поднятый документ вместе с очками за него.
func collect_document() -> void:
	documents_collected += 1
	documents_changed.emit(documents_collected, documents_total)
	add_score(DOCUMENT_SCORE)


func add_score(points: int) -> void:
	score += points
	score_changed.emit(score)


## Собраны ли все документы здания. Здание без красных дверей считается собранным.
func all_documents_collected() -> bool:
	return documents_collected >= documents_total
