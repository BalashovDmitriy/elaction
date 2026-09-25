class_name EnemyBrain
extends RefCounted

## Решения агента: идти, стрелять, уворачиваться или стоять.
##
## Ни узлов, ни физики — принимает вектор до Otto и факты, возвращает состояние.
## Поэтому проверяется без сцены, как [OttoStateMachine] и [DoorVisit].
##
## С M18d решения — по правилам аркадного ROM ([Arcade], ADR-0027). У агента
## своя злость: от неё замах перед выстрелом, пауза после, поза выстрела — стоя,
## присев или лёжа — и шанс увернуться. За Otto он не гонится: бродит по этажу,
## а стреляет, когда смотрит на него; под тревогой — не глядя, сам развернувшись.
##
## В кабинах агент ездит пассажиром (ADR-0025, решение 6), но это решает [Enemy]
## с уровнем, а не мозг. Не прыгает — ни в оригинале, ни здесь (ADR-0026, ADR-0027).

enum State { EMERGING, WALK, SHOOT, DEAD }

## Стойка агента. От неё зависит и рост, и то, какая пуля пройдёт мимо, и на
## какой высоте уйдёт его собственная.
enum Stance { STAND, KNEEL, PRONE }

## Замах не короче этого, с, при любой злости. В ROM при злости 10 и выше замаха
## нет вовсе, и пуля уходит в тот же кадр; от медленной пули ROM это было
## терпимо, от втрое быстрой (ADR-0037, решение 5) без луча прицела не уйти —
## ни человеку, ни боту тестов. Четверть секунды — на реакцию, а не на отдых.
const MIN_TELL: float = 0.25

## Сколько агент выбирается из двери, с: всё это время он не стреляет.
var emerge_time: float = 0.6

## Насколько близко по вертикали, чтобы считать, что Otto на той же линии, м.
var same_line: float = 0.45

## Рост агента в каждой стойке, м. По ним и решается, пройдёт ли пуля мимо.
var stand_height: float = Proportions.BODY
var kneel_height: float = Proportions.KNEEL
var prone_height: float = Proportions.PRONE

## Злость агента, 0..[constant Arcade.TOP]. Растит её [Enemy] со временем.
var anger: int = 0

## Тревога агентов (ADR-0027, решение 5): стреляет, не глядя на Otto.
var alert: bool = false

## Агент из поздних — третий или четвёртый в здании: у него своя таблица поз,
## он чаще стреляет на ходу (table_1D95).
var late: bool = false

## Генератор решений. Свой у каждого агента, посеянный уровнем: иначе прогон
## бота перестаёт повторяться.
var rng := RandomNumberGenerator.new()

var state: State = State.EMERGING
var stance: Stance = Stance.STAND
var facing: float = 1.0

var _emerging_left: float = 0.0
var _cooldown_left: float = 0.0
var _fired_now: bool = false
## Действие — выстрел или увёртка: сколько оно ещё длится и сколько до вылета пули.
var _action_left: float = 0.0
var _wind_up_left: float = 0.0
var _shot_pending: bool = false
## Стреляет ли агент на ходу: поза «прочее» ROM — выстрел без остановки.
var _on_the_move: bool = false
## Брожение: сколько ещё идти и сколько ещё стоять.
var _stroll_left: float = 0.0
var _pause_left: float = 0.0


## Начинает жизнь агента: он выбирается из двери в сторону [param towards].
func start(towards: float) -> void:
	state = State.EMERGING
	stance = Stance.STAND
	facing = signf(towards) if not is_zero_approx(towards) else 1.0
	_emerging_left = emerge_time
	_cooldown_left = 0.0
	_fired_now = false
	_action_left = 0.0
	_shot_pending = false
	_on_the_move = false
	_pause_left = 0.0
	_stroll_left = _stroll_time()


func kill() -> void:
	state = State.DEAD
	# Мёртвый не уклоняется: труп лежит как упал, и стойка на него не влияет.
	stance = Stance.STAND
	_fired_now = false
	_action_left = 0.0
	_shot_pending = false


