class_name BuildingPlan
extends RefCounted

## Раскладка здания: где шахты, эскалаторы, двери и лампы.
##
## Считается по [BuildingRules] и сиду, узлов и сцен не знает — поэтому
## проверяется тестами. Сид — номер здания, чтобы одно и то же здание
## пересобиралось одинаково (ADR-0008, пункт 2).
##
## Шахты не сквозные и делят здание на полосы; там, где полоса кончается,
## генератор обязан поставить эскалатор — иначе спуститься будет нельзя.


## Шахта лифта: занимает свой столбец на этажах с [member top] по [member bottom].
class ShaftSpot:
	extends RefCounted
	var x: float = 0.0
	## Место сетки, в котором стоит шахта. Держится рядом с [member x], потому что
	## обратный счёт из координаты — сравнение дробных, а место нужно точное.
	var slot: int = -1
	var top: int = 0
	var bottom: int = 0

	## Сколько этажей обслуживает.
	func height() -> int:
		return bottom - top + 1


## Эскалатор ведёт с [member floor_index] на следующий этаж вниз.
class EscalatorSpot:
	extends RefCounted
	var x: float = 0.0
	var floor_index: int = 0
	## Куда спускается полотно: -1 влево, +1 вправо.
	var towards: float = -1.0

	## Проём в перекрытии под полотном: пара «левый край, правый край».
	##
	## Дыра не под площадкой, а сбоку от неё, по ходу спуска. Считается здесь,
	## чтобы уровень и [method BuildingPlan.safe_x] видели один и тот же проём.
	func gap(rules: BuildingRules) -> Vector2:
		var near := x + towards * rules.escalator_gap_offset
		var far := near + towards * rules.escalator_gap_width
		return Vector2(minf(near, far), maxf(near, far))


class DoorSpot:
	extends RefCounted
	var x: float = 0.0
	var floor_index: int = 0
	var has_document: bool = false


class LampSpot:
	extends RefCounted
	var x: float = 0.0
	var floor_index: int = 0


## Внутренняя стена, делящая этаж надвое (ADR-0024, решение 5).
##
## Глухая от пола до потолка: сквозь неё не проходят ни люди, ни пули. Стоит на
## границе между местами, а не на месте: она тонкая, и отнимать под неё целый
## шаг сетки незачем.
class WallSpot:
	extends RefCounted
	var x: float = 0.0
	var floor_index: int = 0

	## Полоса, которую стена занимает на этаже: пара «левый край, правый край».
	func band(rules: BuildingRules) -> Vector2:
		var half := rules.inner_wall_width * 0.5
		return Vector2(x - half, x + half)


var floors: int = 0
var shafts: Array[ShaftSpot] = []
var escalators: Array[EscalatorSpot] = []
var doors: Array[DoorSpot] = []
var lamps: Array[LampSpot] = []
var walls: Array[WallSpot] = []
## Где на нижнем этаже стоит выход из здания.
var exit_x: float = 0.0


## Собирает здание по правилам и сиду.
static func generate(rules: BuildingRules, seed_value: int) -> BuildingPlan:
	var plan := BuildingPlan.new()
	plan.floors = rules.floors

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# Занятые места: этаж -> набор мест. Всё ставится в свободное, поэтому
	# ничто не оказывается внутри шахты или на полотне эскалатора.
	var taken: Dictionary = {}
	plan._lay_shafts(rules, rng, taken)
	plan._lay_escalators(rules, rng, taken)
	plan._lay_exit(rules, rng, taken)
	plan._lay_doors(rules, rng, taken)
	plan._lay_lamps(rules, taken)
	# Стены — последними: их проверяют по достижимости документов и выхода,
	# а значит те уже должны стоять.
	plan._lay_walls(rules, rng)
	return plan


## Этажи, на которых лежат документы, снизу вверх.
func document_floors() -> Array[int]:
	var found: Array[int] = []
	for door in doors:
		if door.has_document:
			found.append(door.floor_index)
	found.sort()
	return found


