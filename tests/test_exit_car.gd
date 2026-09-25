extends GutTest

## Тесты машины у выхода. С M21 это модели Cars Pack и жребий по зданию
## (ADR-0032, решение 7); где машина встаёт у выхода на любом сиде, проверяет
## [code]test_building_scenery[/code].
##
## В оригинале здание заканчивается тем, что Otto уезжает на красной машине
## (ADR-0011, пункт 14). Отсюда правило, которое легко потерять при правках:
## здание считается сданным **после** отъезда, а не в момент выхода. Иначе
## следующее здание соберётся поверх уезжающей машины, и кадра не будет.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

## Сколько кадров дать зданию собраться и сколько ждать отъезда. Машина с M24b
## трогается с места и разгоняется, а не уходит сразу на полном ходу: из кадра
## она уезжает за полторы-две секунды, запас — вдвое.
const SETTLE_FRAMES: int = 5
const PATIENCE: int = 480
## Сколько шагов физики ждать, пока Otto сядет и машина тронется: шаг к двери,
## посадка с дверцей ([constant ExitBoarding.GET_IN_TIME], 0.85 с), полсекунды
## в машине ([constant ExitBoarding.SEAT_TIME]) и две секунды стартера
## ([constant ExitBoarding.START_TIME]) — около 200 шагов, остальное запас.
const BOARDING_PATIENCE: int = 300

## Допуск на положение машины, м: полсантиметра. Машина стоит колёсами ровно на
## полу и ровно в зазоре от проёма; широкий допуск пропускал бы и машину,
## утонувшую в перекрытии по крышу.
const TOLERANCE: float = 0.005


func before_each() -> void:
	GameState.instance().start_game()


func after_each() -> void:
	GameState.instance().start_game()


func _building(documents: int = 0) -> GreyboxLevel:
	var rules := BuildingRules.new()
	rules.floors = 4
	# Без красных дверей здание сдано сразу, как только Otto дошёл до выхода:
	# документы здесь не проверяются, проверяется машина.
	rules.documents_cap = documents

	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = rules
	level.building_seed = 1
	level.spawn_agents = false
	add_child_autofree(level)
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	return level


## Машина у выхода — модель под своим именем среди детей уровня.
func _car_of(level: GreyboxLevel) -> Node3D:
	return level.get_node_or_null("ExitCar") as Node3D


func test_the_exit_has_a_car() -> void:
	var level := await _building()
	var car := _car_of(level)
	assert_not_null(car, "у выхода стоит машина")
	if car == null:
		return

	# Числа берутся у здания, а не выписываются в тест. Машина стоит в сцене, а
	# выход задан в плоскости правил — сравниваем в плоскости правил.
	var exit_x := level.plan().exit_x
	var surface := level.rules.floor_surface(level.rules.floors - 1)
	var at := WorldSpace.to_plane(car.global_position)
	assert_almost_eq(at.y, surface, TOLERANCE, "колёсами на полу")

	# Место — у ворот в левом торце, капотом к ним (ADR-0038, решение 3).
	var expected := ExitCar.spot(exit_x, level.rules, level.plan())
	assert_almost_eq(at.x, expected, TOLERANCE, "машина стоит на своём месте")
	var parked := ExitCar.parked_span(level.rules)
	assert_almost_eq(at.x, (parked.x + parked.y) * 0.5, TOLERANCE, "машина у ворот")
	assert_eq((car as ExitCar).towards, -1.0, "капотом к воротам")

	# Выход — водительская дверь: туда идёт бот и там Otto садится
	# (ADR-0038, решение 4).
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
	# Ждём не выдержку, а состояние: посадку уровень замечает на своём шаге
	# физики, и ждать «один кадр» здесь — та же ошибка, что водить съёмку
	# секундомером (docs/testing.md).
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


## Ставит Otto на пол подвала у водительской двери.
func _stand_at_the_door(level: GreyboxLevel) -> void:
	var door := level.exit_position()
	var feet := Vector2(door.x, door.y + GreyboxLevel.EXIT_HEIGHT * 0.5)
	level.otto.global_position = WorldSpace.to_scene(feet)


