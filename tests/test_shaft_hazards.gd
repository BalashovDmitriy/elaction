extends GutTest

## Тесты правил гибели в шахте лифта.
##
## Сами правила — статические функции без состояния, поэтому проверяются
## напрямую, без сцены и физики.

## Собственный прыжок Otto поднимает примерно на столько.
const JUMP_HEIGHT: float = 80.0

## Расстояние между этажами greybox-уровня: падать с этажа глубже, чем прыгать.
const FLOOR_GAP: float = 120.0


func test_fall_into_an_empty_shaft_is_deadly() -> void:
	assert_true(ShaftHazards.is_deadly_fall(false, false, FLOOR_GAP, JUMP_HEIGHT))


func test_stepping_in_from_the_floor_is_safe() -> void:
	assert_false(
		ShaftHazards.is_deadly_fall(true, false, FLOOR_GAP, JUMP_HEIGHT), "вошёл ногами — не падал"
	)


func test_riding_the_car_down_is_safe() -> void:
	assert_false(
		ShaftHazards.is_deadly_fall(false, true, FLOOR_GAP, JUMP_HEIGHT), "приехал в кабине"
	)


func test_own_jump_over_the_shaft_is_not_a_fall() -> void:
	# Нижний этаж сплошной: прыжок над шахтой приземляется в ту же зону и в воздухе.
	assert_false(
		ShaftHazards.is_deadly_fall(false, false, JUMP_HEIGHT - 20.0, JUMP_HEIGHT),
		"глубже своего прыжка Otto не падал"
	)


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