## Куски перекрытия между проёмами: пары «левый край, правый край».
##
## Единственное место, где этаж режется проёмами. По этим кускам строится и
## геометрия ([method BuildingShell.slab_segments]), и граф достижимости
## ([BuildingRoute]) — разъехаться они не должны, поэтому счёт один на всех.
## Проёмы принимаются в любом порядке и сортируются здесь же: по несортированному
## списку куски накладываются друг на друга и проёма как не бывало.
static func spans_between(gaps: Array[Vector2], bounds: Vector2) -> Array[Vector2]:
	var ordered := gaps.duplicate()
	ordered.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

	var spans: Array[Vector2] = []
	var cursor := bounds.x
	for gap: Vector2 in ordered:
		# Проём за краем уровня ничего не режет: у узких этажей он бывает целиком
		# на улице, и без обрезки кусок уходил бы в минус и переворачивался.
		var from := clampf(gap.x, bounds.x, bounds.y)
		var to := clampf(gap.y, bounds.x, bounds.y)
		if from > cursor:
			spans.append(Vector2(cursor, from))
		# maxf, чтобы вложенный проём не отматывал курсор назад.
		cursor = maxf(cursor, to)
	if cursor < bounds.y:
		spans.append(Vector2(cursor, bounds.y))
	return spans


## Шахта, которая доходит до крыши. Над ней встаёт машинное отделение, и ею же
## начинается спуск: [method _lay_shafts] продлевает до крыши самую верхнюю.
##
## Спрашивается у раскладки, а не выводится заново у каждого, кому понадобилось:
## уровень ставит по ней надстройку, а тест по ней же её и ищет. Пустое здание
## шахт не имеет вовсе, поэтому ответ бывает и пустым.
func roof_shaft() -> ShaftSpot:
	var highest: ShaftSpot = null
	for shaft in shafts:
		if highest == null or shaft.top < highest.top:
			highest = shaft
	return highest


## Проёмы в перекрытии этажа: пары «левый край, правый край», в любом порядке.
##
## Считается здесь, а не в уровне: по этим же дырам строится граф достижимости,
## и разъехаться они не должны. Порядок не обещается намеренно: единственный
## потребитель — [method spans_between], а он сортирует у себя.
func gaps_on(rules: BuildingRules, floor_index: int) -> Array[Vector2]:
	var gaps: Array[Vector2] = []

	for shaft in shafts:
		# Кабина проходит сквозь перекрытия своей полосы, кроме нижнего: там она
		# встаёт на пол, и он же служит дном шахты.
		if floor_index >= shaft.top and floor_index < shaft.bottom:
			var half := rules.shaft_width * 0.5
			gaps.append(Vector2(shaft.x - half, shaft.x + half))

	for escalator in escalators:
		if floor_index == escalator.floor_index:
			gaps.append(escalator.gap(rules))

	return gaps


## Что режет этаж для ходьбы: проёмы плюс внутренние стены.
##
## Счёта два, и разводит их ADR-0024, решение 5. Перекрытие режется только
## проёмами ([method gaps_on]) — стена стоит на плите, а не вместо неё. Ходьба
## режется и тем и другим: сквозь стену не пройти, хотя пол под ней есть.
func blocks_on(rules: BuildingRules, floor_index: int) -> Array[Vector2]:
	var blocks := gaps_on(rules, floor_index)
	for wall in walls:
		if wall.floor_index == floor_index:
			blocks.append(wall.band(rules))
	return blocks


## Стоит ли на этаже стена между двумя точками.
##
## Спрашивают о ней те, кому важно, видно ли одну точку из другой: агент за
## глухой стеной Otto не видит и не стреляет — пуля всё равно ушла бы в стену
## (ADR-0024, решение 5).
func wall_between(floor_index: int, from_x: float, to_x: float) -> bool:
	var low := minf(from_x, to_x)
	var high := maxf(from_x, to_x)
	for wall in walls:
		if wall.floor_index == floor_index and wall.x > low and wall.x < high:
			return true
	return false


## Место на этаже, где можно стоять, не провалившись и ни во что не упёршись.
##
## Нужно тем, кого ставят на этаж снаружи раскладки: Otto на старте и после смерти.
## Двери и лампы дыр в полу не делают и потому не мешают, а выход — мешает: воскреснув
## на нём, Otto вышел бы из здания, не сделав ни шага.
func safe_x(rules: BuildingRules, floor_index: int) -> float:
	var spots := safe_spots(rules, floor_index)
	if spots.is_empty():
		# Все места заняты — значит вставать некуда, кроме середины уровня.
		var span := rules.slot_range(floor_index)
		return rules.slot_x((span.x + span.y) / 2)
	return spots[0]


