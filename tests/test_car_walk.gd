extends GutTest

## Walking in a moving cab and stepping out on the move (ADR-0044, decisions 4 and 5).
##
## As in ROM (@45C5, @36F2): the cab listens only to "up/down", while left-right
## Otto walks in it on the move too; one can step off while the floor is no further than 18/48
## of a floor below the cab floor. Before M24h Otto stood in a moving cab.
##
## The scene is minimal — a cab at two stops and the bottom floor's floor to the right of
## the shaft: the cab rule is checked, not the layout.

const CAR_SCENE := preload("res://src/systems/elevators/elevator_car.tscn")
const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")

## How many physics steps to wait for the ride: the pause plus the run, with margin.
const RIDE_FRAMES: int = 600
## Where the shaft ends and the bottom floor's floor begins, m from the cab axis.
const SHAFT_EDGE: float = 0.95


func before_all() -> void:
	Engine.time_scale = 2.0


func after_all() -> void:
	Engine.time_scale = 1.0
	GameState.instance().reset()
	Input.action_release(&"move_down")
	Input.action_release(&"move_right")
	Input.action_release(&"jump")


## The bottom floor's floor to the right of the shaft: its top is at the height of −1 floor.
func _lower_floor() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 0.4, WorldSpace.CORRIDOR_DEPTH)
	shape.shape = box
	shape.position = Vector3(SHAFT_EDGE + 3.0, -0.2, 0.0)
	ground.add_child(shape)
	add_child_autofree(ground)
	ground.global_position = Vector3(0.0, -Proportions.FLOOR, 0.0)


## Otto in the cab at the top stop; the cab has set off downward.
func _riding_down() -> Array:
	GameState.instance().start_game()
	_lower_floor()
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	car.setup(PackedFloat32Array([0.0, Proportions.FLOOR]), 0)
	var otto := OTTO_SCENE.instantiate() as Otto
	add_child_autofree(otto)
	otto.global_position = Vector3(0.0, 0.0, WorldSpace.PLAY_Z)
	await wait_physics_frames(3)
	assert_true(otto.is_riding(), "Otto got into the car")
	Input.action_press(&"move_down")
	for _frame: int in RIDE_FRAMES:
		await wait_physics_frames(1)
		if not car.is_aligned():
			break
	assert_false(car.is_aligned(), "the car started moving")
	return [car, otto]


func test_otto_walks_in_a_moving_car_and_stops_at_its_wall() -> void:
	var pair := await _riding_down()
	var car := pair[0] as ElevatorCar
	var otto := pair[1] as Otto
	var start := otto.global_position.x
	Input.action_press(&"move_right")
	var walked := false
	var room := (car.width() - Proportions.BODY_WIDTH) * 0.5
	for _frame: int in RIDE_FRAMES:
		await wait_physics_frames(1)
		if car.can_step_out():
			break
		walked = walked or otto.global_position.x > start + 0.2
		assert_lte(
			otto.global_position.x - car.global_position.x,
			room + 0.02,
			"between floors the side is a wall"
		)
		assert_true(otto.is_riding(), "and he did not leave the car")
	Input.action_release(&"move_right")
	Input.action_release(&"move_down")
	assert_true(walked, "Otto walks in a moving car")


## The side holds in a jump too: flight speed is taken from the ground, and a running jump
## would carry Otto out of a moving cab into the shaft (M24h code review).
func test_a_jump_in_a_moving_car_stops_at_its_wall_too() -> void:
	var pair := await _riding_down()
	var car := pair[0] as ElevatorCar
	var otto := pair[1] as Otto
	var room := (car.width() - Proportions.BODY_WIDTH) * 0.5
	Input.action_press(&"move_right")
	Input.action_press(&"jump")
	var flew := false
	for _frame: int in RIDE_FRAMES:
		await wait_physics_frames(1)
		if car.can_step_out():
			break
		flew = flew or not otto.is_grounded()
		assert_lte(
			otto.global_position.x - car.global_position.x,
			room + 0.02,
			"in a jump the side is also a wall"
		)
	Input.action_release(&"jump")
	Input.action_release(&"move_right")
	Input.action_release(&"move_down")
	assert_true(flew, "Otto jumped in a moving car")
	assert_true(otto.is_riding(), "and the jump did not carry him out of the car")


func test_otto_steps_out_of_a_moving_car_near_a_floor() -> void:
	var pair := await _riding_down()
	var car := pair[0] as ElevatorCar
	var otto := pair[1] as Otto
	Input.action_press(&"move_right")
	var left_on_the_move := false
	for _frame: int in RIDE_FRAMES:
		await wait_physics_frames(1)
		if not otto.is_riding():
			left_on_the_move = not car.is_aligned()
			break
	Input.action_release(&"move_right")
	Input.action_release(&"move_down")
	assert_false(otto.is_riding(), "Otto left the car")
	assert_true(left_on_the_move, "left on the move, without waiting for the floor")
	await wait_physics_frames(60)
	assert_false(otto.is_dead(), "jumped onto the floor and is alive")
	assert_gt(otto.global_position.x, SHAFT_EDGE, "stands on the floor, not in the shaft")
