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
	for door in plan.doors:
		_claim(busy, door.floor_index, door.x)
	for lamp in plan.lamps:
		_claim(busy, lamp.floor_index, lamp.x)


func _claim(busy: Dictionary, floor_index: int, x: float) -> void:
	var key := "%d:%.0f" % [floor_index, x]
	assert_false(busy.has(key), "место %s занято дважды" % key)
	busy[key] = true
