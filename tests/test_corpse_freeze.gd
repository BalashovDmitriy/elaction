extends GutTest

## A settled body freezes (ADR-0044, decision 11).
##
## M24h measurement: twenty corpses with ragdolls did not fall asleep — in a pile neighbours woke
## each other. A frozen body is static: physics does not compute it, but others still
## lie on it, and it looks the same. If the support goes, the body again
## lives by physics ([method Ragdoll.wake]). One that fell out of the world disappears.

const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const CAR_SCENE := preload("res://src/systems/elevators/elevator_car.tscn")
## How many steps to give a body to lie down and freeze.
const SETTLE_FRAMES: int = 480
## How many steps to wait for the cab to reach the body: the pause plus the run.
const RIDE_FRAMES: int = 1200


func before_all() -> void:
	# As in test_enemy_corpse: the world is faster, the physics step smaller — otherwise the ragdoll
	# joints fly apart on a long step.
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240


func after_all() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Ragdoll.abyss = -INF
	GameState.instance().reset()


## Body pieces, splashes and stains are put into the scene by the cab, not the test: removed here.
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
	assert_true(await _wait_frozen(agent), "the settled body froze")
	var before := agent.corpse.ragdoll.bounds()
	await wait_physics_frames(60)
	var after := agent.corpse.ragdoll.bounds()
	assert_almost_eq(
		after.get_center().distance_to(before.get_center()), 0.0, 0.01, "and does not move"
	)
	assert_gt(after.position.y, -0.1, "lies on the floor, not under it")


func test_another_body_lies_on_a_frozen_one() -> void:
	_floor_at(0.0)
	var first: Enemy = await _corpse_at(Vector3.ZERO)
	assert_true(await _wait_frozen(first), "the first froze")
	var top := first.corpse.ragdoll.bounds().end.y
	var second: Enemy = await _corpse_at(Vector3(0.0, top + 0.3, 0.0))
	await wait_physics_frames(SETTLE_FRAMES / 2)
	# The second may also roll off the first onto the floor — that is not a failure. A failure is
	# lying above the frozen one, but below its top.
	# Measured by the second one's pelvis: the bounds of a body with spread arms and legs
	# overlap the neighbour even for one that rolled onto the floor.
	var lower := first.corpse.ragdoll.bounds()
	var pelvis := Ragdoll.center_of(second.corpse.ragdoll.parts["Body"] as PhysicalBone3D)
	if pelvis.x > lower.position.x + 0.1 and pelvis.x < lower.end.x - 0.1:
		assert_gt(
			pelvis.y,
			lower.position.y + 0.2,
			"the second lay on top instead of falling through the frozen one"
		)
	assert_gt(second.corpse.ragdoll.bounds().position.y, -0.1, "and did not go under the floor")


func test_a_frozen_body_wakes_when_its_floor_goes() -> void:
	var ground := _floor_at(0.0)
	var agent: Enemy = await _corpse_at(Vector3.ZERO)
	assert_true(await _wait_frozen(agent), "froze")
	ground.queue_free()
	await wait_physics_frames(2)
	agent.corpse.ragdoll.wake()
	assert_false(agent.corpse.ragdoll.is_frozen(), "woke up")
	var before := agent.corpse.ragdoll.bounds().position.y
	await wait_physics_frames(60)
	assert_lt(agent.corpse.ragdoll.bounds().position.y, before - 0.5, "and falls")


## A cab with two stops, with a floor [param width] m wide. It stands at the top
## until released ([method _let_go]).
func _held_car(width: float = ElevatorCar.DEFAULT_WIDTH) -> ElevatorCar:
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	car.fit_to_story(Proportions.CLEARANCE, width)
	car.floor_pause = 1000.0
	car.setup(PackedFloat32Array([0.0, Proportions.FLOOR]), 0)
	return car


## Lets the cab go down and waits until it arrives — and holds it there — or until
## [param done] returns true.
func _let_go(car: ElevatorCar, done: Callable = Callable()) -> void:
	car.floor_pause = 0.2
	car.setup(PackedFloat32Array([0.0, Proportions.FLOOR]), 0)
	for _frame: int in RIDE_FRAMES:
		await wait_physics_frames(1)
		if (done.is_valid() and done.call()) or car.global_position.y <= -Proportions.FLOOR + 0.01:
			break
	# An empty cab that arrived would stand a while and go back. A standing one is held, and
	# in the arrival frame it still reports movement.
	await wait_physics_frames(1)
	car.hold(1000.0)
	await wait_physics_frames(30)


## A pile of bodies on the floor of a stopped cab does not freeze and rides with it: a frozen one
## would hang in the air when the cab leaves. The upper body lies not only on the
## cab but also on the lower one.
func test_a_pile_in_a_standing_car_rides_on_with_it() -> void:
	# The cab floor is wider than a body: the pile lies on it entirely instead of hanging over.
	var car := _held_car(6.0)
	var below: Enemy = await _corpse_at(Vector3(0.0, 0.05, 0.0))
	await wait_physics_frames(SETTLE_FRAMES / 4)
	var top := below.corpse.ragdoll.bounds()
	var above: Enemy = await _corpse_at(Vector3(top.get_center().x, top.end.y + 0.3, 0.0))
	await wait_physics_frames(SETTLE_FRAMES)
	assert_false(above.corpse.ragdoll.is_frozen(), "the upper one above the car did not freeze")
	await _let_go(car)
	var floor_y := -Proportions.FLOOR
	assert_lt(
		below.corpse.ragdoll.bounds().position.y, floor_y + 0.5, "the lower one went with the car"
	)
	assert_lt(
		above.corpse.ragdoll.bounds().position.y, floor_y + 1.0, "and the upper one did not hang"
	)


## A body frozen in the shaft pit is still cut by the cab coming down: a frozen one is
## static, and the crush zone must see such bodies too.
func test_a_frozen_body_in_a_shaft_pit_is_still_cut() -> void:
	GameState.instance().start_game()
	_floor_at(-Proportions.FLOOR)
	var car := _held_car()
	var agent: Enemy = await _corpse_at(Vector3(0.0, -Proportions.FLOOR, 0.0))
	assert_true(await _wait_frozen(agent), "in the pit the body froze")
	await _let_go(car, func() -> bool: return agent.corpse.cut != null or agent.corpse.gone)
	assert_true(agent.corpse.cut != null or agent.corpse.gone, "the car cuts it with its underside")


func test_a_body_fallen_out_of_the_world_is_gone() -> void:
	Ragdoll.abyss = -5.0
	var agent: Enemy = await _corpse_at(Vector3.ZERO)
	for _frame: int in SETTLE_FRAMES:
		await wait_physics_frames(1)
		if agent.corpse.gone:
			break
	assert_true(agent.corpse.gone, "a body fallen below the world vanished")
	Ragdoll.abyss = -INF
