extends GutTest

## Разбивается тот, кто упал больше чем на этаж (ADR-0037, решение 7).
##
## Правило одно на всё, на что можно упасть: пол, крышу кабины и дно шахты. Сцена
## минимальная — плиты на нужных высотах и кабина: проверяется Otto, а не
## раскладка здания. Здание целиком с тем же правилом водит бот.

const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")
const CAR_SCENE := preload("res://src/systems/elevators/elevator_car.tscn")

const FLOOR: float = Proportions.FLOOR

## Сколько шагов физики ждать приземления: падение на три этажа — меньше
## секунды, остальное — запас.
const FALL_FRAMES: int = 240

## Сколько шагов держать «вниз» в кабине: три этажа по 1.6 с под time_scale 2.
const RIDE_FRAMES: int = 240

## Сколько шагов ждать пустую кабину с Otto на крыше: три перегона с паузами
## по 1.5 с — около 9 с, то есть 280 шагов под time_scale 2, и запас.
const ROOF_RIDE_FRAMES: int = 420

## Край верхней плиты: с него Otto сходит в пустоту.
const LEDGE_X: float = -Proportions.SHAFT * 0.5


func before_all() -> void:
	Engine.time_scale = 2.0


func after_all() -> void:
	Engine.time_scale = 1.0
	_release()
	GameState.instance().reset()


func after_each() -> void:
	_release()


func _release() -> void:
	for action: StringName in [&"move_right", &"move_down", &"jump"]:
		Input.action_release(action)


## Плита пола: верх на высоте [param top] сцены, от [param from_x] до [param to_x].
func _slab(from_x: float, to_x: float, top: float) -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(to_x - from_x, 0.4, WorldSpace.CORRIDOR_DEPTH)
	shape.shape = box
	shape.position = Vector3((from_x + to_x) * 0.5, top - 0.2, 0.0)
	ground.add_child(shape)
	add_child_autofree(ground)


func _otto_at(x: float, y: float) -> Otto:
	var otto := OTTO_SCENE.instantiate() as Otto
	add_child_autofree(otto)
	otto.global_position = Vector3(x, y, WorldSpace.PLAY_Z)
	return otto


## Кабина, стоящая на одной остановке [param stop] (в плоскости правил, вниз —
## рост): ехать ей некуда, и крыша ждёт падающего на своём месте.
func _parked_car(stop: float) -> ElevatorCar:
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	car.setup(PackedFloat32Array([stop]), 0)
	return car


## Уровень с края: верхняя плита до шахты, внизу — пол на глубине [param depth].
func _ledge_over(depth: float) -> Otto:
	_slab(-8.0, LEDGE_X, 0.0)
	_slab(-8.0, 8.0, -depth)
	return await _standing_otto()


func _standing_otto() -> Otto:
	var otto := _otto_at(LEDGE_X - 1.0, 0.05)
	await wait_physics_frames(4)
	assert_true(otto.is_grounded(), "Otto встал на верхнюю плиту")
	return otto


## Край над шахтой, а в ней кабина на остановке [param stop].
##
## Стенка за осью шахты ловит Otto: скорость полёта задаётся толчком, и сошедший
## с края пролетел бы над крышей мимо — с этажа падать дольше, чем идти до
## дальнего края кабины.
func _over_a_car(stop: float) -> Otto:
	_slab(-8.0, LEDGE_X, 0.0)
	_parked_car(stop)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 3.0, WorldSpace.CORRIDOR_DEPTH)
	shape.shape = box
	shape.position = Vector3(0.3, 1.0, 0.0)
	wall.add_child(shape)
	add_child_autofree(wall)
	return await _standing_otto()


## Приземлился именно на крышу кабины, а не пролетел мимо.
func _assert_on_the_roof(otto: Otto, stop: float) -> void:
	var roof := -stop + Proportions.CLEARANCE
	assert_almost_eq(otto.global_position.y, roof, 0.1, "Otto на крыше кабины")


## Шагает вправо с края и ждёт, пока Otto снова встанет — ниже, чем стоял.
func _step_off(otto: Otto, jump: bool = false) -> void:
	Input.action_press(&"move_right")
	if jump:
		await wait_physics_frames(1)
		Input.action_press(&"jump")
	var left := FALL_FRAMES
	var fell := false
	while left > 0:
		await wait_physics_frames(1)
		left -= 1
		fell = fell or otto.global_position.y < -0.5
		if fell and (otto.is_grounded() or otto.is_dead()):
			break
	_release()
	assert_true(fell, "Otto сошёл с края")


