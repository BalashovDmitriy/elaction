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

## Лампы по этажам: этаж → x ламп в порядке развески.
##
## Порядок не трогается после добавления нарочно: номер лампы в этом списке —
## ключ её темноты в [member _dark], и пересортировка списка переставляла бы
## темноту с одной зоны на другую. Кто левее, решает [method _nearest] по x,
## а не по месту в списке.
var _lamps: Dictionary = {}
## Погашенные лампы: этаж → {номер лампы в списке этажа: true}.
var _dark: Dictionary = {}
## Тёмные этажи карты: ламп на них нет, и темны они с начала здания
## (ADR-0028, решение 4). Этаж → true.
var _unlit: Dictionary = {}


## Вешает лампу на этаж. Зовёт уровень, раскладывая здание: зона считается
## от того, что висит, а не от того, что задумано.
func hang(floor_index: int, x: float) -> void:
	if not _lamps.has(floor_index):
		_lamps[floor_index] = PackedFloat64Array()
	var xs: PackedFloat64Array = _lamps[floor_index]
	xs.append(x)
	_lamps[floor_index] = xs


## Объявляет этаж тёмным целиком: ламп на нём нет по карте, а не по тесноте.
##
## Этаж без ламп по умолчанию светел — ему светит город, как крыше. Тёмный этаж
## о себе заявляет сам: зовёт уровень, раскладывая здание, как и [method hang].
func mark_unlit(floor_index: int) -> void:
	_unlit[floor_index] = true


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
## Тёмный этаж карты тёмен везде; прочий этаж без ламп — крыша — не гаснет
## никогда: ему светит город.
func is_dark_at(floor_index: int, x: float) -> bool:
	if _unlit.has(floor_index):
		return true
	var index := _nearest(floor_index, x)
	if index < 0 or not _dark.has(floor_index):
		return false
	return (_dark[floor_index] as Dictionary).has(index)


## Погашен ли этаж целиком: все его зоны, и хоть одна у него есть. Тёмный этаж
## карты погашен всегда.
func is_dark(floor_index: int) -> bool:
	if _unlit.has(floor_index):
		return true
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


## Номер ближайшей к точке лампы этажа или -1. При равном расстоянии — левая:
## граница зон принадлежит той лампе, что ближе к началу этажа. Сравнивается по
## x, а не по месту в списке: порядок развески ответ решать не должен.
func _nearest(floor_index: int, x: float) -> int:
	if not _lamps.has(floor_index):
		return -1
	var xs: PackedFloat64Array = _lamps[floor_index]
	var best := -1
	var best_gap := INF
	for index in xs.size():
		var gap := absf(xs[index] - x)
		var tied := best >= 0 and is_equal_approx(gap, best_gap)
		if gap < best_gap or (tied and xs[index] < xs[best]):
			best_gap = gap
			best = index
	return best
