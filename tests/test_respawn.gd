extends GutTest

## Otto's return after death and the agent crowd by ROM rules (ADR-0053, decisions 2
## and 5): without a scene and on any building that gets generated.

const SKILLS: Array[int] = [0, 5, 10]
const SEEDS: Array[int] = [1, 2, 3, 5, 8, 13, 21, 34]


## Below the ROM's fifth floor Otto does not return, and above it he returns to his own.
func test_the_respawn_floor_is_never_below_the_fifth() -> void:
	for floors: int in [6, 12, 30]:
		var rules := BuildingRules.new()
		rules.floors = floors
		for index in range(BuildingRules.ROOF, floors):
			var back := RespawnSpot.floor_for(rules, index)
			var rom := Arcade.rom_floor(back, floors)
			assert_true(
				rom >= Arcade.RESPAWN_FROM_FLOOR or back == BuildingRules.ROOF,
				"этажей %d: с %d — на %d, этаж ROM %d" % [floors, index, back, rom]
			)
			if Arcade.rom_floor(index, floors) >= Arcade.RESPAWN_FROM_FLOOR:
				assert_eq(back, index, "этажей %d: с %d увело зря" % [floors, index])
			else:
				assert_lt(back, index, "этажей %d: с %d не подняло" % [floors, index])


## On any floor of any building the return point is a place where one can stand, and
## not in a pocket if the floor has a piece wider than the pocket.
func test_the_respawn_spot_is_safe_on_any_building() -> void:
	for skill in SKILLS:
		var rules := BuildingRules.new()
		rules.skill = skill
		for building_seed in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			for index in range(0, rules.floors):
				var spots := plan.safe_spots(rules, index)
				if spots.is_empty():
					continue
				var x := RespawnSpot.choose(plan, rules, index, NAN)
				var where := "навык %d, сид %d, этаж %d" % [skill, building_seed, index]
				assert_true(spots.has(x), "%s: x=%.2f не место" % [where, x])
				var open := RespawnSpot._off_pockets(plan, rules, index, spots)
				if not open.is_empty():
					assert_true(open.has(x), "%s: x=%.2f в кармане" % [where, x])


## If the floor has a red door with a document, Otto stands by it (@2FAA).
func test_otto_comes_back_at_the_red_door() -> void:
	var checked := 0
	for skill in SKILLS:
		var rules := BuildingRules.new()
		rules.skill = skill
		for building_seed in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			for door in plan.doors:
				if not door.has_document:
					continue
				var x := RespawnSpot.choose(plan, rules, door.floor_index, door.x)
				var nearest := INF
				for spot: float in plan.safe_spots(rules, door.floor_index):
					nearest = minf(nearest, absf(spot - door.x))
				assert_almost_eq(
					absf(x - door.x),
					nearest,
					0.001,
					"навык %d, сид %d: не у красной двери" % [skill, building_seed]
				)
				checked += 1
	assert_gt(checked, 0, "красных дверей не нашлось — тест ничего не проверил")


## After death the slots are free and release in turn: 10, 25, 40, 55 ticks.
func test_the_slots_come_back_one_after_another() -> void:
	var spawn := AgentSpawn.new()
	for slot in AgentSpawn.SLOTS:
		spawn.take(slot)
	spawn.after_death()
	var opened: Array[float] = []
	var elapsed := 0.0
	while elapsed < 5.0 and opened.size() < AgentSpawn.SLOTS:
		spawn.tick(Arcade.TICK)
		elapsed += Arcade.TICK
		var slot := spawn.open_slot(AgentSpawn.SLOTS)
		if slot >= 0:
			opened.append(elapsed)
			spawn.take(slot)
	assert_eq(opened.size(), AgentSpawn.SLOTS, "открылись не все ячейки")
	for index in opened.size():
		var due := Arcade.seconds(Arcade.RESPAWN_WAIT_TICKS[index])
		assert_almost_eq(opened[index], due, Arcade.TICK, "ячейка %d" % index)


## Crowd: from three agents on a floor the extra ones leave, two stay; below the ROM's
## eighth floor — nobody.
func test_the_crowd_sends_the_extra_agents_away() -> void:
	assert_eq(Arcade.crowd_leavers(20, 2), 0, "двое — не толпа")
	assert_eq(Arcade.crowd_leavers(20, 3), 1, "из трёх уходит один")
	assert_eq(Arcade.crowd_leavers(20, 4), 2, "из четырёх — двое")
	assert_eq(Arcade.crowd_leavers(Arcade.LEAVE_FROM_FLOOR - 1, 4), 0, "низ здания не в счёт")


## Crowd in a scene: of three agents on Otto's floor the farthest leaves, the two
## nearest stay; a floor beyond Otto's band the crowd does not count.
func test_the_farthest_of_a_crowd_goes_to_a_door() -> void:
	var rules := BuildingRules.new()
	var here := 5
	var surface := rules.floor_surface(here)
	var crowd: Array[Enemy] = []
	for x: float in [2.0, 4.0, 9.0]:
		var agent := preload("res://src/actors/enemy/enemy.tscn").instantiate() as Enemy
		# They come out of the opening instantly: one who came out of a door in a crowd
		# does not count.
		agent.emerge_time = 0.0
		agent.walk_speed = 0.0
		add_child_autofree(agent)
		agent.global_position = WorldSpace.to_scene(Vector2(x, surface))
		crowd.append(agent)
	await wait_physics_frames(2)
	for agent in crowd:
		assert_false(agent.is_emerging(), "агент так и не вышел из проёма")
	var otto_x := WorldSpace.to_scene(Vector2(1.0, surface)).x
	var extras := AgentCrowd.extras(crowd, rules, here, otto_x)
	assert_eq(extras.size(), 1, "уходит один из трёх")
	assert_true(extras.has(crowd[2]), "уходит дальний от Otto")
	assert_true(AgentCrowd.extras(crowd, rules, here + 2, otto_x).is_empty(), "не у Otto")
	# A leaving agent stays leaving even if it becomes one of the nearest on the way:
	# otherwise leaving would pass from agent to agent every frame, and the crowd would
	# not thin out.
	var still := AgentCrowd.extras(crowd, rules, here, otto_x, {crowd[0]: true})
	assert_eq(still.size(), 1, "уходит всё так же один")
	assert_true(still.has(crowd[0]), "уходящего отозвали ради дальнего")