## Все места уровня, где можно стоять, слева направо.
##
## Нужны тому, кто выбирает между ними: возвращение в игру идёт не на первое
## попавшееся, а на самое дальнее от живых агентов — иначе Otto воскресает под
## тем же стволом, который его убил, и три жизни сгорают на одном месте.
##
## Массив двойной точности, а не одинарной: места сравниваются с координатами
## раскладки через [method @GlobalScope.is_equal_approx], и округление до float32
## развело бы [method safe_x] с [method BuildingRules.slot_x] на любых правилах,
## где шаг между местами не целый.
func safe_spots(rules: BuildingRules, floor_index: int) -> PackedFloat64Array:
	var spots := PackedFloat64Array()
	var span := rules.slot_range(floor_index)
	for slot in range(span.x, span.y + 1):
		var x := rules.slot_x(slot)
		if _is_clear(rules, floor_index, x):
			spots.append(x)
	return spots


func _is_clear(rules: BuildingRules, floor_index: int, x: float) -> bool:
	if floor_index == floors - 1 and is_equal_approx(x, exit_x):
		return false

	for shaft in shafts:
		if floor_index >= shaft.top and floor_index <= shaft.bottom and is_equal_approx(x, shaft.x):
			return false

	for escalator in escalators:
		if floor_index != escalator.floor_index:
			continue
		if is_equal_approx(x, escalator.x):
			return false
		# Дыра под полотном сбоку от площадки, и провалиться можно именно в неё.
		var gap := escalator.gap(rules)
		if x >= gap.x and x <= gap.y:
			return false

	return true


## Шахты — развёрткой сверху вниз (ADR-0024, решение 3).
##
## На каждом уровне известно, сколько шахт его должны обслуживать
## ([method BuildingRules.shafts_on]); выбравшие свой пролёт закрываются,
## недостающие открываются. Перехлёст получается сам и получается неравным:
## открытые на разных этажах закрываются на разных. Открытые у самого дна
## обрезаются нижним этажом и доходят до земли разом — как 1–5, 1–6 и три 1–7
## в оригинале.
func _lay_shafts(rules: BuildingRules, rng: RandomNumberGenerator, taken: Dictionary) -> void:
	var open: Array[ShaftSpot] = []
	var previous_slot := -1

	for index in rules.levels():
		# Выбравшие свой пролёт закрываются. Дно у шахты проставлено при открытии
		# и больше не меняется: по нему и решается, дожила ли она до этого уровня.
		var carried: Array[ShaftSpot] = []
		for shaft in open:
			if index <= shaft.bottom:
				carried.append(shaft)
		open = carried

		for _missing in range(open.size(), rules.shafts_on(index)):
			var shaft := _open_shaft(rules, rng, taken, index, previous_slot)
			if shaft == null:
				# Свободных мест нет — этаж и так гуще, чем позволяет ширина.
				# Не ошибка: число шахт — потолок желаемого, а не обещание.
				break
			open.append(shaft)
			shafts.append(shaft)
			previous_slot = shaft.slot


## Новая шахта от [param index] вниз. [code]null[/code] — ставить её некуда.
##
## Верхняя продлевается до крыши: в оригинале Otto входит в здание лифтом, и это
## единственный проём в её настиле (ADR-0014, пункт 2).
func _open_shaft(
	rules: BuildingRules,
	rng: RandomNumberGenerator,
	taken: Dictionary,
	index: int,
	previous_slot: int
) -> ShaftSpot:
	var shaft := ShaftSpot.new()
	shaft.top = index
	shaft.bottom = mini(index + _shaft_length(rules, rng, index) - 1, floors - 1)

	# Кончиться шахта может либо достаточно высоко, чтобы сменщице хватило места
	# открыться, либо на самом дне. Между этими двумя нет ничего: закрывшись на
	# предпоследнем этаже, она оставляет нижние без пути — новую там уже не
	# открыть, короче [constant BuildingRules.MIN_SHAFT_FLOORS] полос не бывает.
	# На сиде 1 так и выходило: полоса 23..27 закрывалась, и на 28–29 оставалось
	# четыре пути вместо пяти.
	if shaft.bottom > floors - 1 - BuildingRules.MIN_SHAFT_FLOORS:
		shaft.bottom = floors - 1

	# Длину задаёт [method _shaft_length], но дно обрезается по дну здания — и
	# шахта, открытая у самого низа, выходит короче правила. Такая никуда не
	# везёт: кабине некуда ехать, игроку она бесполезна, а указатели в ней
	# гаснут оба.
	#
	# Открывалась она потому, что число шахт на этаже растёт книзу, и на нижних
	# раскладка добирала недостающие. Правило числа — потолок желаемого, а не
	# обещание (см. вызывающего), поэтому здесь честнее не открыть вовсе.
	if shaft.bottom - shaft.top + 1 < BuildingRules.MIN_SHAFT_FLOORS:
		return null

	var levels: Array[int] = []
	for level in range(shaft.top, shaft.bottom + 1):
		levels.append(level)

	# Место должно стоять на всех уровнях шахты разом: здание расширяется книзу,
	# и верх шахты — самое тесное её место.
	var free := _free_slots(rules, taken, levels)
	if free.is_empty():
		return null

	# Соседние шахты не должны стоять в одном столбце: иначе пересадка свелась бы
	# к шагу в сторону, а переход между шахтами — весь смысл спуска.
	shaft.slot = _pick_slot(rng, free, previous_slot)
	shaft.x = rules.slot_x(shaft.slot)
	for level in levels:
		_occupy(taken, level, shaft.slot)
	return shaft


