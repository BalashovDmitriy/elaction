extends GutTest

## Тесты выбора этажа, на который возвращается Otto после смерти.
##
## Правил оригинала найти не удалось, поэтому принято своё: этаж гибели —
## ближайшая по вертикали поверхность (ADR-0006, пункт 4).

const FLOORS: Array[float] = [100.0, 220.0, 340.0]


func test_standing_on_a_floor_returns_that_floor() -> void:
	assert_eq(GreyboxLevel.floor_surface_near(100.0, FLOORS), 100.0)


func test_falling_between_floors_picks_the_nearer_one() -> void:
	assert_eq(GreyboxLevel.floor_surface_near(200.0, FLOORS), 220.0)
	assert_eq(GreyboxLevel.floor_surface_near(140.0, FLOORS), 100.0)


func test_bottom_of_the_shaft_returns_the_bottom_floor() -> void:
	assert_eq(GreyboxLevel.floor_surface_near(345.0, FLOORS), 340.0)


func test_floor_index_matches_the_surface() -> void:
	assert_eq(GreyboxLevel.floor_index_near(105.0, FLOORS), 0, "верхний этаж")
	assert_eq(GreyboxLevel.floor_index_near(215.0, FLOORS), 1)
	assert_eq(GreyboxLevel.floor_index_near(340.0, FLOORS), 2, "нижний этаж")
