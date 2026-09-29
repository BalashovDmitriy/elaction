extends GutTest

## Кабина режет тела и трупы ложатся друг на друга (ADR-0043, решения 7–11).
##
## Днищем сверху кабина срезает то, что под ней, стенкой — рвёт тело поперёк
## порога, когда трогается. Без крови не режет: тело под днищем исчезает, а с
## порога съезжает на опору середины. Сцена минимальная — пол, кабина, тело.

const CAR_SCENE := preload("res://src/systems/elevators/elevator_car.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")

## Сколько шагов физики ждать, пока тело ляжет и уснёт.
const SETTLE_FRAMES: int = 90
## Сколько шагов физики ждать, пока кабина доедет: пауза у этажа плюс
## перегон, с запасом.
const RIDE_FRAMES: int = 600


func before_all() -> void:
	Engine.time_scale = 4.0


func after_all() -> void:
	Engine.time_scale = 1.0
	Blood.enabled = true
	GameState.instance().reset()


func before_each() -> void:
	Blood.enabled = true
	GameState.instance().start_game()


## Куски тел кладёт в сцену кабина, а не тест: убираются тут.
func after_each() -> void:
	for piece: CorpsePiece in _pieces():
		piece.free()
	for child: Node in get_children():
		if child is Decal or child is Blood:
			child.free()


func _floor_at(height: float, width: float = 8.0, x: float = 0.0) -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, 0.4, WorldSpace.CORRIDOR_DEPTH)
	shape.shape = box
	shape.position = Vector3(0.0, -0.2, 0.0)
	ground.add_child(shape)
	add_child_autofree(ground)
	ground.global_position = Vector3(x, height, 0.0)


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


## Убитый, повёрнутый в сторону [param facing]: падает навзничь, в обратную.
func _corpse_at(at: Vector3, facing: float) -> Enemy:
	var agent: Enemy = await _agent_at(at)
	agent.held_facing = facing
	agent.held = true
	agent.held = false
	agent.kill()
	return agent


## Кабина над нижним этажом шахты: стоит этажом выше и поедет вниз сама.
func _car_above_the_bottom() -> ElevatorCar:
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	car.setup(PackedFloat32Array([0.0, Proportions.FLOOR]), 0)
	return car


func _ride_down(car: ElevatorCar) -> void:
	for _frame: int in RIDE_FRAMES:
		await wait_physics_frames(1)
		if car.global_position.y <= -Proportions.FLOOR + 0.01:
			break
	await wait_physics_frames(10)


func _count(kind: String) -> int:
	var found := 0
	for child: Node in get_children():
		if child.name.begins_with(kind):
			found += 1
	return found


func _pieces() -> Array[CorpsePiece]:
	var found: Array[CorpsePiece] = []
	for child: Node in get_children():
		if child is CorpsePiece:
			found.append(child as CorpsePiece)
	return found


## Убитый рядом с лежащим ложится на него, а не сквозь (решение 10).
func test_a_corpse_lands_on_another() -> void:
	_floor_at(0.0)
	var below: Enemy = await _corpse_at(Vector3(0.3, 0.02, 0.0), 1.0)
	await wait_physics_frames(SETTLE_FRAMES)
	var above: Enemy = await _corpse_at(Vector3(0.3, 0.3, 0.0), 1.0)
	await wait_physics_frames(SETTLE_FRAMES)
	assert_almost_eq(below.global_position.y, 0.0, 0.05, "нижний на полу")
	assert_gt(above.global_position.y, Proportions.PRONE * 0.7, "верхний лежит на нижнем")
	assert_true(above.corpse.at_rest, "и уснул там")


## Нижний пропал — верхний просыпается и падает на пол.
func test_the_pile_falls_when_the_bottom_corpse_is_gone() -> void:
	_floor_at(0.0)
	var below: Enemy = await _corpse_at(Vector3(0.3, 0.02, 0.0), 1.0)
	await wait_physics_frames(SETTLE_FRAMES)
	var above: Enemy = await _corpse_at(Vector3(0.3, 0.3, 0.0), 1.0)
	await wait_physics_frames(SETTLE_FRAMES)
	below.corpse.vanish()
	await wait_physics_frames(SETTLE_FRAMES)
	assert_almost_eq(above.global_position.y, 0.0, 0.05, "верхний упал на пол")


## Живой проходит сквозь трупы: слой трупов живые не видят.
func test_the_living_walk_through_corpses() -> void:
	_floor_at(0.0)
	var dead: Enemy = await _corpse_at(Vector3(0.0, 0.02, 0.0), 1.0)
	await wait_physics_frames(SETTLE_FRAMES)
	var alive: Enemy = await _agent_at(Vector3(-1.2, 0.02, 0.0))
	assert_false(alive.get_collision_mask_value(Corpse.LAYER), "у живого трупов в маске нет")
	assert_true(dead.get_collision_mask_value(Corpse.LAYER), "у трупа есть")


## Труп целиком под днищем пропадает, на полу остаётся пятно (решение 7).
func test_a_corpse_under_the_car_is_cut_away() -> void:
	_floor_at(-Proportions.FLOOR)
	var car := _car_above_the_bottom()
	# Лицом вправо тело ложится влево от ступней почти на рост: целиком под
	# кабиной оно, когда ступни у правой стенки.
	var feet := car.width() * 0.5 - 0.1
	var agent: Enemy = await _corpse_at(Vector3(feet, -Proportions.FLOOR + 0.02, 0.0), 1.0)
	await wait_physics_frames(SETTLE_FRAMES)
	await _ride_down(car)
	assert_true(agent.corpse.gone, "труп под днищем срезан целиком")
	assert_false(agent.visible, "и его не видно")
	assert_gt(_count("Puddle"), 0, "на полу пятно")


