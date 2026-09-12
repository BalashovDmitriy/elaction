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


## Место на этаже, где нет ни шахты, ни эскалатора: там можно стоять, не провалившись.
##
## Нужно тем, кого ставят на этаж снаружи раскладки: Otto на старте и после смерти,
## выход из здания. Двери и лампы дыр в полу не делают и потому не мешают.
func safe_x(rules: BuildingRules, floor_index: int) -> float:
	var busy: Dictionary = {}
	for shaft in shafts:
		if floor_index >= shaft.top and floor_index <= shaft.bottom:
			busy[shaft.x] = true
	for escalator in escalators:
		if floor_index == escalator.floor_index or floor_index == escalator.floor_index + 1:
			busy[escalator.x] = true

	for slot in rules.slots:
		var x := rules.slot_x(slot)
		if not busy.has(x):
			return x
	return rules.slot_x(0)


func _lay_shafts(rules: BuildingRules, rng: RandomNumberGenerator, taken: Dictionary) -> void:
	var top := 0
	var previous_slot := -1
	while top < floors:
		var shaft := ShaftSpot.new()
		shaft.top = top
		shaft.bottom = mini(top + rules.shaft_span - 1, floors - 1)

		# Соседние шахты не должны стоять в одном столбце: иначе спуск свёлся бы
		# к «зажать вниз», а переход между полосами — весь смысл здания.
		var slot := _pick_slot(rng, rules.slots, [previous_slot])
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
		var slot := _free_slot(rng, rules.slots, taken, [upper, upper + 1])
		if slot < 0:
			continue

		var escalator := EscalatorSpot.new()
		escalator.floor_index = upper
		escalator.x = rules.slot_x(slot)
		escalator.towards = -1.0 if slot > 0 else 1.0
		_occupy(taken, upper, slot)
		_occupy(taken, upper + 1, slot)
		escalators.append(escalator)


func _lay_doors(rules: BuildingRules, rng: RandomNumberGenerator, taken: Dictionary) -> void:
	var with_document := _document_floors(rules, rng)
	for index in floors:
		for number in rules.doors_per_floor:
			var slot := _free_slot(rng, rules.slots, taken, [index])
			if slot < 0:
				break

			var door := DoorSpot.new()
			door.floor_index = index
			door.x = rules.slot_x(slot)
			# Красная дверь на этаже одна: первая из его дверей.
			door.has_document = number == 0 and with_document.has(index)
			_occupy(taken, index, slot)
			doors.append(door)


func _lay_lamps(rules: BuildingRules, rng: RandomNumberGenerator, taken: Dictionary) -> void:
	for index in floors:
		for _number in rules.lamps_per_floor:
			var slot := _free_slot(rng, rules.slots, taken, [index])
			if slot < 0:
				break

			var lamp := LampSpot.new()
			lamp.floor_index = index
			lamp.x = rules.slot_x(slot)
			_occupy(taken, index, slot)
			lamps.append(lamp)


## Этажи с документами: здание делится на полосы, и из каждой берётся один этаж.
## Так документы разнесены по высоте и пройти приходится всё здание, а не верх.
func _document_floors(rules: BuildingRules, rng: RandomNumberGenerator) -> Dictionary:
	var chosen: Dictionary = {}
	var wanted := mini(rules.documents, floors)
	if wanted <= 0:
		return chosen

	var band := float(floors) / float(wanted)
	for number in wanted:
		var from := int(floor(band * float(number)))
		var to := int(floor(band * float(number + 1))) - 1
		chosen[rng.randi_range(from, maxi(to, from))] = true
	return chosen


func _pick_slot(rng: RandomNumberGenerator, slots: int, avoid: Array) -> int:
	var slot := rng.randi_range(0, slots - 1)
	if slots <= 1 or not avoid.has(slot):
		return slot
	return (slot + 1 + rng.randi_range(0, slots - 2)) % slots


## Свободное место сразу на всех перечисленных этажах или -1.
func _free_slot(rng: RandomNumberGenerator, slots: int, taken: Dictionary, on_floors: Array) -> int:
	var free: Array[int] = []
	for slot in slots:
		var busy := false
		for index: int in on_floors:
			if _is_taken(taken, index, slot):
				busy = true
				break
		if not busy:
			free.append(slot)

	if free.is_empty():
		return -1
	return free[rng.randi_range(0, free.size() - 1)]


func _occupy(taken: Dictionary, floor_index: int, slot: int) -> void:
	if not taken.has(floor_index):
		taken[floor_index] = {}
	taken[floor_index][slot] = true


func _is_taken(taken: Dictionary, floor_index: int, slot: int) -> bool:
	return taken.has(floor_index) and taken[floor_index].has(slot)
