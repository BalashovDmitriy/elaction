class_name LampFall
extends RefCounted

## Падение лампы: сбита или нет, сколько пролетела, долетела ли.
##
## Ни узлов, ни физики — узел спрашивает, на сколько сдвинуться в этом кадре.
## Тем же приёмом, что [DoorVisit] и [EnemyBrain]: правила проверяются без сцены,
## как требуют соглашения проекта.

## Скорость падения, px/с.
var speed: float = 260.0

## Сколько лететь до пола, px. Считается от формы самой лампы.
var distance: float = 40.0

var falling: bool = false

var _fallen: float = 0.0


## Сбивает лампу. Возвращает false, если она уже падает или давно упала: иначе
## вторая пуля в том же кадре подняла бы её обратно — узел исчезает не сразу.
func start() -> bool:
	if falling or _fallen > 0.0:
		return false
	falling = true
	return true


## На сколько лампа сдвигается вниз в этом кадре. Ноль, пока висит или уже упала.
func advance(delta: float) -> float:
	if not falling:
		return 0.0

	var step := minf(speed * delta, distance - _fallen)
	_fallen += step
	if _fallen >= distance:
		falling = false
	return step


## Долетела ли лампа до пола.
func has_landed() -> bool:
	return _fallen >= distance
