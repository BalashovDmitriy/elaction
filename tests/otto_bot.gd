class_name OttoBot
extends RefCounted

## Бот, проходящий здание: спускается сверху вниз, собирает документы, уходит в выход.
##
## Водится **по состоянию, а не по времени**: не «держи вправо 3.5 секунды», а
## «держи вправо, пока не дойдёшь». Тесты по выдержкам в этом проекте ломались
## четырежды подряд — на сценариях съёмки — и каждый раз молча снимали не то, что
## обещали. Здесь такого быть не должно: бот смотрит, где он есть, и решает заново.
##
## Спуск жадный, потому что генератор это гарантирует: на каждом этаже есть шахта
## своей полосы, а на каждом стыке полос — эскалатор.
##
## Отстреливаться и уклоняться бот умеет: под высокую пулю приседает, через низкую
## прыгает. Без этого он мерил бы не игру, а себя — в оригинале присед и прыжок и
## есть защита от огня (ADR-0006, пункт 3), и стоящий под выстрелом бот доказывал
## бы только то, что стоять под выстрелом нельзя.
##
## Подошедшего вплотную агента бот не обходит, а встречает: приседает, поворачивается
## и стреляет. Пока он проходил мимо, размен на трёх-четырёх пикселях был мгновенным
## и уклонение там не помогало — этим и кончались все замеры M11.

## Насколько близко к цели по горизонтали считается «дошёл», px.
const REACHED: float = 18.0

## С какого расстояния бот открывает огонь, px.
##
## Больше, чем [member EnemyBrain.fire_range] (600 px): кто выстрелил первым,
## тот и жив. Стреляет бот, только если агент уже на его линии.
const ENGAGE: float = 720.0

## Насколько агент должен совпадать с Otto по высоте, чтобы считаться целью, px.
## Пуля летит по горизонтали, и агент этажом ниже — не цель, а трата патрона.
const SAME_LINE: float = 72.0

## Сколько бот готов драться, не сходя с места, с игрового времени.
##
## Отсчёт идёт, пока рядом вообще кто-то есть, и обнуляется, только когда линия
## чиста. Дальше бот идёт напролом: агент бывает и недосягаем — за проёмом, на
## кабине, в глухом углу, — а двери подсылают следующего каждые три секунды.
## Бот, который стоит до победы, не уходит с этажа никогда.
const DUEL_PATIENCE: float = 2.0

## За сколько пикселей до попадания бот начинает уклоняться.
##
## Присед мгновенный, но прыжок — нет: чтобы тело успело подняться над низкой
## пулей, прыгать надо заранее. Отсюда запас, а не «в последний кадр».
const DODGE_SIGHT: float = 288.0

## Половина ширины тела Otto, px.
##
## Вместе с длиной пули ([method Bullet.half_length]) даёт габарит, из которого
## она должна выйти, прежде чем вставать. Агент на этом попадался —
## распрямлялся ровно под пулей и ловил её грудью, — и Otto попадался бы так же.
const BODY_HALF_WIDTH: float = 27.0

## Выше этой высоты над ногами пуля считается высокой: от неё приседают.
## Сидячая форма Otto — 81 px, и пуля выше неё проходит над головой.
const HIGH_BULLET: float = 81.0

## Где встать рядом с шахтой, ожидая кабину, px от её оси. У самого края проёма:
## кабина стоит на этаже недолго, и от дальней точки бот не успевал войти.
const WAIT_ASIDE: float = 96.0

## Насколько кабина считается пришедшей на этаж, px.
const CAR_ALIGNED: float = 12.0

## Действия, которые Otto читает по фронту нажатия, а не по удержанию.
##
## Их нельзя отпустить и нажать заново в одном кадре: движок такого фронта не
## видит, и нажатие пропадает целиком. Бот так и делал — и за всю веху не
## выстрелил ни разу и ни разу не прыгнул, а замеры показывали один присед.
## Поэтому одиночное действие держится кадр, следующий кадр отдыхает и только
## потом нажимается снова.
const TAPS: Array[StringName] = [&"jump", &"shoot"]

var _level: GreyboxLevel
var _rules: BuildingRules
var _otto: Otto
var _pressed: Array[StringName] = []
## Была ли кабина на этаже в прошлом кадре и идём ли мы в неё.
var _car_was_here: bool = false
var _boarding: bool = false
## Сколько бот уже дерётся не сходя с места, с. Считается игровым временем, а не
## кадрами: замер идёт под [member Engine.time_scale], и кадр там вчетверо длиннее.
var _duel_time: float = 0.0
## Одиночные действия, отпущенные в этом кадре: нажать их снова можно только
## со следующего.
var _resting: Array[StringName] = []


