class_name OttoBot
extends RefCounted

## Бот, проходящий здание: спускается сверху вниз, собирает документы, уходит в выход.
##
## Водится **по состоянию, а не по времени**: не «держи вправо 3.5 секунды», а
## «держи вправо, пока не дойдёшь». Тесты по выдержкам в этом проекте ломались
## четырежды подряд — на сценариях съёмки — и каждый раз молча снимали не то, что
## обещали. Здесь такого быть не должно: бот смотрит, где он есть, и решает заново.
##
## Путь бот берёт из графа здания ([method BuildingRoute.walkable]), а не ищет
## жадно. До M18 жадности хватало: шахты шли встык, и на каждом стыке стоял
## эскалатор. Теперь шахты перехлёстываются, эскалаторы ходят в обе стороны, а
## глухая стена делит этаж надвое — и «ехать вниз ближайшей шахтой» упирается
## в тупик, из которого выход только назад и вверх (ADR-0024).
##
## Отстреливаться и уклоняться бот умеет: под высокую пулю приседает, через низкую
## прыгает. Без этого он мерил бы не игру, а себя — в оригинале присед и прыжок и
## есть защита от огня (ADR-0006, пункт 3), и стоящий под выстрелом бот доказывал
## бы только то, что стоять под выстрелом нельзя.
##
## С M24a пуля агента втрое быстрее ROM (ADR-0037, решение 5), и бот, как и игрок,
## уходит от выстрела по лучу прицела, а не по самой пуле: луч горит весь замах
## ROM, на высоте будущей пули. Высокий — присесть сразу, низкий — прыгнуть так,
## чтобы пуля пришла, пока ноги над ней.
##
## Подошедшего вплотную агента бот не обходит, а встречает. С M24d — добиванием
## (ADR-0040): агента, который не целится, бот нагоняет стоя и жмёт выстрел в
## упор, а выстрел вплотную и есть добивание. Спиной к нему агента подкарауливают
## издалека — сзади добивание дороже; лицом — только совсем рядом, иначе выстрел
## придёт раньше. Целящегося бот, как и прежде, встречает дуэлью из приседа.
##
## Думает бот в координатах правил — там же, где раскладка и этажи. Из сцены он
## переводит в одном месте, [method _at]: сцена считает Y вверх, правила вниз, и
## бот, читающий сцену напрямую, шёл бы по зданию вверх ногами (ADR-0021).

## Насколько близко к цели по горизонтали считается «дошёл», м.
const REACHED: float = 0.18

## С какого расстояния бот открывает огонь, м.
##
## Полкадра по ширине: дальности огня у агента нет, он бьёт, пока он в кадре
## (ADR-0027, решение 3а), — и кто выстрелил первым, тот и жив. Стреляет бот,
## только если агент уже на его линии.
const ENGAGE: float = SideCamera.DEFAULT_HALF_HEIGHT * 16.0 / 9.0

## Насколько агент должен совпадать с Otto по высоте, чтобы считаться целью, м.
## Пуля летит по горизонтали, и агент этажом ниже — не цель, а трата патрона.
const SAME_LINE: float = 0.72

## С какого расстояния бот идёт добивать агента, стоящего к нему спиной, м.
## Дальше агент успеет обернуться: он бродит с паузами (ADR-0027, решение 3а).
const TAKEDOWN_SNEAK: float = 5.0

## С какого расстояния бот бросается добивать агента, смотрящего на него, м. Два
## шага: дольше идти под взглядом агента — дать ему замахнуться.
const TAKEDOWN_RUSH: float = 2.2

## Сколько бот готов драться, не сходя с места, с игрового времени.
##
## Отсчёт идёт, пока рядом вообще кто-то есть, и обнуляется, только когда линия
## чиста. Дальше бот идёт напролом: агент бывает и недосягаем — за проёмом, на
## кабине, в глухом углу, — а двери подсылают следующего каждые три секунды.
## Бот, который стоит до победы, не уходит с этажа никогда.
const DUEL_PATIENCE: float = 2.0