## Сколько уровней обслужит новая шахта.
##
## Пролёт с разбросом, а не постоянный: иначе шахты, открытые на одном уровне,
## закрываются на одном, и перехлёста нет вовсе — все пересаживаются на одном
## этаже, как было до M18. В оригинале длины шахт разные: 5, 6, 7, 3, 12.
##
## Верхняя идёт по своей длине и без разброса — это шахта 19–30, примета здания.
func _shaft_length(rules: BuildingRules, rng: RandomNumberGenerator, index: int) -> int:
	if index <= BuildingRules.ROOF:
		return maxi(rules.top_shaft_span, 1)
	var spread := maxi(rules.shaft_span_spread, 0)
	# Не короче [constant BuildingRules.MIN_SHAFT_FLOORS]: короткая шахта никуда
	# не везёт, а двухэтажная кабина M18b в ней вовсе не сдвинется.
	return maxi(rules.shaft_span + rng.randi_range(-spread, spread), BuildingRules.MIN_SHAFT_FLOORS)


## Эскалаторы: полоса у порога плюс гарантия на разрыве (ADR-0024, решение 4).
##
## Полоса — нижние этажи однашахтной зоны, где шахта башни кончается над
## стилобатом; там эскалаторов по два, если помещается. Гарантия — этаж, на
## котором шахта кончилась, а другая его с нижним не связывает: без эскалатора
## всё, что ниже, недостижимо.
func _lay_escalators(rules: BuildingRules, rng: RandomNumberGenerator, taken: Dictionary) -> void:
	for index in rules.levels():
		# Крыше эскалатор не нужен — с неё уводит шахта, — а нижнему этажу
		# некуда вести.
		if index <= BuildingRules.ROOF or index >= floors - 1:
			continue

		var unbridged := _ends_at(index) and not _bridges(index)
		var wanted := 2 if rules.in_escalator_band(index) else int(unbridged)
		var built := 0
		# Второй на этаже уводит в другую сторону, чем первый: в оригинале на
		# 17–20 эскалатор и слева и справа. Оба в одну сторону — это лестница
		# в два пролёта, а не два пути вниз.
		var taken_towards := 0.0
		for _each in range(wanted):
			# На разорванном стыке первый эскалатор обязателен: без него всё, что
			# ниже, недостижимо, и ради него не жалко ни двери, ни лампы.
			# Остальные уступают им место.
			var must := unbridged and built == 0
			var towards := _add_escalator(rules, rng, taken, index, taken_towards, must)
			if is_zero_approx(towards):
				break
			taken_towards = towards
			built += 1

		# Молча пропустить нельзя: без эскалатора всё, что ниже, недостижимо.
		if built == 0 and unbridged:
			push_error("этаж %d остался без эскалатора: свободных мест нет" % index)


## Кончается ли на этом уровне хоть одна шахта.
func _ends_at(index: int) -> bool:
	for shaft in shafts:
		if shaft.bottom == index:
			return true
	return false


## Есть ли шахта, связывающая этот уровень со следующим вниз. Пока есть —
## пересадка идёт перехлёстом и эскалатор не обязателен.
func _bridges(index: int) -> bool:
	for shaft in shafts:
		if shaft.top <= index and shaft.bottom > index:
			return true
	return false


