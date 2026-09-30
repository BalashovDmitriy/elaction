extends GutTest

## Поток машин по улице у выезда (ADR-0044, решения 1 и 2).
##
## Правила потока — без сцены здания: улица из одной мостовой, поток на ней и
## шаги, которые тест делает сам ([method StreetTraffic.step]). Сиды разные:
## жребий просветов и скоростей свой у каждого здания, и проверяется любой.

const SEEDS: Array[int] = [1, 2, 3, 5, 8]
const LEFT: float = 0.0
const STREET: float = 0.0
## Шаг потока в тесте, с, и сколько шагов гнать.
const STEP: float = 1.0 / 30.0
const STEPS: int = 1800


func _traffic(building_seed: int) -> StreetTraffic:
	var traffic := StreetTraffic.new()
	add_child_autofree(traffic)
	traffic.build(LEFT, STREET, building_seed)
	return traffic


## Бампер к бамперу по ходу: сколько между машиной и передней, м.
func _gaps(traffic: StreetTraffic, near: bool) -> Array[float]:
	var gaps: Array[float] = []
	var cars := traffic.cars(near)
	for index: int in range(1, cars.size()):
		gaps.append(absf(cars[index - 1].x - cars[index].x) - CarModel.LENGTH)
	return gaps


func test_both_lanes_carry_cars_from_the_first_frame() -> void:
	for building_seed: int in SEEDS:
		var traffic := _traffic(building_seed)
		assert_gt(traffic.cars(true).size(), 0, "сид %d: ближняя полоса не пустая" % building_seed)
		assert_gt(traffic.cars(false).size(), 0, "сид %d: дальняя не пустая" % building_seed)


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
			"сид %d: машины не наезжают друг на друга" % building_seed
		)


func test_the_street_keeps_moving() -> void:
	var traffic := _traffic(2)
	var first := traffic.cars(true)[0]
	var before := first.x
	for _step: int in 60:
		traffic.step(STEP)
	assert_lt(first.x, before, "ближняя полоса идёт влево")
	var far := traffic.cars(false)[0]
	before = far.x
	for _step: int in 60:
		traffic.step(STEP)
	assert_gt(far.x, before, "дальняя — вправо")
	for _step: int in STEPS:
		traffic.step(STEP)
	assert_gt(traffic.cars(true).size(), 0, "уехавших сменяют новые")


## Машина за влившейся машиной Otto держит дистанцию: не проходит насквозь.
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
		assert_true(traffic.is_clear_for(x), "сид %d: просвет наступил" % building_seed)
		traffic.join(guest)
		# Otto трогается медленнее потока: подъезжающим сзади — тормозить.
		var worst := INF
		for _step: int in STEPS / 3:
			guest.position.x -= 3.0 * STEP
			traffic.step(STEP)
			for car: StreetTraffic.Car in traffic.cars(true):
				if car.x > guest.position.x:
					worst = minf(worst, car.x - guest.position.x - CarModel.LENGTH)
		assert_gte(worst, StreetTraffic.MIN_GAP - 0.2, "сид %d: сзади не наехали" % building_seed)


func test_a_car_close_behind_closes_the_gap() -> void:
	var traffic := _traffic(1)
	var car := traffic.cars(true)[traffic.cars(true).size() - 1]
	assert_false(traffic.is_clear_for(car.x - CarModel.LENGTH - 3.0), "машина в трёх метрах сзади")


## Дорожная ситуация — жребий здания (ADR-0046, решение 3): на разных сидах
## выпадают все три, и в плотной просветы уже, а ждать дольше, чем в свободной.
func test_the_road_situation_is_a_draw_of_the_building() -> void:
	var seen: Dictionary = {}
	for building_seed: int in 60:
		var density := StreetTraffic.density_for(building_seed)
		seen[density] = true
		var traffic := _traffic(building_seed)
		assert_eq(traffic.density, density, "сид %d: ситуация — первым жребием" % building_seed)
	assert_eq(seen.size(), StreetTraffic.Density.size(), "выпадают все ситуации")
	var light := StreetTraffic.GAPS[StreetTraffic.Density.LIGHT]
	var heavy := StreetTraffic.GAPS[StreetTraffic.Density.HEAVY]
	assert_gt(light.x, heavy.y, "в свободной просвет шире, чем в плотной любой")
	assert_lt(
		StreetTraffic.WAIT_LIMITS[StreetTraffic.Density.LIGHT],
		StreetTraffic.WAIT_LIMITS[StreetTraffic.Density.HEAVY],
		"в плотной ждать дольше"
	)


## Машины потока — разные: жребий модели и краски у каждой.
func test_traffic_cars_are_a_mix_of_models() -> void:
	var models: Dictionary = {}
	for building_seed: int in SEEDS:
		var traffic := _traffic(building_seed)
		for near: bool in [true, false]:
			for car: StreetTraffic.Car in traffic.cars(near):
				models[car.node.get_child(0).scene_file_path] = true
	assert_gt(models.size(), 2, "в потоке больше двух моделей")
