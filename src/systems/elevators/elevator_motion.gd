class_name ElevatorMotion
extends RefCounted

## Логика движения кабины лифта.
##
## Не знает ни про узлы, ни про физику: принимает время кадра, команду игрока и
## факт занятости кабины, а возвращает новую вертикальную координату. Поэтому
## тестируется без сцены — тем же приёмом, что [OttoStateMachine] в M1.
##
## Правила механики и цитаты источников — в ADR-0004.

## Допуск, внутри которого кабина считается совпавшей с этажом, px.
const FLOOR_EPSILON: float = 0.5

## Ниже этого порога команда игрока считается отпущенной.
const COMMAND_THRESHOLD: float = 0.1

## Направления те же, что у эскалатора и двери: одно место на проект.
const UP := Intent.UP
const DOWN := Intent.DOWN

## Этажи-остановки: координата кабины на каждом из них, по возрастанию.
var floors: PackedFloat32Array = PackedFloat32Array()

## Скорость кабины, px/с.
var speed: float = 60.0

## Пауза пустой кабины на этаже, с. В оригинале — от секунды до двух.
var floor_pause: float = 1.5

## Встаёт ли кабина игрока между этажами.
##
## Единственное решение вехи, не подтверждённое сверкой (ADR-0004, пункт 6).
## При [code]false[/code] кабина доезжает до ближайшего этажа по ходу движения.
var stops_between_floors: bool = true

## Текущая координата кабины.
var position: float = 0.0

## Направление движения: -1 вверх, +1 вниз, 0 стоим.
var direction: float = 0.0

## Фактическая скорость за последний кадр, px/с. Нужна для сдавливания: важно
## не намерение кабины, а то, сдвинулась ли она на самом деле.
var velocity: float = 0.0

## Задержка отклика на команду, с. По тревоге кабина слушается хуже, и это
## прямо описано в оригинале (ADR-0009, пункт 1).
var response_delay: float = 0.0

var _pause_left: float = 0.0
var _held: float = 0.0


## Задаёт остановки и ставит кабину на один из этажей.
func setup(stops: PackedFloat32Array, start_floor: int = 0) -> void:
	floors = stops.duplicate()
	floors.sort()
	direction = 0.0
	velocity = 0.0
	if not floors.is_empty():
		position = floors[clampi(start_floor, 0, floors.size() - 1)]
	# На этаже кабина стоит — в том числе на том, с которого начинает.
	_pause_left = floor_pause


## Двигает кабину за кадр и возвращает новую координату.
##
## [param command] — намерение игрока: -1 вверх, +1 вниз, 0 отпущено.
## [param occupied] — стоит ли Otto внутри. Занятая кабина слушается только его,
## пустая ездит сама от этажа к этажу (ADR-0004, пункты 1 и 4).
func update(delta: float, command: float, occupied: bool) -> float:
	if floors.is_empty():
		return position

	var previous := position
	if occupied:
		_drive(delta, command)
	else:
		_run_on_its_own(delta)
	velocity = (position - previous) / delta if delta > 0.0 else 0.0
	return position


## Совпал ли пол кабины с полом этажа: только тогда из неё можно выйти.
func is_aligned() -> bool:
	return aligned_floor() >= 0


## Индекс этажа, с которым совпала кабина, или -1.
func aligned_floor() -> int:
	for index: int in floors.size():
		if absf(floors[index] - position) <= FLOOR_EPSILON:
			return index
	return -1


## Стоит ли кабина на месте прямо сейчас.
func is_stopped() -> bool:
	return is_zero_approx(velocity)


func _drive(delta: float, command: float) -> void:
	# Пассажиру кабина подчиняется без пауз, но держит счётчик полным: как только
	# он выйдет, она постоит на месте, как любая пустая (ADR-0004, пункт 4).
	_pause_left = floor_pause

	if absf(command) > COMMAND_THRESHOLD:
		_held += delta
		if _held < response_delay:
			# Кабина ещё «думает»: команду слышит, но не трогается.
			return
		direction = signf(command)
		_move_towards(_shaft_limit(direction), delta)
		return

	# Команда отпущена.
	_held = 0.0
	if stops_between_floors or is_aligned() or direction == 0.0:
		direction = 0.0
		return

	var target := _next_floor(direction)
	if is_nan(target) or _move_towards(target, delta):
		direction = 0.0


func _run_on_its_own(delta: float) -> void:
	if _pause_left > 0.0:
		_pause_left = maxf(_pause_left - delta, 0.0)
		return

	if direction == 0.0:
		direction = DOWN

	var target := _next_floor(direction)
	if is_nan(target):
		# Приехали в конец шахты — разворачиваемся.
		direction = -direction
		target = _next_floor(direction)
	if is_nan(target):
		# Шахта в один этаж: ехать некуда.
		direction = 0.0
		return

	if _move_towards(target, delta):
		_pause_left = floor_pause


## Двигает кабину к цели и сообщает, доехала ли она в этом кадре.
func _move_towards(target: float, delta: float) -> bool:
	var step := speed * delta
	var gap := target - position
	if absf(gap) <= step:
		position = target
		return true
	position += signf(gap) * step
	return false


## Дальняя граница шахты по направлению движения.
func _shaft_limit(towards: float) -> float:
	return floors[0] if towards < 0.0 else floors[floors.size() - 1]


## Ближайший этаж строго по ходу движения или NAN, если дальше ехать некуда.
func _next_floor(towards: float) -> float:
	var best := NAN
	for stop: float in floors:
		var gap := stop - position
		if towards < 0.0 and gap < -FLOOR_EPSILON:
			if is_nan(best) or stop > best:
				best = stop
		elif towards > 0.0 and gap > FLOOR_EPSILON:
			if is_nan(best) or stop < best:
				best = stop
	return best
