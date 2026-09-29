extends GutTest

## Труп агента лежит до конца здания телом на суставах (ADR-0037, решение 6;
## ADR-0043, решение 12).
##
## Тело не мишень, падает от удара по ходу пули, ложится на пол, а не под
## него, падает в пустую шахту и едет на полу кабины, в которой его убили.
## Улёгшись, засыпает: трупы до конца здания ничего не стоят кадру.

const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const CAR_SCENE := preload("res://src/systems/elevators/elevator_car.tscn")

## Сколько шагов физики ждать, пока тело ляжет.
const SETTLE_FRAMES: int = 150

## Сколько шагов физики ждать, пока кабина тронется и отъедет: пауза у этажа
## плюс перегон, с запасом.
const RIDE_FRAMES: int = 600


func before_all() -> void:
	# Мир вчетверо быстрее, а шаг физики прежний: на вчетверо длинном шаге
	# суставы рэгдолла разлетаются, и тело проваливается сквозь пол.
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240


func after_all() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
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


func test_a_corpse_lies_on_the_floor_and_falls_asleep() -> void:
	_floor_at(0.0)
	var agent: Enemy = await _agent_at(Vector3.ZERO)
	agent.kill()
	await wait_physics_frames(SETTLE_FRAMES)
	assert_true(is_instance_valid(agent), "тело не исчезло")
	assert_true(agent.corpse.fallen, "и упало")
	assert_false(agent.is_physics_processing(), "физика агента стоит — тело ведут части")
	assert_false(agent.get_node("Body").is_processing(), "поза тоже")
	var box := agent.corpse.ragdoll.bounds()
	assert_gt(box.position.y, -0.1, "лежит на полу, а не под ним")
	assert_lt(box.end.y, 0.6, "и лежит, а не стоит")
	assert_true(agent.corpse.ragdoll.asleep(), "и улеглось")
	assert_eq(agent.collision_layer, 0, "мишенью труп не служит")


## Пуля слева роняет тело вправо: по её ходу.
func test_a_bullet_throws_the_body_along_its_flight() -> void:
	_floor_at(0.0)
	var agent: Enemy = await _agent_at(Vector3.ZERO)
	agent.set_meta(Corpse.HIT_META, 1.0)
	agent.kill()
	await wait_physics_frames(SETTLE_FRAMES)
	assert_gt(agent.corpse.ragdoll.bounds().get_center().x, 0.2, "тело упало вправо")


## Убитый в кабине едет с ней на её полу. Стоит у правой стенки и падает
## навзничь влево: тело длиной почти в кабину ложится в неё целиком.
func test_a_corpse_in_a_car_rides_with_it() -> void:
	GameState.instance().start_game()
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	car.setup(PackedFloat32Array([0.0, Proportions.FLOOR]), 0)
	await wait_physics_frames(2)
	var agent: Enemy = await _agent_at(car.global_position + Vector3(0.5, 0.05, 0.0))
	agent.kill()
	await wait_physics_frames(40)
	var start := car.global_position.y
	var gap := agent.corpse.ragdoll.bounds().position.y - car.global_position.y
	for _frame: int in RIDE_FRAMES:
		await wait_physics_frames(1)
		if absf(car.global_position.y - start) > Proportions.FLOOR * 0.5:
			break
	assert_gt(absf(car.global_position.y - start), Proportions.FLOOR * 0.5, "кабина уехала")
	var now := agent.corpse.ragdoll.bounds().position.y - car.global_position.y
	assert_almost_eq(now, gap, 0.25, "а труп — вместе с ней, на её полу")


## Убитый над пустой шахтой падает на её дно.
func test_a_corpse_over_an_empty_shaft_falls_to_the_bottom() -> void:
	_floor_at(-Proportions.FLOOR * 2.0)
	var agent: Enemy = await _agent_at(Vector3(0.0, 0.05, 0.0))
	agent.kill()
	await wait_physics_frames(SETTLE_FRAMES * 2)
	var bottom := agent.corpse.ragdoll.bounds().position.y
	assert_almost_eq(bottom, -Proportions.FLOOR * 2.0, 0.1, "лежит на дне")


## Добитый сценкой падает, когда сценка его отпустит, а не раньше.
func test_a_held_corpse_falls_when_released() -> void:
	_floor_at(0.0)
	var agent: Enemy = await _agent_at(Vector3.ZERO)
	agent.held = true
	agent.kill(false, "knocked")
	assert_false(agent.corpse.fallen, "пока держит сценка, тело не в физике")
	agent.held = false
	assert_true(agent.corpse.fallen, "отпустила — упало")