## Ждёт, пока машина тронется; true — тронулась.
func _wait_for_the_start(level: GreyboxLevel) -> bool:
	var car := _car_of(level) as ExitCar
	for _frame: int in BOARDING_PATIENCE:
		if car.is_leaving():
			return true
		await get_tree().physics_frame
	return car.is_leaving()


## Без всех документов у двери ничего не происходит: машина не ждёт, Otto свой.
## Попасть в подвал без документов нельзя вовсе ([BasementLock]), но правило
## выхода от этого не зависит — Otto здесь ставит тест.
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


## Севший Otto заперт и недосягаем: ввода нет, тела нет, агентам его не видно.
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
	# Формы тела выключаются отложенно — к отъезду машины они давно выключены.
	var standing := otto.get_node("StandingShape") as CollisionShape3D
	var crouching := otto.get_node("CrouchingShape") as CollisionShape3D
	assert_true(standing.disabled and crouching.disabled, "пуле попасть не во что")
	var door := level.exit_position()
	assert_almost_eq(
		WorldSpace.to_plane(otto.global_position).x, door.x, 0.01, "сел у водительской двери"
	)


## Машина уезжает в свою сторону и разгоняется, с зажжёнными фарами.
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


## Ворота паркинга открываются, когда Otto садится: машина уезжает в них.
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


## Габарит машины по всем её мешам, в системе самой машины.
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


## Любая машина жребия стоит между задней стеной и телом Otto: в стену не входит
## и в плоскость игры не выходит, поэтому Otto проходит перед машиной, а не
## сквозь неё. Седан в полтора метра шириной заходил в обе стороны (авторевью
## M18c и M20), а машины пака в 1.8 м — тем более, пока их не сжали.
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
		# По длине машина ставится в зазор у выхода: длиннее — и заденет проём.
		assert_almost_eq(box.size.x, CarModel.LENGTH, 0.02, "%s: длина по бамперам" % label)
		assert_almost_eq(box.position.y, 0.0, 0.02, "%s: колёса на земле" % label)
		assert_lt(box.size.y, Proportions.BODY, "%s ниже Otto" % label)
		assert_gt(CarModel.wheels(car).size(), 0, "%s: колёса крутятся" % label)


## Колёса на отъезде крутятся вокруг своих осей и катятся вперёд: середина колеса
## стоит на месте, а низ уходит назад по ходу. Начало узла колеса у пака — в нуле
## машины, и поворот вокруг него носил колёса кругом по кузову (авторевью M21).
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


## Первое здание — красная спортивная, как в 1983 году (ADR-0032, решение 7).
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


## Кузов перекрашен краской жребия: материал `Paint` пака подменён.
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


## Посадку видно (ADR-0038, решение 4): Otto поворачивается к машине, дверца
## распахивается, он шагает в глубину к борту и скрывается, дверца захлопывается.
## Раньше он пропадал перед кузовом, шагнув к двери.
func test_otto_gets_in_through_the_open_driver_door() -> void:
	var level := await _building()
	var car := _car_of(level) as ExitCar
	var boarding := level.get(&"_boarding") as ExitBoarding
	assert_eq(car.door_openness(), 0.0, "у стоящей машины дверца закрыта")
	var hinge := car.get_node("DoorHinge") as Node3D
	assert_false(hinge.visible, "закрытую дверцу рисует сама модель")
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
	assert_false(hinge.visible)


## С посадки кадр раздвигается влево за торец: ворота, площадка и тоннель в
## кадре. Машина трогается — кадр едет за ней вверх по пандусу до улицы, и
## уходит она из кадра уже по улице, а не с середины подъёма.
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
	assert_lt(last.end.y, bottom - rules.floor_height * 0.9, "и поднялся вместе с ней")
	assert_gt(car.position.y, floor_y + rules.floor_height * 0.99, "уходит по улице")
