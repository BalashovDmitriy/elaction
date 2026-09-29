extends GutTest

## Кабина режет тела, трупы ложатся друг на друга (ADR-0043, решения 7–12).
##
## Днищем сверху кабина срезает то, что под ней, стенкой — рвёт тело поперёк
## порога, когда трогается. Без крови не режет: тело под днищем исчезает, а с
## порога его тянут суставы. Сцена минимальная — пол, кабина, тело.

const CAR_SCENE := preload("res://src/systems/elevators/elevator_car.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")

## Сколько шагов физики ждать, пока тело ляжет.
const SETTLE_FRAMES: int = 120
## Сколько шагов физики ждать, пока кабина доедет: пауза у этажа плюс
## перегон, с запасом.
const RIDE_FRAMES: int = 600


func before_all() -> void:
	# Мир вчетверо быстрее, а шаг физики прежний: на вчетверо длинном шаге
	# суставы рэгдолла разлетаются, и тело проваливается сквозь пол.
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240


func after_all() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Blood.enabled = true
	GameState.instance().reset()


func before_each() -> void:
	Blood.enabled = true
	GameState.instance().start_game()


## Куски тел, брызги и пятна кладёт в сцену кабина, а не тест: убираются тут.
func after_each() -> void:
	for child: Node in get_children():
		if child is CorpsePiece or child is Decal or child is Blood:
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


## Убитый в точке [param at], отброшенный пулей в сторону [param push].
func _corpse_at(at: Vector3, push: float = 0.0) -> Enemy:
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.walk_speed = 0.0
	add_child_autofree(agent)
	agent.global_position = at
	agent.setup(null, 1.0)
	while agent.is_emerging():
		await wait_physics_frames(1)
	if push != 0.0:
		agent.set_meta(Corpse.HIT_META, push)
	agent.kill()
	return agent


## Кабина над нижним этажом шахты: стоит этажом выше и поедет вниз сама.
func _car_above_the_bottom() -> ElevatorCar:
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	car.setup(PackedFloat32Array([0.0, Proportions.FLOOR]), 0)
	car.hold(Engine.time_scale * SETTLE_FRAMES / 60.0 + 1.0)
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


## Середины частей тела по X.
func _centers(corpse: Corpse) -> PackedFloat32Array:
	var found := PackedFloat32Array()
	for part: PhysicalBone3D in corpse.ragdoll.parts.values():
		found.append(Ragdoll.center_of(part).x)
	return found


## Убитый над лежащим ложится на него, а не сквозь (решение 10).
func test_a_corpse_lands_on_another() -> void:
	_floor_at(0.0)
	var below: Enemy = await _corpse_at(Vector3(0.0, 0.02, 0.0))
	await wait_physics_frames(SETTLE_FRAMES)
	var under := below.corpse.ragdoll.bounds()
	var above: Enemy = await _corpse_at(Vector3(under.get_center().x, 0.6, 0.0))
	await wait_physics_frames(SETTLE_FRAMES)
	var pelvis_below := Ragdoll.center_of(below.corpse.ragdoll.parts["Body"] as PhysicalBone3D)
	var pelvis_above := Ragdoll.center_of(above.corpse.ragdoll.parts["Body"] as PhysicalBone3D)
	assert_gt(pelvis_above.y, pelvis_below.y + 0.05, "верхний лежит на нижнем, а не сквозь")


## Нижний пропал — верхний падает на пол.
func test_the_pile_falls_when_the_bottom_corpse_is_gone() -> void:
	_floor_at(0.0)
	var below: Enemy = await _corpse_at(Vector3(0.0, 0.02, 0.0))
	await wait_physics_frames(SETTLE_FRAMES)
	var above: Enemy = await _corpse_at(
		Vector3(below.corpse.ragdoll.bounds().get_center().x, 0.6, 0.0)
	)
	await wait_physics_frames(SETTLE_FRAMES)
	below.corpse.vanish()
	await wait_physics_frames(SETTLE_FRAMES)
	assert_lt(above.corpse.ragdoll.bounds().position.y, 0.08, "верхний упал на пол")


## Живые трупов не видят: у них в маске нет слоя трупов.
func test_the_living_walk_through_corpses() -> void:
	_floor_at(0.0)
	var dead: Enemy = await _corpse_at(Vector3(0.0, 0.02, 0.0))
	var part := dead.corpse.ragdoll.parts.values()[0] as PhysicalBone3D
	var alive := ENEMY_SCENE.instantiate() as Enemy
	add_child_autofree(alive)
	var otto := OTTO_SCENE.instantiate() as Otto
	add_child_autofree(otto)
	assert_eq(alive.collision_mask & part.collision_layer, 0, "агент сквозь трупы")
	assert_eq(otto.collision_mask & part.collision_layer, 0, "Otto сквозь трупы")


## Труп целиком под днищем пропадает, на полу остаётся пятно (решение 7).
## Кабина вдвое шире шахты: лежащее тело длиннее обычной.
func test_a_corpse_under_the_car_is_cut_away() -> void:
	_floor_at(-Proportions.FLOOR)
	var car := _car_above_the_bottom()
	car.fit_to_story(ElevatorCar.DEFAULT_CLEAR_HEIGHT, 4.0)
	var agent: Enemy = await _corpse_at(Vector3(0.0, -Proportions.FLOOR + 0.02, 0.0))
	await wait_physics_frames(SETTLE_FRAMES)
	await _ride_down(car)
	assert_true(agent.corpse.gone, "труп под днищем срезан целиком")
	assert_gt(_count("Puddle"), 0, "на полу пятно")


