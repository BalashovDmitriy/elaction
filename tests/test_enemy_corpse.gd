extends GutTest

## An agent's corpse lies until the end of the building as a body on joints (ADR-0037,
## decision 6; ADR-0043, decision 12).
##
## The body is not a target, falls from the hit along the bullet's path, lies on the
## floor and not under it, falls into an empty shaft and rides on the floor of the cab it
## was killed in. Once settled, it sleeps: corpses cost the frame nothing until the end
## of the building.

const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const CAR_SCENE := preload("res://src/systems/elevators/elevator_car.tscn")

## How many physics steps to wait for the body to settle.
const SETTLE_FRAMES: int = 150

## How many physics steps to wait for the cab to start and move off: the pause at the
## floor plus the run, with margin.
const RIDE_FRAMES: int = 600


func before_all() -> void:
	# The world is four times faster, but the physics step is the same: on a step four
	# times longer the ragdoll's joints fly apart and the body falls through the floor.
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


## An agent who came out of the opening and stands still: one coming out cannot be killed.
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
	assert_true(is_instance_valid(agent), "the body did not vanish")
	assert_true(agent.corpse.fallen, "and fell")
	assert_false(
		agent.is_physics_processing(), "the agent physics is off - the parts drive the body"
	)
	assert_false(agent.get_node("Body").is_processing(), "the pose too")
	var box := agent.corpse.ragdoll.bounds()
	assert_gt(box.position.y, -0.1, "lies on the floor, not under it")
	assert_lt(box.end.y, 0.6, "and lies, not stands")
	assert_true(agent.corpse.ragdoll.asleep(), "and settled")
	assert_eq(agent.collision_layer, 0, "the corpse is not a target")


## A bullet from the left drops the body to the right: along its path.
func test_a_bullet_throws_the_body_along_its_flight() -> void:
	_floor_at(0.0)
	var agent: Enemy = await _agent_at(Vector3.ZERO)
	agent.set_meta(Corpse.HIT_META, 1.0)
	agent.kill()
	await wait_physics_frames(SETTLE_FRAMES)
	assert_gt(agent.corpse.ragdoll.bounds().get_center().x, 0.2, "the body fell to the right")


## One killed in a cab rides with it on its floor. He stands at the right wall and falls
## on his back to the left: a body nearly as long as the cab lies in it entirely.
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
	assert_gt(absf(car.global_position.y - start), Proportions.FLOOR * 0.5, "the car moved away")
	var now := agent.corpse.ragdoll.bounds().position.y - car.global_position.y
	assert_almost_eq(now, gap, 0.25, "and the corpse with it, on its floor")


## One killed over an empty shaft falls to its bottom.
func test_a_corpse_over_an_empty_shaft_falls_to_the_bottom() -> void:
	_floor_at(-Proportions.FLOOR * 2.0)
	var agent: Enemy = await _agent_at(Vector3(0.0, 0.05, 0.0))
	agent.kill()
	await wait_physics_frames(SETTLE_FRAMES * 2)
	var bottom := agent.corpse.ragdoll.bounds().position.y
	assert_almost_eq(bottom, -Proportions.FLOOR * 2.0, 0.1, "lies on the bottom")


## One finished off by a takedown falls when the takedown releases him, not earlier.
func test_a_held_corpse_falls_when_released() -> void:
	_floor_at(0.0)
	var agent: Enemy = await _agent_at(Vector3.ZERO)
	agent.held = true
	agent.kill(false, "knocked")
	assert_false(agent.corpse.fallen, "while the scene holds it, the body is not in physics")
	agent.held = false
	assert_true(agent.corpse.fallen, "released - it fell")
