class_name OttoBot
extends RefCounted

## Бот, проходящий здание: спускается сверху вниз, собирает документы, уходит в выход.
##
## Водится **по состоянию, а не по времени**: не «держи вправо 3.5 секунды», а
## «держи вправо, пока не дойдёшь». Тесты по выдержкам в этом проекте ломались
## четырежды подряд — на сценариях съёмки — и каждый раз молча снимали не то, что
## обещали. Здесь такого быть не должно: бот смотрит, где он есть, и решает заново.
##
## Спуск жадный, потому что генератор это гарантирует: на каждом этаже есть шахта
## своей полосы, а на каждом стыке полос — эскалатор.

## Насколько близко к цели по горизонтали считается «дошёл», px.
const REACHED: float = 6.0

## Где встать рядом с шахтой, ожидая кабину, px от её оси. У самого края проёма:
## кабина стоит на этаже недолго, и от дальней точки бот не успевал войти.
const WAIT_ASIDE: float = 32.0

## Насколько кабина считается пришедшей на этаж, px.
const CAR_ALIGNED: float = 4.0

var _level: GreyboxLevel
var _rules: BuildingRules
var _otto: Otto
var _pressed: Array[StringName] = []
## Была ли кабина на этаже в прошлом кадре и идём ли мы в неё.
var _car_was_here: bool = false
var _boarding: bool = false


func _init(level: GreyboxLevel) -> void:
	_level = level
	_rules = level.rules
	_otto = level.otto


## Один шаг решения. Зовётся каждый физический кадр.
func step() -> void:
	_release_all()
	if _otto.is_dead():
		return

	var floor_index := _rules.floor_index_near(_otto.global_position.y)

	if _riding_further(floor_index):
		_ride_down()
		return

	var door := _document_door_on(floor_index)
	if door != null:
		_approach_door(door)
		return

	if floor_index == _rules.floors - 1:
		_walk_to(_level.exit_position().x)
		return

	_descend(floor_index)


## Отпускает всё, что держал: без этого Otto продолжал бы идти после смены решения.
func release() -> void:
	_release_all()


## Везёт ли кабина дальше, или пора выходить и идти своим ходом.
##
## Сравнение идёт с самим полом, а не с номером этажа: номер меняется на
## полпути, и бот бросал ехать, вися в полупролёте, откуда выйти нельзя.
##
## А стоящую на этаже кабину бот проходит насквозь по дороге к эскалатору, и
## считать это поездкой нельзя: иначе он разворачивался и ходил туда-сюда.
func _riding_further(here: int) -> bool:
	if not _otto.is_riding():
		return false

	var shaft := _shaft_on(here)
	if shaft == null:
		return true
	var surface := _rules.floor_surface(_stop_floor(shaft, here))
	return _otto.global_position.y < surface - CAR_ALIGNED


func _ride_down() -> void:
	_press(&"move_down")


## На каком этаже выходить: на ближайшем снизу с документом, иначе в самом низу полосы.
func _stop_floor(shaft: BuildingPlan.ShaftSpot, here: int) -> int:
	for index in range(maxi(shaft.top, here), shaft.bottom + 1):
		if _document_door_on(index) != null:
			return index
	return shaft.bottom


func _descend(floor_index: int) -> void:
	var shaft := _shaft_on(floor_index)
	if shaft != null and floor_index < shaft.bottom:
		_take_the_car(shaft, floor_index)
		return

	var escalator := _escalator_on(floor_index)
	if escalator != null:
		_take_the_escalator(escalator)
		return

	# Ни шахты вниз, ни эскалатора: дальше бот не знает, что делать.
	_walk_to(_rules.slot_x(0))


## Заходит в кабину, дождавшись её. В пустой проём шагать нельзя — это падение.
## Заходит в кабину, дождавшись её у самого края проёма.
##
## Входит только на приезд кабины и только стоя рядом. Если заходить в любой
## момент стоянки, можно попасть на её конец: кабина уедет, пока бот делает
## последние шаги, и он шагнёт в пустую шахту — а падение в неё смертельно.
## Пропустить приезд не страшно: кабина вернётся, кадров на это заложено.
func _take_the_car(shaft: BuildingPlan.ShaftSpot, floor_index: int) -> void:
	var surface := _rules.floor_surface(floor_index)
	var here := _car_waits_at(shaft.x, surface)
	var aside := absf(_otto.global_position.x - shaft.x) <= WAIT_ASIDE + REACHED

	if here and not _car_was_here and aside:
		_boarding = true
	if not here:
		_boarding = false
	_car_was_here = here

	if _boarding:
		_walk_to(shaft.x)
		return

	var side := -1.0 if _otto.global_position.x < shaft.x else 1.0
	_walk_to(shaft.x + side * WAIT_ASIDE)


func _take_the_escalator(escalator: BuildingPlan.EscalatorSpot) -> void:
	if not _walk_to(escalator.x):
		return
	_press(&"move_down")


func _approach_door(door: BuildingPlan.DoorSpot) -> void:
	if not _walk_to(door.x):
		return
	_press(&"move_up")


## Идёт к точке. Возвращает true, когда уже пришёл.
func _walk_to(x: float) -> bool:
	var gap := x - _otto.global_position.x
	if absf(gap) <= REACHED:
		return true
	_press(&"move_right" if gap > 0.0 else &"move_left")
	return false


func _car_waits_at(x: float, surface: float) -> bool:
	for child in _level.get_children():
		var car := child as ElevatorCar
		if car == null:
			continue
		if absf(car.global_position.x - x) > CAR_ALIGNED:
			continue
		if absf(car.global_position.y - surface) <= CAR_ALIGNED:
			return true
	return false


func _document_door_on(floor_index: int) -> BuildingPlan.DoorSpot:
	for spot in _level.plan().doors:
		if spot.has_document and spot.floor_index == floor_index and _still_pending(spot):
			return spot
	return null


## Дверь ещё красная: собранная перестаёт ею быть, и второй раз в неё не надо.
##
## Сверяется и этаж: места на этажах общие, и красная дверь сверху, стоящая в том
## же столбце, выдавала бы уже собранную за несобранную — бот ходил бы к ней вечно.
func _still_pending(spot: BuildingPlan.DoorSpot) -> bool:
	for door in _level.doors():
		if not door.is_pending():
			continue
		var mat := door.mat_position()
		if absf(mat.x - spot.x) <= REACHED and _rules.floor_index_near(mat.y) == spot.floor_index:
			return true
	return false


func _shaft_on(floor_index: int) -> BuildingPlan.ShaftSpot:
	for shaft in _level.plan().shafts:
		if floor_index >= shaft.top and floor_index <= shaft.bottom:
			return shaft
	return null


func _escalator_on(floor_index: int) -> BuildingPlan.EscalatorSpot:
	for escalator in _level.plan().escalators:
		if escalator.floor_index == floor_index:
			return escalator
	return null


func _press(action: StringName) -> void:
	Input.action_press(action)
	_pressed.append(action)


func _release_all() -> void:
	for action in _pressed:
		Input.action_release(action)
	_pressed.clear()
