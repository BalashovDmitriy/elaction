class_name DemoRun
extends Node

## Одно демо (ADR-0041): здание, бот за Otto и отсчёт до конца.
##
## Ставит Otto в точку старта [DemoPlan], ведёт бота тем же темпом, что в тестах, —
## решение раз в два шага физики (правило M13, `docs/testing.md`), — и сообщает
## [signal finished], когда время вышло или Otto погиб. Живёт под зданием: здание
## выбросили — демо уходит с ним.

## Демо кончилось само: время вышло или Otto погиб.
signal finished

var _level: GreyboxLevel = null
var _bot: OttoBot = null
var _point: int = DemoPlan.Point.ROOF
var _time: float = 0.0
var _frame: int = 0
var _done: bool = false


## Демо в здании [param level] с точки [param point]. Узел встаёт под здание.
static func start(level: GreyboxLevel, point: int) -> DemoRun:
	var run := DemoRun.new()
	run.name = "Demo"
	run._level = level
	run._point = point
	level.add_child(run)
	return run


## С какой точки идёт демо. Тестам.
func point() -> int:
	return _point


func _ready() -> void:
	_level.otto.died.connect(_finish)
	if _point != DemoPlan.Point.ROOF:
		_place()


## Останавливает бота: отпускает всё, что он держит. Здание при этом живёт —
## остановить его дело того, кто кончает демо.
func stop() -> void:
	_done = true
	if _bot != null:
		_bot.release()


func _physics_process(delta: float) -> void:
	if _done:
		return
	_time += delta
	if _time >= DemoPlan.LENGTH:
		_finish()
		return
	# Вступление с вертолётом смотрят, а не пропускают: бот жмёт выстрел и прыжок,
	# а ими вступление и пропускается.
	if _level.is_in_the_intro() or (_bot == null and not _level.otto.is_grounded()):
		return
	if _bot == null:
		_bot = OttoBot.new(_level)
	_frame += 1
	if _frame % 2 == 0:
		_bot.step()


## Середина и низ: вступление пропущено, Otto — на свободном месте этажа старта.
## Снизу подвал открыт: документы с этажей выше засчитаны, и бот идёт к выходу,
## а не наверх за ними.
func _place() -> void:
	_level.skip_the_intro()
	var rules := _level.rules
	var index := DemoPlan.floor_of(_point, rules.floors)
	var spots := _level.plan().safe_spots(rules, index)
	if spots.is_empty():
		return
	var x: float = spots[spots.size() / 2]
	_level.otto.global_position = WorldSpace.to_scene(Vector2(x, rules.floor_surface(index)))
	if _point == DemoPlan.Point.BOTTOM:
		var game := GameState.instance()
		for door: Door in _level.doors():
			if door.is_pending() and rules.floor_index_near(door.mat_position().y) < index:
				door.has_document = false
				game.collect_document()


func _finish() -> void:
	if _done:
		return
	stop()
	finished.emit()