func _init(level: GreyboxLevel) -> void:
	_level = level
	_rules = level.rules
	_otto = level.otto


## Один шаг решения. Зовётся каждый физический кадр.
func step() -> void:
	_release_all()
	if _otto.is_dead():
		_duel_time = 0.0
		return

	var floor_index := _rules.floor_index_near(_otto.global_position.y)
	var threat := _threat()
	if threat == null:
		_duel_time = 0.0
	else:
		_duel_time += _otto.get_physics_process_delta_time()

	# Уклонение идёт вместо шага, но не вместо выстрела: чужая пуля важнее
	# спуска, а вот стрелять она не мешает. Бот, который на время уклонения
	# переставал делать всё остальное, вставал намертво — двери подсылают
	# агентов без перерыва, и пуля в воздухе есть почти всегда.
	var bullet_height := _incoming_height()
	# Уклонение отменяет дуэль: нажата будет не сторона, а присед или прыжок.
	# В кабине уклонения нет вовсе — там от пули не уйти, и остаётся стрелять.
	var dodging := bullet_height >= 0.0 and not _otto.is_riding()
	# Повёрнут ли ствол к цели этим же кадром: в дуэли бот сам нажимает сторону,
	# и целиться отдельным кадром не надо.
	var aiming := not dodging and _duelling(threat)
	if dodging:
		_dodge(bullet_height)
	elif aiming:
		_hold_the_line(threat)
	else:
		_advance(floor_index)

	# Огонь идёт вдогонку плану, а не вместо него. Бой, который останавливает
	# спуск, останавливает его навсегда: двери подсылают следующего каждые три
	# секунды, и бот, который сперва «зачищает этаж», не уходит с него никогда.
	# Поэтому на ходу бот стреляет только вперёд: разворот спорил бы с шагом.
	if threat != null and (aiming or is_equal_approx(_otto.facing(), _side_of(threat))):
		_press(&"shoot")


## Шаг спуска: куда бот идёт на этом этаже.
func _advance(floor_index: int) -> void:
	if _riding_further(floor_index):
		_ride_down()
		return

	var door := _document_door_on(floor_index)
	if door != null:
		_approach_door(door)
		return

	if floor_index == _rules.floors - 1:
		_walk_to(_level.exit_position().x)
		return

	_descend(floor_index)


## Отпускает всё, что держал: без этого Otto продолжал бы идти после смены решения.
func release() -> void:
	_release_all()


## Ближайший живой агент на линии огня или null.
func _threat() -> Enemy:
	var here := _otto.global_position
	var closest: Enemy = null
	var nearest := ENGAGE
	for agent in _level.agents():
		if agent.is_dead():
			continue
		var to_agent := agent.global_position - here
		if absf(to_agent.y) > SAME_LINE:
			continue
		if absf(to_agent.x) > nearest:
			continue
		nearest = absf(to_agent.x)
		closest = agent
	return closest


## Высота ближайшей летящей в Otto пули над его ногами, px, или -1, если лететь
## нечему. Считается так же, как у агента, — по группе пуль, а не по детям уровня.
func _incoming_height() -> float:
	var best := -1.0
	var nearest := DODGE_SIGHT
	for node in _otto.get_tree().get_nodes_in_group(Bullet.GROUP):
		var bullet := node as Bullet
		if bullet == null or bullet.collision_mask != Bullet.FROM_ENEMY:
			continue
		var to_bullet := bullet.global_position - _otto.global_position
		# Летит ли она в нас — и не ушла ли уже за спину. Мерка не «с какой
		# стороны», а «сколько ей до нас осталось»: пуля, миновавшая середину,
		# но не вышедшая из габарита хвостом, всё ещё попадает.
		if -to_bullet.x * bullet.direction < -(BODY_HALF_WIDTH + bullet.half_length()):
			continue
		var reach := absf(to_bullet.x)
		if reach > nearest:
			continue
		nearest = reach
		best = -to_bullet.y
	return best


## Уходит с линии огня: под высокую пулю приседает, через низкую прыгает.
##
## Прыгать можно только с пола: в воздухе нажатие пропадёт впустую, и бот
## встретит пулю стоя. С пола не получилось — приседаем, это хоть что-то.
##
## «Не получилось» — это и кадр отдыха: прыжок одиночный, и на таком кадре
## [method _press] его не нажимает. Пустой кадр под пулей дороже неидеального
## уклонения, поэтому ответ проверяется, а не предполагается.
func _dodge(bullet_height: float) -> void:
	if bullet_height > HIGH_BULLET:
		_press(&"move_down")
		return
	if _otto.is_grounded() and _press(&"jump"):
		return
	_press(&"move_down")