## Ставит эскалатор с [param index] на следующий уровень вниз и отвечает, куда он
## спускается. [code]0.0[/code] — места не нашлось; вызывающий на этом и
## останавливается.
##
## [param avoid_towards] — сторона, в которую на этом этаже уже уводит другой
## эскалатор; ноль, если он первый.
##
## Эскалатор занимает два места: своё и следующее по ходу спуска. Проём уходит от
## оси на 2.28 м, площадка — на 2.88, и в один шаг сетки это не укладывается
## (ADR-0024, решение 1). Занимал он раньше одно, и на площадку могла встать дверь.
func _add_escalator(
	rules: BuildingRules,
	rng: RandomNumberGenerator,
	taken: Dictionary,
	index: int,
	avoid_towards: float,
	must: bool
) -> float:
	var levels: Array[int] = [index, index + 1]
	# Эскалатор занимает по два места на каждом из двух этажей, и полоса из них
	# выедает узкий этаж целиком: на семиместном этаже два эскалатора сверху и
	# два своих не оставляют ни двери, ни лампе. Необязательный уступает.
	if not must:
		for level in levels:
			if not _room_left(rules, taken, level, 2):
				return 0.0

	var from_x := _shaft_x_near(rules, index)
	var free := _free_slots(rules, taken, levels)
	var slot := _pick_escalator_slot(rules, rng, free, index, from_x, avoid_towards)
	if slot < 0:
		return 0.0

	var escalator := EscalatorSpot.new()
	escalator.floor_index = index
	escalator.x = rules.slot_x(slot)
	escalator.towards = _descent_towards(rules, slot, index, from_x)
	for level in levels:
		_occupy(taken, level, slot)
		_occupy(taken, level, slot + int(escalator.towards))
	escalators.append(escalator)
	return escalator.towards


## Место под эскалатор: годится то, где свободно и само место, и следующее за ним
## по ходу спуска. [code]-1[/code] — годного места нет.
##
## Из годных предпочитаются те, где полотно уходит прочь от шахты: у стены
## уводить некуда, и там проём ложится Otto под ноги на полпути от лифта. Ещё
## раньше — те, что уводят не в ту сторону, куда уже уводит сосед по этажу.
func _pick_escalator_slot(
	rules: BuildingRules,
	rng: RandomNumberGenerator,
	free: Array[int],
	floor_index: int,
	from_x: float,
	avoid_towards: float
) -> int:
	var roomy: Array[int] = []
	var fitting: Array[int] = []
	var opposite: Array[int] = []
	for slot in free:
		var towards := _descent_towards(rules, slot, floor_index, from_x)
		if not free.has(slot + int(towards)):
			continue
		roomy.append(slot)
		if not is_equal_approx(towards, _away_from(rules, slot, from_x)):
			continue
		fitting.append(slot)
		if not is_equal_approx(towards, avoid_towards):
			opposite.append(slot)

	var pool := roomy if fitting.is_empty() else fitting
	if not opposite.is_empty():
		pool = opposite
	return -1 if pool.is_empty() else _pick_any(rng, pool)


## Останется ли на уровне место под обязательное — двери и лампы, — если занять
## на нём ещё [param taking] мест.
##
## Без этого счёта раскладка тратит последние места этажа на то, что можно и не
## ставить, а лампа потом делит место с дверью: этаж без лампы чёрен в кадре, и
## для правила темноты он вечно горящий — гасить нечего (ADR-0023).
func _room_left(rules: BuildingRules, taken: Dictionary, level: int, taking: int) -> bool:
	var free := _free_slots(rules, taken, [level] as Array[int])
	return free.size() - taking >= rules.doors_on(level) + rules.lamps_on(level)


## Где ближайшая к середине этажа шахта, которая его обслуживает. Ею меряется,
## куда эскалатору уводить: прочь от лифта, из которого Otto пришёл.
##
## Шахт на этаже нет вовсе — берётся середина этажа: уводить всё равно надо,
## а отсчитывать не от чего.
func _shaft_x_near(rules: BuildingRules, index: int) -> float:
	var span := rules.floor_span(index)
	var centre := (span.x + span.y) * 0.5
	var nearest := centre
	var best := INF
	for shaft in shafts:
		if shaft.top > index or shaft.bottom < index:
			continue
		var distance := absf(shaft.x - centre)
		if distance < best:
			best = distance
			nearest = shaft.x
	return nearest


## Куда проём должен смотреть: прочь от шахты, из которой Otto приходит.
static func _away_from(rules: BuildingRules, slot: int, comes_from_x: float) -> float:
	return 1.0 if rules.slot_x(slot) > comes_from_x else -1.0


## Куда спускается полотно на самом деле. Это [method _away_from], если только
## место не у стены: оттуда спуск возможен лишь внутрь здания.
##
## Стена берётся по границам самого уровня, а не здания: на узком этаже крайнее
## место стоит посреди ширины, и по краям здания полотно уводило бы на улицу.
static func _descent_towards(
	rules: BuildingRules, slot: int, floor_index: int, comes_from_x: float
) -> float:
	var span := rules.slot_range(floor_index)
	if slot <= span.x:
		return 1.0
	if slot >= span.y:
		return -1.0
	return _away_from(rules, slot, comes_from_x)


