class_name EnemyBrain
extends RefCounted

## Решения агента: идти, стрелять или стоять.
##
## Ни узлов, ни физики — принимает вектор до Otto и факты, возвращает состояние.
## Поэтому проверяется без сцены, как [OttoStateMachine] и [DoorVisit].
##
## В M4a агент умеет выйти из двери, дойти и выстрелить по линии. Уклоняться от
## пуль и ездить на лифте он в оригинале умеет, но это отложено — см. ADR-0006.

enum State { EMERGING, WALK, SHOOT, DEAD }

## Сколько агент выбирается из двери, с: всё это время он не стреляет.
var emerge_time: float = 0.6

## Насколько близко по вертикали, чтобы считать, что Otto на той же линии, px.
var same_line: float = 10.0

## Дальше этого агент не стреляет, px.
var fire_range: float = 200.0

## Пауза между выстрелами, с.
var fire_cooldown: float = 1.1

var state: State = State.EMERGING
var facing: float = 1.0

var _emerging_left: float = 0.0
var _cooldown_left: float = 0.0
var _fired_now: bool = false


## Начинает жизнь агента: он выбирается из двери в сторону [param towards].
func start(towards: float) -> void:
	state = State.EMERGING
	facing = signf(towards) if not is_zero_approx(towards) else 1.0
	_emerging_left = emerge_time
	_cooldown_left = 0.0
	_fired_now = false


func kill() -> void:
	state = State.DEAD
	_fired_now = false


func is_dead() -> bool:
	return state == State.DEAD


## Выстрелил ли агент именно в этом кадре. Спрашивают сразу после [method update].
func fired() -> bool:
	return _fired_now


## Пересчитывает решение по вектору до Otto.
##
## [param to_target] — от агента к Otto. [param target_alive] — есть ли вообще
## в кого целиться: по мёртвому не стреляют.
func update(delta: float, to_target: Vector2, target_alive: bool) -> State:
	_fired_now = false
	if state == State.DEAD:
		return state

	_cooldown_left = maxf(_cooldown_left - delta, 0.0)

	if state == State.EMERGING:
		_emerging_left -= delta
		if _emerging_left > 0.0:
			return state
		state = State.WALK

	if not target_alive:
		state = State.WALK
		return state

	if absf(to_target.x) > same_line:
		facing = signf(to_target.x)

	if not _on_the_same_line(to_target):
		state = State.WALK
		return state

	state = State.SHOOT
	if _cooldown_left <= 0.0:
		_cooldown_left = fire_cooldown
		_fired_now = true
	return state


func _on_the_same_line(to_target: Vector2) -> bool:
	return absf(to_target.y) <= same_line and absf(to_target.x) <= fire_range
