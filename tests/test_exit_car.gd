extends GutTest

## Tests of the car at the exit. Since M21 these are Cars Pack models and a per-building draw
## (ADR-0032, decision 7); where the car stands at the exit on any seed is checked by
## [code]test_building_scenery[/code].
##
## In the original a building ends with Otto driving away in a red car (ADR-0011, item 14). Hence a
## rule that is easy to lose during edits: the building counts as cleared **after** the departure,
## not at the moment of exit. Otherwise the next building would be assembled on top of the departing
## car, and there would be no shot.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

## How many frames to give the building to assemble and how long to wait for the departure. Since
## M24b the car pulls away and accelerates rather than leaving at full speed at once; since M24g the
## view overtakes it so that the road under the headlights is visible (ADR-0043, decision 18), and
## it leaves the frame in about six seconds. Since M24h it also stops at the edge of the roadway and
## waits for a gap in traffic — up to [method StreetTraffic.wait_limit] and somewhat more while the
## gap arrives (ADR-0044, decision 2): a margin of fifteen seconds.
const SETTLE_FRAMES: int = 5
const PATIENCE: int = 1800
## How many physics steps to wait until Otto gets in and the car pulls away: a step to the door,
## getting in with the door ([constant ExitBoarding.GET_IN_TIME], 0.85 s), half a second in the car
## ([constant ExitBoarding.SEAT_TIME]) and two seconds of the starter ([constant
## ExitBoarding.START_TIME]) — about 200 steps, the rest is margin.
const BOARDING_PATIENCE: int = 300

## Tolerance on the car position, m: half a centimetre. The car stands with its wheels exactly on
## the floor and exactly at the gap from the opening; a wide tolerance would also let through a car
## sunk into the slab up to its roof.
const TOLERANCE: float = 0.005


func before_each() -> void:
	GameState.instance().start_game()


func after_each() -> void:
	GameState.instance().start_game()


func _building(documents: int = 0) -> GreyboxLevel:
	var rules := BuildingRules.new()
	rules.floors = 4
	# Without red doors the building is cleared as soon as Otto reaches the exit: documents are not
	# checked here, the car is.
	rules.documents_cap = documents

	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = rules
	level.building_seed = 1
	level.spawn_agents = false
	add_child_autofree(level)
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	return level


## The car at the exit is a model under its own name among the level's children.
func _car_of(level: GreyboxLevel) -> Node3D:
	return level.get_node_or_null("ExitCar") as Node3D


func test_the_exit_has_a_car() -> void:
	var level := await _building()
	var car := _car_of(level)
	assert_not_null(car, "у выхода стоит машина")
	if car == null:
		return

	# Numbers are taken from the building, not written into the test. The car stands in the scene, and
	# the exit is set in the rules plane — we compare in the rules plane.
	var exit_x := level.plan().exit_x
	var surface := level.rules.floor_surface(level.rules.floors - 1)
	var at := WorldSpace.to_plane(car.global_position)
	assert_almost_eq(at.y, surface, TOLERANCE, "колёсами на полу")

	# Its place is at the gate in the left end wall, bonnet toward it (ADR-0038, decision 3).
	var expected := ExitCar.spot(exit_x, level.rules, level.plan())
	assert_almost_eq(at.x, expected, TOLERANCE, "машина стоит на своём месте")
	var parked := ExitCar.parked_span(level.rules)
	assert_almost_eq(at.x, (parked.x + parked.y) * 0.5, TOLERANCE, "машина у ворот")
	assert_eq((car as ExitCar).towards, -1.0, "капотом к воротам")

	# The exit is the driver's door: the bot goes there and Otto gets in there (ADR-0038, decision 4).
	var door := level.exit_position()
	assert_almost_eq(door.x, (car as ExitCar).door_x(), TOLERANCE, "выход — у двери машины")
	assert_almost_eq(door.y + GreyboxLevel.EXIT_HEIGHT * 0.5, surface, TOLERANCE)
	assert_between(door.x, parked.x, parked.y, "дверь — в длине машины")