## Выход из здания: своё место на нижнем этаже, чтобы на нём не оказались ни дверь,
## ни лампа, ни точка возврата после смерти — иначе Otto выходил бы, едва воскреснув.
func _lay_exit(rules: BuildingRules, rng: RandomNumberGenerator, taken: Dictionary) -> void:
	var bottom := floors - 1
	var slot := _free_slot(rng, rules, taken, [bottom] as Array[int])
	if slot < 0:
		push_error("нижнему этажу не хватило места под выход")
		slot = rules.slot_range(bottom).y
	exit_x = rules.slot_x(slot)
	_occupy(taken, bottom, slot)


func _lay_doors(rules: BuildingRules, rng: RandomNumberGenerator, taken: Dictionary) -> void:
	# Красные кладутся первыми: на почти пустом этаже место им найдётся скорее.
	#
	# И только туда, куда ведёт маршрут: проём режет этаж надвое, и за дырой
	# документ достаётся лишь прыжком через неё, а промах роняет этажом ниже.
	var with_document := _lay_documents(rules, rng, taken)

	for index in floors:
		var already := 1 if with_document.has(index) else 0
		for _number in rules.doors_on(index) - already:
			if not _lay_door(rules, rng, taken, index, false):
				break


## Ставит дверь на свободное место этажа. Возвращает false, если места не нашлось.
func _lay_door(
	rules: BuildingRules,
	rng: RandomNumberGenerator,
	taken: Dictionary,
	floor_index: int,
	with_document: bool,
	routed: Dictionary = {},
	spans: Dictionary = {}
) -> bool:
	var free := _free_slots(rules, taken, [floor_index] as Array[int])
	if not routed.is_empty():
		free = free.filter(
			func(candidate: int) -> bool:
				var x := rules.slot_x(candidate)
				return routed.has(BuildingRoute.node_in(spans, floor_index, x))
		)
	if free.is_empty():
		return false

	var slot := _pick_any(rng, free)

	var door := DoorSpot.new()
	door.floor_index = floor_index
	door.x = rules.slot_x(slot)
	door.has_document = with_document
	_occupy(taken, floor_index, slot)
	doors.append(door)
	return true


## Раскладывает лампы: по ширине этажа и по серединам равных зон.
##
## Крыша ламп не получает — над ней небо, подвес держать не на чем. В диапазон
## она и не входит: этажи начинаются с нулевого, крыша лежит выше (ADR-0014).
##
## Не случайно, как остальное: зона лампы — единица темноты (ADR-0023), и лампы,
## сбившиеся в один край, оставили бы другой край этажа тёмным при всех горящих.
## Этаж делится на столько зон, сколько ламп, и каждая встаёт в ближайшее к
## середине своей зоны свободное место.
##
## Лампы кладутся последними и уступают шахтам, эскалаторам и дверям, поэтому
## свободного места может не хватить — тогда ламп меньше. **Но не ноль:** этаж
## без единой лампы не светел и погасить его нечем — для правила темноты он
## навсегда освещённый, хотя в кадре он чёрный. Когда свободных мест не
## осталось, лампа делит место с дверью: дверь стоит у задней стены, лампа
## висит под потолком, и мешают друг другу они только на плане. С правилами по
## умолчанию до этого не доходит — 12000 этажей на 400 сидах получили хотя бы
## одну, — но запас нужен тем правилам, которых ещё нет.
func _lay_lamps(rules: BuildingRules, taken: Dictionary) -> void:
	for index in floors:
		var span := rules.slot_range(index)
		var free: Array[int] = []
		for slot in range(span.x, span.y + 1):
			if not _is_taken(taken, index, slot):
				free.append(slot)
		if free.is_empty():
			free = _slots_beside_the_openings(rules, index)

		var wanted := rules.lamps_on(index)
		for number in wanted:
			if free.is_empty():
				break
			var ideal := (
				float(span.x)
				+ float(span.y - span.x) * (2.0 * float(number) + 1.0) / (2.0 * float(wanted))
			)
			var slot := _nearest_slot(free, ideal)
			free.erase(slot)

			var lamp := LampSpot.new()
			lamp.floor_index = index
			lamp.x = rules.slot_x(slot)
			_occupy(taken, index, slot)
			lamps.append(lamp)


