extends GutTest

## Тесты раскладки здания.
##
## Раскладка не знает про узлы: считается по правилам и сиду, поэтому проверяется
## напрямую. Главное, что здесь стережётся, — проходимость: шахты не сквозные,
## и если генератор забудет эскалатор на стыке полос, спуститься будет нельзя.


func _rules() -> BuildingRules:
	return BuildingRules.new()


## Отпечаток здания: по нему сравниваются два прогона с одним сидом.
func _fingerprint(plan: BuildingPlan) -> String:
	var parts := PackedStringArray()
	for shaft in plan.shafts:
		parts.append("s%d:%d:%.0f" % [shaft.top, shaft.bottom, shaft.x])
	for escalator in plan.escalators:
		parts.append("e%d:%.0f" % [escalator.floor_index, escalator.x])
	for door in plan.doors:
		parts.append("d%d:%.0f:%s" % [door.floor_index, door.x, door.has_document])
	for lamp in plan.lamps:
		parts.append("l%d:%.0f" % [lamp.floor_index, lamp.x])
	return "|".join(parts)


func test_same_seed_builds_the_same_building() -> void:
	var first := BuildingPlan.generate(_rules(), 7)
	var second := BuildingPlan.generate(_rules(), 7)
	assert_eq(_fingerprint(first), _fingerprint(second), "сид задаёт здание целиком")


func test_another_seed_moves_the_documents() -> void:
	var first := BuildingPlan.generate(_rules(), 1)
	var second := BuildingPlan.generate(_rules(), 2)
	assert_ne(_fingerprint(first), _fingerprint(second), "здания различаются")


func test_shafts_cover_every_floor() -> void:
	var rules := _rules()
	var plan := BuildingPlan.generate(rules, 3)
	var covered: Dictionary = {}
	for shaft in plan.shafts:
		for index in range(shaft.top, shaft.bottom + 1):
			assert_false(covered.has(index), "полосы шахт не налезают друг на друга")
			covered[index] = true
	assert_eq(covered.size(), rules.floors, "каждый этаж обслуживается шахтой")


func test_neighbouring_shafts_stand_in_different_columns() -> void:
	var plan := BuildingPlan.generate(_rules(), 4)
	for index in plan.shafts.size() - 1:
		var here := plan.shafts[index].x
		var below := plan.shafts[index + 1].x
		assert_ne(here, below, "иначе спуск свёлся бы к «зажать вниз»")


func test_every_shaft_boundary_has_an_escalator() -> void:
	var plan := BuildingPlan.generate(_rules(), 5)
	var bridged: Dictionary = {}
	for escalator in plan.escalators:
		bridged[escalator.floor_index] = true
	for index in plan.shafts.size() - 1:
		var boundary: int = plan.shafts[index].bottom
		assert_true(bridged.has(boundary), "со стыка полос надо как-то спуститься")


func test_building_holds_exactly_the_wanted_documents() -> void:
	var rules := _rules()
	var plan := BuildingPlan.generate(rules, 6)
	assert_eq(plan.document_floors().size(), rules.documents)


func test_documents_lie_on_different_floors() -> void:
	var plan := BuildingPlan.generate(_rules(), 8)
	var seen: Dictionary = {}
	for index: int in plan.document_floors():
		assert_false(seen.has(index), "на этаже не больше одной красной двери")
		seen[index] = true


func test_documents_are_spread_over_the_height() -> void:
	var rules := _rules()
	var plan := BuildingPlan.generate(rules, 9)
	var floors := plan.document_floors()
	var lowest: int = floors[floors.size() - 1]
	# Иначе всё здание можно было бы не проходить.
	assert_gt(lowest, rules.floors / 2, "нижний документ — в нижней половине здания")
	assert_lt(floors[0], rules.floors / 2, "верхний — в верхней")


func test_nothing_shares_a_place_on_a_floor() -> void:
	var rules := _rules()
	var plan := BuildingPlan.generate(rules, 10)
	var busy: Dictionary = {}

	for shaft in plan.shafts:
		for index in range(shaft.top, shaft.bottom + 1):
			_claim(busy, index, shaft.x)
	for escalator in plan.escalators:
		_claim(busy, escalator.floor_index, escalator.x)
		_claim(busy, escalator.floor_index + 1, escalator.x)
	_claim(busy, plan.floors - 1, plan.exit_x)
	for door in plan.doors:
		_claim(busy, door.floor_index, door.x)
	for lamp in plan.lamps:
		_claim(busy, lamp.floor_index, lamp.x)


## Проём эскалатора лежит сбоку от площадки, и подойти к ней надо, не перейдя его.
## Иначе Otto, идущий от лифта, проваливается на этаж ниже мимо эскалатора.
func test_escalator_pad_shields_its_gap_from_the_shaft() -> void:
	var rules := _rules()
	for building_seed in range(1, 12):
		var plan := BuildingPlan.generate(rules, building_seed)
		for escalator in plan.escalators:
			var from_x := _shaft_x_on(plan, escalator.floor_index)
			var gap := escalator.gap(rules)
			var near := minf(from_x, escalator.x)
			var far := maxf(from_x, escalator.x)
			assert_false(
				near < gap.y and gap.x < far,
				(
					"сид %d, этаж %d: дыра между лифтом и площадкой"
					% [building_seed, escalator.floor_index]
				)
			)


## На месте возврата нельзя ставить выход: иначе Otto выходил бы из здания,
## едва воскреснув, — а с последним документом это ещё и сдавало бы здание само.
func test_otto_does_not_come_back_to_life_inside_the_exit() -> void:
	var rules := _rules()
	for building_seed in range(1, 12):
		var plan := BuildingPlan.generate(rules, building_seed)
		assert_ne(plan.safe_x(rules, plan.floors - 1), plan.exit_x, "сид %d" % building_seed)


## Место возврата не должно попадать в проём: провалиться сразу после смерти — не то.
func test_safe_spot_never_hangs_over_a_hole() -> void:
	var rules := _rules()
	var plan := BuildingPlan.generate(rules, 12)
	for index in plan.floors:
		var x := plan.safe_x(rules, index)
		for escalator in plan.escalators:
			if escalator.floor_index != index:
				continue
			var gap := escalator.gap(rules)
			assert_false(x >= gap.x and x <= gap.y, "этаж %d стоит над проёмом" % index)


## Крыша — верхний край здания, вешать лампу там не на что: она висела бы в небе.
func test_no_lamp_hangs_over_the_roof() -> void:
	var plan := BuildingPlan.generate(_rules(), 13)
	for lamp in plan.lamps:
		assert_gt(lamp.floor_index, 0, "на крыше нет потолка")


func _shaft_x_on(plan: BuildingPlan, floor_index: int) -> float:
	for shaft in plan.shafts:
		if floor_index >= shaft.top and floor_index <= shaft.bottom:
			return shaft.x
	return 0.0


func _claim(busy: Dictionary, floor_index: int, x: float) -> void:
	var key := "%d:%.0f" % [floor_index, x]
	assert_false(busy.has(key), "место %s занято дважды" % key)
	busy[key] = true