## За сколько секунд до попадания бот замечает летящую пулю.
##
## Прежние 2.88 м при пуле ROM, 8.88 м/с, — это 0.32 с; пуля втрое быстрее, и
## мерить её надо временем, а не метрами (ADR-0037, решение 5). Главный знак
## теперь луч прицела, а пуля в полёте — запасной: луч мог упереться в стену
## между ними, а бот — не успеть по нему.
const DODGE_SIGHT: float = 0.32

## За сколько секунд до попадания бот прыгает через низкую пулю.
##
## Ступни Otto поднимаются над низкой пулей ROM (0.68 м) через 0.1 с после
## толчка и держатся над ней до 0.85 с (прыжок 7.9 м/с при тяжести 16.6). Решает
## бот раз в два кадра под [member Engine.time_scale] 4, то есть раз в 0.13 с, —
## прыгнув при 0.55 с до пули, он встречает её с ногами наверху при любом шаге.
const JUMP_LEAD: float = 0.55

## Половина ширины тела Otto, м.
##
## Вместе с длиной пули ([method Bullet.half_length]) даёт габарит, из которого
## она должна выйти, прежде чем вставать. Агент на этом попадался —
## распрямлялся ровно под пулей и ловил её грудью, — и Otto попадался бы так же.
const BODY_HALF_WIDTH: float = Proportions.BODY_WIDTH * 0.5

## Выше этой высоты над ногами пуля считается высокой: от неё приседают.
## Сидячая форма Otto — 1.08 м, и пуля выше неё проходит над головой.
const HIGH_BULLET: float = Proportions.CROUCH

## Где встать рядом с шахтой, ожидая кабину, м от её оси.
##
## **Вне габарита кабины, а не у самого края проёма.** Кабина широкая 1.8 м
## ([constant Proportions.SHAFT], [member BuildingRules.shaft_width] здания по
## умолчанию), то есть занимает 0.9 м от оси; Otto
## широк [constant BODY_HALF_WIDTH] = 0.36. Значит его середина обязана держаться
## дальше 1.26 м от оси, иначе край заходит в габарит кабины.
##
## Встать бот может на [constant REACHED] ближе цели, и последний шаг он делает
## целиком: путь за два кадра под [member Engine.time_scale] 4 — это 0.36 м при
## [member Otto.walk_speed] 2.7 м/с (`docs/testing.md`, пункт 4). Ближе, чем
## [code]WAIT_ASIDE - REACHED[/code] = 1.47 м, он поэтому не встаёт — с запасом
## в 0.21 м от опасных 1.26. Соседнее место в 1.8 м от оси шахтой не бывает
## (ADR-0026, решение 3), поэтому там, где бот ждёт, всегда есть пол.
##
## Прежние 0.96 м этого не учитывали, и край Otto оказывался в 0.54 м от оси —
## внутри кабины. Поднимающаяся снизу кабина цепляла его крышей и увозила
## наверх, а крышей управлять нельзя ([method Otto.is_riding]). На сиде 2 это
## давало бесконечный круг: подъём на крышу, падение обратно на этаж, снова
## ожидание — бот не сходил с 21-го этажа до конца прогона.
const WAIT_ASIDE: float = Proportions.SHAFT * 0.5 + BODY_HALF_WIDTH + REACHED + 0.21

## Насколько кабина считается пришедшей на этаж, м.
const CAR_ALIGNED: float = 0.12

## Действия, которые Otto читает по фронту нажатия, а не по удержанию.
##
## Их нельзя отпустить и нажать заново в одном кадре: движок такого фронта не
## видит, и нажатие пропадает целиком. Бот так и делал — и за всю веху не
## выстрелил ни разу и ни разу не прыгнул, а замеры показывали один присед.
## Поэтому одиночное действие держится кадр, следующий кадр отдыхает и только
## потом нажимается снова.
const TAPS: Array[StringName] = [&"jump", &"shoot"]

## За сколько секунд до попадания бот в кабине уводит её с линии огня.
const CAR_DODGE_SIGHT: float = 0.6

## Ниже этой высоты над ногами пулю в кабине перепрыгивают: потолок кабины
## не пускает прыжок выше.
const CAR_LOW_BULLET: float = 0.6

## Допуск на то, что луч дотянулся до Otto, м.
const LASER_SLACK: float = 0.1

