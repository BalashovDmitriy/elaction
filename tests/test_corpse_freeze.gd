extends GutTest

## Улёгшееся тело застывает (ADR-0044, решение 11).
##
## Замер M24h: двадцать трупов с рэгдоллом не засыпали — в стопке соседи будили
## друг друга. Застывшее тело статично: физика его не считает, но на него
## по-прежнему ложатся другие, и выглядит оно так же. Опора ушла — тело снова
## живёт физикой ([method Ragdoll.wake]). Выпавшее из мира — пропадает.

const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const CAR_SCENE := preload("res://src/systems/elevators/elevator_car.tscn")
## Сколько шагов дать телу лечь и застыть.
const SETTLE_FRAMES: int = 480
## Сколько шагов ждать, пока кабина доедет до тела: пауза плюс перегон.
const RIDE_FRAMES: int = 1200


func before_all() -> void:
	# Как в test_enemy_corpse: мир быстрее, шаг физики мельче — иначе суставы
	# рэгдолла на длинном шаге разлетаются.
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240


func after_all() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Ragdoll.abyss = -INF
	GameState.instance().reset()


## Куски тел, брызги и пятна кладёт в сцену кабина, а не тест: убираются тут.
func after_each() -> void:
	for child: Node in get_children():
		if child is CorpsePiece or child is Decal or child is Blood:
			child.free()


func _floor_at(height: float) -> StaticBody3D:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 0.4, WorldSpace.CORRIDOR_DEPTH)
	shape.shape = box
	shape.position = Vector3(0.0, -0.2, 0.0)
	ground.add_child(shape)
	add_child_autofree(ground)
	ground.global_position = Vector3(0.0, height, 0.0)
	return ground


func _corpse_at(at: Vector3) -> Enemy:
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.walk_speed = 0.0
	add_child_autofree(agent)
	agent.global_position = at
	agent.setup(null, 1.0)
	while agent.is_emerging():
		await wait_physics_frames(1)
	agent.kill()
	return agent


func _wait_frozen(agent: Enemy) -> bool:
	for _frame: int in SETTLE_FRAMES:
		await wait_physics_frames(1)
		if agent.corpse.ragdoll.is_frozen():
			return true
	return false


func test_a_body_at_rest_freezes_where_it_lies() -> void:
	_floor_at(0.0)
	var agent: Enemy = await _corpse_at(Vector3.ZERO)
	assert_true(await _wait_frozen(agent), "улёгшееся тело застыло")
	var before := agent.corpse.ragdoll.bounds()
	await wait_physics_frames(60)
	var after := agent.corpse.ragdoll.bounds()
	assert_almost_eq(
		after.get_center().distance_to(before.get_center()), 0.0, 0.01, "и не двигается"
	)
	assert_gt(after.position.y, -0.1, "лежит на полу, а не под ним")


func test_another_body_lies_on_a_frozen_one() -> void:
	_floor_at(0.0)
	var first: Enemy = await _corpse_at(Vector3.ZERO)
	assert_true(await _wait_frozen(first), "первое застыло")
	var top := first.corpse.ragdoll.bounds().end.y
	var second: Enemy = await _corpse_at(Vector3(0.0, top + 0.3, 0.0))
	await wait_physics_frames(SETTLE_FRAMES / 2)
	# Второе может и скатиться с первого на пол — это не провал. Провал —
	# лежать над застывшим, но ниже его верха.
	# Меряется тазом второго: габарит тела с раскинутыми руками и ногами
	# перекрывает соседа и у скатившегося на пол.
	var lower := first.corpse.ragdoll.bounds()
	var pelvis := Ragdoll.center_of(second.corpse.ragdoll.parts["Body"] as PhysicalBone3D)
	if pelvis.x > lower.position.x + 0.1 and pelvis.x < lower.end.x - 0.1:
		assert_gt(
			pelvis.y,
			lower.position.y + 0.2,
			"второе легло сверху, а не провалилось сквозь застывшее"
		)
	assert_gt(second.corpse.ragdoll.bounds().position.y, -0.1, "и не ушло под пол")


