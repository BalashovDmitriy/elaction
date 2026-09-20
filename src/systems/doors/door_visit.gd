class_name DoorVisit
extends RefCounted

## Правила посещения двери: кого пускать и когда выпускать.
##
## Ни узлов, ни физики: узел двери подставляет факты о госте и исполняет решение,
## а решает этот класс. Поэтому правила проверяются без сцены — тем же приёмом,
## что [OttoStateMachine] и [ElevatorMotion]. Основания — ADR-0005, пункты 2-3.
##
## Створку он не ведёт: это дело [DoorCycle]. Раньше оба жили здесь и делили один
## таймер, из-за чего дверь агента нельзя было открыть, не заведя гостя
## (ADR-0020, решение 1).

## Сколько гость может пересидеть внутри, с. Ровно ли пять — ждёт сверки в MAME.
var hide_time: float = 5.0

var _timer: float = 0.0
## Отпустил ли гость «вверх» после того, как дверь его выпустила. Без этого та же
## зажатая кнопка втягивала бы его обратно раз за разом: выставили — и сразу взяли.
var _entry_armed: bool = true
## Отпустил ли гость направление после входа. Без этого тот же зажатый «влево»,
## которым он пришёл к двери, вытолкнул бы его в первом же кадре.
var _exit_armed: bool = false


## Просится ли гость внутрь. Спрашивают только про того, кто стоит на коврике.
func knock(grounded: bool, vertical: float) -> bool:
	if vertical > -Intent.PRESS:
		# «Вверх» отпустили: следующее нажатие снова считается просьбой войти.
		_entry_armed = true
		return false
	return _entry_armed and grounded


## Впускает гостя: дальше он сидит внутри, пока не выйдет время или не попросится.
func admit() -> void:
	_timer = hide_time
	_exit_armed = false


## Шаг двери с гостем внутри. Возвращает true, когда его пора выпустить.
##
## [param door_open] — открылась ли створка. Пока она идёт, гость ещё входит:
## время отсидки не течёт и наружу не просятся.
func tick(delta: float, horizontal: float, door_open: bool) -> bool:
	var pressed := absf(horizontal) >= Intent.PRESS
	if not pressed:
		_exit_armed = true

	if not door_open:
		return false

	_timer -= delta
	return _timer <= 0.0 or (pressed and _exit_armed)


## Выпускает гостя наружу.
func release() -> void:
	_entry_armed = false
