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


var floors: int = 0
var shafts: Array[ShaftSpot] = []
var escalators: Array[EscalatorSpot] = []
var doors: Array[DoorSpot] = []
var lamps: Array[LampSpot] = []
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
	plan._lay_lamps(rules, rng, taken)
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
## геометрия ([method GreyboxLevel.slab_segments]), и граф достижимости
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
func safe_spots(rules: BuildingRules, floor_index: int) -> PackedFloat32Array:
	var spots := PackedFloat32Array()
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


func _lay_shafts(rules: BuildingRules, rng: RandomNumberGenerator, taken: Dictionary) -> void:
	var top := 0
	var previous_slot := -1
	# Не меньше этажа на шахту: нулевой span зациклил бы генерацию намертво.
	var span := maxi(rules.shaft_span, 1)
	while top < floors:
		var shaft := ShaftSpot.new()
		# Верхняя шахта продлевается до крыши: в оригинале Otto входит в здание
		# лифтом, и это единственный проём в её настиле (ADR-0014, пункт 2).
		# Полос от этого не прибавляется — крыша достаётся первой, а не своей.
		shaft.top = BuildingRules.ROOF if top == 0 else top
		shaft.bottom = mini(top + span - 1, floors - 1)

		var levels: Array[int] = []
		for index in range(shaft.top, shaft.bottom + 1):
			levels.append(index)

		# Место должно стоять на всех уровнях полосы разом: здание расширяется
		# книзу, и верх полосы — самое тесное её место.
		var free := _free_slots(rules, taken, levels)
		if free.is_empty():
			push_error("полосе %d..%d негде поставить шахту" % [shaft.top, shaft.bottom])
			return

		# Соседние шахты не должны стоять в одном столбце: иначе спуск свёлся бы
		# к «зажать вниз», а переход между полосами — весь смысл здания.
		var slot := _pick_slot(rng, free, previous_slot)
		shaft.x = rules.slot_x(slot)
		for index in levels:
			_occupy(taken, index, slot)

		shafts.append(shaft)
		previous_slot = slot
		top = shaft.bottom + 1


func _lay_escalators(rules: BuildingRules, rng: RandomNumberGenerator, taken: Dictionary) -> void:
	# Эскалатор нужен на стыке полос: с нижнего этажа шахты лифт дальше не идёт.
	for index in shafts.size() - 1:
		var upper := shafts[index].bottom
		var from_x := shafts[index].x
		var free := _free_slots(rules, taken, [upper, upper + 1] as Array[int])
		if free.is_empty():
			# Молча пропустить нельзя: без эскалатора полоса ниже недостижима.
			push_error("этаж %d остался без эскалатора: свободных мест нет" % upper)
			continue

		var slot := _pick_escalator_slot(rules, rng, free, upper, from_x)
		var escalator := EscalatorSpot.new()
		escalator.floor_index = upper
		escalator.x = rules.slot_x(slot)
		escalator.towards = _descent_towards(rules, slot, upper, from_x)
		_occupy(taken, upper, slot)
		_occupy(taken, upper + 1, slot)
		escalators.append(escalator)


## Место под эскалатор: из свободных берутся те, где площадка встаёт между шахтой
## и проёмом. У стены полотно уводить некуда, и там проём ложится Otto под ноги на
## полпути от лифта — такие места отбрасываем, пока есть из чего выбрать.
func _pick_escalator_slot(
	rules: BuildingRules,
	rng: RandomNumberGenerator,
	free: Array[int],
	floor_index: int,
	from_x: float
) -> int:
	var fitting: Array[int] = []
	for slot in free:
		var towards := _descent_towards(rules, slot, floor_index, from_x)
		if is_equal_approx(towards, _away_from(rules, slot, from_x)):
			fitting.append(slot)

	var pool := free if fitting.is_empty() else fitting
	return _pick_any(rng, pool)


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


func _lay_lamps(rules: BuildingRules, rng: RandomNumberGenerator, taken: Dictionary) -> void:
	# Крыша ламп не получает — над ней небо, подвес держать не на чем. В диапазон
	# она и не входит: этажи начинаются с нулевого, крыша лежит выше (ADR-0014).
	# Сам нулевой этаж лампу теперь получает: потолок у него появился.
	for index in floors:
		for _number in rules.lamps_per_floor:
			var slot := _free_slot(rng, rules, taken, [index] as Array[int])
			if slot < 0:
				break

			var lamp := LampSpot.new()
			lamp.floor_index = index
			lamp.x = rules.slot_x(slot)
			_occupy(taken, index, slot)
			lamps.append(lamp)


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
