class_name VisibleFloors
extends RefCounted

## Какие этажи попадают в кадр.
##
## В здании 30 этажей и по источнику света на каждом, а в кадр влезает два
## с половиной. Гореть должны только видимые — ADR-0010, пункт 8.
##
## Считается по номерам этажей, а не по прямоугольнику камеры: высота этажа
## известна, номер — это деление. Поэтому проверяется без сцены и без кадра,
## тем же приёмом, что [OttoStateMachine] и [ElevatorMotion].

## Сколько этажей зажигается сверх видимых, с каждой стороны.
##
## Без запаса источник включался бы ровно на кромке кадра, и въезжающий снизу
## этаж был бы виден тёмным ровно один миг — это заметно и читается как мигание.
const MARGIN: int = 1


## Первый и последний этаж, которым положено гореть, включительно.
##
## [param view] — видимый кусок мира, его отдаёт [method Otto.camera_view].
static func around(rules: BuildingRules, view: Rect2) -> Vector2i:
	var first := rules.floor_index_near(view.position.y) - MARGIN
	var last := rules.floor_index_near(view.end.y) + MARGIN
	return Vector2i(maxi(first, 0), mini(last, rules.floors - 1))


## Попадает ли этаж в кадр. Тот же счёт, что у [method around], только ответ
## про один этаж: уровню удобнее спрашивать так, когда он обходит все подряд.
static func covers(span: Vector2i, index: int) -> bool:
	return index >= span.x and index <= span.y