## Ближе этого к этажу отпущенная кабина дотягивает сама
## ([member ElevatorMotion.settle_distance]).
const SETTLE_BY_ITSELF: float = 0.3

var _level: GreyboxLevel
var _rules: BuildingRules
var _otto: Otto
var _pressed: Array[StringName] = []
## Идём ли мы в кабину, которая стоит на этаже.
var _boarding: bool = false
## Сколько бот уже дерётся не сходя с места, с. Считается игровым временем, а не
## кадрами: замер идёт под [member Engine.time_scale], и кадр там вчетверо длиннее.
var _duel_time: float = 0.0
## Одиночные действия, отпущенные в этом кадре: нажать их снова можно только
## со следующего.
var _resting: Array[StringName] = []
## Куски этажей и подписанные переходы между ними — [method BuildingRoute.walkable].
var _graph: Dictionary = {}
## На каком уровне выходить из кабины. Пока едем — цель поездки.
var _ride_to: int = 0
## Куда эта поездка идёт. Направление запоминается при входе: по нему
## останавливаются, и пересчитывать его на ходу нельзя — выйдут качели.
var _riding_down: bool = true
## Столбец шахты, которой задумана поездка. Без него бот, решив «иду к соседней
## шахте и еду до этажа N», ехал в той кабине, в которой стоял, — если её пролёт
## этаж N тоже накрывает. С перехлёстом это сплошь и рядом.
var _ride_shaft_x: float = INF
## Что бот решил последним разбором: для трассы прогона.
var _decision: String = ""
## Сколько ещё держать кабину в сторону, выбранную от пули, с. Решение
## держится до пролёта пули: сменивший ход тут же выходит из-под луча, и
## пересчёт на каждом шаге качал бы кабину туда-сюда прямо на линии огня.
var _car_dodge_left: float = 0.0
var _car_dodge_dir: float = 0.0


func _init(level: GreyboxLevel) -> void:
	_level = level
	_rules = level.rules
	_otto = level.otto
	# Граф считается один раз: раскладка за партию не меняется, а решение
	# принимается каждый кадр.
	_graph = BuildingRoute.walkable(level.plan(), _rules)


## Один шаг решения. Зовётся каждый физический кадр.
func step() -> void:
	_release_all()
	if _otto.is_dead():
		_duel_time = 0.0
		return

	var floor_index := _rules.floor_index_near(_at(_otto).y)
	var threat := _threat()
	if threat == null:
		_duel_time = 0.0
	else:
		_duel_time += _otto.get_physics_process_delta_time()

	# Уклонение идёт вместо шага, но не вместо выстрела: чужая пуля важнее
	# спуска, а вот стрелять она не мешает. Бот, который на время уклонения
	# переставал делать всё остальное, вставал намертво — двери подсылают
	# агентов без перерыва, и пуля в воздухе есть почти всегда.
	var incoming := _incoming()
	var bullet_height := _dodge_height(incoming)
	# Уклонение отменяет дуэль: нажата будет не сторона, а присед или прыжок.
	# В кабине присесть нельзя, и уклонение там своё — увести кабину с линии
	# ([method _dodge_in_car]). До M24a его не было вовсе: пуля ROM медленная,
	# и бот успевал выстрелить первым. Втрое быстрая пуля по едущему вниз Otto
	# — это половина смертей замера M24a.
	#
	# Приседать в стоящей кабине пробовали на M18: замер это отверг — бот
	# приседал вместо того, чтобы идти, и на одном сиде не собрал ни одного
	# документа за весь прогон.
	var dodging := bullet_height >= 0.0 and not _otto.is_riding()
	var car := _car_of_otto() if _otto.is_riding() else null
	_car_dodge_left = maxf(_car_dodge_left - _otto.get_physics_process_delta_time(), 0.0)
	if car == null:
		_car_dodge_left = 0.0
	var car_dodging := (
		car != null
		and (_car_dodge_left > 0.0 or (incoming.x >= 0.0 and incoming.y <= CAR_DODGE_SIGHT))
	)
	# Добить важнее, чем дуэль: агента, который не целится, бот нагоняет стоя.
	var closing := not dodging and not car_dodging and _worth_a_takedown(threat)
	# Повёрнут ли ствол к цели этим же кадром: в дуэли бот сам нажимает сторону,
	# и целиться отдельным кадром не надо.
	var aiming := not dodging and not car_dodging and not closing and _duelling(threat)
	if dodging:
		_dodge(bullet_height)
	elif car_dodging:
		_dodge_in_car(car, incoming)
	elif closing:
		_close_in(threat)
		return
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


