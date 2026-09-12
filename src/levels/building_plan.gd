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
static func spans_between(gaps: Array[Vector2], width: float) -> Array[Vector2]:
	var ordered := gaps.duplicate()
	ordered.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

	var spans: Array[Vector2] = []
	var cursor := 0.0
	for gap: Vector2 in ordered:
		if gap.x > cursor:
			spans.append(Vector2(cursor, gap.x))
		# maxf, чтобы вложенный проём не отматывал курсор назад.
		cursor = maxf(cursor, gap.y)
	if cursor < width:
		spans.append(Vector2(cursor, width))
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
	for slot in rules.slots:
		var x := rules.slot_x(slot)
		if _is_clear(rules, floor_index, x):
			return x
	return rules.slot_x(0)


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
		shaft.top = top
		shaft.bottom = mini(top + span - 1, floors - 1)

		# Соседние шахты не должны стоять в одном столбце: иначе спуск свёлся бы
		# к «зажать вниз», а переход между полосами — весь смысл здания.
		var slot := _pick_slot(rng, rules.slots, [previous_slot] as Array[int])
		shaft.x = rules.slot_x(slot)
		for index in range(shaft.top, shaft.bottom + 1):
			_occupy(taken, index, slot)

		shafts.append(shaft)
		previous_slot = slot
		top = shaft.bottom + 1


func _lay_escalators(rules: BuildingRules, rng: RandomNumberGenerator, taken: Dictionary) -> void:
	# Эскалатор нужен на стыке полос: с нижнего этажа шахты лифт дальше не идёт.
	for index in shafts.size() - 1:
		var upper := shafts[index].bottom
		var from_x := shafts[index].x
		var free := _free_slots(rules.slots, taken, [upper, upper + 1] as Array[int])
		if free.is_empty():
			# Молча пропустить нельзя: без эскалатора полоса ниже недостижима.
			push_error("этаж %d остался без эскалатора: свободных мест нет" % upper)
			continue

		var slot := _pick_escalator_slot(rules, rng, free, from_x)
		var escalator := EscalatorSpot.new()
		escalator.floor_index = upper
		escalator.x = rules.slot_x(slot)
		escalator.towards = _descent_towards(rules, slot, from_x)
		_occupy(taken, upper, slot)
		_occupy(taken, upper + 1, slot)
		escalators.append(escalator)


## Место под эскалатор: из свободных берутся те, где площадка встаёт между шахтой
## и проёмом. У стены полотно уводить некуда, и там проём ложится Otto под ноги на
## полпути от лифта — такие места отбрасываем, пока есть из чего выбрать.
func _pick_escalator_slot(
	rules: BuildingRules, rng: RandomNumberGenerator, free: Array[int], from_x: float
) -> int:
	var fitting: Array[int] = []
	for slot in free:
		if is_equal_approx(_descent_towards(rules, slot, from_x), _away_from(rules, slot, from_x)):
			fitting.append(slot)

	var pool := free if fitting.is_empty() else fitting
	return _pick_any(rng, pool)


## Куда проём должен смотреть: прочь от шахты, из которой Otto приходит.
static func _away_from(rules: BuildingRules, slot: int, comes_from_x: float) -> float:
	return 1.0 if rules.slot_x(slot) > comes_from_x else -1.0


## Куда спускается полотно на самом деле. Это [method _away_from], если только
## место не у стены: оттуда спуск возможен лишь внутрь здания.
static func _descent_towards(rules: BuildingRules, slot: int, comes_from_x: float) -> float:
	if slot <= 0:
		return 1.0
	if slot >= rules.slots - 1:
		return -1.0
	return _away_from(rules, slot, comes_from_x)


## Выход из здания: своё место на нижнем этаже, чтобы на нём не оказались ни дверь,
## ни лампа, ни точка возврата после смерти — иначе Otto выходил бы, едва воскреснув.
func _lay_exit(rules: BuildingRules, rng: RandomNumberGenerator, taken: Dictionary) -> void:
	var bottom := floors - 1
	var slot := _free_slot(rng, rules.slots, taken, [bottom] as Array[int])
	if slot < 0:
		push_error("нижнему этажу не хватило места под выход")
		slot = rules.slots - 1
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
		for _number in rules.doors_per_floor - already:
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
	spans: Array = []
) -> bool:
	var free := _free_slots(rules.slots, taken, [floor_index] as Array[int])
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
	# С нулевого этажа лампу вешать не на что: крыша — верхний край здания,
	# и подвес висел бы в небе над ним.
	for index in range(1, floors):
		for _number in rules.lamps_per_floor:
			var slot := _free_slot(rng, rules.slots, taken, [index] as Array[int])
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


func _pick_slot(rng: RandomNumberGenerator, slots: int, avoid: Array[int]) -> int:
	var slot := rng.randi_range(0, slots - 1)
	if slots <= 1 or not avoid.has(slot):
		return slot
	return (slot + 1 + rng.randi_range(0, slots - 2)) % slots


## Свободное место сразу на всех перечисленных этажах или -1.
func _free_slot(
	rng: RandomNumberGenerator, slots: int, taken: Dictionary, on_floors: Array[int]
) -> int:
	var free := _free_slots(slots, taken, on_floors)
	if free.is_empty():
		return -1
	return _pick_any(rng, free)


## Любое место из набора. Счёт сида зависит от порядка обращений к генератору,
## поэтому выбор — одной строкой на весь файл, а не переписанным трижды.
static func _pick_any(rng: RandomNumberGenerator, pool: Array[int]) -> int:
	return pool[rng.randi_range(0, pool.size() - 1)]


## Все места, свободные сразу на всех перечисленных этажах.
func _free_slots(slots: int, taken: Dictionary, on_floors: Array[int]) -> Array[int]:
	var free: Array[int] = []
	for slot in slots:
		var busy := false
		for index in on_floors:
			if _is_taken(taken, index, slot):
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