func test_the_building_is_cleared_only_after_the_car_leaves() -> void:
	var level := await _building()
	var car := _car_of(level)
	assert_not_null(car)
	if car == null:
		return

	var cleared := [false]
	level.building_cleared.connect(func() -> void: cleared[0] = true)

	var parked_at := car.position.x
	_stand_at_the_door(level)
	# We wait for a state, not a delay: the level notices boarding on its own physics step, and waiting
	# "one frame" here is the same mistake as driving a shot with a stopwatch (docs/testing.md).
	var started := 0
	while is_equal_approx(car.position.x, parked_at) and started < BOARDING_PATIENCE:
		await get_tree().physics_frame
		started += 1

	assert_ne(car.position.x, parked_at, "машина поехала")
	assert_false(cleared[0], "выход ещё не конец: машина только тронулась")

	var waited := 0
	while not cleared[0] and waited < PATIENCE:
		await get_tree().process_frame
		waited += 1
	assert_true(cleared[0], "здание сдано, когда машина уехала")


## The lane is busy — the car stops at the edge of the roadway, waits for a gap with the right
## indicator on and merges into the near lane (ADR-0044, decisions 1–2; ADR-0046, decisions 2–3).
## The test keeps it busy: the nearest car of the traffic stays right behind the merge point until
## Otto's car has stopped.
func test_a_busy_lane_makes_the_car_wait_with_the_indicator_on() -> void:
	var level := await _building()
	var car := _car_of(level) as ExitCar
	if car == null or car.traffic == null:
		fail_test("у выезда нет потока")
		return
	_stand_at_the_door(level)
	var lane := car.traffic.cars(true)
	var blocker: StreetTraffic.Car = lane[lane.size() - 1]
	var stages: Dictionary = {}
	var waited := 0
	var lit := false
	var dark_while_signalling := false
	while car.stage != ExitCar.Stage.CRUISE and waited < PATIENCE:
		if car.stage == ExitCar.Stage.CLIMB and car.is_leaving():
			_hold_behind(blocker, car.stop_x())
		await get_tree().physics_frame
		stages[car.stage] = true
		if car.is_signalling():
			lit = lit or car.indicator_lit()
			dark_while_signalling = dark_while_signalling or not car.indicator_lit()
		if car.stage == ExitCar.Stage.WAIT:
			assert_almost_eq(car.position.x, car.stop_x(), 0.05, "ждёт у края мостовой")
		waited += 1
	assert_true(stages.has(ExitCar.Stage.WAIT), "полоса занята — машина вставала у края мостовой")
	assert_eq(car.stage, ExitCar.Stage.CRUISE, "влилась в поток")
	assert_almost_eq(car.position.z, car.traffic.near_lane_z(), 0.01, "в ближней полосе")
	assert_true(lit and dark_while_signalling, "поворотник мигал, пока машина ждала")
	await get_tree().physics_frame
	assert_false(car.is_signalling(), "в полосе поворотник выключен")
	assert_false(car.indicator_lit())


## The lane is free — the car does not stop at the edge of the roadway but pulls out on the move,
## with the indicator on (ADR-0046, decision 3). The test keeps it free: the near lane is empty, and
## entry onto it is held back.
func test_a_clear_lane_lets_the_car_merge_without_stopping() -> void:
	var level := await _building()
	var car := _car_of(level) as ExitCar
	if car == null or car.traffic == null:
		fail_test("у выезда нет потока")
		return
	car.traffic.hold_back(true)
	for other: StreetTraffic.Car in car.traffic.cars(true):
		other.x = -1000.0
		other.node.position.x = other.x
	_stand_at_the_door(level)
	var stages: Dictionary = {}
	var slowest := INF
	var signalled := false
	var waited := 0
	while car.stage != ExitCar.Stage.CRUISE and waited < PATIENCE:
		car.traffic.hold_back(true)
		await get_tree().physics_frame
		stages[car.stage] = true
		signalled = signalled or car.is_signalling()
		if car.is_leaving() and absf(car.position.x - car.stop_x()) < 0.5:
			slowest = minf(slowest, car.speed_now())
		waited += 1
	assert_false(stages.has(ExitCar.Stage.WAIT), "не вставала у края мостовой")
	assert_gt(slowest, 1.0, "у края мостовой не останавливалась, м/с")
	assert_eq(car.stage, ExitCar.Stage.CRUISE, "влилась в поток")
	assert_true(signalled, "поворотник мигал на съезде")


