extends GutTest

## Whoever falls more than a floor is killed (ADR-0037, decision 7).
##
## One rule for everything one can fall onto: floor, cab roof and shaft bottom. The scene
## is minimal — slabs at the needed heights and a cab: Otto is checked, not the building
## layout. The bot drives the whole building under the same rule.

const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")
const CAR_SCENE := preload("res://src/systems/elevators/elevator_car.tscn")

const FLOOR: float = Proportions.FLOOR

## How many physics steps to wait for landing: a three-floor fall is under a second, the
## rest is margin.
const FALL_FRAMES: int = 240

## How many steps to hold "down" in the cab: three floors at 1.6 s each under time_scale 2.
const RIDE_FRAMES: int = 240

## How many steps to wait for the empty cab with Otto on its roof: three runs with
## 1.5 s pauses — about 9 s, that is 280 steps under time_scale 2, plus margin.
const ROOF_RIDE_FRAMES: int = 420

## Edge of the upper slab: Otto steps off it into the void.
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


## Floor slab: top at scene height [param top], from [param from_x] to [param to_x].
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


## A cab standing at a single stop [param stop] (in the rules plane, down is growth): it
## has nowhere to go, and its roof waits for the faller in its place.
func _parked_car(stop: float) -> ElevatorCar:
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	car.setup(PackedFloat32Array([stop]), 0)
	return car


## A level with an edge: the upper slab up to the shaft, below — a floor at depth
## [param depth].
func _ledge_over(depth: float) -> Otto:
	_slab(-8.0, LEDGE_X, 0.0)
	_slab(-8.0, 8.0, -depth)
	return await _standing_otto()


func _standing_otto() -> Otto:
	var otto := _otto_at(LEDGE_X - 1.0, 0.05)
	await wait_physics_frames(4)
	assert_true(otto.is_grounded(), "Otto stood on the upper slab")
	return otto


## An edge over the shaft, and in it a cab at stop [param stop].
##
## A wall beyond the shaft's axis catches Otto: the flight speed is set by a push, and
## one stepping off the edge would fly over the roof and miss it — falling a floor takes
## longer than walking to the cab's far edge.
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


## Landed exactly on the cab's roof and did not fly past.
func _assert_on_the_roof(otto: Otto, stop: float) -> void:
	var roof := -stop + Proportions.CLEARANCE
	assert_almost_eq(otto.global_position.y, roof, 0.1, "Otto on the cab roof")


## Steps right off the edge and waits until Otto stands again — lower than he stood.
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
	assert_true(fell, "Otto stepped off the edge")


func test_falling_one_floor_is_survivable() -> void:
	var otto := await _ledge_over(FLOOR)
	await _step_off(otto)
	assert_false(otto.is_dead(), "you can jump down one floor")


func test_jumping_down_one_floor_is_survivable() -> void:
	# Jump height is not added to the fall: it is counted from the support, not from the
	# top of the flight.
	var otto := await _ledge_over(FLOOR)
	await _step_off(otto, true)
	assert_false(otto.is_dead(), "from a jump one floor down too")


func test_falling_two_floors_is_deadly() -> void:
	var otto := await _ledge_over(FLOOR * 2.0)
	await _step_off(otto)
	assert_true(otto.is_dead(), "two floors is death")


func test_own_jump_on_the_spot_is_not_a_fall() -> void:
	_slab(-8.0, 8.0, 0.0)
	var otto := await _standing_otto()
	Input.action_press(&"jump")
	await wait_physics_frames(2)
	Input.action_release(&"jump")
	await wait_physics_frames(60)
	assert_true(otto.is_grounded(), "landed")
	assert_false(otto.is_dead(), "his own jump is not a fall")


func test_a_teleport_down_is_not_a_fall() -> void:
	# The level, tests and captures put Otto wherever they need — that is not a fall.
	_slab(-8.0, 8.0, 0.0)
	_slab(-8.0, 8.0, -FLOOR * 3.0)
	var otto := await _standing_otto()
	otto.global_position = Vector3(0.0, -FLOOR * 3.0 + 0.5, WorldSpace.PLAY_Z)
	await wait_physics_frames(30)
	assert_true(otto.is_grounded(), "stood on the lower slab")
	assert_false(otto.is_dead(), "a repositioned one does not die")


func test_landing_on_a_car_roof_one_floor_down_is_survivable() -> void:
	# The cab stands two floors lower: its roof is a floor and a slab below the edge.
	var otto := await _over_a_car(FLOOR * 2.0)
	await _step_off(otto)
	_assert_on_the_roof(otto, FLOOR * 2.0)
	assert_false(otto.is_dead(), "you can jump onto a cab one floor down")


func test_landing_on_a_car_roof_two_floors_down_is_deadly() -> void:
	var otto := await _over_a_car(FLOOR * 3.0)
	await _step_off(otto)
	_assert_on_the_roof(otto, FLOOR * 3.0)
	assert_true(otto.is_dead(), "the cab roof does not save from two floors")


func test_riding_a_car_down_is_not_a_fall() -> void:
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	car.setup(PackedFloat32Array([0.0, FLOOR, FLOOR * 2.0, FLOOR * 3.0]), 0)
	var otto := _otto_at(0.0, 0.02)
	await wait_physics_frames(4)
	assert_true(otto.is_riding(), "Otto in the cab")

	Input.action_press(&"move_down")
	var left := RIDE_FRAMES
	while left > 0 and WorldSpace.to_plane(car.global_position).y < FLOOR * 3.0 - 0.01:
		await wait_physics_frames(1)
		left -= 1
	Input.action_release(&"move_down")
	await wait_physics_frames(10)
	assert_almost_eq(
		WorldSpace.to_plane(car.global_position).y, FLOOR * 3.0, 0.05, "rode to the bottom"
	)
	assert_false(otto.is_dead(), "a ride down in the cab is not a fall")


func test_riding_a_car_roof_down_is_not_a_fall() -> void:
	# On the roof the cab carries the same as inside: the support moves under the feet.
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	car.setup(PackedFloat32Array([0.0, FLOOR, FLOOR * 2.0, FLOOR * 3.0]), 0)
	var otto := _otto_at(0.0, Proportions.CLEARANCE + 0.05)
	await wait_physics_frames(4)
	assert_true(otto.is_grounded(), "Otto stands on the roof")
	assert_false(otto.is_riding(), "the cab is not controlled from the roof")

	var left := ROOF_RIDE_FRAMES
	while left > 0 and WorldSpace.to_plane(car.global_position).y < FLOOR * 3.0 - 0.01:
		await wait_physics_frames(1)
		left -= 1
	assert_almost_eq(
		WorldSpace.to_plane(car.global_position).y, FLOOR * 3.0, 0.05, "the cab rode to the bottom"
	)
	assert_false(otto.is_dead(), "a ride down on the roof is not a fall")
