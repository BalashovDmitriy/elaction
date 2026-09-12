class_name DoorVisit
extends RefCounted

## Правила посещения двери: кого пускать и когда выпускать.
##
## Ни узлов, ни физики: узел двери подставляет факты о госте и исполняет решение,
## а решает этот класс. Поэтому правила проверяются без сцены — тем же приёмом,
## что [OttoStateMachine] и [ElevatorMotion]. Основания — ADR-0005, пункты 2-3.

enum Phase { CLOSED, OPENING, OPEN }

## Сколько открывается створка, с.
var open_time: float = 0.25

## Сколько гость может пересидеть внутри, с. Ровно ли пять — ждёт сверки в MAME.
var hide_time: float = 5.0

var phase: Phase = Phase.CLOSED

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


## Впускает гостя: створка пошла открываться.
func admit() -> void:
	phase = Phase.OPENING
	_timer = open_time
	_exit_armed = false


## Шаг двери с гостем внутри. Возвращает true, когда его пора выпустить.
func tick(delta: float, horizontal: float) -> bool:
	var pressed := absf(horizontal) >= Intent.PRESS
	if not pressed:
		_exit_armed = true

	_timer -= delta
	if phase == Phase.OPENING:
		# Пока створка открывается, наружу не просятся: гость ещё входит.
		if _timer <= 0.0:
			phase = Phase.OPEN
			_timer = hide_time
		return false

	return _timer <= 0.0 or (pressed and _exit_armed)


## Выпускает гостя наружу.
func release() -> void:
	phase = Phase.CLOSED
	_entry_armed = false
