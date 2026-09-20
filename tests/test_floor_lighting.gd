extends GutTest

## Тесты света этажей по зонам ламп.
##
## Сбитая лампа гасит свою зону и обратно та не загорается — наше решение, не
## механика оригинала (ADR-0007, ADR-0023). Без сцены: [FloorLighting] помнит
## лампы и темноту, и больше ничего.


## Этаж 1 с двумя лампами — на 5 и на 15 метрах: граница зон на десяти.
func _two_lamps() -> FloorLighting:
	var lighting := FloorLighting.new()
	lighting.hang(1, 15.0)
	lighting.hang(1, 5.0)
	lighting.hang(2, 10.0)
	return lighting


func test_floors_start_lit() -> void:
	var lighting := _two_lamps()
	assert_false(lighting.is_dark(1))
	assert_false(lighting.is_dark_at(1, 5.0))


func test_a_lamp_darkens_its_own_zone() -> void:
	var lighting := _two_lamps()
	assert_true(lighting.darken(1, 5.0), "зона погасла впервые")
	assert_true(lighting.is_dark_at(1, 5.0), "под сбитой лампой темно")
	assert_true(lighting.is_dark_at(1, 8.0), "и по всей её зоне")


func test_the_neighbouring_zone_stays_lit() -> void:
	var lighting := _two_lamps()
	lighting.darken(1, 5.0)
	assert_false(lighting.is_dark_at(1, 15.0), "соседняя лампа горит")
	assert_false(lighting.is_dark_at(1, 12.0), "и её зона тоже")
	assert_false(lighting.is_dark(1), "этаж целиком не погашен")


func test_the_zone_border_lies_halfway_between_lamps() -> void:
	var lighting := _two_lamps()
	lighting.darken(1, 5.0)
	assert_true(lighting.is_dark_at(1, 9.9), "чуть левее середины — зона левой")
	assert_false(lighting.is_dark_at(1, 10.1), "чуть правее — зона правой")
	assert_almost_eq(lighting.zone_of(1, 9.9), 5.0, 0.001)
	assert_almost_eq(lighting.zone_of(1, 10.1), 15.0, 0.001)


func test_the_floor_is_dark_once_every_zone_is() -> void:
	var lighting := _two_lamps()
	lighting.darken(1, 5.0)
	lighting.darken(1, 15.0)
	assert_true(lighting.is_dark(1), "обе лампы сбиты — этаж тёмен")
	assert_eq(lighting.dark_zones(), 2)


func test_neighbouring_floors_stay_lit() -> void:
	var lighting := _two_lamps()
	lighting.darken(1, 5.0)
	assert_false(lighting.is_dark_at(2, 10.0), "гаснет только своя зона, не всё здание")
	assert_false(lighting.is_dark(2))


func test_a_second_shot_at_the_same_zone_changes_nothing() -> void:
	var lighting := _two_lamps()
	lighting.darken(1, 5.0)
	assert_false(lighting.darken(1, 6.0), "гасить погашенное незачем")
	assert_eq(lighting.dark_zones(), 1)


func test_a_floor_without_lamps_never_goes_dark() -> void:
	# Крыша: ламп нет, светит город.
	var lighting := _two_lamps()
	assert_false(lighting.darken(BuildingRules.ROOF, 0.0), "гасить нечего")
	assert_false(lighting.is_dark_at(BuildingRules.ROOF, 0.0))
	assert_false(lighting.is_dark(BuildingRules.ROOF))
	assert_true(is_nan(lighting.zone_of(BuildingRules.ROOF, 0.0)))


func test_lamps_hang_in_any_order() -> void:
	# Раскладка отдаёт лампы как выложила; зона считается по месту, не по порядку.
	var lighting := FloorLighting.new()
	lighting.hang(0, 30.0)
	lighting.hang(0, 10.0)
	lighting.hang(0, 20.0)
	lighting.darken(0, 20.0)
	assert_true(lighting.is_dark_at(0, 21.0))
	assert_false(lighting.is_dark_at(0, 11.0))
	assert_false(lighting.is_dark_at(0, 29.0))
