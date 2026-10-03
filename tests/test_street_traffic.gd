extends GutTest

## Traffic on the street at the exit (ADR-0044, decisions 1 and 2).
##
## Traffic rules — without the building scene: a street of one roadway, traffic on it and
## steps the test makes itself ([method StreetTraffic.step]). Seeds differ:
## each building has its own draw of gaps and speeds, and any one is checked.

const SEEDS: Array[int] = [1, 2, 3, 5, 8]
const LEFT: float = 0.0
const STREET: float = 0.0
## Traffic step in the test, s, and how many steps to run.
const STEP: float = 1.0 / 30.0
const STEPS: int = 1800


func _traffic(building_seed: int) -> StreetTraffic:
	var traffic := StreetTraffic.new()
	add_child_autofree(traffic)
	traffic.build(LEFT, STREET, building_seed)
	return traffic


## Bumper to bumper along the way: how much between a car and the one in front, m.
func _gaps(traffic: StreetTraffic, near: bool) -> Array[float]:
	var gaps: Array[float] = []
	var cars := traffic.cars(near)
	for index: int in range(1, cars.size()):
		gaps.append(absf(cars[index - 1].x - cars[index].x) - CarModel.LENGTH)
	return gaps


func test_both_lanes_carry_cars_from_the_first_frame() -> void:
	for building_seed: int in SEEDS:
		var traffic := _traffic(building_seed)
		assert_gt(
			traffic.cars(true).size(), 0, "seed %d: the near lane is not empty" % building_seed
		)
		assert_gt(
			traffic.cars(false).size(), 0, "seed %d: the far one is not empty" % building_seed
		)


func test_cars_never_run_into_each_other() -> void:
	for building_seed: int in SEEDS:
		var traffic := _traffic(building_seed)
		var worst := INF
		for _step: int in STEPS:
			traffic.step(STEP)
			for near: bool in [true, false]:
				for gap: float in _gaps(traffic, near):
					worst = minf(worst, gap)
		assert_gte(
			worst,
			StreetTraffic.MIN_GAP - 0.2,
			"seed %d: cars do not run into each other" % building_seed
		)


func test_the_street_keeps_moving() -> void:
	var traffic := _traffic(2)
	var first := traffic.cars(true)[0]
	var before := first.x
	for _step: int in 60:
		traffic.step(STEP)
	assert_lt(first.x, before, "the near lane goes left")
	var far := traffic.cars(false)[0]
	before = far.x
	for _step: int in 60:
		traffic.step(STEP)
	assert_gt(far.x, before, "the far one — right")
	for _step: int in STEPS:
		traffic.step(STEP)
	assert_gt(traffic.cars(true).size(), 0, "new ones replace those that left")


## A car behind Otto's merged car keeps its distance: it does not pass through.
func test_cars_behind_otto_s_car_keep_their_distance() -> void:
	for building_seed: int in SEEDS:
		var traffic := _traffic(building_seed)
		var guest := Node3D.new()
		add_child_autofree(guest)
		var x := LEFT - ExitStreet.FROM * 0.4
		guest.position.x = x
		traffic.hold_back(true)
		for _step: int in STEPS:
			traffic.step(STEP)
			if traffic.is_clear_for(x):
				break
		traffic.hold_back(false)
		assert_true(traffic.is_clear_for(x), "seed %d: the gap came" % building_seed)
		traffic.join(guest)
		# Otto starts slower than the traffic: those coming up from behind must brake.
		var worst := INF
		for _step: int in STEPS / 3:
			guest.position.x -= 3.0 * STEP
			traffic.step(STEP)
			for car: StreetTraffic.Car in traffic.cars(true):
				if car.x > guest.position.x:
					worst = minf(worst, car.x - guest.position.x - CarModel.LENGTH)
		assert_gte(
			worst,
			StreetTraffic.MIN_GAP - 0.2,
			"seed %d: nobody ran into the one behind" % building_seed
		)


func test_a_car_close_behind_closes_the_gap() -> void:
	var traffic := _traffic(1)
	var car := traffic.cars(true)[traffic.cars(true).size() - 1]
	assert_false(traffic.is_clear_for(car.x - CarModel.LENGTH - 3.0), "a car three metres behind")


## The traffic situation is a building draw (ADR-0046, decision 3): on different seeds
## all three come up, and in dense traffic the gaps are narrower, and the wait longer than in light.
func test_the_road_situation_is_a_draw_of_the_building() -> void:
	var seen: Dictionary = {}
	for building_seed: int in 60:
		var density := StreetTraffic.density_for(building_seed)
		seen[density] = true
		var traffic := _traffic(building_seed)
		assert_eq(
			traffic.density, density, "seed %d: the situation — by the first draw" % building_seed
		)
	assert_eq(seen.size(), StreetTraffic.Density.size(), "all situations come up")
	var light := StreetTraffic.GAPS[StreetTraffic.Density.LIGHT]
	var heavy := StreetTraffic.GAPS[StreetTraffic.Density.HEAVY]
	assert_gt(light.x, heavy.y, "in the free one the gap is wider than any in the dense one")
	assert_lt(
		StreetTraffic.WAIT_LIMITS[StreetTraffic.Density.LIGHT],
		StreetTraffic.WAIT_LIMITS[StreetTraffic.Density.HEAVY],
		"in the dense one the wait is longer"
	)


## Traffic cars differ: each has a draw of model and paint.
func test_traffic_cars_are_a_mix_of_models() -> void:
	var models: Dictionary = {}
	for building_seed: int in SEEDS:
		var traffic := _traffic(building_seed)
		for near: bool in [true, false]:
			for car: StreetTraffic.Car in traffic.cars(near):
				models[car.node.get_child(0).scene_file_path] = true
	assert_gt(models.size(), 2, "more than two models in the flow")