## Шаг к цели: чем бот воспользуется прямо сейчас.
##
## Решение принимает граф здания, а не жадный спуск: с M18 шахты
## перехлёстываются, эскалаторы ходят в обе стороны, а глухая стена делит этаж
## надвое (ADR-0024). «Ехать вниз ближайшей шахтой» на таком здании упирается
## в тупик — бот доходил до середины и давил в стену до конца прогона.
func _advance(floor_index: int) -> void:
	if _riding_further():
		_decision = "едем к этажу %d %s" % [_ride_to, "вниз" if _riding_down else "вверх"]
		_ride_on()
		return
	if _otto.is_riding() and not _car_aligned_under_otto():
		# Кабина стоит между этажами — увёл её с линии огня. Довести до этажа.
		var nearest := _rules.floor_surface(floor_index)
		_decision = "довожу кабину до этажа %d" % floor_index
		# Вблизи этажа кабина дотягивает сама, стоит только отпустить: держать
		# сторону — значит качать её вокруг этажа.
		if absf(_at(_otto).y - nearest) > SETTLE_BY_ITSELF:
			_press(&"move_down" if _at(_otto).y < nearest else &"move_up")
		return

	var goal := _goal()
	var move := BuildingRoute.step_toward(
		_graph, floor_index, _at(_otto).x, int(goal["floor"]), float(goal["x"])
	)
	if move.is_empty():
		# Цель недостижима. Генератор такого не выпускает, и ловит это тест
		# проходимости; здесь остаётся только не ломиться наугад.
		#
		# Решение переписывается, а не оставляется прежним: по нему читает трассу
		# прогона и сторож простоя, а прошлое — успешное — решение увело бы разбор
		# ровно туда, где всё в порядке.
		_decision = (
			"хода нет: цель %s на %d"
			% ["документ" if bool(goal["enter"]) else "выход", int(goal["floor"])]
		)
		return

	_decision = (
		"%s к x=%.1f → этаж %d, цель %s на %d"
		% [
			move["kind"],
			float(move["x"]),
			int(move["floor"]),
			"документ" if bool(goal["enter"]) else "выход",
			int(goal["floor"])
		]
	)

	match String(move["kind"]):
		"shaft":
			_ride_to = int(move["floor"])
			_riding_down = _ride_to > floor_index
			_ride_shaft_x = float(move["x"])
			if _ride_to == floor_index:
				_cross_the_shaft(_ride_shaft_x, float(move["to_x"]), floor_index)
			else:
				_take_the_car(_ride_shaft_x, floor_index)
		"escalator":
			_take_the_escalator(float(move["x"]), int(move["floor"]) < floor_index)
		_:
			if _walk_to(float(move["x"])) and bool(goal["enter"]):
				_press(&"move_up")


## Куда бот идёт: к верхнему несобранному документу, а если все собраны — к выходу.
##
## Верхний, а не ближайший: спуск идёт сверху вниз, и документ выше текущего
## этажа означает, что его пропустили, — а без всех пяти выход возвращает назад.
func _goal() -> Dictionary:
	var best: BuildingPlan.DoorSpot = null
	for spot in _level.plan().doors:
		if not spot.has_document or not _still_pending(spot):
			continue
		if best == null or spot.floor_index < best.floor_index:
			best = spot
	if best != null:
		return {"floor": best.floor_index, "x": best.x, "enter": true}
	return {"floor": _rules.floors - 1, "x": _level.exit_position().x, "enter": false}


## Что бот решил этим кадром: цель и ход к ней. Нужно трассе прогона — по
## «жмёт [down]» не видно, куда он собирался и почему передумал.
func decision() -> String:
	return _decision


