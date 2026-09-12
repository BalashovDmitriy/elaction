class_name DocumentRoute
extends RefCounted

## Выбор двери, к которой возвращают за пропущенным документом.
##
## Отдельно от узлов, чтобы проверяться без сцены. Правило — в ADR-0005, пункт 5:
## выход из здания не блокируется, но без всех документов Otto переносит на самый
## верхний этаж, где красная дверь ещё не открыта.


## Индекс самой верхней несобранной двери или -1, если возвращать не за чем.
##
## Верхняя — с наименьшей y. При равенстве берём левую: оригинал этот случай не
## описывает, а правило должно быть однозначным, иначе перенос станет случайным.
static func door_to_return_to(pending: PackedVector2Array) -> int:
	var best := -1
	for index: int in pending.size():
		if best < 0 or _is_higher(pending[index], pending[best]):
			best = index
	return best


static func _is_higher(candidate: Vector2, current: Vector2) -> bool:
	if not is_equal_approx(candidate.y, current.y):
		return candidate.y < current.y
	return candidate.x < current.x
