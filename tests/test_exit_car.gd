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

## Сколько кадров дать зданию собраться и сколько ждать отъезда.
const SETTLE_FRAMES: int = 5
const PATIENCE: int = 240

## Допуск на положение машины, м: полсантиметра. Машина стоит колёсами ровно на
## полу и ровно в зазоре от проёма; широкий допуск пропускал бы и машину,
## утонувшую в перекрытии по крышу.
const TOLERANCE: float = 0.005


func before_each() -> void:
	GameState.instance().start_game()


func after_each() -> void:
	GameState.instance().start_game()


func _building() -> GreyboxLevel:
	var rules := BuildingRules.new()
	rules.floors = 4
	# Без красных дверей здание сдано сразу, как только Otto дошёл до выхода:
	# документы здесь не проверяются, проверяется машина.
	rules.documents_cap = 0

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
	var exit_at := level.exit_position()
	var surface := exit_at.y + GreyboxLevel.EXIT_HEIGHT * 0.5
	var at := WorldSpace.to_plane(car.global_position)
	assert_almost_eq(at.y, surface, TOLERANCE, "колёсами на полу")

	# Место — у ворот в левом торце, капотом к ним (ADR-0038, решение 3); выход —
	# место Otto у водительской двери, на самой машине.
	var expected := ExitCar.spot(exit_at.x, level.rules, level.plan())
	assert_almost_eq(at.x, expected, TOLERANCE, "машина стоит на своём месте")
	var parked := ExitCar.parked_span(level.rules)
	assert_almost_eq(at.x, (parked.x + parked.y) * 0.5, TOLERANCE, "машина у ворот")
	assert_between(exit_at.x, parked.x, parked.y, "выход у машины")
	assert_eq((car as ExitCar).towards, -1.0, "капотом к воротам")


func test_the_building_is_cleared_only_after_the_car_leaves() -> void:
	var level := await _building()
	var car := _car_of(level)
	assert_not_null(car)
	if car == null:
		return

	var cleared := [false]
	level.building_cleared.connect(func() -> void: cleared[0] = true)

	var parked_at := car.position.x
	level.otto.global_position = WorldSpace.to_scene(level.exit_position())
	# Ждём не выдержку, а состояние: зона выхода замечает тело на своём шаге
	# физики, и ждать «один кадр» здесь — та же ошибка, что водить съёмку
	# секундомером (docs/testing.md).
	var started := 0
	while is_equal_approx(car.position.x, parked_at) and started < SETTLE_FRAMES * 6:
		await get_tree().physics_frame
		started += 1

	assert_ne(car.position.x, parked_at, "машина поехала")
	assert_false(cleared[0], "выход ещё не конец: машина только тронулась")

	var waited := 0
	while not cleared[0] and waited < PATIENCE:
		await get_tree().process_frame
		waited += 1
	assert_true(cleared[0], "здание сдано, когда машина уехала")


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