## Отпускает всё, что держал: без этого Otto продолжал бы идти после смены решения.
func release() -> void:
	_release_all()


## Где узел стоит в плоскости правил.
static func _at(node: Node3D) -> Vector2:
	return WorldSpace.to_plane(node.global_position)


## Ближайший живой агент на линии огня или null.
func _threat() -> Enemy:
	var here := _at(_otto)
	var closest: Enemy = null
	var nearest := ENGAGE
	for agent in _level.agents():
		if agent.is_dead():
			continue
		var to_agent := _at(agent) - here
		if absf(to_agent.y) > SAME_LINE:
			continue
		if absf(to_agent.x) > nearest:
			continue
		nearest = absf(to_agent.x)
		closest = agent
	return closest


## Ближайшая угроза: высота будущей или летящей пули над ногами Otto, м, и через
## сколько секунд она придёт. Нечему лететь — высота −1.
##
## Первым смотрится луч прицела: пуля втрое быстрее ROM, и видно её слишком
## поздно, а луч горит весь замах (ADR-0037, решение 5) — и при злости 10 и выше
## не короче [constant EnemyBrain.MIN_TELL]. Пуля в полёте — запасной знак: на
## случай, когда луч бот пропустил.
func _incoming() -> Vector2:
	var best := Vector2(-1.0, INF)
	for agent in _level.agents():
		if agent.is_dead():
			continue
		var threat := _laser_threat(agent)
		if threat.x >= 0.0 and threat.y < best.y:
			best = threat
	for node in _otto.get_tree().get_nodes_in_group(Bullet.GROUP):
		var bullet := node as Bullet
		if bullet == null or bullet.collision_mask != Bullet.FROM_ENEMY:
			continue
		var to_bullet := WorldSpace.direction_to_plane(
			bullet.global_position - _otto.global_position
		)
		# Летит ли она в нас — и не ушла ли уже за спину. Мерка не «с какой
		# стороны», а «сколько ей до нас осталось»: пуля, миновавшая середину,
		# но не вышедшая из габарита хвостом, всё ещё попадает.
		if -to_bullet.x * bullet.direction < -(BODY_HALF_WIDTH + bullet.half_length()):
			continue
		var time := absf(to_bullet.x) / maxf(bullet.speed, 0.01)
		if time > DODGE_SIGHT or time >= best.y:
			continue
		best = Vector2(-to_bullet.y, time)
	return best


## Луч прицела агента, если он смотрит в Otto: высота будущей пули над ногами
## Otto, м, и секунды до попадания — замах и полёт. Иначе высота −1.
##
## Луч в Otto — это луч, который до него дотянулся: упёршийся в стену между
## ними не в счёт. Присевший под высоким лучом его уже не перекрывает, и луч
## уходит дальше, — поэтому мерится длина, а не то, во что он упёрся: иначе бот
## вставал бы ровно под выстрел.
func _laser_threat(agent: Enemy) -> Vector2:
	var laser := agent.laser
	if laser == null or not laser.is_on():
		return Vector2(-1.0, INF)
	var to_otto := _otto.global_position - laser.global_position
	if signf(to_otto.x) != laser.direction:
		return Vector2(-1.0, INF)
	var gap := absf(to_otto.x)
	# Луч, упёршийся в самого Otto, кончается ровно у края его тела, и сравнение
	# без допуска отбрасывало его через раз — по погрешности плавающей точки.
	if laser.length() < gap - BODY_HALF_WIDTH - LASER_SLACK:
		return Vector2(-1.0, INF)
	var height := -to_otto.y
	var time := laser.time_to(gap)
	# В кабине Otto сам едет на линию или с неё: мерится высота на момент, когда
	# пуля придёт. Возвращается нынешняя — по ней решает [method _dodge_in_car].
	var car := _car_of_otto() if _otto.is_riding() else null
	var arriving := height + (car.speed_now() * time if car != null else 0.0)
	var slack := 0.1 if car != null else 0.0
	if arriving < -slack or arriving > Proportions.BODY + slack:
		return Vector2(-1.0, INF)
	return Vector2(height, time)