func test_a_frozen_body_wakes_when_its_floor_goes() -> void:
	var ground := _floor_at(0.0)
	var agent: Enemy = await _corpse_at(Vector3.ZERO)
	assert_true(await _wait_frozen(agent), "застыло")
	ground.queue_free()
	await wait_physics_frames(2)
	agent.corpse.ragdoll.wake()
	assert_false(agent.corpse.ragdoll.is_frozen(), "проснулось")
	var before := agent.corpse.ragdoll.bounds().position.y
	await wait_physics_frames(60)
	assert_lt(agent.corpse.ragdoll.bounds().position.y, before - 0.5, "и падает")


## Кабина на двух остановках, с полом [param width] м шириной. Стоит наверху,
## пока её не отпустят ([method _let_go]).
func _held_car(width: float = ElevatorCar.DEFAULT_WIDTH) -> ElevatorCar:
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	car.fit_to_story(Proportions.CLEARANCE, width)
	car.floor_pause = 1000.0
	car.setup(PackedFloat32Array([0.0, Proportions.FLOOR]), 0)
	return car


## Отпускает кабину вниз и ждёт, пока доедет — и там держит, — или пока
## [param done] не вернёт true.
func _let_go(car: ElevatorCar, done: Callable = Callable()) -> void:
	car.floor_pause = 0.2
	car.setup(PackedFloat32Array([0.0, Proportions.FLOOR]), 0)
	for _frame: int in RIDE_FRAMES:
		await wait_physics_frames(1)
		if (done.is_valid() and done.call()) or car.global_position.y <= -Proportions.FLOOR + 0.01:
			break
	# Доехавшая пустая кабина постояла бы и поехала обратно. Держат стоящую, а
	# в кадр прибытия она ещё отчитывается ходом.
	await wait_physics_frames(1)
	car.hold(1000.0)
	await wait_physics_frames(30)


## Стопка тел на полу вставшей кабины не застывает и едет с ней: застывшая
## повисла бы в воздухе, когда кабина уедет. Верхнее тело лежит не только на
## кабине, но и на нижнем.
func test_a_pile_in_a_standing_car_rides_on_with_it() -> void:
	# Пол кабины шире тела: стопка ложится на неё целиком, а не свешивается.
	var car := _held_car(6.0)
	var below: Enemy = await _corpse_at(Vector3(0.0, 0.05, 0.0))
	await wait_physics_frames(SETTLE_FRAMES / 4)
	var top := below.corpse.ragdoll.bounds()
	var above: Enemy = await _corpse_at(Vector3(top.get_center().x, top.end.y + 0.3, 0.0))
	await wait_physics_frames(SETTLE_FRAMES)
	assert_false(above.corpse.ragdoll.is_frozen(), "верхнее над кабиной не застыло")
	await _let_go(car)
	var floor_y := -Proportions.FLOOR
	assert_lt(below.corpse.ragdoll.bounds().position.y, floor_y + 0.5, "нижнее уехало с кабиной")
	assert_lt(above.corpse.ragdoll.bounds().position.y, floor_y + 1.0, "и верхнее — не повисло")


## Застывшее в яме шахты тело кабина, съехав, всё равно режет: застывшее
## статично, и зона давки обязана видеть и такие тела.
func test_a_frozen_body_in_a_shaft_pit_is_still_cut() -> void:
	GameState.instance().start_game()
	_floor_at(-Proportions.FLOOR)
	var car := _held_car()
	var agent: Enemy = await _corpse_at(Vector3(0.0, -Proportions.FLOOR, 0.0))
	assert_true(await _wait_frozen(agent), "в яме тело застыло")
	await _let_go(car, func() -> bool: return agent.corpse.cut != null or agent.corpse.gone)
	assert_true(agent.corpse.cut != null or agent.corpse.gone, "кабина режет его днищем")


func test_a_body_fallen_out_of_the_world_is_gone() -> void:
	Ragdoll.abyss = -5.0
	var agent: Enemy = await _corpse_at(Vector3.ZERO)
	for _frame: int in SETTLE_FRAMES:
		await wait_physics_frames(1)
		if agent.corpse.gone:
			break
	assert_true(agent.corpse.gone, "упавшее ниже мира тело пропало")
	Ragdoll.abyss = -INF
