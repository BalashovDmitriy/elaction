class_name GameState
extends Node

## Состояние партии: счёт, жизни и прогресс по документам.
##
## Первый синглтон игрового состояния в проекте. Двери, HUD и выход не знают друг
## о друге и связываются через него сигналами — как предписывают соглашения.
## В M5 сюда приедет номер здания.
##
## В дерево его ставит автолоад `Game`, а код обращается через [method instance].
## Имя автолоада само по себе идентификатором не является: `--check-only` разбирает
## каждый скрипт по отдельности и таких имён не знает, а имя класса знает. Побочная
## выгода — тесты создают свой экземпляр и глобального не трогают.

signal score_changed(value: int)
signal documents_changed(collected: int, total: int)
signal lives_changed(value: int)
## Жизни кончились. Партия окончена.
signal game_over

## Таблица очков оригинала (ADR-0005, пункт 1 и ADR-0006, пункт 5).
const DOCUMENT_SCORE: int = 500
const ENEMY_SHOT_SCORE: int = 100
const ENEMY_KICK_SCORE: int = 150
const LAMP_SCORE: int = 300

## Во сколько раз дороже убийство на погашенном этаже. Надбавка в оригинале
## есть, но её размер не называет ни один источник — ADR-0007, пункт 5.
const DARK_KILL_MULTIPLIER: int = 2

## Жизней на партию — три, как в оригинале (ADR-0006, пункт 4).
const STARTING_LIVES: int = 3

static var _instance: GameState = null

var score: int = 0
var lives: int = STARTING_LIVES
var documents_collected: int = 0
var documents_total: int = 0


## Состояние партии. До входа автолоада в дерево — null.
static func instance() -> GameState:
	return _instance


## Очки за убитого агента с учётом того, темно ли там, где его достали.
static func kill_score(base: int, in_the_dark: bool) -> int:
	return base * DARK_KILL_MULTIPLIER if in_the_dark else base


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
	lives = STARTING_LIVES
	documents_collected = 0
	documents_total = 0
	score_changed.emit(score)
	lives_changed.emit(lives)
	documents_changed.emit(documents_collected, documents_total)


## Засчитывает поднятый документ вместе с очками за него.
func collect_document() -> void:
	documents_collected += 1
	documents_changed.emit(documents_collected, documents_total)
	add_score(DOCUMENT_SCORE)


## Снимает жизнь. Возвращает true, если Otto ещё может вернуться в игру.
##
## После конца партии ничего не делает: [signal game_over] сообщает о переходе,
## а не о состоянии, и повторно он не приходит.
func lose_life() -> bool:
	if lives <= 0:
		return false
	lives -= 1
	lives_changed.emit(lives)
	if lives > 0:
		return true
	game_over.emit()
	return false


func add_score(points: int) -> void:
	score += points
	score_changed.emit(score)


## Собраны ли все документы здания. Здание без красных дверей считается собранным.
func all_documents_collected() -> bool:
	return documents_collected >= documents_total
