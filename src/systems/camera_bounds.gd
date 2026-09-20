class_name CameraBounds
extends RefCounted

## Куда камере можно смотреть: правило кадрирования отдельно от узла.
##
## [Camera2D] давал это даром — `limit_left`, `limit_top`, сглаживание. У
## [Camera3D] ничего этого нет, и при переезде на 3D всё пришлось бы писать
## в [code]_process[/code] узла. Правило в узле — ошибка по ADR-0021, решение 5,
## поэтому оно здесь и проверяется без сцены.
##
## Работает в координатах сцены (Y вверх): переводит их [WorldSpace], а сюда они
## приходят уже переведёнными.

## Половина кадра по вертикали и горизонтали, м. Задаётся размером ортокамеры
## и соотношением сторон окна.
var half_height: float = 5.4
var half_width: float = 9.6

## Прямоугольник, за который камере нельзя выходить, в координатах сцены.
var limits := Rect2(-INF, -INF, INF, INF)


## Середина кадра, допустимая при этих границах.
##
## Если разрешённая полоса уже кадра, камера встаёт по её середине: упереться
## в оба края разом нельзя, а дёргаться между ними — худшее из возможного.
func clamp_centre(wanted: Vector2) -> Vector2:
	return Vector2(
		_clamp_axis(wanted.x, limits.position.x, limits.end.x, half_width),
		_clamp_axis(wanted.y, limits.position.y, limits.end.y, half_height)
	)


## Что сейчас попадает в кадр, в координатах сцены.
func view_at(centre: Vector2) -> Rect2:
	var size := Vector2(half_width, half_height) * 2.0
	return Rect2(centre - size * 0.5, size)


## Шаг сглаживания: куда камера сдвинется за [param delta] при скорости
## [param speed].
##
## Экспоненциальное приближение, а не линейное: оно не зависит от частоты кадров
## и не даёт камере обгонять цель на просадке. [code]speed <= 0[/code] — жёсткая
## привязка без сглаживания, она нужна тестам и съёмке кадров.
static func smoothed(from: Vector2, towards: Vector2, speed: float, delta: float) -> Vector2:
	if speed <= 0.0 or delta <= 0.0:
		return towards
	return from.lerp(towards, 1.0 - exp(-speed * delta))


func _clamp_axis(wanted: float, low: float, high: float, half: float) -> float:
	if not is_finite(low) or not is_finite(high):
		return wanted
	if high - low <= half * 2.0:
		return (low + high) * 0.5
	return clampf(wanted, low + half, high - half)
