extends GutTest

## The cab crushes agents: 300 points, as in the ROM (ADR-0027, decision 6).
##
## A debt from M18b: only Otto got crushed. The scene is minimal, a floor, a cab above it
## and an agent under its bottom: a whole building is not needed here, what is checked is
## the cab rule, not the layout.

const CAR_SCENE := preload("res://src/systems/elevators/elevator_car.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")

## How many physics steps to wait for the cab to go down: the pause at a floor plus the
## run, with a margin.
const RIDE_FRAMES: int = 600


func before_all() -> void:
	Engine.time_scale = 4.0


func after_all() -> void:
	Engine.time_scale = 1.0
	GameState.instance().reset()


## The lower floor at a scene height of −3.6 m: the cab stands one floor higher.
func _floor_at(height: float) -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 0.4, WorldSpace.CORRIDOR_DEPTH)
	shape.shape = box
	shape.position = Vector3(0.0, -0.2, 0.0)
	ground.add_child(shape)
	add_child_autofree(ground)
	ground.global_position = Vector3(0.0, height, 0.0)


func _agent_under_the_car(x: float = 0.0) -> Enemy:
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.walk_speed = 0.0
	add_child_autofree(agent)
	agent.global_position = Vector3(x, -Proportions.FLOOR, 0.0)
	agent.setup(null, 1.0)
	return agent


## The cab is at the upper of two stops; it will go down by itself, on its own schedule.
func _car() -> ElevatorCar:
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	car.setup(PackedFloat32Array([0.0, Proportions.FLOOR]), 0)
	return car


## Waits until the cab goes down or [param done] returns true.
func _ride_down(done: Callable) -> void:
	for _frame: int in RIDE_FRAMES:
		await wait_physics_frames(1)
		if done.call():
			return


func test_a_descending_car_crushes_the_agent_under_it() -> void:
	GameState.instance().start_game()
	_floor_at(-Proportions.FLOOR)
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	# Stops in rules coordinates: down means growing. The cab is at the upper one and will
	# go to the lower one by itself, on its own schedule.
	car.setup(PackedFloat32Array([0.0, Proportions.FLOOR]), 0)
	var agent := _agent_under_the_car()
	var before := GameState.instance().score

	for _frame: int in RIDE_FRAMES:
		await wait_physics_frames(1)
		if agent.is_dead():
			break

	assert_true(agent.is_dead(), "кабина раздавила агента под днищем")
	assert_eq(GameState.instance().score - before, 0, "кабина ехала сама — очков нет, как в ROM")


## Crush points come only from the cab Otto rides in (@4A97 ROM,
## ADR-0044, decision 7).
func test_otto_s_own_car_scores_the_crush() -> void:
	GameState.instance().start_game()
	_floor_at(-Proportions.FLOOR)
	_car()
	var otto := OTTO_SCENE.instantiate() as Otto
	add_child_autofree(otto)
	otto.global_position = Vector3(0.0, 0.0, WorldSpace.PLAY_Z)
	var agent := _agent_under_the_car()
	var before := GameState.instance().score
	await wait_physics_frames(3)
	assert_true(otto.is_riding(), "Otto сел в кабину")
	Input.action_press(&"move_down")
	await _ride_down(func() -> bool: return agent.is_dead())
	Input.action_release(&"move_down")
	assert_true(agent.is_dead(), "кабина Otto раздавила агента")
	var gained := GameState.instance().score - before
	assert_true(
		(
			gained == GameState.CRUSH_SCORE
			or gained == GameState.kill_score(GameState.CRUSH_SCORE, true)
		),
		"300 очков, с надбавкой за темноту, если темно: %d" % gained
	)


## Someone caught by the edge is not crushed by the cab but pushed out to the shaft edge
## (@4713 ROM, ADR-0044, decision 6). Previously a touch of the side wall killed.
func test_a_car_edge_pushes_the_agent_aside() -> void:
	GameState.instance().start_game()
	_floor_at(-Proportions.FLOOR)
	var car := _car()
	# The agent's middle is 0.7 m from the axis: half the body is under the side, half
	# outside.
	var agent := _agent_under_the_car(0.7)
	await _ride_down(
		func() -> bool: return agent.is_dead() or car.is_aligned() and car.global_position.y < -1.0
	)
	assert_false(agent.is_dead(), "задетый краем жив")
	var clear := (car.width() + Proportions.BODY_WIDTH) * 0.5
	assert_gte(agent.global_position.x, clear - 0.05, "его вытолкнуло за борт")


func test_a_car_edge_pushes_otto_aside() -> void:
	GameState.instance().start_game()
	_floor_at(-Proportions.FLOOR)
	var car := _car()
	var otto := OTTO_SCENE.instantiate() as Otto
	add_child_autofree(otto)
	otto.global_position = Vector3(-0.7, -Proportions.FLOOR, WorldSpace.PLAY_Z)
	await _ride_down(
		func() -> bool: return otto.is_dead() or car.is_aligned() and car.global_position.y < -1.0
	)
	assert_false(otto.is_dead(), "задетый краем Otto жив")
	assert_lte(
		otto.global_position.x, -(car.width() + Proportions.BODY_WIDTH) * 0.5 + 0.05, "вытолкнут"
	)


## The cab also crushes Otto standing under it on the floor: he is not a passenger.
##
## Before M24a Otto became a passenger as soon as his head entered the opening of a
## descending cab: being occupied saved him from crushing, and an occupied cab with no
## command stopped between floors, so both froze forever (ADR-0037, decision 1).
func test_a_descending_car_crushes_otto_under_it() -> void:
	GameState.instance().start_game()
	_floor_at(-Proportions.FLOOR)
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	car.setup(PackedFloat32Array([0.0, Proportions.FLOOR]), 0)
	var otto := OTTO_SCENE.instantiate() as Otto
	add_child_autofree(otto)
	otto.global_position = Vector3(0.0, -Proportions.FLOOR, WorldSpace.PLAY_Z)

	var boarded := false
	for _frame: int in RIDE_FRAMES:
		await wait_physics_frames(1)
		boarded = boarded or otto.is_riding()
		if otto.is_dead() or boarded:
			break

	assert_false(boarded, "стоящий под кабиной — не пассажир")
	assert_true(otto.is_dead(), "кабина раздавила Otto под днищем")
