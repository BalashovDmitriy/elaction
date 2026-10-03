extends GutTest

## Tests of floor light by lamp zones.
##
## A shot lamp darkens its zone and the zone does not light up again — our decision, not
## the original's mechanics (ADR-0007, ADR-0023). Without a scene: [FloorLighting] remembers
## lamps and darkness, and nothing else.


## Floor 1 with two lamps — at 5 and 15 metres: the zone boundary at ten.
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
	assert_true(lighting.darken(1, 5.0), "the zone went dark for the first time")
	assert_true(lighting.is_dark_at(1, 5.0), "it is dark under the shot-out lamp")
	assert_true(lighting.is_dark_at(1, 8.0), "and across its whole zone")


func test_the_neighbouring_zone_stays_lit() -> void:
	var lighting := _two_lamps()
	lighting.darken(1, 5.0)
	assert_false(lighting.is_dark_at(1, 15.0), "the neighbouring lamp is lit")
	assert_false(lighting.is_dark_at(1, 12.0), "and its zone too")
	assert_false(lighting.is_dark(1), "the floor as a whole is not dark")


func test_the_zone_border_lies_halfway_between_lamps() -> void:
	var lighting := _two_lamps()
	lighting.darken(1, 5.0)
	assert_true(lighting.is_dark_at(1, 9.9), "a bit left of the middle — the left one's zone")
	assert_false(lighting.is_dark_at(1, 10.1), "a bit right — the right one's zone")
	assert_almost_eq(lighting.zone_of(1, 9.9), 5.0, 0.001)
	assert_almost_eq(lighting.zone_of(1, 10.1), 15.0, 0.001)


func test_the_floor_is_dark_once_every_zone_is() -> void:
	var lighting := _two_lamps()
	lighting.darken(1, 5.0)
	lighting.darken(1, 15.0)
	assert_true(lighting.is_dark(1), "both lamps shot out — the floor is dark")
	assert_true(lighting.is_dark_at(1, 5.0) and lighting.is_dark_at(1, 15.0))


func test_neighbouring_floors_stay_lit() -> void:
	var lighting := _two_lamps()
	lighting.darken(1, 5.0)
	assert_false(
		lighting.is_dark_at(2, 10.0), "only its own zone goes dark, not the whole building"
	)
	assert_false(lighting.is_dark(2))


func test_a_second_shot_at_the_same_zone_changes_nothing() -> void:
	var lighting := _two_lamps()
	lighting.darken(1, 5.0)
	assert_false(lighting.darken(1, 6.0), "no point in darkening what is dark")
	assert_false(lighting.is_dark_at(1, 15.0), "and it does not darken the neighbour")


func test_a_floor_without_lamps_never_goes_dark() -> void:
	# Roof: no lamps, the city lights it.
	var lighting := _two_lamps()
	assert_false(lighting.darken(BuildingRules.ROOF, 0.0), "nothing to darken")
	assert_false(lighting.is_dark_at(BuildingRules.ROOF, 0.0))
	assert_false(lighting.is_dark(BuildingRules.ROOF))
	assert_true(is_nan(lighting.zone_of(BuildingRules.ROOF, 0.0)))


func test_lamps_hang_in_any_order() -> void:
	# The layout hands out lamps as it laid them; the zone is computed by position, not order.
	var lighting := FloorLighting.new()
	lighting.hang(0, 30.0)
	lighting.hang(0, 10.0)
	lighting.hang(0, 20.0)
	lighting.darken(0, 20.0)
	assert_true(lighting.is_dark_at(0, 21.0))
	assert_false(lighting.is_dark_at(0, 11.0))
	assert_false(lighting.is_dark_at(0, 29.0))


## A dark floor on the map is dark at any point from the start of the building, and there is nothing
## to darken on it (ADR-0028, decision 4). The neighbouring floor without lamps — the roof — is lit.
func test_an_unlit_floor_is_dark_everywhere() -> void:
	var lighting := FloorLighting.new()
	lighting.mark_unlit(3)
	for x: float in [0.0, 7.5, 30.0]:
		assert_true(lighting.is_dark_at(3, x), "a dark floor is dark at x=%.1f" % x)
	assert_true(lighting.is_dark(3), "and dark as a whole")
	assert_false(lighting.darken(3, 1.0), "nothing to darken on it")
	assert_false(lighting.is_dark_at(BuildingRules.ROOF, 1.0), "the roof without lamps is light")
