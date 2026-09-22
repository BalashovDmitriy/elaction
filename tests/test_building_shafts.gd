extends GutTest

## Тесты шахт и эскалаторов: из чего складывается спуск.
##
## С M18 шахты перехлёстываются и число путей растёт книзу (ADR-0024, решение 3),
## а эскалаторы стоят полосой у порога и на разрывах перехлёста (решение 4). Обе
## вещи проверяются по раскладке, без узлов и сцены, и потому на десятках сидов
## за доли секунды — а дыры в генерации вылезают именно на редких.
##
## Своим файлом, а не в [code]test_building_plan.gd[/code]: тот уперся в потолок
## публичных методов, и спуск — самая крупная его часть.

## Сиды, на которых проверяются правила. Здание случайно, и одна проверка на
## одном сиде подтверждает только его.
const SEEDS: Array[int] = [1, 2, 3, 5, 8, 13, 21, 34]


func _rules() -> BuildingRules:
	return BuildingRules.new()


## Уровень без шахты — это уровень, с которого не уехать. Перехлёст при этом
## не только допустим, но и обязателен книзу: ADR-0024, решение 3.
func test_shafts_cover_every_floor() -> void:
	var rules := _rules()
	var plan := BuildingPlan.generate(rules, 3)
	var serving: Dictionary = {}
	for shaft in plan.shafts:
		for index in range(shaft.top, shaft.bottom + 1):
			serving[index] = int(serving.get(index, 0)) + 1

	for index: int in rules.levels():
		assert_true(serving.has(index), "уровень %d остался без шахты" % index)
	assert_true(serving.has(BuildingRules.ROOF), "верхняя шахта доходит до крыши")


## Короткая шахта — не шахта: кабине в ней некуда ехать.
##
## Длину задаёт [code]_shaft_length[/code], но дно обрезается по дну здания, и
## открытая у самого низа полоса выходила короче правила — на сиде 2 такая
## стояла на 29-м этаже одна-одинёшенька. Ловится это только на редком сиде,
## поэтому проверка идёт по всем сразу.
##
## Порог — [constant BuildingRules.MIN_SHAFT_FLOORS], три этажа, и три они
## не случайно: двухэтажная кабина M18b в шахте на два этажа не сдвинется.
func test_no_shaft_is_too_short_to_ride() -> void:
	var rules := _rules()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for shaft in plan.shafts:
			assert_gte(
				shaft.bottom - shaft.top + 1,
				BuildingRules.MIN_SHAFT_FLOORS,
				(
					"сид %d: шахта на x=%.1f обслуживает этажи %d..%d"
					% [building_seed, shaft.x, shaft.top, shaft.bottom]
				)
			)


## Чем ниже, тем больше путей — главный вывод сверки с оригиналом, где на нижних
## семи этажах сходятся пять шахт, а в верхней трети работает одна.
func test_paths_multiply_towards_the_ground() -> void:
	var rules := _rules()
	for building_seed in range(1, 12):
		var plan := BuildingPlan.generate(rules, building_seed)
		var serving: Dictionary = {}
		for shaft in plan.shafts:
			for index in range(shaft.top, shaft.bottom + 1):
				serving[index] = int(serving.get(index, 0)) + 1

		for index: int in rules.levels():
			var here := int(serving.get(index, 0))
			var wanted := rules.shafts_on(index)
			assert_eq(here, wanted, "сид %d: этаж %d обслуживают не так" % [building_seed, index])

		var top := int(serving.get(BuildingRules.ROOF, 0))
		var bottom := int(serving.get(rules.floors - 1, 0))
		assert_eq(top, 1, "наверху спуск безальтернативен")
		assert_eq(bottom, rules.shafts_max, "на дне сходятся все")


func test_neighbouring_shafts_stand_in_different_columns() -> void:
	var plan := BuildingPlan.generate(_rules(), 4)
	for index in plan.shafts.size() - 1:
		var here := plan.shafts[index].x
		var below := plan.shafts[index + 1].x
		assert_ne(here, below, "иначе спуск свёлся бы к «зажать вниз»")


## Со дна шахты надо как-то спуститься: либо другая шахта берёт этот этаж
## и следующий разом, либо на этаже стоит эскалатор (ADR-0024, решение 4).
##
## До M18 шахты шли встык и эскалатор был обязан стоять на каждом стыке. Теперь
## шахты перехлёстываются, и эскалатор нужен только там, где перехлёста не вышло.
func test_every_shaft_bottom_is_bridged() -> void:
	for building_seed in range(1, 12):
		var plan := BuildingPlan.generate(_rules(), building_seed)
		var bridged: Dictionary = {}
		for escalator in plan.escalators:
			bridged[escalator.floor_index] = true

		for shaft in plan.shafts:
			if shaft.bottom >= plan.floors - 1:
				continue
			var overlapped := false
			for other in plan.shafts:
				if other.top <= shaft.bottom and other.bottom > shaft.bottom:
					overlapped = true
					break
			var where := "этаж %d, сид %d" % [shaft.bottom, building_seed]
			assert_true(
				overlapped or bridged.has(shaft.bottom),
				"со дна шахты надо как-то спуститься: " + where
			)


## Эскалаторы живут полосой у порога, где шахта башни кончается над стилобатом
## (ADR-0024, решение 4). Всё, что вне полосы, оправдано разрывом: там кончилась
## шахта и другая этот стык не перекрыла.
func test_escalators_live_in_the_band_or_bridge_a_gap() -> void:
	var rules := _rules()
	for building_seed in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		var in_band := 0
		for escalator in plan.escalators:
			var index := escalator.floor_index
			if rules.in_escalator_band(index):
				in_band += 1
				continue
			var ends_here := false
			for shaft in plan.shafts:
				if shaft.bottom == index:
					ends_here = true
					break
			var where := "сид %d, этаж %d" % [building_seed, index]
			assert_true(ends_here, "эскалатор вне полосы оправдан разрывом: " + where)
		assert_gt(in_band, 0, "сид %d: полоса эскалаторов пуста" % building_seed)


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


func _shaft_x_on(plan: BuildingPlan, floor_index: int) -> float:
	for shaft in plan.shafts:
		if floor_index >= shaft.top and floor_index <= shaft.bottom:
			return shaft.x
	return 0.0