## Высота, от которой уходить этим кадром, или −1.
##
## Под высокую пулю присесть можно сразу: присед мгновенный, и сидеть под лучом
## безопасно весь замах. Через низкую прыгают вовремя: раньше [constant
## JUMP_LEAD] бот приземлился бы прямо на неё.
func _dodge_height(incoming: Vector2) -> float:
	if incoming.x < 0.0:
		return -1.0
	if incoming.x > HIGH_BULLET or incoming.y <= JUMP_LEAD:
		return incoming.x
	return -1.0


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


## Стоит ли идти добивать [param threat] (ADR-0040): стоя на своих ногах, не в
## кабине, агент готов к добиванию и не целится — и близко: спиной — до
## [constant TAKEDOWN_SNEAK], лицом — до [constant TAKEDOWN_RUSH].
##
## И только на своём куске этажа. Нагоняет бот напрямик, мимо графа, а между ним
## и агентом бывает проём шахты или глухая стена: шагнувший в пустую шахту гибнет,
## упёршийся в стену стоит до конца прогона (авторевью M24e).
func _worth_a_takedown(threat: Enemy) -> bool:
	if threat == null or not threat.takedown_ready:
		return false
	if _otto.is_riding() or not _otto.is_grounded() or _otto.takedown != null:
		return false
	if threat.laser != null and threat.laser.is_on():
		return false
	var here := _at(_otto)
	var there := _at(threat)
	if not _same_piece(_rules.floor_index_near(here.y), here.x, there.x):
		return false
	var side := Takedown.side_of(_otto.global_position.x, threat.global_position.x, threat.facing())
	var reach := TAKEDOWN_SNEAK if side == Takedown.Side.BACK else TAKEDOWN_RUSH
	return absf(there.x - here.x) <= reach


## Нагоняет агента стоя и в упор жмёт выстрел: вплотную он и есть добивание.
## Пока не вплотную, бот идёт и не стреляет — пуля забрала бы агента дешевле.
func _close_in(threat: Enemy) -> void:
	var side := _side_of(threat)
	var gap := absf(threat.global_position.x - _otto.global_position.x)
	var facing_it := is_equal_approx(_otto.facing(), side) or is_zero_approx(side)
	if facing_it and gap <= Takedown.REACH * 0.85:
		_decision = "добиваю"
		_press(&"shoot")
		return
	_decision = "иду добивать"
	_press(&"move_right" if side > 0.0 else &"move_left")


## На одном ли куске этажа [param floor_index] точки [param a] и [param b]: дойти
## от одной до другой можно пешком, без кабины и эскалатора.
func _same_piece(floor_index: int, a: float, b: float) -> bool:
	var pieces: Dictionary = _graph["pieces"]
	for piece: Vector2 in pieces.get(floor_index, []):
		if a >= piece.x and a <= piece.y:
			return b >= piece.x and b <= piece.y
	return false


## С какой стороны от Otto стоит агент: -1 слева, +1 справа.
func _side_of(agent: Enemy) -> float:
	return signf(_at(agent).x - _at(_otto).x)


## Пора ли драться, а не идти дальше.
##
## Пройти мимо агента, который держит тебя на мушке, нельзя: на считанных
## сантиметрах размен мгновенный, и уклонение там уже ничего не решает — именно
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
	return absf(_at(threat).x - _at(_otto).x) <= _duel_reach()


## Ближе какого расстояния бот не проходит мимо агента, а дерётся, м.
##
## Та же мерка, что у огня: драться стоит ровно с теми, кто может попасть, а
## попасть с M18d может любой в кадре (ADR-0027, решение 3а).
func _duel_reach() -> float:
	return ENGAGE


