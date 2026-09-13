class_name GameState
extends Node

## Состояние партии: счёт, жизни и прогресс по документам.
##
## Первый синглтон игрового состояния в проекте. Двери, HUD и выход не знают друг
## о друге и связываются через него сигналами — как предписывают соглашения.
## Здесь же живёт партия целиком: номер здания и тревога.
##
## В дерево его ставит автолоад `Game`, а код обращается через [method instance].
## Имя автолоада само по себе идентификатором не является: `--check-only` разбирает
## каждый скрипт по отдельности и таких имён не знает, а имя класса знает. Побочная
## выгода — тесты создают свой экземпляр и глобального не трогают.

signal score_changed(value: int)
signal documents_changed(collected: int, total: int)
signal lives_changed(value: int)

## Выдана дополнительная жизнь за очки. Отдельно от [signal lives_changed]:
## HUD по нему показывает, за что жизнь прибавилась, а звук — что вообще.
signal extra_life_awarded
## Жизни кончились. Партия окончена.
signal game_over

## Otto вошёл в новое здание.
signal building_changed(number: int)

## Провозились: агенты злеют, кабина отвечает с задержкой (ADR-0009).
signal alarm_raised

## Таблица очков оригинала (ADR-0005, пункт 1 и ADR-0006, пункт 5).
const DOCUMENT_SCORE: int = 500
const ENEMY_SHOT_SCORE: int = 100
const ENEMY_KICK_SCORE: int = 150
const LAMP_SCORE: int = 300

## Надбавка за убийство на погашенном этаже. Плоская, а не множитель: сверка
## перед M6 нашла таблицу — выстрел 100, выстрел в темноте 150, ногой 150,
## ногой в темноте 200 (ADR-0010, пункт 6). До сверки здесь стояло удвоение.
const DARK_KILL_BONUS: int = 50

## Жизней на партию — три, как в оригинале (ADR-0006, пункт 4).
const STARTING_LIVES: int = 3

## Дополнительная жизнь за очки. Порог — минимальный из четырёх, которые
## мануал Taito отдаёт DIP-переключателями (ADR-0012, пункт 5): 10 000.
##
## Выдаётся один раз за партию. Повтор каждые десять тысяч мануалом не
## подтверждён, а на тёмном этаже с респавном агентов он превратился бы
## в бесконечные жизни — эту ферму мы себе уже предсказывали в ADR-0010.
const EXTRA_LIFE_SCORE: int = 10000

## Бонус за сданное здание: 1000 × его номер. Источники расходятся, взят
## вариант с множителем — ADR-0008, пункт 5. Не сверено.
const BUILDING_BONUS: int = 1000

static var _instance: GameState = null

var score: int = 0
var lives: int = STARTING_LIVES
var documents_collected: int = 0
var documents_total: int = 0

## Номер здания, он же сид его раскладки.
var building: int = 1
var alarm := Alarm.new()

## Идёт ли партия. На паузе и после Game Over время не тикает.
var _running: bool = false

## Выдана ли уже дополнительная жизнь в этой партии.
var _extra_life_given: bool = false


## Состояние партии. До входа автолоада в дерево — null.
static func instance() -> GameState:
	return _instance


## Очки за убитого агента с учётом того, темно ли там, где его достали.
static func kill_score(base: int, in_the_dark: bool) -> int:
	return base + DARK_KILL_BONUS if in_the_dark else base


func _enter_tree() -> void:
	# Экземпляр из автолоада входит в дерево первым и становится общим.
	if _instance == null:
		_instance = self


func _process(delta: float) -> void:
	if not _running:
		return
	if alarm.tick(delta):
		alarm_raised.emit()


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


## Начинает партию заново: счёт, жизни, первое здание.
func start_game() -> void:
	reset()
	_running = true
	building_changed.emit(building)


## Здание сдано: бонус за него и переход к следующему. Тревога снимается
## только здесь — смерть её не снимала и не снимет.
func finish_building() -> void:
	add_score(BUILDING_BONUS * building)
	building += 1
	alarm.enter_building()
	building_changed.emit(building)


## Начинает партию в здании с известным числом красных дверей.
func start_building(total_documents: int) -> void:
	documents_total = maxi(total_documents, 0)
	documents_collected = 0
	documents_changed.emit(documents_collected, documents_total)


## Обнуляет всё: счёт, жизни, документы, номер здания и тревогу.
func reset() -> void:
	score = 0
	lives = STARTING_LIVES
	documents_collected = 0
	documents_total = 0
	building = 1
	_extra_life_given = false
	alarm.enter_building()
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
	_running = false
	game_over.emit()
	return false


func add_score(points: int) -> void:
	score += points
	score_changed.emit(score)
	_check_extra_life()


## Дополнительная жизнь за очки — один раз за партию и только пока она идёт.
##
## После Game Over очки ещё начисляются (бонус за здание приходит отложенно),
## и без этой проверки мёртвому выдавали бы жизнь, с которой он не оживёт.
func _check_extra_life() -> void:
	if _extra_life_given or score < EXTRA_LIFE_SCORE or lives <= 0:
		return
	_extra_life_given = true
	lives += 1
	lives_changed.emit(lives)
	extra_life_awarded.emit()


## Собраны ли все документы здания. Здание без красных дверей считается собранным.
func all_documents_collected() -> bool:
	return documents_collected >= documents_total