## С какой стороны от Otto стоит агент: -1 слева, +1 справа.
func _side_of(agent: Enemy) -> float:
	return signf(agent.global_position.x - _otto.global_position.x)


## Пора ли драться, а не идти дальше.
##
## Пройти мимо агента, который держит тебя на мушке, нельзя: на трёх-четырёх
## пикселях размен мгновенный, и уклонение там уже ничего не решает — именно
## этим кончались все замеры вехи (ADR-0016, «Чем веха кончилась»).
func _duelling(threat: Enemy) -> bool:
	if threat == null:
		return false
	# Дуэль — это присесть и повернуться, а в кабине нельзя ни того, ни другого:
	# присед там выключен (ADR-0004, пункт 3), а шаг вбок в пути уводит в пустую
	# шахту. Пока кабина не встала у этажа, бот просто едет.
	var riding := _otto.is_riding()
	if riding and not _car_aligned():
		return false
	if _duel_time > DUEL_PATIENCE:
		return false
	return absf(threat.global_position.x - _otto.global_position.x) <= _duel_reach()


## Ближе какого расстояния бот не проходит мимо агента, а дерётся, px.
##
## На ногах это дальность огня самого агента: драться стоит ровно с теми, кто
## может попасть. Того, кто дальше, бот обстреливает на ходу — останавливаться,
## пока размен идёт в его пользу, незачем.
##
## В кабине мерка шире, вся [constant ENGAGE]: там нельзя ни присесть, ни
## отпрыгнуть (ADR-0004, пункт 3), и единственная защита — выстрелить первым.
func _duel_reach() -> float:
	return ENGAGE if _otto.is_riding() else _rules.agent_fire_range


## Дуэль: присесть, повернуться к агенту и держать его под огнём.
##
## Присед здесь не отступление, а лучшая позиция из всех: пуля агента летит в
## 20 px над полом и проходит над присевшим (его форма — 18 px), а сам Otto из
## приседа бьёт ниже — и достаёт и стоящего, и вставшего на колено. Ходить
## присев нельзя, но в дуэли и не надо.
##
## Сторона нажимается этим же кадром, и выстрел уйдёт уже в неё: Otto берёт
## направление огня из того же нажатия, которым поворачивается.
func _hold_the_line(threat: Enemy) -> void:
	if not _otto.is_riding():
		_press(&"move_down")
	_press(&"move_right" if _side_of(threat) > 0.0 else &"move_left")


## Стоит ли кабина, в которой едет бот, у этажа.
##
## Пока она в пути, шаг вбок — это шаг в пустую шахту, а падение в неё
## смертельно. У этажа выйти можно: под ногами пол.
func _car_aligned() -> bool:
	for child in _level.get_children():
		var car := child as ElevatorCar
		if car == null:
			continue
		# Мерка вширь узкая нарочно, хотя Otto и едет где встал, а не на оси:
		# на всю ширину кабины дуэль в ней включается почти всегда, а из неё бот
		# выходит боком на этаж — и до низа здания не доезжает (ADR-0016).
		if absf(car.global_position.x - _otto.global_position.x) > CAR_ALIGNED:
			continue
		if absf(car.global_position.y - _otto.global_position.y) > CAR_ALIGNED:
			continue
		return car.is_aligned()
	return false


## Везёт ли кабина дальше, или пора выходить и идти своим ходом.
##
## Сравнение идёт с самим полом, а не с номером этажа: номер меняется на
## полпути, и бот бросал ехать, вися в полупролёте, откуда выйти нельзя.
##
## А стоящую на этаже кабину бот проходит насквозь по дороге к эскалатору, и
## считать это поездкой нельзя: иначе он разворачивался и ходил туда-сюда.
func _riding_further(here: int) -> bool:
	if not _otto.is_riding():
		return false

	var shaft := _shaft_on(here)
	if shaft == null:
		return true
	var surface := _rules.floor_surface(_stop_floor(shaft, here))
	return _otto.global_position.y < surface - CAR_ALIGNED


func _ride_down() -> void:
	_press(&"move_down")