## Дуэль: присесть, повернуться к агенту и держать его под огнём.
##
## Присед здесь не отступление, а лучшая позиция из всех: пуля агента летит в
## 1.4 м над полом и проходит над присевшим (его форма — 1.08 м), а сам Otto
## из приседа бьёт ниже — и достаёт и стоящего, и вставшего на колено. Ходить
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
	var here := _at(_otto)
	for child in _level.get_children():
		var car := child as ElevatorCar
		if car == null:
			continue
		var at := _at(car)
		# Мерка вширь узкая нарочно, хотя Otto и едет где встал, а не на оси:
		# на всю ширину кабины дуэль в ней включается почти всегда, а из неё бот
		# выходит боком на этаж — и до низа здания не доезжает (ADR-0016).
		if absf(at.x - here.x) > CAR_ALIGNED:
			continue
		if absf(at.y - here.y) > CAR_ALIGNED:
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
func _riding_further() -> bool:
	if not _otto.is_riding():
		return false

	# Кабина, в которой стоим, до цели поездки может и не доходить: шахты
	# перехлёстываются, и пересадка идёт в кабине, стоящей на своём дне. Такую
	# надо покинуть, а не давить в ней «вниз» до конца прогона.
	# Та ли это кабина: стоять можно в одной, а ехать собираться в другой.
	var shaft := _shaft_under_otto()
	if shaft == null or not is_equal_approx(shaft.x, _ride_shaft_x):
		return false
	if _ride_to < shaft.top or _ride_to > shaft.bottom:
		return false

	# Остановка односторонняя: «пока не совпало с полом» не годится, потому что
	# за кадр кабина проходит больше допуска выравнивания и цель перескакивает.
	# Бот тогда жмёт то вверх, то вниз и качается вокруг этажа до конца прогона.
	var surface := _rules.floor_surface(_ride_to)
	var y := _at(_otto).y
	return y < surface - CAR_ALIGNED if _riding_down else y > surface + CAR_ALIGNED


## Шахта, в чьём столбце стоит Otto. [code]null[/code] — он не в шахте.
##
## Столбца мало: две шахты могут стоять в одном месте на разной высоте. Поэтому
## проверяется и уровень — на одном уровне столбцы у шахт разные.
func _shaft_under_otto() -> BuildingPlan.ShaftSpot:
	var here := _at(_otto)
	var index := _rules.floor_index_near(here.y)
	for shaft in _level.plan().shafts:
		if shaft.top > index or shaft.bottom < index:
			continue
		if absf(shaft.x - here.x) <= _rules.shaft_width * 0.5:
			return shaft
	return null


## Ведёт кабину к уровню, на котором решено выходить. Вверх тоже: с M18 путь
## вниз иногда лежит через этаж выше, где этаж не разрезан (ADR-0024).
func _ride_on() -> void:
	_press(&"move_down" if _riding_down else &"move_up")


## Заходит в кабину, дождавшись её у самого края проёма.
##
## Входит только на приезд кабины и только стоя рядом. Если заходить в любой
## момент стоянки, можно попасть на её конец: кабина уедет, пока бот делает
## последние шаги, и он шагнёт в пустую шахту — а падение в неё смертельно.
## Пропустить приезд не страшно: кабина вернётся, кадров на это заложено.
func _take_the_car(shaft_x: float, floor_index: int) -> void:
	var surface := _rules.floor_surface(floor_index)
	var here := _car_waits_at(shaft_x, surface)
	var x := _at(_otto).x
	var aside := absf(x - shaft_x) <= WAIT_ASIDE + REACHED

	# Садится, как только кабина здесь и он рядом, — не дожидаясь её приезда.
	# Ждать именно приезда бот умел с M2, и это было дёшево, пока кабина была
	# одна на полосу. С перехлёстом он ждёт у шахт постоянно — и переход через
	# проём идёт как раз к стоящей кабине, которая приезжать уже не собирается.
	# Каждое такое ожидание — стойка под огнём: все смерти замера случились там.
	#
	# Безопасно это потому, что к столбцу он двигается только пока кабина на
	# месте: ушла — [code]_boarding[/code] снимается тем же кадром.
	if here and aside:
		_boarding = true
	if not here:
		_boarding = false

	if _boarding:
		_walk_to(shaft_x)
		return

	var side := -1.0 if x < shaft_x else 1.0
	_walk_to(shaft_x + side * WAIT_ASIDE)