## Holds the traffic car [param blocker] right behind the merge point [param x]: behind, five metres
## bumper to bumper, standing.
func _hold_behind(blocker: StreetTraffic.Car, x: float) -> void:
	if not is_instance_valid(blocker.node):
		return
	blocker.x = x + CarModel.LENGTH + 5.0
	blocker.speed = 0.0
	blocker.node.position.x = blocker.x


## Puts Otto on the basement floor at the driver's door.
func _stand_at_the_door(level: GreyboxLevel) -> void:
	var door := level.exit_position()
	var feet := Vector2(door.x, door.y + GreyboxLevel.EXIT_HEIGHT * 0.5)
	level.otto.global_position = WorldSpace.to_scene(feet)


## Waits until the car pulls away; true — it pulled away.
func _wait_for_the_start(level: GreyboxLevel) -> bool:
	var car := _car_of(level) as ExitCar
	for _frame: int in BOARDING_PATIENCE:
		if car.is_leaving():
			return true
		await get_tree().physics_frame
	return car.is_leaving()


## Without all documents nothing happens at the door: the car does not wait, Otto is in control.
## Getting into the basement without documents is impossible anyway ([BasementLock]), but the exit
## rule does not depend on that — here the test places Otto.
func test_the_car_does_not_take_otto_without_every_document() -> void:
	var level := await _building(1)
	assert_false(GameState.instance().all_documents_collected(), "документ ещё за дверью")
	_stand_at_the_door(level)
	for _frame: int in BOARDING_PATIENCE:
		await get_tree().physics_frame
	var car := _car_of(level) as ExitCar
	assert_false(car.is_leaving(), "машина стоит")
	assert_true(level.otto.is_on_foot(), "Otto свой — управление не забрали")
	assert_false(level.otto.is_hidden())


## An Otto who got in is locked and unreachable: no input, no body, agents cannot see him.
func test_the_seated_otto_is_locked_and_out_of_reach() -> void:
	var level := await _building()
	var started := [false]
	level.car_started.connect(func() -> void: started[0] = true)
	_stand_at_the_door(level)
	assert_true(await _wait_for_the_start(level), "Otto сел, машина тронулась")
	assert_true(started[0], "уровень сказал, что машина тронулась")

	var otto := level.otto
	assert_true(otto.is_hidden(), "Otto в машине: снаружи его нет")
	assert_false(otto.is_on_foot(), "управление забрано")
	assert_eq(otto.vertical_intent(), 0.0, "ввод не доходит")
	# Body shapes are disabled deferred — by the car's departure they have long been disabled.
	var standing := otto.get_node("StandingShape") as CollisionShape3D
	var crouching := otto.get_node("CrouchingShape") as CollisionShape3D
	assert_true(standing.disabled and crouching.disabled, "пуле попасть не во что")
	var door := level.exit_position()
	assert_almost_eq(
		WorldSpace.to_plane(otto.global_position).x, door.x, 0.01, "сел у водительской двери"
	)


