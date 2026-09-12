class_name FloorLighting
extends RefCounted

## Свет этажей здания.
##
## Сбитая лампа гасит свой этаж, и обратно он не загорается — сознательный отход
## от оригинала, где гаснет всё здание и секунд на пять (ADR-0006, пункт 7).
##
## Класс только помнит, где темно. Картинку и поведение агентов по нему настраивает
## уровень, поэтому проверяется без сцены.

var _dark: Dictionary = {}


## Гасит этаж. Возвращает false, если он и так был погашен.
func darken(floor_index: int) -> bool:
	if _dark.has(floor_index):
		return false
	_dark[floor_index] = true
	return true


func is_dark(floor_index: int) -> bool:
	return _dark.has(floor_index)


## Сколько этажей уже погашено.
func dark_floors() -> int:
	return _dark.size()
