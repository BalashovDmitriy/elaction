extends GutTest

## Тесты проходимости здания.
##
## Здание — чистая функция от сида, поэтому проверять надо не «этот уровень
## работает», а «любое здание, которое сгенерируется, работает». Три бага M5a
## вылезли не на всех сидах — на сиде 1 их было не видно.

const SEEDS: int = 40


func _rules() -> BuildingRules:
	return BuildingRules.new()


func test_every_building_can_be_finished() -> void:
	var rules := _rules()
	for building_seed in range(1, SEEDS + 1):
		var plan := BuildingPlan.generate(rules, building_seed)
		var missing := BuildingRoute.unreachable_spots(plan, rules)
		assert_true(missing.is_empty(), "сид %d: недостижимо — %s" % [building_seed, missing])


func test_start_is_reachable_from_itself() -> void:
	var rules := _rules()
	var plan := BuildingPlan.generate(rules, 1)
	assert_false(BuildingRoute.reachable(plan, rules).is_empty())


func test_route_reaches_every_floor() -> void:
	var rules := _rules()
	var plan := BuildingPlan.generate(rules, 2)
	var seen := BuildingRoute.reachable(plan, rules)

	var floors_seen: Dictionary = {}
	for node: String in seen:
		floors_seen[node.split(":")[0]] = true
	assert_eq(floors_seen.size(), rules.floors + 1, "до каждого уровня можно добраться")


## Проходимость должна ловиться, а не подтверждаться всегда.
##
## До M18 здание ломали, убрав эскалаторы: полосы шахт шли встык и без них не
## соединялись. Теперь шахты перехлёстываются (ADR-0024, решение 3), и без
## эскалаторов спуск остаётся — ломать надо иначе.
func test_an_isolated_bottom_floor_is_not_winnable() -> void:
	var rules := _rules()
	var plan := BuildingPlan.generate(rules, 3)
	assert_true(BuildingRoute.is_winnable(plan, rules), "целое здание проходимо")

	var bottom := plan.floors - 1
	var kept: Array[BuildingPlan.ShaftSpot] = []
	for shaft in plan.shafts:
		if shaft.bottom < bottom:
			kept.append(shaft)
	plan.shafts = kept
	plan.escalators.clear()
	assert_false(BuildingRoute.is_winnable(plan, rules), "до отрезанного низа не добраться")


## Стена режет ходьбу, но не перекрытие (ADR-0024, решение 5). Счёта два, и
## разъехаться им нельзя: этаж со стеной остаётся цельной плитой, по которой
## насквозь всё равно не пройти.
func test_a_wall_cuts_walking_but_not_the_slab() -> void:
	var rules := _rules()
	var plan := BuildingPlan.generate(rules, 4)
	var index := plan.floors - 1
	var span := rules.floor_span(index)

	var before := BuildingPlan.spans_between(plan.blocks_on(rules, index), span)
	var wall := BuildingPlan.WallSpot.new()
	wall.floor_index = index
	wall.x = (span.x + span.y) * 0.5
	plan.walls.append(wall)

	var slab := BuildingPlan.spans_between(plan.gaps_on(rules, index), span)
	var walk := BuildingPlan.spans_between(plan.blocks_on(rules, index), span)
	assert_eq(slab.size(), 1, "нижний этаж — цельная плита, стена на ней стоит")
	assert_eq(walk.size(), before.size() + 1, "а ходьба разрезана ею надвое")


## Граф не обещает поездки, которой пара не сделает.
##
## Ярусы скреплены через этаж, и вошедший не выбирает, какой из них его
## встретит: верхний не спускается на нижний этаж шахты, нижний не поднимается
## на верхний (ADR-0025, решение 1). Обещать можно только то, что довезёт любой
## из двух, — иначе бот, задумав такую поездку, будет держать «вниз» до конца
## бюджета, а игрок решит, что лифт сломан.
##
## Переход через проём при этом остаётся на всех этажах шахты: кабина на них
## встаёт, и сквозь неё проходят с одного края на другой.
func test_a_pair_promises_only_what_both_decks_reach() -> void:
	var rules := _rules()
	var found := 0
	for building_seed in range(1, 21):
		var plan := BuildingPlan.generate(rules, building_seed)
		var graph := BuildingRoute.walkable(plan, rules)
		var moves: Dictionary = graph["moves"]
		for shaft in plan.shafts:
			if not shaft.double_deck:
				continue
			found += 1
			for from_node: String in moves:
				var from_floor := int(from_node.split(":")[0])
				for move: Dictionary in moves[from_node]:
					if move["kind"] != "shaft" or not is_equal_approx(move["x"], shaft.x):
						continue
					var to_floor := int(move["floor"])
					if to_floor == from_floor:
						continue
					# Столбец сам по себе шахту не опознаёт: полосы не
					# перекрываются по этажам, но одно и то же место сетки
					# занимают разные шахты на разной высоте.
					if not _inside(shaft, from_floor) or not _inside(shaft, to_floor):
						continue
					assert_true(
						shaft.rides_between(from_floor, to_floor),
						(
							"сид %d: шахта %d..%d с парой обещает %d -> %d"
							% [building_seed, shaft.top, shaft.bottom, from_floor, to_floor]
						)
					)
	assert_gt(found, 0, "на двадцати сидах хоть одна пара обязана выпасть")


## Лежит ли этаж в полосе шахты.
func _inside(shaft: BuildingPlan.ShaftSpot, floor_index: int) -> bool:
	return floor_index >= shaft.top and floor_index <= shaft.bottom