## Труп поперёк стенки кабины на дне срезан по стенке: снаружи он остался
## (решение 8).
func test_a_corpse_across_the_wall_is_cut_along_it() -> void:
	_floor_at(-Proportions.FLOOR)
	var car := _car_above_the_bottom()
	var wall := car.global_position.x - car.width() * 0.5
	var agent: Enemy = await _corpse_at(Vector3(wall + 0.3, -Proportions.FLOOR + 0.02, 0.0), -1.0)
	await wait_physics_frames(SETTLE_FRAMES)
	await _ride_down(car)
	# Прижатую к днищу часть физика выталкивает из-под кабины не за шаг.
	await wait_physics_frames(SETTLE_FRAMES)
	assert_false(agent.corpse.gone, "снаружи тело осталось")
	# Середина части у стенки — на радиус капсулы от неё: часть прижата снаружи.
	for x: float in _centers(agent.corpse):
		assert_lt(x, wall + 0.1, "осталось только то, что снаружи")


## Без крови тело под днищем исчезает целиком, пятна нет.
func test_without_blood_a_corpse_under_the_car_vanishes() -> void:
	Blood.enabled = false
	_floor_at(-Proportions.FLOOR)
	var car := _car_above_the_bottom()
	var agent: Enemy = await _corpse_at(Vector3(0.0, -Proportions.FLOOR + 0.02, 0.0))
	await wait_physics_frames(SETTLE_FRAMES)
	await _ride_down(car)
	assert_true(agent.corpse.gone, "тело исчезло")
	assert_eq(_count("Puddle"), 0, "пятна нет")


## Кабина стоит на этаже, площадка слева вровень; труп поперёк порога:
## ступни в кабине, голова на площадке.
func _corpse_across_the_threshold() -> Array:
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	car.setup(PackedFloat32Array([0.0, Proportions.FLOOR]), 0)
	# Кабина стоит, пока тело ложится: сама она тронулась бы через паузу этажа.
	car.hold(Engine.time_scale * SETTLE_FRAMES / 60.0 + 1.0)
	await wait_physics_frames(2)
	var wall := car.global_position.x - car.width() * 0.5
	_floor_at(car.global_position.y, 4.0, wall - 2.0)
	var agent: Enemy = await _corpse_at(
		Vector3(wall + 0.35, car.global_position.y + 0.02, 0.0), -1.0
	)
	await wait_physics_frames(SETTLE_FRAMES - 10)
	return [car, agent, wall]


func _ride_away(car: ElevatorCar) -> void:
	var start := car.global_position.y
	for _frame: int in RIDE_FRAMES:
		await wait_physics_frames(1)
		if absf(car.global_position.y - start) > Proportions.FLOOR * 0.5:
			break


## Тело поперёк порога лежит, пока кабина стоит.
func test_a_corpse_lies_across_a_standing_car() -> void:
	var setup: Array = await _corpse_across_the_threshold()
	var agent := setup[1] as Enemy
	var wall := setup[2] as float
	var reach := agent.corpse.span()
	assert_lt(reach.x, wall, "одним концом на площадке")
	assert_gt(reach.y, wall, "другим в кабине")


## Кабина тронулась — тело рвётся по стенке: части внутри едут с ней, части
## снаружи лежат на площадке (решение 11).
func test_a_leaving_car_tears_the_corpse_across_its_wall() -> void:
	var setup: Array = await _corpse_across_the_threshold()
	var car := setup[0] as ElevatorCar
	var agent := setup[1] as Enemy
	var wall := setup[2] as float
	var floor_y := car.global_position.y
	await _ride_away(car)
	var pieces := _pieces()
	assert_eq(pieces.size(), 1, "оторван один кусок")
	for x: float in _centers(agent.corpse):
		assert_lt(x, wall + 0.1, "на площадке — то, что было снаружи")
	assert_almost_eq(agent.corpse.ragdoll.bounds().position.y, floor_y, 0.15, "и лежит на ней")
	if pieces.is_empty():
		return
	var piece := pieces[0].corpse.ragdoll.bounds()
	assert_lt(piece.end.y, floor_y - 1.0, "кусок уехал вниз вместе с кабиной")


## Без крови тело не рвётся.
func test_without_blood_a_leaving_car_does_not_tear() -> void:
	Blood.enabled = false
	var setup: Array = await _corpse_across_the_threshold()
	await _ride_away(setup[0] as ElevatorCar)
	assert_eq(_pieces().size(), 0, "кусков нет")


## Otto под днищем режется, как агент; воскресший — целый (решения 9 и 12).
func test_otto_under_the_car_is_cut_and_revives_whole() -> void:
	_floor_at(-Proportions.FLOOR)
	var car := _car_above_the_bottom()
	var otto := OTTO_SCENE.instantiate() as Otto
	add_child_autofree(otto)
	otto.global_position = Vector3(0.0, -Proportions.FLOOR, WorldSpace.PLAY_Z)
	await _ride_down(car)
	assert_true(otto.is_dead(), "раздавлен")
	assert_not_null(otto.corpse.cut, "и срезан днищем")
	otto.global_position = Vector3(3.0, -Proportions.FLOOR, WorldSpace.PLAY_Z)
	otto.revive()
	assert_false(otto.corpse.fallen, "воскрес на ногах")
	assert_eq(otto.corpse.ragdoll.parts.size(), Ragdoll.PARTS.size(), "и целым")
