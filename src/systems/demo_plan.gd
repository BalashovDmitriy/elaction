class_name DemoPlan
extends RefCounted

## Демо-режим (ADR-0041): когда включается, сколько идёт и откуда.
##
## Как в автомате: демо стартует по очереди с трёх мест — верха, середины и низа
## здания, — идёт около 30 с и кончается смертью Otto. Играет бот тестов, а не
## запись нажатий. Правило без узлов, как [OttoStateMachine]; ведёт демо в игре
## [DemoRun].

## Откуда демо стартует.
enum Point { ROOF, MIDDLE, BOTTOM }

## Сколько бездействия в главном меню до демо, с (решение пользователя).
const IDLE_TIME: float = 45.0
## Сколько идёт демо, с — между записями ROM (25 и 35 с).
const LENGTH: float = 30.0

## Этажи старта по счёту ROM — снизу, из тридцати: 18 и 5 (`$802C`). Верхняя
## точка — крыша с вертолётом, а не 28-й этаж ROM: вертолёт — лучшее, что есть
## у здания.
const ROM_FLOORS: Dictionary = {Point.MIDDLE: 18, Point.BOTTOM: 5}

## На сколько этажей от этажа ROM демо ищет шахту, чья кабина начинает с этого
## этажа: там бот садится сразу, а не ждёт кабину полдемо.
const SHAFT_SEARCH: int = 4


## Следующая точка по кругу.
static func next(point: int) -> int:
	return (point + 1) % Point.size()


## Индекс этажа старта для здания с [param floors] этажами: у нас они считаются
## сверху, у ROM — снизу. Для крыши — [constant BuildingRules.ROOF].
static func floor_of(point: int, floors: int) -> int:
	if not ROM_FLOORS.has(point):
		return BuildingRules.ROOF
	return clampi(floors - int(ROM_FLOORS[point]), 0, floors - 1)