func is_dead() -> bool:
	return state == State.DEAD


## Разворачивает агента. Зовёт узел, когда пол впереди кончился: бродящий
## агент идёт дальше в другую сторону, а не стоит у края.
func turn_around() -> void:
	facing = -facing


## Поворачивает агента в заданную сторону. Зовёт узел, когда идти надо не куда
## глаза глядят, а к стоящей кабине (ADR-0025, решение 6).
func face(towards: float) -> void:
	if not is_zero_approx(towards):
		facing = signf(towards)


## Выстрелил ли агент именно в этом кадре. Спрашивают сразу после [method update].
func fired() -> bool:
	return _fired_now


## Замахивается ли агент: выстрел решён, а пуля ещё не ушла. Всё это время
## виден луч прицела (ADR-0037, решение 5). Замаха короче [constant MIN_TELL]
## нет и при злости 10 и выше, где у ROM он нулевой (@1BDF): луч есть всегда.
func is_winding_up() -> bool:
	return state == State.SHOOT and _shot_pending and _wind_up_left > 0.0


## Сколько ещё до вылета пули, с; ноль — замаха нет.
func wind_up_left() -> float:
	return maxf(_wind_up_left, 0.0) if is_winding_up() else 0.0


## Пересчитывает решение.
##
## [param to_target] — от агента к Otto. [param target_alive] — есть ли в кого
## целиться: жив ли Otto и виден ли. Невидимого — в тени или за дверью — мозг
## не обстреливает (ADR-0023, решение 8).
##
## [param incoming_height] — высота летящей в агента пули над его ногами, м;
## отрицательная — ничего не летит. [param in_range] — достаёт ли выстрел: в
## ROM дальности нет, этаж оригинала целиком на экране, и у нас это «агент
## в кадре» (ADR-0027, решение 3а). [param gun_free] — нет ли в полёте его
## прошлой пули: она у агента одна (@1BAE). [param target_low] — Otto присел:
## тогда агент стреляет из приседа (@1CD8).
func update(
	delta: float,
	to_target: Vector2,
	target_alive: bool,
	incoming_height: float = -1.0,
	in_range: bool = true,
	gun_free: bool = true,
	target_low: bool = false
) -> State:
	_fired_now = false
	if state == State.DEAD:
		return state

	_cooldown_left = maxf(_cooldown_left - delta, 0.0)

	if state == State.EMERGING:
		_emerging_left -= delta
		if _emerging_left > 0.0:
			return state
		state = State.WALK

	if _action_left > 0.0:
		# Otto скрылся за дверью или погиб, пока агент замахивался: выстрела нет.
		# Невидимого не обстреливают (ADR-0023, решение 8), и замах, начатый по
		# видимому, этого не отменяет — иначе дверь переставала бы прятать.
		if _shot_pending and not target_alive:
			_shot_pending = false
		_act(delta)
		return state

	if _dodges(delta, incoming_height):
		return state

	if target_alive and in_range and gun_free and _cooldown_left <= 0.0:
		if _on_the_same_line(to_target) and _faces(to_target):
			_open_fire(to_target, target_low)
			return state

	state = State.WALK
	_stroll(delta)
	return state


## Хочет ли агент сейчас идти. Стоя на месте он целится, уворачивается или
## стоит паузу брожения.
func wants_to_walk() -> bool:
	if state == State.EMERGING:
		return true
	if state == State.SHOOT:
		return _on_the_move
	return stance == Stance.STAND and _action_left <= 0.0 and _pause_left <= 0.0


## Стойка против летящей пули: от высокой — на колено, от низкой — лечь (@05F5).
##
## Высокая — та, что проходит над присевшим; всё ниже — низкая.
func stance_against(incoming_height: float) -> Stance:
	if incoming_height < 0.0:
		return Stance.STAND
	return Stance.KNEEL if incoming_height > kneel_height else Stance.PRONE


## Рост в текущей стойке. По нему уровень задаёт форму коллизии.
func height() -> float:
	match stance:
		Stance.KNEEL:
			return kneel_height
		Stance.PRONE:
			return prone_height
		_:
			return stand_height