## На каком этаже выходить: на ближайшем снизу с документом, иначе в самом низу полосы.
func _stop_floor(shaft: BuildingPlan.ShaftSpot, here: int) -> int:
	for index in range(maxi(shaft.top, here), shaft.bottom + 1):
		if _document_door_on(index) != null:
			return index
	return shaft.bottom


func _descend(floor_index: int) -> void:
	var shaft := _shaft_on(floor_index)
	if shaft != null and floor_index < shaft.bottom:
		_take_the_car(shaft, floor_index)
		return

	var escalator := _escalator_on(floor_index)
	if escalator != null:
		_take_the_escalator(escalator)
		return

	# Ни шахты вниз, ни эскалатора: дальше бот не знает, что делать.
	_walk_to(_rules.slot_x(0))


## Заходит в кабину, дождавшись её. В пустой проём шагать нельзя — это падение.
## Заходит в кабину, дождавшись её у самого края проёма.
##
## Входит только на приезд кабины и только стоя рядом. Если заходить в любой
## момент стоянки, можно попасть на её конец: кабина уедет, пока бот делает
## последние шаги, и он шагнёт в пустую шахту — а падение в неё смертельно.
## Пропустить приезд не страшно: кабина вернётся, кадров на это заложено.
func _take_the_car(shaft: BuildingPlan.ShaftSpot, floor_index: int) -> void:
	var surface := _rules.floor_surface(floor_index)
	var here := _car_waits_at(shaft.x, surface)
	var aside := absf(_otto.global_position.x - shaft.x) <= WAIT_ASIDE + REACHED

	if here and not _car_was_here and aside:
		_boarding = true
	if not here:
		_boarding = false
	_car_was_here = here

	if _boarding:
		_walk_to(shaft.x)
		return

	var side := -1.0 if _otto.global_position.x < shaft.x else 1.0
	_walk_to(shaft.x + side * WAIT_ASIDE)


func _take_the_escalator(escalator: BuildingPlan.EscalatorSpot) -> void:
	if not _walk_to(escalator.x):
		return
	_press(&"move_down")


func _approach_door(door: BuildingPlan.DoorSpot) -> void:
	if not _walk_to(door.x):
		return
	_press(&"move_up")


## Идёт к точке. Возвращает true, когда уже пришёл.
func _walk_to(x: float) -> bool:
	var gap := x - _otto.global_position.x
	if absf(gap) <= REACHED:
		return true
	_press(&"move_right" if gap > 0.0 else &"move_left")
	return false


func _car_waits_at(x: float, surface: float) -> bool:
	for child in _level.get_children():
		var car := child as ElevatorCar
		if car == null:
			continue
		if absf(car.global_position.x - x) > CAR_ALIGNED:
			continue
		if absf(car.global_position.y - surface) <= CAR_ALIGNED:
			return true
	return false


func _document_door_on(floor_index: int) -> BuildingPlan.DoorSpot:
	for spot in _level.plan().doors:
		if spot.has_document and spot.floor_index == floor_index and _still_pending(spot):
			return spot
	return null


## Дверь ещё красная: собранная перестаёт ею быть, и второй раз в неё не надо.
##
## Сверяется и этаж: места на этажах общие, и красная дверь сверху, стоящая в том
## же столбце, выдавала бы уже собранную за несобранную — бот ходил бы к ней вечно.
func _still_pending(spot: BuildingPlan.DoorSpot) -> bool:
	for door in _level.doors():
		if not door.is_pending():
			continue
		var mat := door.mat_position()
		if absf(mat.x - spot.x) <= REACHED and _rules.floor_index_near(mat.y) == spot.floor_index:
			return true
	return false


func _shaft_on(floor_index: int) -> BuildingPlan.ShaftSpot:
	for shaft in _level.plan().shafts:
		if floor_index >= shaft.top and floor_index <= shaft.bottom:
			return shaft
	return null


func _escalator_on(floor_index: int) -> BuildingPlan.EscalatorSpot:
	for escalator in _level.plan().escalators:
		if escalator.floor_index == floor_index:
			return escalator
	return null


## Нажимает действие. Возвращает, нажалось ли: одиночное действие, отпущенное
## этим же кадром, нажать нельзя — фронта не выйдет, кадр пропускается, и на
## следующем нажатие уходит.
func _press(action: StringName) -> bool:
	if _resting.has(action):
		return false
	Input.action_press(action)
	_pressed.append(action)
	return true


func _release_all() -> void:
	_resting.clear()
	for action in _pressed:
		Input.action_release(action)
		if TAPS.has(action):
			_resting.append(action)
	_pressed.clear()