## Переходит проём шахты насквозь: через стоящую кабину.
##
## Шахта режет этаж своим проёмом, и половины сообщаются только так — как в
## оригинале, где кабина перекрывает проём собой. Пока кабины нет, к проёму
## подходить нельзя: шагнувший в пустую шахту гибнет, — поэтому бот сперва
## дожидается её там же, где дожидается поездки.
func _cross_the_shaft(shaft_x: float, to_x: float, floor_index: int) -> void:
	if not _car_waits_at(shaft_x, _rules.floor_surface(floor_index)):
		_take_the_car(shaft_x, floor_index)
		return
	_walk_to(to_x)


## Встаёт на площадку эскалатора и отправляется. Вверх — тоже: полотно ходит
## в обе стороны, и обойти разрезанный этаж иногда можно только так.
func _take_the_escalator(pad_x: float, upward: bool) -> void:
	if not _walk_to(pad_x):
		return
	_press(&"move_up" if upward else &"move_down")


## Идёт к точке. Возвращает true, когда уже пришёл.
func _walk_to(x: float) -> bool:
	var gap := x - _at(_otto).x
	if absf(gap) <= REACHED:
		return true
	_press(&"move_right" if gap > 0.0 else &"move_left")
	return false


## Стоит ли на этаже кабина, в которую можно шагнуть.
##
## Мало оказаться рядом: кабина должна **совпасть полом с полом этажа**, а не
## просто пройти мимо в допуске [constant CAR_ALIGNED]. Допуск этот — 0.12 м,
## а кабина идёт 1.8 м/с и проскакивает его за четыре кадра; шагнув в такую,
## Otto попадает не внутрь, а на крышу — её потолок как раз проходит сквозь
## уровень пола, пока кабина подъезжает снизу.
##
## С крыши кабиной не управляют (так в оригинале, [method Otto.is_riding] это
## прямо оговаривает), а сойти с неё между этажами некуда. На M18a это и вышло:
## на сиде 2 бот простоял на крыше 21356 решений до конца прогона. Поэтому
## посадка идёт только по [method ElevatorCar.is_aligned] — то есть по стоянке.
func _car_waits_at(x: float, surface: float) -> bool:
	for child in _level.get_children():
		var car := child as ElevatorCar
		if car == null:
			continue
		var at := _at(car)
		if absf(at.x - x) > CAR_ALIGNED:
			continue
		if absf(at.y - surface) <= CAR_ALIGNED:
			return car.is_aligned()
	return false


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


## Кабина, в которой едет Otto, или null.
func _car_of_otto() -> ElevatorCar:
	var here := _at(_otto)
	for child in _level.get_children():
		var car := child as ElevatorCar
		if car == null or not car.has_rider():
			continue
		var at := _at(car)
		if absf(at.x - here.x) > car.width() * 0.5 or absf(at.y - here.y) > 0.6:
			continue
		return car
	return null


## Стоит ли кабина Otto у этажа.
func _car_aligned_under_otto() -> bool:
	var car := _car_of_otto()
	return car == null or car.is_aligned()


## Уход от выстрела в кабине: присесть там нельзя, зато можно увести кабину.
##
## Кабина идёт ровным ходом без разгона, и за оставшееся до пули время она
## сдвигает Otto на [code]скорость · время[/code]. Вниз — пуля уходит над
## головой, вверх — под ноги, в днище. Берётся сторона с большим запасом;
## низкую пулю в стоящей кабине проще перепрыгнуть.
func _dodge_in_car(car: ElevatorCar, incoming: Vector2) -> void:
	if _car_dodge_left > 0.0:
		if car.can_go(_car_dodge_dir):
			_press(&"move_down" if _car_dodge_dir > 0.0 else &"move_up")
		return
	var height := incoming.x
	if (
		height <= CAR_LOW_BULLET
		and car.is_aligned()
		and _otto.is_grounded()
		and incoming.y <= JUMP_LEAD
		and _press(&"jump")
	):
		return
	var shift := car.speed * incoming.y
	var over_head := height + shift - Proportions.BODY
	var under_feet := shift - height
	var down := over_head if car.can_go(1.0) else -INF
	var up := under_feet if car.can_go(-1.0) else -INF
	if is_inf(down) and is_inf(up):
		return
	_car_dodge_dir = 1.0 if down >= up else -1.0
	_car_dodge_left = incoming.y + 0.1
	_press(&"move_down" if _car_dodge_dir > 0.0 else &"move_up")
