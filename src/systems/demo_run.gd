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

## Сколько кабины у уровня старта стоят после того, как бот пошёл, с: дорога
## к шахте с запасом. С крыши демо идёт через
## вертолёт, и за вступление кабины уезжали вниз по расписанию — бот потом ждал
## их у шахты по двадцать секунд, полдемо стоя.
const CAR_WAIT: float = 8.0

var _level: GreyboxLevel = null
var _bot: OttoBot = null
var _point: int = DemoPlan.Point.ROOF
var _time: float = 0.0
## Уровень старта: у него стоянка кабин продлевается, пока Otto не пошёл.
var _start_level: int = BuildingRules.ROOF
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
	# Кабины встают на остановки уже в дереве, не к [method Node._ready] демо, —
	# поэтому стоянка у уровня старта продлевается каждый шаг, пока бот не пошёл.
	if _bot == null:
		_hold_cars_at(_start_level)
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


## Середина и низ: Otto — у шахты, чья кабина начинает с этого этажа, возле этажа
## ROM. Кабины стартуют с верхней остановки своей шахты: Otto посреди случайного
## этажа ждал кабину полдемо стоя (кадры M24E). Снизу подвал открыт: документы с
## этажей выше засчитаны, и бот идёт к выходу, а не наверх за ними.
##
## Вступление снимает сама перестановка, а не [method GreyboxLevel.skip_the_intro]:
## переставленного вступление отпускает и ставит кадр на него снимком. Пропуск
## оставлял кадр вступления на крыше, и камера ехала к Otto через всё здание
## (авторевью M24e).
func _place() -> void:
	var rules := _level.rules
	var wanted := DemoPlan.floor_of(_point, rules.floors)
	var index := wanted
	var near_x := NAN
	var best := DemoPlan.SHAFT_SEARCH + 1
	for shaft: BuildingPlan.ShaftSpot in _level.plan().shafts:
		var gap := absi(shaft.top - wanted)
		if shaft.top >= 0 and gap < best:
			best = gap
			index = shaft.top
			near_x = shaft.x
	_start_level = index
	var spots := _level.plan().safe_spots(rules, index)
	if spots.is_empty():
		_level.skip_the_intro()
		return
	var x: float = spots[spots.size() / 2]
	if not is_nan(near_x):
		# Место рядом с шахтой: там, где бот и ждёт кабину.
		var closest := INF
		for spot: float in spots:
			var gap := absf(absf(spot - near_x) - OttoBot.WAIT_ASIDE)
			if gap < closest:
				closest = gap
				x = spot
	_level.otto.global_position = WorldSpace.to_scene(Vector2(x, rules.floor_surface(index)))
	if _point == DemoPlan.Point.BOTTOM:
		var game := GameState.instance()
		for door: Door in _level.doors():
			if door.is_pending() and rules.floor_index_near(door.mat_position().y) < index:
				door.has_document = false
				game.collect_document(false)


## Кабины у уровня [param level] стоят, пока идёт вступление и бот идёт к шахте.
## Кабина при этом живая: севшего она видит и везёт.
func _hold_cars_at(level: int) -> void:
	var surface := _level.rules.floor_surface(level)
	for child: Node in _level.get_children():
		var car := child as ElevatorCar
		if car != null and absf(WorldSpace.to_plane(car.global_position).y - surface) < 0.5:
			car.hold(CAR_WAIT)


func _finish() -> void:
	if _done:
		return
	stop()
	finished.emit()