## Внутренние стены: не на каждом этаже, и та, что запирает, снимается.
##
## Стена ставится и тут же проверяется целиком собранным зданием. Проверить
## заранее нельзя: достижимость зависит от всех стен разом, а не от каждой по
## отдельности, — две безобидные порознь запирают этаж вдвоём.
##
## Проверка идёт по [BuildingRoute], а не по своему обходу: куски этажа и связи
## между ними разъезжаться не должны, и счёт им один на весь проект.
func _lay_walls(rules: BuildingRules, rng: RandomNumberGenerator) -> void:
	for index in range(floors):
		if rng.randf() >= rules.wall_chance:
			continue
		var x := _pick_wall_x(rules, rng, index)
		if is_inf(x):
			continue

		var wall := WallSpot.new()
		wall.floor_index = index
		wall.x = x
		walls.append(wall)
		if not BuildingRoute.is_winnable(self, rules):
			walls.pop_back()


## Где на этаже встанет стена: граница между соседними местами. [code]INF[/code] —
## годной границы нет.
##
## Границы у самого края этажа отброшены: стена там отрезает не половину этажа, а
## полоску, на которой нечему стоять. С каждой стороны остаётся не меньше двух мест.
##
## Граница внутри проёма тоже не годится: под стеной должен быть пол, иначе она
## висит над шахтой.
func _pick_wall_x(rules: BuildingRules, rng: RandomNumberGenerator, index: int) -> float:
	var span := rules.slot_range(index)
	var busy := _wall_blockers(rules, index)
	var half := rules.inner_wall_width * 0.5

	# Копятся места, а не координаты: выбор из набора идёт одной строкой на весь
	# файл ([method _pick_any]), потому что счёт сида зависит от порядка обращений
	# к генератору.
	var fitting: Array[int] = []
	for slot in range(span.x + 1, span.y - 1):
		var x := _wall_x_at(rules, slot)
		var in_the_way := false
		for zone: Vector2 in busy:
			if x + half > zone.x and x - half < zone.y:
				in_the_way = true
				break
		if not in_the_way:
			fitting.append(slot)

	if fitting.is_empty():
		return INF
	return _wall_x_at(rules, _pick_any(rng, fitting))


## Середина границы между местом [param slot] и следующим за ним: там и стоит стена.
static func _wall_x_at(rules: BuildingRules, slot: int) -> float:
	return (rules.slot_x(slot) + rules.slot_x(slot + 1)) * 0.5


## Куда стену ставить нельзя: полосы, которые она перекрыла бы собой или
## прижала бы к себе вплотную.
##
## Зазор в полшага сетки не украшение: у стены почти метр толщины, и вставшая
## впритык к проёму она не оставляет места, чтобы стоять. Эскалатор попадался
## на этом дважды — площадкой сверху и площадкой приземления на этаже ниже:
## полотно упиралось в стену, и граф достижимости терял связь.
func _wall_blockers(rules: BuildingRules, index: int) -> Array[Vector2]:
	var clearance := (rules.slot_x(1) - rules.slot_x(0)) * 0.5
	var busy: Array[Vector2] = []
	for gap: Vector2 in gaps_on(rules, index):
		busy.append(Vector2(gap.x - clearance, gap.y + clearance))

	# Столбец шахты считается целиком, а не по дырам из [method gaps_on]: на дне
	# шахты дыры нет — плита там целая, — но кабина стоит и на нём, и стена,
	# поставленная по одним дырам, вырастала прямо сквозь неё. На сиде 6 такая
	# вставала в 0.45 м внутрь кабины шахты 15..21: вошедший в неё Otto оказывался
	# в стене, а граф достижимости обещал выход только в одну сторону.
	#
	# Так же считает и [method _is_clear]: шахта занимает место на всех своих
	# уровнях, дно включая.
	var shaft_half := rules.shaft_width * 0.5 + clearance
	for shaft in shafts:
		if shaft.top <= index and index <= shaft.bottom:
			busy.append(Vector2(shaft.x - shaft_half, shaft.x + shaft_half))

	for escalator in escalators:
		if escalator.floor_index == index:
			busy.append(Vector2(escalator.x - clearance, escalator.x + clearance))
		elif escalator.floor_index == index - 1:
			var landing := escalator.x + escalator.towards * rules.escalator_run
			busy.append(Vector2(landing - clearance, landing + clearance))

	# Дверь за стеной — дверь, в которую не войти, а выход — непроходимое здание.
	for door in doors:
		if door.floor_index == index:
			busy.append(Vector2(door.x - clearance, door.x + clearance))
	if index == floors - 1:
		busy.append(Vector2(exit_x - clearance, exit_x + clearance))
	return busy


