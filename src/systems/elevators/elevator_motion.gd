class_name ElevatorMotion
extends RefCounted

## Логика движения кабины лифта.
##
## Не знает ни про узлы, ни про физику: принимает время кадра, команду игрока и
## факт занятости кабины, а возвращает новую вертикальную координату. Поэтому
## тестируется без сцены — тем же приёмом, что [OttoStateMachine] в M1.
##
## Правила механики и цитаты источников — в ADR-0004.

## Допуск, внутри которого кабина считается совпавшей с этажом, м.
const FLOOR_EPSILON: float = 0.015

## Ниже этого порога команда игрока считается отпущенной.
const COMMAND_THRESHOLD: float = 0.1

## Насколько пол кабины может быть выше пола этажа, чтобы из неё ещё можно было
## спрыгнуть на ходу, в долях этажа: 18 px из 48 в ROM (@36F2).
const STEP_OUT_SHARE: float = 18.0 / 48.0

## Направления те же, что у эскалатора и двери: одно место на проект.
const UP := Intent.UP
const DOWN := Intent.DOWN

## Этажи-остановки: координата кабины на каждом из них, по возрастанию.
var floors: PackedFloat32Array = PackedFloat32Array()

## Скорость кабины, м/с.
var speed: float = 1.8

## Пауза пустой кабины на этаже, с. В оригинале — от секунды до двух.
var floor_pause: float = 1.5

## Насколько близко к этажу кабина сама дотягивает, отпущенная, м: ближе
## этого она встаёт на ближний этаж, даже если он позади, а дальше — едет до
## следующего этажа по ходу. Между этажами кабина игрока не встаёт, как и в
## ROM (@5E1E): отпущенная, она идёт, пока не поравняется с этажом
## (ADR-0053, решение 1). Сама дальше она не едет — это уже наше: в аркаде
## кабина через 2 с трогалась без игрока.
##
## Без доводки выйти можно было только на краях шахты: «совпала с этажом» —
## это половина сантиметра, а кабина проходит её за долю кадра, и попасть
## в такое окно вручную нельзя. Промежуточные этажи были недостижимы.
var settle_distance: float = 0.36

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

## Заперта ли нижняя остановка: кабина не спускается на неё ни с пассажиром,
## ни сама. Так шахта в подвал не везёт туда, пока не собраны все документы
## (M24b; правило ставит [BasementLock]). Кабину, уже стоящую ниже, замок не
## двигает — он только не пускает вниз.
var bottom_locked: bool = false

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
	_held = 0.0


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
		# Пустая кабина ничего не обдумывает: вошедший начинает отсчёт заново,
		# иначе задержка по тревоге работала бы только на первую поездку.
		_held = 0.0
		_run_on_its_own(delta)
	velocity = (position - previous) / delta if delta > 0.0 else 0.0
	return position


## Может ли кабина ещё пойти в эту сторону: -1 вверх, +1 вниз.
##
## Шахты не сквозные (ADR-0008), и у полосы есть верх и низ. Доехавшая до края
## кабина команду слышит, но стоит — и без этого вопроса игроку неоткуда узнать,
## что дело в шахте, а не в игре.
func can_go(towards: float) -> bool:
	if floors.is_empty() or is_zero_approx(towards):
		return false
	# По направлению, а не по модулю: кабина под запертой остановкой ниже
	# своего предела, и «вниз» к пределу вело бы её вверх.
	return (_shaft_limit(towards) - position) * signf(towards) > FLOOR_EPSILON


## Можно ли сойти из кабины на этаж прямо сейчас — в том числе на ходу.
##
## Как в ROM (@36F2–3712): из едущей кабины спрыгивают, пока её пол выше пола
## этажа под ним не больше чем на [constant STEP_OUT_SHARE] этажа; ниже этажа —
## только вровень (ADR-0044, решение 5). До M24h выйти можно было только из
## совпавшей с этажом кабины.
func can_step_out() -> bool:
	if floors.is_empty():
		return false
	var step := _floor_step()
	for stop: float in floors:
		# Ось правил вниз: этаж под полом кабины — с большей координатой.
		var drop := stop - position
		if drop >= -FLOOR_EPSILON and drop <= step * STEP_OUT_SHARE:
			return true
	return false