## The car drives off in its own direction and accelerates, with headlights on.
func test_the_car_leaves_accelerating_with_its_lights_on() -> void:
	var level := await _building()
	var car := _car_of(level) as ExitCar
	assert_false(car.lights_on(), "заглушённая машина стоит без фар")
	_stand_at_the_door(level)
	assert_true(await _wait_for_the_start(level))
	assert_true(car.lights_on(), "фары горят")

	var before := car.position.x
	await get_tree().physics_frame
	var first := (car.position.x - before) * car.towards
	for _frame: int in 20:
		await get_tree().physics_frame
	before = car.position.x
	await get_tree().physics_frame
	var later := (car.position.x - before) * car.towards
	assert_gt(first, 0.0, "едет туда, куда смотрит капот")
	assert_gt(later, first, "разгоняется")


## The garage gate opens when Otto gets in: the car drives out through it.
func test_the_garage_gate_opens_for_the_car() -> void:
	var level := await _building()
	var garage := level.garage()
	assert_not_null(garage, "паркинг построен")
	if garage == null:
		return
	assert_false(garage.is_gate_open(), "до посадки ворота закрыты")
	_stand_at_the_door(level)
	assert_true(await _wait_for_the_start(level))
	assert_true(garage.is_gate_open(), "машина тронулась — ворота открыты")


