class_name EnemyBrain
extends RefCounted

## Решения агента: идти, стрелять или стоять.
##
## Ни узлов, ни физики — принимает вектор до Otto и факты, возвращает состояние.
## Поэтому проверяется без сцены, как [OttoStateMachine] и [DoorVisit].
##
## Уклоняться агент учится в M11 ([ADR-0016](../../docs/adr/0016-combat-balance.md),
## пункт 2): от высокой пули он уходит на колено, от низкой — ложится. Ездить на
## лифте по-прежнему не умеет, это отложено с ADR-0006.

enum State { EMERGING, WALK, SHOOT, DEAD }

## Стойка агента. От неё зависит и рост, и то, какая пуля пройдёт мимо.
enum Stance { STAND, KNEEL, PRONE }

## Сколько агент выбирается из двери, с: всё это время он не стреляет.
var emerge_time: float = 0.6

## Насколько близко по вертикали, чтобы считать, что Otto на той же линии, px.
var same_line: float = 45.0

## Дальше этого агент не стреляет, px.
var fire_range: float = 600.0

## Пауза между выстрелами, с.
var fire_cooldown: float = 1.1

## Замах: сколько агент целится, прежде чем выстрелить в только что появившуюся
## цель, с.
##
## Без замаха первый выстрел уходит в тот же кадр, в котором Otto попал на линию,
## и у игрока нет хода вовсе. Хуже всего это било в кабине лифта: там присед
## выключен (ADR-0004, пункт 3), уклоняться нечем, и каждая остановка у этажа,
## где агент стоит у проёма, была смертью без вариантов.
##
## Оригиналом не подтверждено — это число баланса, подобранное замером
## (ADR-0016, пункт 5).
var aim_time: float = 0.35

## Рост агента в каждой стойке, px. По ним и решается, пройдёт ли пуля мимо:
## стойка годится, если она ниже летящей пули.
var stand_height: float = 117.0
var kneel_height: float = 76.0
var prone_height: float = 36.0

## Что агенту разрешено. В первых зданиях он только стоит, дальше учится
## приседать, ещё дальше — ложиться. Разрешение даёт злость, см. [Enemy].
var can_kneel: bool = false
var can_go_prone: bool = false

var state: State = State.EMERGING
var stance: Stance = Stance.STAND
var facing: float = 1.0

var _emerging_left: float = 0.0
var _cooldown_left: float = 0.0
var _fired_now: bool = false


## Начинает жизнь агента: он выбирается из двери в сторону [param towards].
func start(towards: float) -> void:
	state = State.EMERGING
	stance = Stance.STAND
	facing = signf(towards) if not is_zero_approx(towards) else 1.0
	_emerging_left = emerge_time
	_cooldown_left = 0.0
	_fired_now = false


func kill() -> void:
	state = State.DEAD
	# Мёртвый не уклоняется: труп лежит как упал, и стойка на него не влияет.
	stance = Stance.STAND
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
##
## [param incoming_height] — высота летящей в агента пули над его ногами, px.
## Отрицательное значение означает «ничего не летит»: пуля ниже ног невозможна,
## а отдельный флаг рядом с числом рано или поздно разошёлся бы с ним.
func update(
	delta: float, to_target: Vector2, target_alive: bool, incoming_height: float = -1.0
) -> State:
	_fired_now = false
	if state == State.DEAD:
		return state

	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	stance = stance_against(incoming_height)

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

	# Замах даётся на входе в стрельбу: агент, который уже держит Otto на мушке,
	# целиться заново не должен — иначе он не попадёт никогда.
	if state != State.SHOOT:
		_cooldown_left = maxf(_cooldown_left, aim_time)
	state = State.SHOOT
	if _cooldown_left <= 0.0:
		_cooldown_left = fire_cooldown
		_fired_now = true
	return state


## Стойка против летящей пули: самая высокая из разрешённых, под которой пуля
## пройдёт мимо.
##
## Самая высокая, а не самая низкая, нарочно: лёжа агент неподвижен и бесполезен,
## поэтому ложиться он должен только тогда, когда колено уже не спасает.
func stance_against(incoming_height: float) -> Stance:
	if incoming_height < 0.0:
		return Stance.STAND
	if can_kneel and incoming_height > kneel_height:
		return Stance.KNEEL
	if can_go_prone and incoming_height > prone_height:
		return Stance.PRONE
	# Ни одна разрешённая стойка не ниже пули — уклоняться нечем.
	return Stance.STAND


## Рост в текущей стойке. По нему уровень задаёт форму коллизии.
func height() -> float:
	match stance:
		Stance.KNEEL:
			return kneel_height
		Stance.PRONE:
			return prone_height
		_:
			return stand_height


## Стоит ли агент на ногах. Приседая и лёжа он не ходит: уклонение — это замереть,
## а не идти дальше пригнувшись.
func is_standing() -> bool:
	return stance == Stance.STAND


## Выходит ли агент ещё из проёма двери.
##
## Пока выходит — он неуязвим: иначе телеграф створки превращает дверь в тир,
## и игрок снимает каждого на выходе (ADR-0020, решение 3).
func is_emerging() -> bool:
	return state == State.EMERGING


func _on_the_same_line(to_target: Vector2) -> bool:
	return absf(to_target.y) <= same_line and absf(to_target.x) <= fire_range
