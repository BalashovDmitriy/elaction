extends GutTest

## Тесты правил здания.
##
## Отсюда берётся вся вертикальная арифметика: где поверхность этажа, какой этаж
## ближе к точке, где потолок. По ним же считается место возврата после смерти
## и геометрия затемняющей полосы.


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