## Места этажа, куда лампу повесить всё-таки можно, когда свободных не осталось:
## всё, кроме проёмов — шахт, эскалаторов и выхода. Над проёмом лампы не будет
## никогда: там ездит кабина и падать лампе некуда.
func _slots_beside_the_openings(rules: BuildingRules, floor_index: int) -> Array[int]:
	var free: Array[int] = []
	var span := rules.slot_range(floor_index)
	for slot in range(span.x, span.y + 1):
		if _is_clear(rules, floor_index, rules.slot_x(slot)):
			free.append(slot)
	return free


## Свободное место, ближайшее к желаемому. При равном расстоянии — левое.
static func _nearest_slot(free: Array[int], ideal: float) -> int:
	var best := free[0]
	for slot in free:
		if absf(float(slot) - ideal) < absf(float(best) - ideal):
			best = slot
	return best


## Раскладывает красные двери: здание делится на полосы, и из каждой берётся
## один этаж. Так документы разнесены по высоте и пройти приходится всё здание.
##
## Внутри полосы этажи перебираются, пока дверь не встанет: на достижимой части
## этажа может не остаться места, и тогда документ переезжает на соседний этаж,
## а не пропадает — собрать четыре из пяти нельзя.
func _lay_documents(
	rules: BuildingRules, rng: RandomNumberGenerator, taken: Dictionary
) -> Dictionary:
	var chosen: Dictionary = {}
	var wanted := mini(rules.documents, floors)
	if wanted <= 0:
		# Раньше проверки: маршрут — перебор всей раскладки, а в здании без
		# документов он никому не нужен. Да и на здании в ноль этажей он падает.
		return chosen

	# Куски этажей считаем один раз: сами по себе они — перебор всей раскладки,
	# и маршруту нужны ровно те же самые.
	var spans := BuildingRoute.segments(self, rules)
	var routed := BuildingRoute.reachable_in(self, rules, spans)

	var band := float(floors) / float(wanted)
	for number in wanted:
		var from := int(floor(band * float(number)))
		var to := maxi(int(floor(band * float(number + 1))) - 1, from)
		var placed := false

		for index: int in _shuffled_range(rng, from, to):
			if chosen.has(index):
				continue
			if not _lay_door(rules, rng, taken, index, true, routed, spans):
				continue
			chosen[index] = true
			placed = true
			break

		if not placed:
			push_error("в полосе %d..%d некуда положить документ" % [from, to])
	return chosen


## Этажи полосы в случайном порядке. Своя тасовка, а не [method Array.shuffle]:
## та берёт глобальный генератор, и здание перестало бы повторяться по сиду.
func _shuffled_range(rng: RandomNumberGenerator, from: int, to: int) -> Array[int]:
	var order: Array[int] = []
	for index in range(from, to + 1):
		order.append(index)
	for index in range(order.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var kept := order[index]
		order[index] = order[other]
		order[other] = kept
	return order


## Место из набора, по возможности не [param avoid]. Если выбора нет — любое:
## запрет мягкий, а оставить полосу без шахты нельзя.
static func _pick_slot(rng: RandomNumberGenerator, free: Array[int], avoid: int) -> int:
	var pool := free.filter(func(slot: int) -> bool: return slot != avoid)
	return _pick_any(rng, pool if not pool.is_empty() else free)


## Свободное место сразу на всех перечисленных этажах или -1.
func _free_slot(
	rng: RandomNumberGenerator, rules: BuildingRules, taken: Dictionary, on_floors: Array[int]
) -> int:
	var free := _free_slots(rules, taken, on_floors)
	if free.is_empty():
		return -1
	return _pick_any(rng, free)


## Любое место из набора. Счёт сида зависит от порядка обращений к генератору,
## поэтому выбор — одной строкой на весь файл, а не переписанным трижды.
static func _pick_any(rng: RandomNumberGenerator, pool: Array[int]) -> int:
	return pool[rng.randi_range(0, pool.size() - 1)]


## Все места, свободные сразу на всех перечисленных уровнях.
##
## Место за силуэтом уровня свободным не считается: там улица, а не этаж.
func _free_slots(rules: BuildingRules, taken: Dictionary, on_floors: Array[int]) -> Array[int]:
	var free: Array[int] = []
	for slot in rules.slots:
		var busy := false
		for index in on_floors:
			if _is_taken(taken, index, slot) or not rules.slot_available(slot, index):
				busy = true
				break
		if not busy:
			free.append(slot)
	return free


func _occupy(taken: Dictionary, floor_index: int, slot: int) -> void:
	if not taken.has(floor_index):
		taken[floor_index] = {}
	taken[floor_index][slot] = true


func _is_taken(taken: Dictionary, floor_index: int, slot: int) -> bool:
	return taken.has(floor_index) and taken[floor_index].has(slot)
