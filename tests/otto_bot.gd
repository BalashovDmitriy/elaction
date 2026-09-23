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
## Подошедшего вплотную агента бот не обходит, а встречает: приседает, поворачивается
## и стреляет. Пока он проходил мимо, размен на считанных сантиметрах был мгновенным
## и уклонение там не помогало — этим и кончались все замеры M11.
##
## Думает бот в координатах правил — там же, где раскладка и этажи. Из сцены он
## переводит в одном месте, [method _at]: сцена считает Y вверх, правила вниз, и
## бот, читающий сцену напрямую, шёл бы по зданию вверх ногами (ADR-0021).

## Насколько близко к цели по горизонтали считается «дошёл», м.
const REACHED: float = 0.18

## С какого расстояния бот открывает огонь, м.
##
## Больше, чем [member EnemyBrain.fire_range] (6 м): кто выстрелил первым,
## тот и жив. Стреляет бот, только если агент уже на его линии.
const ENGAGE: float = 7.2

## Насколько агент должен совпадать с Otto по высоте, чтобы считаться целью, м.
## Пуля летит по горизонтали, и агент этажом ниже — не цель, а трата патрона.
const SAME_LINE: float = 0.72

## Сколько бот готов драться, не сходя с места, с игрового времени.
##
## Отсчёт идёт, пока рядом вообще кто-то есть, и обнуляется, только когда линия
## чиста. Дальше бот идёт напролом: агент бывает и недосягаем — за проёмом, на
## кабине, в глухом углу, — а двери подсылают следующего каждые три секунды.
## Бот, который стоит до победы, не уходит с этажа никогда.
const DUEL_PATIENCE: float = 2.0

## За сколько метров до попадания бот начинает уклоняться.
##
## Присед мгновенный, но прыжок — нет: чтобы тело успело подняться над низкой
## пулей, прыгать надо заранее. Отсюда запас, а не «в последний кадр».
const DODGE_SIGHT: float = 2.88

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
## ([member BuildingRules.shaft_width]), то есть занимает 0.9 м от оси; Otto
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
	var bullet_height := _incoming_height()
	# Уклонение отменяет дуэль: нажата будет не сторона, а присед или прыжок.
	# В кабине уклонения нет вовсе — там от пули не уйти, и остаётся стрелять.
	#
	# Разрешать его в стоящей кабине пробовали на M18: на этаже она тот же пол,
	# и присед на ней работает. Замер это отверг — бот приседал вместо того,
	# чтобы идти, и на одном сиде не собрал ни одного документа за весь прогон.
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


## Высота ближайшей летящей в Otto пули над его ногами, м, или -1, если лететь
## нечему. Считается так же, как у агента, — по группе пуль, а не по детям уровня.
func _incoming_height() -> float:
	var best := -1.0
	var nearest := DODGE_SIGHT
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
