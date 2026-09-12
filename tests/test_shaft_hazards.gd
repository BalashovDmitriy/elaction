extends GutTest

## Тесты правил гибели в шахте лифта.
##
## Сами правила — статические функции без состояния, поэтому проверяются
## напрямую, без сцены и физики.


func test_fall_into_an_empty_shaft_is_deadly() -> void:
	assert_true(ShaftHazards.is_deadly_fall(false, false))


func test_stepping_in_from_the_floor_is_safe() -> void:
	assert_false(ShaftHazards.is_deadly_fall(true, false), "вошёл ногами — не падал")


func test_riding_the_car_down_is_safe() -> void:
	assert_false(ShaftHazards.is_deadly_fall(false, true), "приехал в кабине")


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
