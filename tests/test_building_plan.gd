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


func test_building_holds_exactly_the_wanted_documents() -> void:
	var rules := _rules()
	var plan := BuildingPlan.generate(rules, 6)
	assert_eq(plan.document_floors().size(), BuildingDocuments.count(rules))


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
## уступают дверям, шахтам и эскалаторам. Тёмный этаж карты — ни одной
## (ADR-0028, решение 4); прочий — хоть одну.
func test_floors_get_as_many_lamps_as_their_width_asks() -> void:
	var rules := _rules()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for index: int in rules.floors:
			var on_floor := _lamps_on(plan, index)
			if rules.is_unlit(index):
				assert_eq(
					on_floor.size(), 0, "сид %d: тёмный этаж %d с лампой" % [building_seed, index]
				)
				continue
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


## Тесное здание: этажи, на которых шахте, эскалаторам и обязательной двери не
## оставить лампе свободного места. Такой этаж всё равно обязан получить лампу —
## иначе он не светел и погасить его нечем, а правило темноты считает его горящим
## навсегда.
##
## Запасная ветка раскладки (лампа делит место с дверью) с M20 на таких правилах
## не срабатывает: лампы встают раньше лишних дверей, обязательная дверь одна, а
## этаж выхода, где раньше выход, шахта и дверь съедали все три места, стал
## гаражом без дверей (ADR-0031, решение 4). Ветка оставлена как страховка для
## правил, которых ещё нет; тест держит гарантию — лампа на каждом светлом этаже.
func test_a_crowded_floor_still_gets_a_lamp() -> void:
	var rules := _rules()
	# Три места, а не пять: с M18e двери сверх обязательной встают после ламп
	# (ADR-0028, решение 2), и на пяти местах лампе место находится всегда.
	rules.slots = 3
	rules.top_slots = 3
	rules.width = 16.8
	rules.floors = 6
	# Здание одной ширины: порог ниже дна, и узкой части нет вовсе.
	rules.wide_from = 0
	rules.documents_cap = 1
	rules.doors_cap = 3
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for index: int in rules.floors:
			var on_floor := _lamps_on(plan, index)
			if rules.is_unlit(index):
				continue
			assert_gte(
				on_floor.size(),
				1,
				"сид %d: этаж %d остался без единой лампы" % [building_seed, index]
			)


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


func _claim(busy: Dictionary, floor_index: int, x: float) -> void:
	var key := "%d:%.0f" % [floor_index, x]
	assert_false(busy.has(key), "место %s занято дважды" % key)
	busy[key] = true


## Места не делятся — но и габариты не должны налезать друг на друга.
##
## Место — точка сетки, а предмет на нём — полоса: створка двери 1.2 м, проём
## шахты 1.8, лампа 0.6, стена 0.9. При шаге 1.8 м (ADR-0026, решение 3) место
## занято почти целиком, и у соседей остаётся 0.6 м зазора. Проверка мест этого
## не видит: две соседние шахты стояли бы каждая на своём месте и смыкались бы
## без пола между ними.
##
## Проём шахты считается на всех её уровнях, дно включая: кабина стоит и там.
## Проём эскалатора — только на его этаже: этажом ниже там пол.
func test_nothing_on_a_floor_overlaps_its_neighbours() -> void:
	var rules := _rules()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for index: int in rules.levels():
			var bands := _footprints(plan, rules, index)
			bands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
			for number in range(1, bands.size()):
				var before: Array = bands[number - 1]
				var after: Array = bands[number]
				assert_lte(
					before[1] as float,
					(after[0] as float) + 0.001,
					(
						"сид %d, этаж %d: %s налезает на %s"
						% [building_seed, index, before[2], after[2]]
					)
				)


## Две шахты в соседних местах сомкнулись бы: между ними не осталось бы пола,
## и выйти из кабины можно было бы только в соседнюю.
func test_shafts_never_stand_side_by_side() -> void:
	var rules := _rules()
	var pitch := rules.slot_x(1) - rules.slot_x(0)
	for building_seed: int in range(1, 41):
		var plan := BuildingPlan.generate(rules, building_seed)
		for one in plan.shafts:
			for other in plan.shafts:
				if one == other or one.top > other.bottom or other.top > one.bottom:
					continue
				assert_gt(
					absf(one.x - other.x),
					pitch * 1.5,
					"сид %d: шахты %d и %d рядом" % [building_seed, one.slot, other.slot]
				)


## Полосы, которые предметы занимают на этаже: [левый край, правый край, что это].
func _footprints(plan: BuildingPlan, rules: BuildingRules, index: int) -> Array:
	var bands: Array = []
	var shaft_half := rules.shaft_width * 0.5
	for shaft in plan.shafts:
		if shaft.top <= index and index <= shaft.bottom:
			bands.append([shaft.x - shaft_half, shaft.x + shaft_half, "шахта"])
	for escalator in plan.escalators:
		if escalator.floor_index == index:
			var gap := escalator.gap(rules)
			bands.append([gap.x, gap.y, "эскалатор"])
	var door_half := Door.LEAF_SIZE.x * 0.5
	for door in plan.doors:
		if door.floor_index == index:
			bands.append([door.x - door_half, door.x + door_half, "дверь"])
	if index == plan.floors - 1:
		var exit_half := BuildingShell.EXIT_WIDTH * 0.5
		bands.append([plan.exit_x - exit_half, plan.exit_x + exit_half, "выход"])
	var wall_half := rules.inner_wall_width * 0.5
	for wall in plan.walls:
		if wall.floor_index == index:
			bands.append([wall.x - wall_half, wall.x + wall_half, "стена"])
	return bands


## Пол между двумя проёмами — либо его нет вовсе, либо на нём помещается тело.
##
## Полоса уже тела — ловушка: на ней нельзя встать, а агент, вышедший из
## кабины, упирается в неё щупом и замирает полкорпусом в шахте. При шаге 1.8 м
## такую давал эскалатор, спускавшийся к шахте через место: 0.6 м пола против
## 0.72 тела (авторевью M18c).
func test_floor_between_openings_fits_a_body() -> void:
	var rules := _rules()
	for building_seed: int in range(1, 41):
		var plan := BuildingPlan.generate(rules, building_seed)
		for index: int in rules.levels():
			var holes: Array = []
			for band: Array in _footprints(plan, rules, index):
				if band[2] == "шахта" or band[2] == "эскалатор":
					holes.append(band)
			holes.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
			for number in range(1, holes.size()):
				var strip: float = (holes[number][0] as float) - (holes[number - 1][1] as float)
				if strip <= 0.001:
					continue
				assert_gte(
					strip,
					Proportions.BODY_WIDTH,
					(
						"сид %d, этаж %d: между %s и %s %.2f м пола"
						% [building_seed, index, holes[number - 1][2], holes[number][2], strip]
					)
				)