func test_falling_one_floor_is_survivable() -> void:
	var otto := await _ledge_over(FLOOR)
	await _step_off(otto)
	assert_false(otto.is_dead(), "на этаж ниже спрыгнуть можно")


func test_jumping_down_one_floor_is_survivable() -> void:
	# Высота прыжка к падению не прибавляется: считается от опоры, а не от
	# верхней точки полёта.
	var otto := await _ledge_over(FLOOR)
	await _step_off(otto, true)
	assert_false(otto.is_dead(), "с прыжка на этаж ниже — тоже")


func test_falling_two_floors_is_deadly() -> void:
	var otto := await _ledge_over(FLOOR * 2.0)
	await _step_off(otto)
	assert_true(otto.is_dead(), "с двух этажей — смерть")


func test_own_jump_on_the_spot_is_not_a_fall() -> void:
	_slab(-8.0, 8.0, 0.0)
	var otto := await _standing_otto()
	Input.action_press(&"jump")
	await wait_physics_frames(2)
	Input.action_release(&"jump")
	await wait_physics_frames(60)
	assert_true(otto.is_grounded(), "приземлился")
	assert_false(otto.is_dead(), "свой прыжок — не падение")


func test_a_teleport_down_is_not_a_fall() -> void:
	# Уровень, тесты и съёмка ставят Otto куда им надо — это не падение.
	_slab(-8.0, 8.0, 0.0)
	_slab(-8.0, 8.0, -FLOOR * 3.0)
	var otto := await _standing_otto()
	otto.global_position = Vector3(0.0, -FLOOR * 3.0 + 0.5, WorldSpace.PLAY_Z)
	await wait_physics_frames(30)
	assert_true(otto.is_grounded(), "встал на нижнюю плиту")
	assert_false(otto.is_dead(), "переставленный не разбивается")


func test_landing_on_a_car_roof_one_floor_down_is_survivable() -> void:
	# Кабина стоит двумя этажами ниже: крыша на этаж и плиту ниже края.
	var otto := await _over_a_car(FLOOR * 2.0)
	await _step_off(otto)
	_assert_on_the_roof(otto, FLOOR * 2.0)
	assert_false(otto.is_dead(), "на кабину этажом ниже спрыгнуть можно")


func test_landing_on_a_car_roof_two_floors_down_is_deadly() -> void:
	var otto := await _over_a_car(FLOOR * 3.0)
	await _step_off(otto)
	_assert_on_the_roof(otto, FLOOR * 3.0)
	assert_true(otto.is_dead(), "крыша кабины с двух этажей не спасает")


func test_riding_a_car_down_is_not_a_fall() -> void:
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	car.setup(PackedFloat32Array([0.0, FLOOR, FLOOR * 2.0, FLOOR * 3.0]), 0)
	var otto := _otto_at(0.0, 0.02)
	await wait_physics_frames(4)
	assert_true(otto.is_riding(), "Otto в кабине")

	Input.action_press(&"move_down")
	var left := RIDE_FRAMES
	while left > 0 and WorldSpace.to_plane(car.global_position).y < FLOOR * 3.0 - 0.01:
		await wait_physics_frames(1)
		left -= 1
	Input.action_release(&"move_down")
	await wait_physics_frames(10)
	assert_almost_eq(
		WorldSpace.to_plane(car.global_position).y, FLOOR * 3.0, 0.05, "доехал до низа"
	)
	assert_false(otto.is_dead(), "спуск в кабине — не падение")


func test_riding_a_car_roof_down_is_not_a_fall() -> void:
	# На крыше кабина везёт так же, как внутри: опора едет под ногами.
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	car.setup(PackedFloat32Array([0.0, FLOOR, FLOOR * 2.0, FLOOR * 3.0]), 0)
	var otto := _otto_at(0.0, Proportions.CLEARANCE + 0.05)
	await wait_physics_frames(4)
	assert_true(otto.is_grounded(), "Otto стоит на крыше")
	assert_false(otto.is_riding(), "с крыши кабиной не управляют")

	var left := ROOF_RIDE_FRAMES
	while left > 0 and WorldSpace.to_plane(car.global_position).y < FLOOR * 3.0 - 0.01:
		await wait_physics_frames(1)
		left -= 1
	assert_almost_eq(
		WorldSpace.to_plane(car.global_position).y, FLOOR * 3.0, 0.05, "кабина доехала до низа"
	)
	assert_false(otto.is_dead(), "спуск на крыше — не падение")
