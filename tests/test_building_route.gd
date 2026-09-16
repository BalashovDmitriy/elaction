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


## Если убрать эскалаторы, полосы шахт перестают соединяться — тест проверяет,
## что проходимость ловится, а не подтверждается всегда.
func test_building_without_escalators_is_not_winnable() -> void:
	var rules := _rules()
	var plan := BuildingPlan.generate(rules, 3)
	plan.escalators.clear()
	assert_false(BuildingRoute.is_winnable(plan, rules), "без эскалаторов спуска нет")