## Стоит ли агент на ногах.
func is_standing() -> bool:
	return stance == Stance.STAND


## Выходит ли агент ещё из проёма двери.
##
## Пока выходит — он неуязвим: иначе телеграф створки превращает дверь в тир,
## и игрок снимает каждого на выходе (ADR-0020, решение 3).
func is_emerging() -> bool:
	return state == State.EMERGING


## Идёт действие: замах, выстрел, выдержка позы. Кончилось — агент встаёт.
func _act(delta: float) -> void:
	_action_left -= delta
	if _shot_pending:
		_wind_up_left -= delta
		if _wind_up_left <= 0.0:
			_shot_pending = false
			_fired_now = true
			_cooldown_left = Arcade.cooldown(anger)
	if _action_left <= 0.0:
		_action_left = 0.0
		stance = Stance.STAND
		_on_the_move = false
		state = State.WALK


## Увёртка: пуля Otto рядом, и злость дала шанс — агент приседает или ложится
## на время действия. Шанс в ROM — за тик, здесь переведён на кадр.
func _dodges(delta: float, incoming_height: float) -> bool:
	if incoming_height < 0.0:
		return false
	var per_tick := Arcade.dodge_chance(anger)
	if per_tick <= 0.0:
		return false
	var per_frame := 1.0 - pow(1.0 - minf(per_tick, 1.0), delta / Arcade.TICK)
	if rng.randf() >= per_frame:
		return false
	stance = stance_against(incoming_height)
	state = State.WALK
	_action_left = Arcade.action_time(anger)
	return true


## Начинает выстрел: поза по злости, разворот к Otto, замах.
func _open_fire(to_target: Vector2, target_low: bool) -> void:
	face(to_target.x)
	var pose := Arcade.fire_pose(anger, rng.randi_range(0, 255), late)
	if pose == Arcade.Pose.STAND and target_low and anger > 0:
		pose = Arcade.Pose.CROUCH
	_on_the_move = pose == Arcade.Pose.ON_THE_MOVE
	match pose:
		Arcade.Pose.CROUCH:
			stance = Stance.KNEEL
		Arcade.Pose.PRONE:
			stance = Stance.PRONE
		_:
			stance = Stance.STAND
	state = State.SHOOT
	_wind_up_left = tell_time(anger)
	# Действие по ROM всегда длиннее замаха на два тика и больше (@1C7A): пуля
	# уходит внутри него.
	_action_left = Arcade.action_time(anger)
	_shot_pending = true
	# Замаха в ноль не бывает ([constant MIN_TELL]), но шаг зовётся сразу: так
	# замах начинается в этом же кадре, а не в следующем.
	_act(0.0)


## Замах перед выстрелом на злости [param level], с: по ROM, но не короче
## [constant MIN_TELL].
static func tell_time(level: int) -> float:
	return maxf(MIN_TELL, Arcade.wind_up(level))


## Брожение по этажу: идёт, стоит, снова идёт — в случайную сторону (@5D13).
func _stroll(delta: float) -> void:
	if _pause_left > 0.0:
		_pause_left -= delta
		if _pause_left <= 0.0:
			_pause_left = 0.0
			facing = -1.0 if rng.randf() < 0.5 else 1.0
			_stroll_left = _stroll_time()
		return
	_stroll_left -= delta
	if _stroll_left <= 0.0:
		# Пауза 7 тиков плюс случайная добавка, как между решениями ROM (@04E6).
		_pause_left = Arcade.seconds(7.0 + float(rng.randi_range(0, 7)))


func _stroll_time() -> float:
	return rng.randf_range(0.6, 2.4)


## Смотрит ли агент на Otto. Под тревогой не нужно: развернётся сам (@0568).
func _faces(to_target: Vector2) -> bool:
	return alert or is_zero_approx(to_target.x) or signf(to_target.x) == facing


func _on_the_same_line(to_target: Vector2) -> bool:
	return absf(to_target.y) <= same_line
