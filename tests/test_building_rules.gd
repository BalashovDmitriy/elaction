extends GutTest

## Тесты правил здания.
##
## Отсюда берётся вся вертикальная арифметика: где поверхность этажа, какой этаж
## ближе к точке, где потолок. По ним же считается место возврата после смерти
## и геометрия затемняющей полосы. И злость агентов — она растёт из двух мест
## сразу, и потолок на ней держит игру проходимой.


func _rules() -> BuildingRules:
	var rules := BuildingRules.new()
	rules.floors = 30
	rules.floor_height = 120.0
	rules.slab_height = 20.0
	return rules


func test_top_floor_is_the_roof() -> void:
	var rules := _rules()
	assert_eq(rules.floor_surface(0), rules.slab_height, "нулевой этаж — самый верхний")


func test_floors_go_down_by_their_height() -> void:
	var rules := _rules()
	assert_eq(rules.floor_surface(1) - rules.floor_surface(0), rules.floor_height)


func test_nearest_floor_is_the_one_underfoot() -> void:
	var rules := _rules()
	assert_eq(rules.floor_index_near(rules.floor_surface(4)), 4)
	assert_eq(rules.floor_index_near(rules.floor_surface(4) + 10.0), 4, "чуть ниже — тот же")


func test_nearest_floor_never_leaves_the_building() -> void:
	var rules := _rules()
	assert_eq(rules.floor_index_near(-500.0), 0, "выше крыши этажей нет")
	assert_eq(rules.floor_index_near(100000.0), rules.floors - 1)


func test_top_floor_has_no_ceiling_above_it() -> void:
	assert_eq(_rules().story_top(0), 0.0)


func test_ceiling_is_the_underside_of_the_slab_above() -> void:
	var rules := _rules()
	var expected := rules.floor_surface(0) + rules.slab_height
	assert_eq(rules.story_top(1), expected)


func test_slots_spread_between_the_margins() -> void:
	var rules := _rules()
	assert_eq(rules.slot_x(0), rules.margin, "первое место — у левого отступа")
	assert_eq(rules.slot_x(rules.slots - 1), rules.width - rules.margin)


func test_agents_get_meaner_building_by_building() -> void:
	var first := BuildingRules.for_building(1).agent_menace
	var second := BuildingRules.for_building(2).agent_menace
	assert_eq(first, 1.0, "первое здание — обычные агенты")
	assert_almost_eq(second - first, BuildingRules.MENACE_PER_BUILDING, 0.001)


func test_growth_by_building_leaves_room_for_the_alarm() -> void:
	var far := BuildingRules.for_building(100).agent_menace
	assert_eq(far, BuildingRules.MENACE_BY_BUILDING_CAP)
	assert_lt(
		far,
		BuildingRules.MENACE_CAP,
		"рост от зданий упирается ниже общего потолка, иначе сирене нечего добавить"
	)


## Потолок общий: пока он стоял только на росте от зданий, тревога множила уже
## обрезанное число и уводила дальность выстрела на 900 px при этаже в 1120 px.
func test_the_alarm_cannot_push_menace_past_the_cap() -> void:
	var rules := BuildingRules.for_building(100)
	assert_eq(rules.menace_with(1.5), BuildingRules.MENACE_CAP)
	assert_eq(rules.menace_with(100.0), BuildingRules.MENACE_CAP, "и никакая другая")


func test_the_alarm_still_bites_on_early_buildings() -> void:
	var rules := BuildingRules.for_building(1)
	assert_gt(rules.menace_with(1.5), rules.menace_with(1.0))


## Ноль из инспектора делил бы на себя задержку смены агента и запер бы дверь.
func test_menace_never_reaches_zero() -> void:
	var rules := BuildingRules.new()
	rules.agent_menace = 0.0
	assert_gt(rules.menace_with(1.0), 0.0)
