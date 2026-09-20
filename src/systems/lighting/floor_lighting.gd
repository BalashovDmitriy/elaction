class_name FloorLighting
extends RefCounted

## Свет этажей здания — по зонам ламп.
##
## На этаже несколько ламп, и каждая освещает свою зону: полосу этажа, к которой
## она ближе остальных, с границами посередине между соседями. Сбитая лампа
## гасит свою зону, и обратно та не загорается (ADR-0023, решение 2).
##
## Это второй шаг от оригинала: в 1983 гасло всё здание на несколько секунд,
## ADR-0007 сделал темноту поэтажной и навсегда, здесь она стала зонной — иначе
## с несколькими лампами на этаж любой выстрел был бы выключателем всего этажа.
##
## Класс только помнит, где лампы и какие погашены. Картинку и поведение агентов
## по нему настраивает уровень, поэтому проверяется без сцены.

## Лампы по этажам: этаж → x ламп по возрастанию.
var _lamps: Dictionary = {}
## Погашенные лампы: этаж → {номер лампы в списке этажа: true}.
var _dark: Dictionary = {}


## Вешает лампу на этаж. Зовёт уровень, раскладывая здание: зона считается
## от того, что висит, а не от того, что задумано.
func hang(floor_index: int, x: float) -> void:
	if not _lamps.has(floor_index):
		_lamps[floor_index] = PackedFloat64Array()
	var xs: PackedFloat64Array = _lamps[floor_index]
	xs.append(x)
	xs.sort()
	_lamps[floor_index] = xs


## Гасит зону лампы, ближайшей к [param x]. Лампа падает там же, где висела,
## поэтому её место и есть её зона. Возвращает false, если зона уже была погашена
## или ламп на этаже нет вовсе.
func darken(floor_index: int, x: float) -> bool:
	var index := _nearest(floor_index, x)
	if index < 0:
		return false
	if not _dark.has(floor_index):
		_dark[floor_index] = {}
	var dark: Dictionary = _dark[floor_index]
	if dark.has(index):
		return false
	dark[index] = true
	return true


## Темно ли в точке этажа: погашена ли зона ближайшей к ней лампы.
## Этаж без ламп — крыша — не гаснет никогда: ему светит город.
func is_dark_at(floor_index: int, x: float) -> bool:
	var index := _nearest(floor_index, x)
	if index < 0 or not _dark.has(floor_index):
		return false
	return (_dark[floor_index] as Dictionary).has(index)


## Погашен ли этаж целиком: все его зоны, и хоть одна у него есть.
func is_dark(floor_index: int) -> bool:
	if not _lamps.has(floor_index) or not _dark.has(floor_index):
		return false
	var xs: PackedFloat64Array = _lamps[floor_index]
	return (_dark[floor_index] as Dictionary).size() >= xs.size()


## Где висит лампа, чья зона накрывает точку. NAN, если ламп на этаже нет.
func zone_of(floor_index: int, x: float) -> float:
	var index := _nearest(floor_index, x)
	if index < 0:
		return NAN
	return (_lamps[floor_index] as PackedFloat64Array)[index]


## Сколько зон уже погашено во всём здании.
func dark_zones() -> int:
	var total := 0
	for floor_index: int in _dark:
		total += (_dark[floor_index] as Dictionary).size()
	return total


## Номер ближайшей к точке лампы этажа или -1. При равном расстоянии — левая:
## граница зон принадлежит той лампе, что ближе к началу этажа.
func _nearest(floor_index: int, x: float) -> int:
	if not _lamps.has(floor_index):
		return -1
	var xs: PackedFloat64Array = _lamps[floor_index]
	var best := -1
	var best_gap := INF
	for index in xs.size():
		var gap := absf(xs[index] - x)
		if gap < best_gap:
			best_gap = gap
			best = index
	return best
