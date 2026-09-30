extends GutTest

## Ходьба в едущей кабине и выход на ходу (ADR-0044, решения 4 и 5).
##
## Как в ROM (@45C5, @36F2): кабина слушает только «вверх/вниз», а влево-вправо
## Otto ходит в ней и на ходу; сойти можно, пока пол этажа не дальше 18/48
## этажа под полом кабины. До M24h в едущей кабине Otto стоял.
##
## Сцена минимальная — кабина на двух остановках и пол нижнего этажа справа от
## шахты: проверяется правило кабины, а не раскладка.

const CAR_SCENE := preload("res://src/systems/elevators/elevator_car.tscn")
const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")

## Сколько шагов физики ждать поездки: пауза плюс перегон, с запасом.
const RIDE_FRAMES: int = 600
## Где кончается шахта и начинается пол нижнего этажа, м от оси кабины.
const SHAFT_EDGE: float = 0.95


func before_all() -> void:
	Engine.time_scale = 2.0


func after_all() -> void:
	Engine.time_scale = 1.0
	GameState.instance().reset()
	Input.action_release(&"move_down")
	Input.action_release(&"move_right")


## Пол нижнего этажа справа от шахты: верх — на высоте −1 этаж.
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


## Otto в кабине на верхней остановке; кабина тронулась вниз.
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
	assert_true(otto.is_riding(), "Otto сел в кабину")
	Input.action_press(&"move_down")
	for _frame: int in RIDE_FRAMES:
		await wait_physics_frames(1)
		if not car.is_aligned():
			break
	assert_false(car.is_aligned(), "кабина тронулась")
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
			"между этажами борт — стена"
		)
		assert_true(otto.is_riding(), "и из кабины он не вышел")
	Input.action_release(&"move_right")
	Input.action_release(&"move_down")
	assert_true(walked, "в едущей кабине Otto идёт")


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
	assert_false(otto.is_riding(), "Otto вышел из кабины")
	assert_true(left_on_the_move, "вышел на ходу, не дожидаясь этажа")
	await wait_physics_frames(60)
	assert_false(otto.is_dead(), "спрыгнул на этаж и жив")
	assert_gt(otto.global_position.x, SHAFT_EDGE, "стоит на этаже, а не в шахте")
