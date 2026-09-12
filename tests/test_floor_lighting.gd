extends GutTest

## Тесты света этажей.
##
## Сбитая лампа гасит свой этаж и обратно он не загорается — это наше решение,
## а не механика оригинала (ADR-0006, пункт 7).


func test_floors_start_lit() -> void:
	assert_false(FloorLighting.new().is_dark(0))


func test_lamp_darkens_its_floor() -> void:
	var lighting := FloorLighting.new()
	assert_true(lighting.darken(1), "этаж погас впервые")
	assert_true(lighting.is_dark(1))


func test_neighbours_stay_lit() -> void:
	var lighting := FloorLighting.new()
	lighting.darken(1)
	assert_false(lighting.is_dark(0), "гаснет только свой этаж, не всё здание")
	assert_false(lighting.is_dark(2))


func test_second_lamp_on_the_same_floor_changes_nothing() -> void:
	var lighting := FloorLighting.new()
	lighting.darken(1)
	assert_false(lighting.darken(1), "гасить погашенное незачем")
	assert_eq(lighting.dark_floors(), 1)
