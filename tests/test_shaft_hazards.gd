extends GutTest

## Tests of the elevator shaft death rules.
##
## The rules themselves are stateless static functions, so they are checked
## directly, without a scene and physics.

## Floor step of the standard building, m.
const FLOOR: float = Proportions.FLOOR


func test_falling_one_floor_is_survivable() -> void:
	assert_false(ShaftHazards.is_deadly_fall(FLOOR, FLOOR), "you can jump down one floor")


func test_falling_two_floors_is_deadly() -> void:
	assert_true(ShaftHazards.is_deadly_fall(FLOOR * 2.0, FLOOR), "two floors is death")


func test_falling_on_a_car_roof_two_floors_down_is_one_floor() -> void:
	# The cab roof is below the floor above it by the slab thickness: a cab standing two
	# floors down meets with its roof a floor and a slab lower — that is one more floor.
	var roof := FLOOR + Proportions.SLAB
	assert_false(ShaftHazards.is_deadly_fall(roof, FLOOR), "a cab roof one floor down")


func test_falling_on_a_car_roof_three_floors_down_is_deadly() -> void:
	var roof := FLOOR * 2.0 + Proportions.SLAB
	assert_true(ShaftHazards.is_deadly_fall(roof, FLOOR), "a cab roof is no salvation")


func test_standing_still_is_not_a_fall() -> void:
	assert_false(ShaftHazards.is_deadly_fall(0.0, FLOOR))


func test_the_rule_follows_the_building_floor() -> void:
	# The building sets the floor height: on a low floor a fall of two is shorter too.
	var low := FLOOR * 0.5
	assert_true(ShaftHazards.is_deadly_fall(FLOOR, low), "two low floors is death")


func test_descending_car_crushes_the_one_standing_under_it() -> void:
	assert_true(ShaftHazards.crushes(60.0, true, false))


func test_rising_car_crushes_nobody() -> void:
	assert_false(ShaftHazards.crushes(-60.0, true, false), "upward means away from the victim")


func test_standing_car_crushes_nobody() -> void:
	assert_false(ShaftHazards.crushes(0.0, true, false))


func test_passenger_rides_and_is_not_crushed() -> void:
	assert_false(ShaftHazards.crushes(60.0, true, true), "the passenger stands on the cab floor")


func test_airborne_victim_is_pushed_not_crushed() -> void:
	assert_false(ShaftHazards.crushes(60.0, false, false), "in the air it just pushes him")


func test_touching_the_car_edge_crushes_nobody() -> void:
	assert_false(ShaftHazards.crushes(60.0, true, false, false), "clipped by the edge, not pinned")


func test_a_body_inside_the_car_span_is_under_it() -> void:
	assert_true(ShaftHazards.is_fully_under(0.0, 0.72, 0.0, 1.8))
	assert_true(
		ShaftHazards.is_fully_under(0.54, 0.72, 0.0, 1.8), "right against the side: still under it"
	)


func test_a_body_across_the_car_edge_is_not_under_it() -> void:
	assert_false(ShaftHazards.is_fully_under(0.7, 0.72, 0.0, 1.8))
	assert_false(ShaftHazards.is_fully_under(-0.7, 0.72, 0.0, 1.8))


func test_the_push_goes_to_the_side_of_the_body() -> void:
	assert_almost_eq(ShaftHazards.push_out(0.7, 0.72, 0.0, 1.8), 1.26, 0.001)
	assert_almost_eq(ShaftHazards.push_out(-0.7, 0.72, 0.0, 1.8), -1.26, 0.001)
