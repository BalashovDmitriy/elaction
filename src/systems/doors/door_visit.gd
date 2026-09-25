class_name DoorVisit
extends RefCounted

## Правила посещения двери: кого пускать, когда спрятать и когда выпустить.
##
## Ни узлов, ни физики: узел двери подставляет факты о госте и створке и исполняет
## решение, а решает этот класс. Поэтому правила проверяются без сцены — тем же
## приёмом, что [OttoStateMachine] и [ElevatorMotion]. Основания — ADR-0005,
## пункты 2-3, и ADR-0038, решение 2.
##
## Створку он не ведёт: это дело [DoorCycle]. Раньше оба жили здесь и делили один
## таймер, из-за чего дверь агента нельзя было открыть, не заведя гостя
## (ADR-0020, решение 1). Визит только говорит, когда створке пора пойти.
##
## Ход визита как в ROM (@3BDA, `update_in_room_timer_3c3e`): створка открывается,
## гость уходит внутрь, она закрывается за ним; через [member hide_time] от стука
## она открывается снова и выпускает его. Раньше не выйти — решение пользователя
## (ADR-0038, решение 2): в ROM можно, толкнув от двери.

## Что визит велит двери в этом кадре.
## [code]HIDE[/code] — створка открылась, гость ушёл внутрь: спрятать и закрыть;
## [code]LET_OUT[/code] — время почти вышло: открывать, чтобы к сроку проём был;
## [code]OUT[/code] — срок, и створка открыта: гость снаружи.
enum Cue { NONE, HIDE, LET_OUT, OUT }

enum Phase { OUTSIDE, ENTERING, INSIDE, LEAVING }

## Сколько гость проводит внутри, считая от стука, с: 70 тиков ROM.
var hide_time: float = Arcade.seconds(Arcade.ROOM_TICKS)

## Ход створки, с. Выпускать начинают заранее на столько, чтобы к концу
## [member hide_time] проём уже был открыт: срок — это выход, а не начало выхода.
var leaf_time: float = 0.25

var phase: Phase = Phase.OUTSIDE

## Сколько гость уже у двери, с: от стука.
var _elapsed: float = 0.0
## Отпустил ли гость «вверх» после того, как дверь его выпустила. Без этого та же
## зажатая кнопка втягивала бы его обратно раз за разом: выставили — и сразу взяли.
var _entry_armed: bool = true


## Просится ли гость внутрь. Спрашивают только про того, кто стоит на коврике.
func knock(grounded: bool, vertical: float) -> bool:
	if vertical > -Intent.PRESS:
		# «Вверх» отпустили: следующее нажатие снова считается просьбой войти.
		_entry_armed = true
		return false
	return _entry_armed and grounded


## Впускает гостя: с этой минуты идёт срок, и ввод его больше не слушают.
func admit() -> void:
	_elapsed = 0.0
	phase = Phase.ENTERING


## Шаг визита. [param leaf_open] — открыта ли створка настежь.
##
## Ввода гостя здесь нет нарочно: выйти раньше срока нельзя ничем.
func tick(delta: float, leaf_open: bool) -> Cue:
	if phase == Phase.OUTSIDE:
		return Cue.NONE
	_elapsed += delta
	match phase:
		Phase.ENTERING:
			if leaf_open:
				phase = Phase.INSIDE
				return Cue.HIDE
		Phase.INSIDE:
			if _elapsed >= hide_time - leaf_time:
				phase = Phase.LEAVING
				return Cue.LET_OUT
		Phase.LEAVING:
			# Створка в срок не успела — гость ждёт её: сквозь закрытую не выходят.
			if _elapsed >= hide_time and leaf_open:
				return Cue.OUT
	return Cue.NONE


## Выпускает гостя наружу.
func release() -> void:
	phase = Phase.OUTSIDE
	_entry_armed = false


## Спрятан ли гость: ушёл внутрь и ещё не вышел.
func is_hiding() -> bool:
	return phase == Phase.INSIDE or phase == Phase.LEAVING


## Сколько гость уже у двери, с. Нужно тестам.
func elapsed() -> float:
	return _elapsed
