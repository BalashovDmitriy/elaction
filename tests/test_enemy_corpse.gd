extends GutTest

## Труп агента лежит до конца здания (ADR-0037, решение 6).
##
## До M24a тело уходило через полсекунды. Теперь оно остаётся, где упало, — и
## потому обязано ничего не стоить: не быть мишенью, не держать физику и позу
## каждый кадр и ехать с кабиной, в которой его убили.

const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const CAR_SCENE := preload("res://src/systems/elevators/elevator_car.tscn")

## Сколько шагов физики ждать, пока тело ляжет и уснёт.
const SETTLE_FRAMES: int = 90

## Сколько шагов физики ждать, пока кабина тронется и отъедет: пауза у этажа
## плюс перегон, с запасом.
const RIDE_FRAMES: int = 600


func before_all() -> void:
	Engine.time_scale = 4.0


func after_all() -> void:
	Engine.time_scale = 1.0
	Blood.enabled = true
	GameState.instance().reset()


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


## Агент, вышедший из проёма и стоящий на месте: выходящего не убить.
func _agent_at(at: Vector3) -> Enemy:
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.walk_speed = 0.0
	add_child_autofree(agent)
	agent.global_position = at
	agent.setup(null, 1.0)
	while agent.is_emerging():
		await wait_physics_frames(1)
	return agent


func test_a_corpse_stays_and_falls_asleep() -> void:
	_floor_at(0.0)
	var agent: Enemy = await _agent_at(Vector3.ZERO)
	agent.kill()
	await wait_physics_frames(SETTLE_FRAMES)
	assert_true(is_instance_valid(agent), "тело не исчезло")
	assert_true(agent.is_dead(), "и это труп")
	assert_false(agent.is_physics_processing(), "физика тела уснула")
	assert_false(agent.get_node("Body").is_processing(), "поза тоже")
	assert_almost_eq(agent.global_position.y, 0.0, 0.05, "лежит на полу, а не под ним")
	assert_false(agent.get_collision_layer_value(Enemy.ENEMY_LAYER), "мишенью труп не служит")


## Убитый в кабине едет с ней: тело уснуло, но лежит на её полу, а не висит в
## шахте, когда кабина ушла.
func test_a_corpse_in_a_car_rides_with_it() -> void:
	GameState.instance().start_game()
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	car.setup(PackedFloat32Array([0.0, Proportions.FLOOR]), 0)
	await wait_physics_frames(2)
	var agent: Enemy = await _agent_at(car.global_position + Vector3(0.0, 0.05, 0.0))
	agent.kill()
	await wait_physics_frames(SETTLE_FRAMES)
	var start := car.global_position.y
	var gap := agent.global_position.y - car.global_position.y
	for _frame: int in RIDE_FRAMES:
		await wait_physics_frames(1)
		if absf(car.global_position.y - start) > Proportions.FLOOR * 0.5:
			break
	assert_gt(absf(car.global_position.y - start), Proportions.FLOOR * 0.5, "кабина уехала")
	# Смотрим после кадра отрисовки, как игрок: посреди шага физики кабина уже
	# сдвинулась, а труп — ещё нет, его шаг идёт после кабин.
	await get_tree().process_frame
	assert_almost_eq(
		agent.global_position.y - car.global_position.y, gap, 0.05, "а труп — вместе с ней"
	)


## Плита слева от кабины: верх вровень с полом кабины, край у её левой стенки.
func _landing_left_of(car: ElevatorCar) -> void:
	var slab := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 0.4, WorldSpace.CORRIDOR_DEPTH)
	shape.shape = box
	slab.add_child(shape)
	add_child_autofree(slab)
	var edge := car.global_position.x - car.width() * 0.5
	slab.global_position = Vector3(edge - 2.0, car.global_position.y - 0.2, 0.0)


## Агент, повёрнутый в сторону [param facing]: падает навзничь, в обратную.
func _facing(agent: Enemy, facing: float) -> void:
	agent.held_facing = facing
	agent.held = true
	agent.held = false


## Убитый у края кабины падает туловищем на площадку: когда кабина уходит, он
## съезжает на неё целиком и остаётся на этаже, — а не едет с ней сквозь
## перекрытия, как ехал, пока решали ступни (ADR-0042, решение 1). Так — без
## крови; с кровью его рвёт стенка кабины (ADR-0043, решение 11, `test_car_cut`).
func test_a_corpse_across_the_car_edge_stays_on_the_landing() -> void:
	GameState.instance().start_game()
	Blood.enabled = false
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	car.setup(PackedFloat32Array([0.0, Proportions.FLOOR]), 0)
	await wait_physics_frames(2)
	_landing_left_of(car)
	var edge := car.global_position.x - car.width() * 0.5
	var agent: Enemy = await _agent_at(Vector3(edge + 0.3, car.global_position.y + 0.05, 0.0))
	_facing(agent, 1.0)
	agent.kill()
	await wait_physics_frames(SETTLE_FRAMES)
	var floor_y := car.global_position.y
	var start := car.global_position.y
	for _frame: int in RIDE_FRAMES:
		await wait_physics_frames(1)
		if absf(car.global_position.y - start) > Proportions.FLOOR * 0.5:
			break
	assert_gt(absf(car.global_position.y - start), Proportions.FLOOR * 0.5, "кабина уехала")
	assert_almost_eq(agent.global_position.y, floor_y, 0.05, "труп остался на площадке")
	assert_lt(agent.global_position.x, edge, "и лежит на ней, а не над шахтой")
	Blood.enabled = true


## Убитый над пустой шахтой падает на её дно и засыпает там.
func test_a_corpse_over_an_empty_shaft_falls_to_the_bottom() -> void:
	_floor_at(-Proportions.FLOOR * 2.0)
	var agent: Enemy = await _agent_at(Vector3(0.0, 0.05, 0.0))
	agent.kill()
	await wait_physics_frames(SETTLE_FRAMES * 2)
	assert_almost_eq(agent.global_position.y, -Proportions.FLOOR * 2.0, 0.05, "лежит на дне")
	assert_false(agent.is_physics_processing(), "и уснул там")


## Труп на полу кабины не засыпает: кабина его везёт.
func test_a_corpse_in_a_car_keeps_riding_awake() -> void:
	GameState.instance().start_game()
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	car.setup(PackedFloat32Array([0.0, Proportions.FLOOR]), 0)
	await wait_physics_frames(2)
	var agent: Enemy = await _agent_at(car.global_position + Vector3(0.3, 0.05, 0.0))
	_facing(agent, 1.0)
	agent.kill()
	await wait_physics_frames(SETTLE_FRAMES)
	assert_true(agent.is_physics_processing(), "физика трупа в кабине не спит")
	assert_eq(agent.get_parent(), self, "в узел кабины труп не переходит")
