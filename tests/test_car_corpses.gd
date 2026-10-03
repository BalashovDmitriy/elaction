extends GutTest

## Corpses in a cab do not interfere with controlling it (M24f).
##
## Feedback after playing: "if there are two agent corpses in the elevator, the elevator
## can no longer be controlled" — Otto is in the cab, the arrows do not work. Tests could
## not reproduce it; since M24f corpses do not move into the cab's node but lie on its
## floor as a physical body (ADR-0042, decision 1), and the tests guard that the cab
## obeys with them.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")

const SETTLE_FRAMES: int = 4
const LIE_FRAMES: int = 120
const DRIVE_FRAMES: int = 60
const MOVED: float = 0.2


func before_all() -> void:
	Engine.time_scale = 1.0


func after_all() -> void:
	GameState.instance().reset()


func _build(building_seed: int) -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = building_seed
	level.spawn_agents = false
	add_child_autofree(level)
	return level


func _first_car(level: GreyboxLevel) -> ElevatorCar:
	for child: Node in level.get_children():
		var car := child as ElevatorCar
		if car != null and not car.is_deck():
			return car
	return null


func _agent_at(level: GreyboxLevel, at: Vector3) -> Enemy:
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.walk_speed = 0.0
	level.add_child(agent)
	agent.global_position = at
	agent.setup(null, 1.0)
	while agent.is_emerging():
		await wait_physics_frames(1)
	return agent


func _drive(action: StringName) -> void:
	Input.action_press(action)
	await wait_physics_frames(DRIVE_FRAMES)
	Input.action_release(action)
	await wait_physics_frames(1)


func _moves_with(level: GreyboxLevel, car: ElevatorCar, corpses: int) -> float:
	var shaft: BuildingPlan.ShaftSpot = level.plan().shafts[0]
	var stops := PackedFloat32Array()
	for floor_index: int in range(shaft.top, shaft.bottom + 1):
		stops.append(level.rules.floor_surface(floor_index))
	# Middle of the band: there is somewhere to go both up and down.
	car.setup(stops, (shaft.bottom - shaft.top) / 2)
	await wait_physics_frames(1)
	level.otto.global_position = car.global_position
	level.otto.velocity = Vector3.ZERO
	await wait_physics_frames(SETTLE_FRAMES)
	for index: int in corpses:
		var side := -0.4 if index % 2 == 0 else 0.4
		var agent: Enemy = await _agent_at(level, car.global_position + Vector3(side, 0.05, 0.0))
		agent.kill()
	await wait_physics_frames(LIE_FRAMES)
	var start := car.global_position.y
	await _drive(&"move_down")
	return absf(car.global_position.y - start)


func test_the_car_obeys_with_two_corpses_inside() -> void:
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)
	var car := _first_car(level)
	var moved := await _moves_with(level, car, 2)
	assert_true(car.has_rider(), "Otto in the car")
	assert_gt(moved, MOVED, "the car obeys even with two corpses")


## All cabs of three buildings: Otto gets in where corpses already lie.
func test_every_car_obeys_after_corpses_rode_in_it() -> void:
	for building_seed: int in [1, 2, 3]:
		var level := _build(building_seed)
		await wait_physics_frames(SETTLE_FRAMES)
		var cars: Array[ElevatorCar] = []
		for child: Node in level.get_children():
			var found := child as ElevatorCar
			if found != null and not found.is_deck():
				cars.append(found)
		for car: ElevatorCar in cars:
			for index: int in 2:
				var side := -0.4 if index == 0 else 0.4
				var agent: Enemy = await _agent_at(
					level, car.global_position + Vector3(side, 0.05, 0.0)
				)
				agent.kill()
			await wait_physics_frames(LIE_FRAMES)
			level.otto.global_position = car.global_position
			level.otto.velocity = Vector3.ZERO
			await wait_physics_frames(SETTLE_FRAMES)
			var start := car.global_position.y
			await _drive(&"move_down")
			var moved := absf(car.global_position.y - start)
			if moved < MOVED:
				start = car.global_position.y
				await _drive(&"move_up")
				moved = absf(car.global_position.y - start)
			assert_gt(moved, MOVED, "seed %d, car %s obeys" % [building_seed, car.name])
		level.queue_free()
		await wait_physics_frames(2)


## Two takedowns from above inside the cab — and the cab still obeys.
func test_the_car_obeys_after_takedowns_inside() -> void:
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)
	var car := _first_car(level)
	var shaft: BuildingPlan.ShaftSpot = level.plan().shafts[0]
	var stops := PackedFloat32Array()
	for floor_index: int in range(shaft.top, shaft.bottom + 1):
		stops.append(level.rules.floor_surface(floor_index))
	car.setup(stops, (shaft.bottom - shaft.top) / 2)
	await wait_physics_frames(1)
	level.otto.global_position = car.global_position
	level.otto.velocity = Vector3.ZERO
	await wait_physics_frames(SETTLE_FRAMES)
	for index: int in 2:
		var agent: Enemy = await _agent_at(level, car.global_position + Vector3(0.3, 0.05, 0.0))
		var rng := RandomNumberGenerator.new()
		TakedownScene.play(level.otto, agent, Takedown.pick(Takedown.Side.ABOVE, "", rng))
		while level.otto.takedown != null:
			await wait_physics_frames(1)
	await wait_physics_frames(LIE_FRAMES)
	var start := car.global_position.y
	await _drive(&"move_down")
	assert_gt(absf(car.global_position.y - start), MOVED, "the car obeys after takedowns")
