extends GutTest

## Эскалаторы у края этажа, под 45°, зигзагом (ADR-0043, решение 15).
##
## Посередине этажа эскалатор выглядел нелепо. Теперь он спускается к краю:
## верхняя площадка внутри этажа, нижняя — у края этажа ниже, проём тянется от
## площадки к краю и к площадке ведёт пол, а не прыжок через дыру.

const SEEDS: Array[int] = [1, 2, 3, 5, 8, 13, 21, 34, 55, 89]


func _rules() -> BuildingRules:
	return BuildingRules.new()


func test_the_flight_is_forty_five_degrees() -> void:
	var rules := _rules()
	var angle := rad_to_deg(atan2(rules.floor_height, rules.escalator_run))
	assert_almost_eq(angle, 45.0, 0.01, "пролёт под 45°")


## Нижняя площадка — у края, до которого пролёт уходит: не дальше места от
## отступа, и полотно смотрит к этому краю.
func test_every_escalator_lands_at_the_edge() -> void:
	var rules := _rules()
	var pitch := rules.slot_x(1) - rules.slot_x(0)
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for escalator in plan.escalators:
			var index := escalator.floor_index
			var here := rules.floor_span(index)
			var below := rules.floor_span(index + 1)
			var left := escalator.towards < 0.0
			var edge := maxf(here.x, below.x) if left else minf(here.y, below.y)
			var from_edge := absf(escalator.landing(rules) - edge)
			var where := "сид %d, этаж %d" % [building_seed, index]
			assert_gte(
				from_edge, rules.escalator_edge_margin - 0.001, where + ": площадка не в стене"
			)
			assert_lt(from_edge, rules.escalator_edge_margin + pitch, where + ": площадка у края")


## Проём уходит от площадки к краю, и между серединой этажа и площадкой дыры
## нет: к эскалатору доходят пешком.
func test_the_gap_runs_from_the_pad_to_the_edge() -> void:
	var rules := _rules()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for escalator in plan.escalators:
			var gap := escalator.gap(rules)
			var span := rules.floor_span(escalator.floor_index)
			var where := "сид %d, этаж %d" % [building_seed, escalator.floor_index]
			if escalator.towards < 0.0:
				assert_almost_eq(gap.x, span.x, 0.001, where + ": проём до левого края")
				assert_lt(gap.y, escalator.x, where + ": площадка справа от проёма")
			else:
				assert_almost_eq(gap.y, span.y, 0.001, where + ": проём до правого края")
				assert_gt(gap.x, escalator.x, where + ": площадка слева от проёма")


## Эскалатор с этажа, на который пришёл другой, первым пробует спуск к другому
## краю: зигзагом (решение 15). Второй на этаже — только в другую сторону, чем
## первый. Правило проверяется напрямую: в зданиях по умолчанию эскалаторы подряд
## почти не встают — пара с этажа выше занимает края этажа ниже.
func test_the_next_escalator_tries_the_other_edge_first() -> void:
	var plan := BuildingPlan.new()
	var arrived := BuildingPlan.EscalatorSpot.new()
	arrived.floor_index = 4
	arrived.towards = -1.0
	plan.escalators.append(arrived)
	for coin: int in [0, 1]:
		var sides: Array[float] = plan._escalator_sides(coin, 5, 0.0)
		assert_eq(sides[0], 1.0, "пришли слева — первым вправо, жребий %d" % coin)
	assert_eq(plan._escalator_sides(0, 5, 1.0), [-1.0] as Array[float], "второй — в другую сторону")


## Площадка, на которую приехал эскалатор, не лежит в проёме следующего.
func test_no_arrival_lands_in_the_next_gap() -> void:
	var rules := _rules()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for upper in plan.escalators:
			for lower in plan.escalators:
				if lower.floor_index != upper.floor_index + 1:
					continue
				var arrival := upper.landing(rules)
				var gap := lower.gap(rules)
				assert_false(
					arrival >= gap.x and arrival <= gap.y,
					(
						"сид %d, этаж %d: площадка прибытия в проёме"
						% [building_seed, lower.floor_index]
					)
				)
		assert_true(true, "сид %d разобран" % building_seed)


## Лампа висит на потолке: под проёмом эскалатора с этажа выше её нет.
func test_no_lamp_hangs_under_an_escalator_gap() -> void:
	var rules := _rules()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for lamp in plan.lamps:
			for escalator in plan.escalators:
				if escalator.floor_index != lamp.floor_index - 1:
					continue
				var gap := escalator.gap(rules)
				assert_false(
					lamp.x > gap.x and lamp.x < gap.y,
					"сид %d, этаж %d: лампа под проёмом" % [building_seed, lamp.floor_index]
				)