## Шаг этажа шахты: разница соседних остановок. У шахты в одну остановку
## шага нет — тогда выйти можно только вровень.
func _floor_step() -> float:
	if floors.size() < 2:
		return 0.0
	return floors[1] - floors[0]


## Совпал ли пол кабины с полом этажа.
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


## Забыть, сколько команда уже держится: ожидание считается заново.
##
## Нужно, когда [member response_delay] меняется на ходу — по тревоге. Otto
## держит «вниз» всю поездку, счётчик к этому времени давно перевалил за новую
## задержку, и начатая до сирены поездка доезжала бы по-старому: наказание
## догоняло бы только следующее нажатие.
func forget_command() -> void:
	_held = 0.0


## Стоящая на этаже пустая кабина стоит ещё не меньше [param seconds]. Демо с
## крыши держит так кабину у крыши, пока вертолёт высаживает Otto (ADR-0041):
## иначе она уезжала вниз по расписанию, и бот ждал её полдемо. Едущую не трогает.
func hold(seconds: float) -> void:
	if is_stopped():
		_pause_left = maxf(_pause_left, seconds)


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
		if can_go(direction):
			_move_towards(_shaft_limit(direction), delta)
		return

	# Команда отпущена.
	_held = 0.0
	if is_aligned() or direction == 0.0:
		direction = 0.0
		return

	var nearest := _nearest_floor()
	if absf(nearest - position) <= settle_distance:
		# Остановились почти на этаже — дотягиваем, иначе с него не сойти.
		if _move_towards(nearest, delta):
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
##
## Прибытие считается с допуском [constant FLOOR_EPSILON], а не сравнением
## остатка с шагом в лоб. Без допуска остаток, равный шагу с точностью до
## последнего бита дроби, не засчитывался: кабина вставала в микроне от
## остановки — «выровненной» по тому же допуску, — но паузы не получала и на
## следующем кадре разворачивалась. На пикселях числа сходились в ноль и
## правило держалось на удаче; на метрах и float32-остановках удача кончилась
## (M15, найдено ботом на крыше тридцатиэтажки).
func _move_towards(target: float, delta: float) -> bool:
	var step := speed * delta
	var gap := target - position
	if absf(gap) <= step + FLOOR_EPSILON:
		position = target
		return true
	position += signf(gap) * step
	return false


## Ближайший открытый этаж, в любую сторону.
func _nearest_floor() -> float:
	var best := floors[0]
	for stop: float in _open_floors():
		if absf(stop - position) < absf(best - position):
			best = stop
	return best


## Дальняя граница шахты по направлению движения.
func _shaft_limit(towards: float) -> float:
	var open := _open_floors()
	return open[0] if towards < 0.0 else open[open.size() - 1]


## Остановки, на которые кабине можно: все, кроме запертой нижней. У шахты в
## один этаж запирать нечего — иначе у неё не осталось бы ни одной.
func _open_floors() -> PackedFloat32Array:
	if not bottom_locked or floors.size() < 2:
		return floors
	return floors.slice(0, floors.size() - 1)


## Ближайший этаж строго по ходу движения или NAN, если дальше ехать некуда.
func _next_floor(towards: float) -> float:
	var best := NAN
	for stop: float in _open_floors():
		var gap := stop - position
		if towards < 0.0 and gap < -FLOOR_EPSILON:
			if is_nan(best) or stop > best:
				best = stop
		elif towards > 0.0 and gap > FLOOR_EPSILON:
			if is_nan(best) or stop < best:
				best = stop
	return best
