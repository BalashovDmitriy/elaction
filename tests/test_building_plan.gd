extends GutTest

## Тесты раскладки здания.
##
## Раскладка не знает про узлы: считается по правилам и сиду, поэтому проверяется
## напрямую. Главное, что здесь стережётся, — проходимость: шахты не сквозные,
## и если генератор забудет эскалатор на стыке полос, спуститься будет нельзя.

## Сиды, на которых проверяются правила раскладки. Здание случайно, и одна
## проверка на одном сиде подтверждает только его — а дыры вылезают на редких.
const SEEDS: Array[int] = [1, 2, 3, 5, 8, 13, 21, 34]


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
	assert_eq(covered.size(), rules.floors + 1, "каждый уровень обслуживается шахтой")
	assert_true(covered.has(BuildingRules.ROOF), "верхняя шахта доходит до крыши")


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


## Над крышей небо, вешать лампу там не на что: она висела бы в воздухе.
func test_no_lamp_hangs_over_the_roof() -> void:
	var plan := BuildingPlan.generate(_rules(), 13)
	for lamp in plan.lamps:
		assert_gt(lamp.floor_index, BuildingRules.ROOF, "над крышей нет потолка")


## Нулевой этаж перестал быть крышей и лампу наконец получает: потолок у него
## появился, и до этого весь верх здания был единственным этажом без света.
func test_the_top_floor_gets_a_lamp_now_that_it_has_a_ceiling() -> void:
	var plan := BuildingPlan.generate(_rules(), 13)
	var on_top := 0
	for lamp in plan.lamps:
		if lamp.floor_index == 0:
			on_top += 1
	assert_gt(on_top, 0, "у верхнего этажа есть потолок, значит есть и лампа")


## Ламп на этаже столько, сколько просит ширина, — если хватило мест: лампы
## кладутся последними и уступают дверям, шахтам и эскалаторам.
func test_floors_get_as_many_lamps_as_their_width_asks() -> void:
	var rules := _rules()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for index: int in rules.floors:
			var on_floor := _lamps_on(plan, index)
			assert_gte(on_floor.size(), 1, "сид %d: этаж %d без ламп" % [building_seed, index])
			assert_lte(
				on_floor.size(),
				rules.lamps_on(index),
				"сид %d: этаж %d — ламп больше, чем просит ширина" % [building_seed, index]
			)
		assert_gt(
			_lamps_on(plan, rules.floors - 1).size(),
			_lamps_on(plan, 0).size(),
			"сид %d: внизу ламп больше, чем наверху" % building_seed
		)


## Лампы не сбиваются в один край этажа: зона каждой — единица темноты, и
## этаж с лампами в одном углу тёмен в другом при всех горящих. Лампы встают в
## ближайшие свободные места к серединам своих зон, поэтому на тесном этаже
## они могут стоять рядом — но середина между ними остаётся в середине этажа.
func test_lamps_are_spread_along_the_floor() -> void:
	var rules := _rules()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for index: int in rules.floors:
			var on_floor := _lamps_on(plan, index)
			if on_floor.size() < 2:
				continue
			var span := rules.floor_span(index)
			var quarter := (span.y - span.x) * 0.25
			var mean := 0.0
			for x in on_floor:
				mean += x
			mean /= float(on_floor.size())
			assert_between(
				mean,
				span.x + quarter,
				span.y - quarter,
				"сид %d: этаж %d — лампы сбились в один край" % [building_seed, index]
			)
			assert_gt(
				on_floor[on_floor.size() - 1] - on_floor[0],
				0.0,
				"сид %d: этаж %d — две лампы в одном месте" % [building_seed, index]
			)


## Тесное здание: этажи, на которых шахте, эскалаторам и дверям не оставить
## лампе ни одного свободного места. Такой этаж всё равно обязан получить
## лампу — иначе он не светел и погасить его нечем, а правило темноты считает
## его горящим навсегда.
##
## Проверяются вырожденные правила, а не сид: с правилами по умолчанию такого
## этажа не встретилось ни на одном из 400 сидов, и запасная ветка раскладки
## не исполнялась бы никогда. Тест сторожит и её саму — хотя бы одна лампа
## обязана оказаться над дверью, иначе здание вышло просторным и проверять
## тут нечего.
func test_a_crowded_floor_still_gets_a_lamp() -> void:
	var rules := _rules()
	rules.slots = 5
	rules.width = 16.8
	rules.floors = 6
	rules.width_steps = 1
	rules.documents = 1
	rules.doors_per_floor = 3
	rules.top_doors = 3
	var shared := 0
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for index: int in rules.floors:
			var on_floor := _lamps_on(plan, index)
			assert_gte(
				on_floor.size(),
				1,
				"сид %d: этаж %d остался без единой лампы" % [building_seed, index]
			)
			for door in plan.doors:
				if door.floor_index != index:
					continue
				for x: float in on_floor:
					if is_equal_approx(door.x, x):
						shared += 1
	assert_gt(shared, 0, "здание оказалось просторным — запасная ветка не сработала")


func _lamps_on(plan: BuildingPlan, floor_index: int) -> PackedFloat64Array:
	var xs := PackedFloat64Array()
	for lamp in plan.lamps:
		if lamp.floor_index == floor_index:
			xs.append(lamp.x)
	xs.sort()
	return xs


## Крыша — место, а не этаж: агенты на ней не появляются, потому что нет дверей.
## Пока она была нулевым этажом, двое стояли в зоне огня от точки старта.
func test_the_roof_carries_no_doors() -> void:
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(_rules(), building_seed)
		for door in plan.doors:
			assert_gt(door.floor_index, BuildingRules.ROOF, "сид %d" % building_seed)


## Шахта проходит сквозь этажи разной ширины, и её столбец должен стоять
## на каждом из них: здание расширяется книзу, самый тесный — верх полосы.
func test_every_shaft_stands_on_a_slot_its_whole_band_offers() -> void:
	var rules := _rules()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for shaft in plan.shafts:
			for index in range(shaft.top, shaft.bottom + 1):
				var span := rules.floor_span(index)
				var half := rules.shaft_width * 0.5
				assert_true(
					shaft.x - half >= span.x and shaft.x + half <= span.y,
					"сид %d: шахта на этаже %d вышла за стену" % [building_seed, index]
				)


## Всё, что раскладка ставит, должно стоять внутри силуэта своего уровня:
## за ним улица, и дверь там висела бы в воздухе.
func test_nothing_is_placed_outside_its_own_floor() -> void:
	var rules := _rules()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for door in plan.doors:
			var span := rules.floor_span(door.floor_index)
			assert_true(
				door.x > span.x and door.x < span.y,
				"сид %d: дверь на этаже %d за стеной" % [building_seed, door.floor_index]
			)
		for lamp in plan.lamps:
			var span := rules.floor_span(lamp.floor_index)
			assert_true(
				lamp.x > span.x and lamp.x < span.y,
				"сид %d: лампа на этаже %d за стеной" % [building_seed, lamp.floor_index]
			)


func _shaft_x_on(plan: BuildingPlan, floor_index: int) -> float:
	for shaft in plan.shafts:
		if floor_index >= shaft.top and floor_index <= shaft.bottom:
			return shaft.x
	return 0.0


func _claim(busy: Dictionary, floor_index: int, x: float) -> void:
	var key := "%d:%.0f" % [floor_index, x]
	assert_false(busy.has(key), "место %s занято дважды" % key)
	busy[key] = true
