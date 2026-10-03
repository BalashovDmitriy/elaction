extends GutTest

## The cab cuts bodies, corpses lie on top of each other (ADR-0043, decisions 7–12).
##
## With its bottom from above the cab cuts off what is under it, with its wall it tears a body
## across the threshold when it starts. Without blood it does not cut: a body under the bottom
## disappears, while at the threshold the joints pull it. The scene is minimal — floor, cab, body.

const CAR_SCENE := preload("res://src/systems/elevators/elevator_car.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")

## How many physics steps to wait for a body to lie down.
const SETTLE_FRAMES: int = 120
## How many physics steps to wait for the cab to arrive: the pause at a floor plus
## the run, with margin.
const RIDE_FRAMES: int = 600


func before_all() -> void:
	# The world is four times faster, but the physics step is the same: on a four times longer step
	# the ragdoll joints fly apart, and the body falls through the floor.
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


## Body pieces, splashes and stains are put into the scene by the cab, not the test: removed here.
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


## Killed at point [param at], thrown by a bullet toward [param push].
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


## A cab above the shaft's bottom floor: it stands a floor higher and will go down on its own.
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


## Middles of body parts along X.
func _centers(corpse: Corpse) -> PackedFloat32Array:
	var found := PackedFloat32Array()
	for part: PhysicalBone3D in corpse.ragdoll.parts.values():
		found.append(Ragdoll.center_of(part).x)
	return found


## One killed above a lying one lies on top of it, not through it (decision 10).
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


## The lower one is gone — the upper one falls to the floor.
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


## The living do not see corpses: their mask has no corpse layer.
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


## A corpse fully under the bottom disappears, a stain stays on the floor (decision 7).
## The cab is twice as wide as the shaft: a lying body is longer than a regular one.
func test_a_corpse_under_the_car_is_cut_away() -> void:
	_floor_at(-Proportions.FLOOR)
	var car := _car_above_the_bottom()
	car.fit_to_story(ElevatorCar.DEFAULT_CLEAR_HEIGHT, 4.0)
	var agent: Enemy = await _corpse_at(Vector3(0.0, -Proportions.FLOOR + 0.02, 0.0))
	await wait_physics_frames(SETTLE_FRAMES)
	await _ride_down(car)
	assert_true(agent.corpse.gone, "труп под днищем срезан целиком")
	assert_gt(_count("Puddle"), 0, "на полу пятно")


## A corpse lying across the cab wall at the bottom is cut along the wall: outside it stays
## (decision 8).
func test_a_corpse_across_the_wall_is_cut_along_it() -> void:
	_floor_at(-Proportions.FLOOR)
	var car := _car_above_the_bottom()
	var wall := car.global_position.x - car.width() * 0.5
	var agent: Enemy = await _corpse_at(Vector3(wall + 0.3, -Proportions.FLOOR + 0.02, 0.0), -1.0)
	await wait_physics_frames(SETTLE_FRAMES)
	await _ride_down(car)
	# Physics pushes a part pressed against the bottom out from under the cab in more than a step.
	await wait_physics_frames(SETTLE_FRAMES)
	assert_false(agent.corpse.gone, "снаружи тело осталось")
	# The middle of a part at the wall is a capsule radius from it: the part is pressed from outside.
	for x: float in _centers(agent.corpse):
		assert_lt(x, wall + 0.1, "осталось только то, что снаружи")


## Without blood a body under the bottom disappears entirely, no stain.
func test_without_blood_a_corpse_under_the_car_vanishes() -> void:
	Blood.enabled = false
	_floor_at(-Proportions.FLOOR)
	var car := _car_above_the_bottom()
	var agent: Enemy = await _corpse_at(Vector3(0.0, -Proportions.FLOOR + 0.02, 0.0))
	await wait_physics_frames(SETTLE_FRAMES)
	await _ride_down(car)
	assert_true(agent.corpse.gone, "тело исчезло")
	assert_eq(_count("Puddle"), 0, "пятна нет")


## The cab stands at a floor, the landing on the left is level; a corpse across the threshold:
## feet in the cab, head on the landing.
func _corpse_across_the_threshold() -> Array:
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	car.setup(PackedFloat32Array([0.0, Proportions.FLOOR]), 0)
	# The cab stands still while the body lies down: on its own it would start after the floor pause.
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


## A body across the threshold lies while the cab stands.
func test_a_corpse_lies_across_a_standing_car() -> void:
	var setup: Array = await _corpse_across_the_threshold()
	var agent := setup[1] as Enemy
	var wall := setup[2] as float
	var reach := agent.corpse.span()
	assert_lt(reach.x, wall, "одним концом на площадке")
	assert_gt(reach.y, wall, "другим в кабине")


## The cab has started — the body tears along the wall: parts inside ride with it, parts
## outside lie on the landing (decision 11).
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


## Without blood the body does not tear.
func test_without_blood_a_leaving_car_does_not_tear() -> void:
	Blood.enabled = false
	var setup: Array = await _corpse_across_the_threshold()
	await _ride_away(setup[0] as ElevatorCar)
	assert_eq(_pieces().size(), 0, "кусков нет")


## A cab going up pins a body on its roof under the top of the shaft: the body
## is gone, instead of sticking through the roof and the slab at once (ADR-0042).
func test_a_corpse_on_the_roof_is_squeezed_away_at_the_shaft_top() -> void:
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	# Stands at the bottom and will go up on its own.
	car.setup(PackedFloat32Array([0.0, Proportions.FLOOR]), 1)
	car.hold(Engine.time_scale * SETTLE_FRAMES / 60.0 + 1.0)
	await wait_physics_frames(2)
	# Top of the shaft: the slab underside is 0.12 m above the cab roof at the top stop,
	# thinner than a lying body.
	_floor_at(ElevatorCar.DEFAULT_CLEAR_HEIGHT + 0.12 + 0.4)
	var roof := car.global_position.y + ElevatorCar.DEFAULT_CLEAR_HEIGHT
	var agent: Enemy = await _corpse_at(Vector3(car.global_position.x, roof + 0.02, 0.0))
	await wait_physics_frames(SETTLE_FRAMES)
	assert_false(agent.corpse.gone, "на крыше тело лежит")
	for _frame: int in RIDE_FRAMES:
		await wait_physics_frames(1)
		if car.global_position.y >= -0.01 and is_zero_approx(car.speed_now()):
			break
	assert_almost_eq(car.global_position.y, 0.0, 0.02, "кабина дошла до верха")
	assert_true(agent.corpse.gone, "зажатого тела нет")


## Otto under the bottom is cut like an agent; resurrected — whole (decisions 9 and 12).
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