## The car's bounds over all its meshes, in the car's own space.
func _car_box(car: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in car.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var to_car := car.global_transform.affine_inverse() * mesh.global_transform
		var part := to_car * mesh.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


## Any car of the draw stands between the back wall and Otto's body: it does not enter the wall and
## does not stick out into the play plane, so Otto walks in front of the car, not through it. A
## sedan one and a half metres wide went in both directions (M18c and M20 code review), and the
## pack's 1.8 m cars all the more, until they were narrowed.
func test_every_car_fits_between_the_wall_and_otto() -> void:
	for index in CarModel.MODELS.size():
		var choice := CarModel.Choice.new()
		choice.model = index
		var car: Node3D = CarModel.build(choice)
		add_child_autofree(car)
		var box := _car_box(car)
		var label := CarModel.MODELS[index].resource_path.get_file()
		assert_gt(ExitCar.Z + box.position.z, WorldSpace.BACK_WALL_Z, "%s входит в стену" % label)
		assert_lt(
			ExitCar.Z + box.end.z,
			WorldSpace.PLAY_Z - WorldSpace.BODY_DEPTH * 0.5,
			"%s выходит в плоскость игры — Otto пройдёт сквозь неё" % label
		)
		# Lengthwise the car is placed into the gap at the exit: any longer and it would hit the opening.
		assert_almost_eq(box.size.x, CarModel.LENGTH, 0.02, "%s: длина по бамперам" % label)
		assert_almost_eq(box.position.y, 0.0, 0.02, "%s: колёса на земле" % label)
		assert_lt(box.size.y, Proportions.BODY, "%s ниже Otto" % label)
		assert_gt(CarModel.wheels(car).size(), 0, "%s: колёса крутятся" % label)


## Wheels on departure spin around their own axles and roll forward: the middle of the wheel stays
## in place, and the bottom moves backward along the travel. The origin of a wheel node in the pack
## is at the car's zero, and rotating around it carried the wheels in a circle around the body (M21
## code review).
func test_the_wheels_roll_about_their_axles() -> void:
	var rules := BuildingRules.new()
	var plan := BuildingPlan.generate(rules, 1)
	var car := ExitCar.new()
	car.park(plan.exit_x, 0.0, rules, plan)
	add_child_autofree(car)
	var wheels := car.find_children("Wheel*", "MeshInstance3D", true, false)
	assert_gt(wheels.size(), 0, "у машины есть колёса")
	var hubs: Array[Vector3] = []
	var treads: Array[Vector3] = []
	for node in wheels:
		var wheel := node as MeshInstance3D
		var box := wheel.mesh.get_aabb()
		var hub := box.get_center()
		hubs.append(car.to_local(wheel.to_global(hub)))
		treads.append(car.to_local(wheel.to_global(hub - Vector3(0.0, box.size.y * 0.5, 0.0))))
	car.drive_away()
	car.advance(1.0 / 120.0, Rect2(-1000.0, -1000.0, 2000.0, 2000.0))
	for index in wheels.size():
		var wheel := wheels[index] as MeshInstance3D
		var box := wheel.mesh.get_aabb()
		var hub := box.get_center()
		var hub_now := car.to_local(wheel.to_global(hub))
		var tread_now := car.to_local(wheel.to_global(hub - Vector3(0.0, box.size.y * 0.5, 0.0)))
		assert_almost_eq(
			hub_now.distance_to(hubs[index]), 0.0, 0.001, "%s: ось на месте" % wheel.name
		)
		assert_lt(
			(tread_now.x - treads[index].x) * car.towards,
			-0.01,
			"%s: низ колеса уходит назад — колесо катится вперёд" % wheel.name
		)


## The first building is a red sports car, as in 1983 (ADR-0032, decision 7).
func test_the_first_building_parks_the_red_sports_car() -> void:
	for building_seed: int in [1, 7, 12345]:
		var choice := CarModel.choose(1, building_seed)
		assert_eq(choice.model, 0, "спортивная")
		assert_eq(choice.paint, 0, "красная")


func test_the_car_is_a_draw_of_the_building_and_stays_the_same() -> void:
	var seen := {}
	for building in range(2, 40):
		var choice := CarModel.choose(building, building * 31)
		var again := CarModel.choose(building, building * 31)
		assert_eq(choice.model, again.model, "жребий повторяется для того же здания")
		assert_eq(choice.paint, again.paint)
		assert_between(choice.model, 0, CarModel.MODELS.size() - 1)
		assert_between(choice.paint, 0, CarModel.PAINTS.size() - 1)
		seen[choice.model] = true
	assert_gt(seen.size(), 2, "в зданиях стоят разные машины")


## The body is repainted in the draw's paint: the pack's `Paint` material is replaced.
func test_the_body_takes_the_drawn_paint() -> void:
	var choice := CarModel.Choice.new()
	choice.model = 2
	choice.paint = 1
	var car: Node3D = CarModel.build(choice)
	add_child_autofree(car)
	var painted := false
	for node in car.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var override := mesh.get_surface_override_material(surface) as StandardMaterial3D
			if override != null and override.albedo_color.is_equal_approx(CarModel.PAINTS[1]):
				painted = true
	assert_true(painted, "кузов в краске жребия")


## Every car of the draw has a driver's door opening with a hinged door, an interior, a dome light
## under the roof and indicators (ADR-0046, decision 1): boarding works in any of them, not only in
## the red one of the first building. The door is on the side facing the camera, within the car's
## length, and the interior is inside the body, not under or above it.
func test_every_car_has_a_door_a_cabin_and_indicators() -> void:
	for index: int in CarModel.MODELS.size():
		var choice := CarModel.Choice.new()
		choice.model = index
		var car: Node3D = CarModel.build(choice)
		add_child_autofree(car)
		var door := car.find_child("DriverDoor", true, false) as MeshInstance3D
		var cabin := car.find_child("CarInterior", true, false) as MeshInstance3D
		assert_not_null(door, "модель %d: дверь" % index)
		assert_not_null(cabin, "модель %d: салон" % index)
		assert_not_null(car.find_child("DomeLight", true, false), "модель %d: плафон" % index)
		assert_not_null(
			car.find_child("IndicatorRight", true, false), "модель %d: поворотник" % index
		)
		if door == null or cabin == null:
			continue
		var span := door.mesh.get_aabb()
		var front := door.position.x
		assert_lt(door.position.z, 0.0, "модель %d: дверь у борта -Z — к камере у ворот" % index)
		assert_between(span.size.x, 0.6, 1.4, "модель %d: длина двери, м" % index)
		assert_between(
			front, 0.0, CarModel.LENGTH * 0.5, "модель %d: петля перед серединой" % index
		)
		var inside := cabin.mesh.get_aabb()
		assert_gt(inside.position.y, 0.1, "модель %d: салон не под днищем" % index)
		assert_lt(inside.end.y, 1.4, "модель %d: салон не над крышей" % index)


## Boarding is visible (ADR-0038, decision 4): Otto turns to the car, the door swings open, he steps
## deeper toward the side and disappears, the door slams shut. Before, he vanished in front of the
## body after stepping to the door.
func test_otto_gets_in_through_the_open_driver_door() -> void:
	var level := await _building()
	var car := _car_of(level) as ExitCar
	var boarding := level.get(&"_boarding") as ExitBoarding
	assert_eq(car.door_openness(), 0.0, "у стоящей машины дверца закрыта")
	var door := car.find_child("DriverDoor", true, false) as Node3D
	assert_not_null(door, "дверца — деталь модели, кузов под ней прорезан")
	assert_almost_eq(door.rotation.y, 0.0, 0.001, "закрытая дверца — вровень с кузовом")
	_stand_at_the_door(level)
	var widest := 0.0
	var deepest := WorldSpace.PLAY_Z
	var hidden_behind_door := false
	for _frame: int in BOARDING_PATIENCE:
		await get_tree().physics_frame
		if boarding.phase == ExitBoarding.Phase.GETTING_IN:
			widest = maxf(widest, car.door_openness())
			if not level.otto.is_hidden():
				deepest = minf(deepest, level.otto.global_position.z)
			elif car.door_openness() > 0.0:
				hidden_behind_door = true
		if car.is_leaving():
			break
	assert_gt(widest, 0.95, "дверца распахнулась")
	assert_lt(deepest, car.seat_z() + 0.05, "Otto шагнул в глубину к борту")
	assert_true(hidden_behind_door, "скрылся, пока дверца ещё открыта")
	assert_true(car.is_leaving(), "машина тронулась")
	assert_eq(car.door_openness(), 0.0, "дверца захлопнулась")
	assert_almost_eq(door.rotation.y, 0.0, 0.001)


## From boarding the view widens to the left past the end wall: gate, landing and tunnel are in the
## frame. The car pulls away — the view follows it up the ramp to the street, and it leaves the
## frame already along the street, not from the middle of the climb.
func test_the_car_drives_up_the_ramp_in_the_widened_frame() -> void:
	var level := await _building()
	var car := _car_of(level) as ExitCar
	var rules := level.rules
	var gate := rules.floor_span(rules.floors - 1).x
	var floor_y := car.position.y
	var cleared := [false]
	level.building_cleared.connect(func() -> void: cleared[0] = true)
	var before := level.otto.camera_view(true)
	assert_gte(before.position.x, 0.0, "до посадки кадр — в границах здания")
	_stand_at_the_door(level)
	assert_true(await _wait_for_the_start(level))
	var view := level.otto.camera_view(true)
	assert_lt(view.position.x, gate - GarageRamp.TUNNEL, "тоннель в кадре")
	assert_gt(view.end.x, car.position.x + ExitCar.LENGTH * 0.5, "и машина у ворот")
	var bottom := view.end.y
	var waited := 0
	var last := view
	while not cleared[0] and waited < PATIENCE:
		last = level.otto.camera_view(true)
		await get_tree().physics_frame
		waited += 1
	assert_true(cleared[0], "машина ушла из кадра")
	var top := gate - GarageGate.RAMP_APRON - GarageGate.RAMP_RUN
	assert_lt(last.position.x, top, "кадр доехал за машиной до улицы")
	# Under the car the view keeps the street strip: without it, it would rise by a floor.
	var rise := rules.floor_height - ExitBoarding.STREET_VIEW
	assert_lt(last.end.y, bottom - rise * 0.9, "и поднялся вместе с ней")
	assert_gt(car.position.y, floor_y + rules.floor_height * 0.99, "уходит по улице")