## Труп поперёк стенки кабины на дне срезан по стенке: снаружи он остался
## (решение 8).
func test_a_corpse_across_the_wall_is_cut_along_it() -> void:
	_floor_at(-Proportions.FLOOR)
	var car := _car_above_the_bottom()
	var wall := car.global_position.x - car.width() * 0.5
	# Ступни внутри у стенки, голова снаружи: навзничь, лицом вправо.
	var agent: Enemy = await _corpse_at(Vector3(wall + 0.2, -Proportions.FLOOR + 0.02, 0.0), 1.0)
	await wait_physics_frames(SETTLE_FRAMES)
	await _ride_down(car)
	assert_false(agent.corpse.gone, "снаружи тело осталось")
	assert_true(agent.visible, "и его видно")
	assert_lt(agent.corpse.span().y, wall + 0.01, "форма кончается у стенки")


## Без крови тело под днищем исчезает целиком, пятна нет.
func test_without_blood_a_corpse_under_the_car_vanishes() -> void:
	Blood.enabled = false
	_floor_at(-Proportions.FLOOR)
	var car := _car_above_the_bottom()
	var wall := car.global_position.x - car.width() * 0.5
	var agent: Enemy = await _corpse_at(Vector3(wall + 0.2, -Proportions.FLOOR + 0.02, 0.0), 1.0)
	await wait_physics_frames(SETTLE_FRAMES)
	await _ride_down(car)
	assert_true(agent.corpse.gone, "тело исчезло")
	assert_eq(_count("Puddle"), 0, "пятна нет")


## Кабина стоит на этаже, площадка слева вровень; труп поперёк порога.
func _corpse_across_the_threshold() -> Array:
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	car.setup(PackedFloat32Array([0.0, Proportions.FLOOR]), 0)
	# Кабина стоит, пока тело ложится: сама она тронулась бы через паузу этажа.
	car.hold(Engine.time_scale * SETTLE_FRAMES / 60.0 + 2.0)
	await wait_physics_frames(2)
	var wall := car.global_position.x - car.width() * 0.5
	_floor_at(car.global_position.y, 4.0, wall - 2.0)
	var agent: Enemy = await _corpse_at(Vector3(wall + 0.3, car.global_position.y + 0.02, 0.0), 1.0)
	await wait_physics_frames(SETTLE_FRAMES)
	return [car, agent, wall]


func _ride_away(car: ElevatorCar) -> void:
	var start := car.global_position.y
	for _frame: int in RIDE_FRAMES:
		await wait_physics_frames(1)
		if absf(car.global_position.y - start) > Proportions.FLOOR * 0.5:
			break


## Тело поперёк порога лежит спокойно, пока кабина стоит.
func test_a_corpse_across_a_standing_car_stays_put() -> void:
	var setup: Array = await _corpse_across_the_threshold()
	var agent := setup[1] as Enemy
	var wall := setup[2] as float
	var reach := agent.corpse.span()
	assert_lt(reach.x, wall, "одним концом на площадке")
	assert_gt(reach.y, wall, "другим в кабине")


## Кабина тронулась — тело рвётся по стенке: часть внутри едет с ней, часть
## снаружи лежит на площадке (решение 11).
func test_a_leaving_car_tears_the_corpse_across_its_wall() -> void:
	var setup: Array = await _corpse_across_the_threshold()
	var car := setup[0] as ElevatorCar
	var agent := setup[1] as Enemy
	var wall := setup[2] as float
	var floor_y := car.global_position.y
	await _ride_away(car)
	var pieces := _pieces()
	assert_eq(pieces.size(), 1, "оторван один кусок")
	assert_almost_eq(agent.global_position.y, floor_y, 0.05, "тело на площадке осталось")
	assert_lt(agent.corpse.span().y, wall + 0.01, "и кончается у стенки")
	if pieces.is_empty():
		return
	await get_tree().process_frame
	var piece := pieces[0]
	assert_gt(piece.corpse.span().x, wall - 0.01, "кусок — та часть, что в кабине")
	assert_almost_eq(piece.global_position.y, car.global_position.y, 0.08, "и едет с кабиной")


## Без крови тело не рвётся: съезжает целиком на опору середины.
func test_without_blood_a_leaving_car_does_not_tear() -> void:
	Blood.enabled = false
	var setup: Array = await _corpse_across_the_threshold()
	var car := setup[0] as ElevatorCar
	await _ride_away(car)
	assert_eq(_pieces().size(), 0, "кусков нет")


## Otto под днищем режется, как агент; воскресший — целый (решение 9).
func test_otto_under_the_car_is_cut_and_revives_whole() -> void:
	_floor_at(-Proportions.FLOOR)
	var car := _car_above_the_bottom()
	var otto := OTTO_SCENE.instantiate() as Otto
	add_child_autofree(otto)
	otto.global_position = Vector3(0.0, -Proportions.FLOOR, WorldSpace.PLAY_Z)
	await _ride_down(car)
	assert_true(otto.is_dead(), "раздавлен")
	assert_not_null(otto.car_cut, "и срезан днищем")
	otto.global_position = Vector3(3.0, -Proportions.FLOOR, WorldSpace.PLAY_Z)
	otto.revive()
	assert_null(otto.car_cut, "воскрес без среза")
	assert_eq(otto.figure.kept(), Vector2(-INF, INF), "и целым")
