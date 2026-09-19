class_name DoorCycle
extends RefCounted

## Ход створки двери: закрыта, открывается, открыта, закрывается.
##
## Ни узлов, ни физики: узел двери спрашивает, что показывать, и исполняет.
## Поэтому ход проверяется без сцены — тем же приёмом, что [OttoStateMachine],
## [ElevatorMotion] и [DoorVisit]. Основания — ADR-0020, решение 1.
##
## Отделён от [DoorVisit] нарочно. Тот про правила визита — кого пустить и когда
## выпустить; этот про саму створку, которой всё равно, кто её открыл: Otto,
## пришедший за документом, или агент, идущий в засаду.

enum Phase { CLOSED, OPENING, OPEN, CLOSING }

## Сколько идёт створка в одну сторону, с. Задаётся тем, кто открывает: визит
## Otto быстрый, выход агента медленный, потому что он ещё и предупреждение
## (ADR-0020, решение 2).
var travel_time: float = 0.25

var phase: Phase = Phase.CLOSED

## Насколько створка отошла: 0 — закрыта, 1 — открыта настежь.
var _openness: float = 0.0


## Открывает створку. Уже открытую не трогает.
func open() -> void:
	if phase != Phase.OPEN:
		phase = Phase.OPENING


## Закрывает створку. Уже закрытую не трогает.
func close() -> void:
	if phase != Phase.CLOSED:
		phase = Phase.CLOSING


## Шаг створки.
func tick(delta: float) -> void:
	if phase == Phase.OPENING:
		_openness = minf(_openness + _step(delta), 1.0)
		if _openness >= 1.0:
			phase = Phase.OPEN
	elif phase == Phase.CLOSING:
		_openness = maxf(_openness - _step(delta), 0.0)
		if _openness <= 0.0:
			phase = Phase.CLOSED


## Открыта ли створка настежь: только тогда из двери можно выйти.
func is_open() -> bool:
	return phase == Phase.OPEN


## Закрыта ли створка совсем: только такую дверь можно занять заново.
func is_shut() -> bool:
	return phase == Phase.CLOSED


## Ход створки, 0..1. По нему узел и ведёт картинку (ADR-0020, решение 7).
func openness() -> float:
	return _openness


## Доля хода за кадр. Нулевое время хода — мгновенная створка, а не деление
## на ноль: так дверь без анимации остаётся рабочей дверью.
func _step(delta: float) -> float:
	return delta / travel_time if travel_time > 0.0 else 1.0
