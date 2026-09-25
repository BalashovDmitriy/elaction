extends GutTest

## Тесты правил гибели в шахте лифта.
##
## Сами правила — статические функции без состояния, поэтому проверяются
## напрямую, без сцены и физики.

## Шаг этажа стандартного здания, м.
const FLOOR: float = Proportions.FLOOR


func test_falling_one_floor_is_survivable() -> void:
	assert_false(ShaftHazards.is_deadly_fall(FLOOR, FLOOR), "на этаж ниже спрыгнуть можно")


func test_falling_two_floors_is_deadly() -> void:
	assert_true(ShaftHazards.is_deadly_fall(FLOOR * 2.0, FLOOR), "с двух этажей — смерть")


func test_falling_on_a_car_roof_two_floors_down_is_one_floor() -> void:
	# Крыша кабины ниже пола над ней на толщину плиты: кабина, стоящая двумя
	# этажами ниже, встречает крышей на этаж и плиту ниже — это ещё этаж.
	var roof := FLOOR + Proportions.SLAB
	assert_false(ShaftHazards.is_deadly_fall(roof, FLOOR), "крыша кабины этажом ниже")


func test_falling_on_a_car_roof_three_floors_down_is_deadly() -> void:
	var roof := FLOOR * 2.0 + Proportions.SLAB
	assert_true(ShaftHazards.is_deadly_fall(roof, FLOOR), "крыша кабины — не спасение")


func test_standing_still_is_not_a_fall() -> void:
	assert_false(ShaftHazards.is_deadly_fall(0.0, FLOOR))


func test_the_rule_follows_the_building_floor() -> void:
	# Этаж задаёт здание: у низкого этажа и падение на два короче.
	var low := FLOOR * 0.5
	assert_true(ShaftHazards.is_deadly_fall(FLOOR, low), "два низких этажа — смерть")


func test_descending_car_crushes_the_one_standing_under_it() -> void:
	assert_true(ShaftHazards.crushes(60.0, true, false))


func test_rising_car_crushes_nobody() -> void:
	assert_false(ShaftHazards.crushes(-60.0, true, false), "вверх — значит от жертвы")


func test_standing_car_crushes_nobody() -> void:
	assert_false(ShaftHazards.crushes(0.0, true, false))


func test_passenger_rides_and_is_not_crushed() -> void:
	assert_false(ShaftHazards.crushes(60.0, true, true), "пассажир стоит на полу кабины")


func test_airborne_victim_is_pushed_not_crushed() -> void:
	assert_false(ShaftHazards.crushes(60.0, false, false), "в воздухе его просто толкает")
