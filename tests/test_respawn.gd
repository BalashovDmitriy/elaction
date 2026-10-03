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
				"floors %d: from %d to %d, ROM floor %d" % [floors, index, back, rom]
			)
			if Arcade.rom_floor(index, floors) >= Arcade.RESPAWN_FROM_FLOOR:
				assert_eq(back, index, "floors %d: from %d moved needlessly" % [floors, index])
			else:
				assert_lt(back, index, "floors %d: from %d did not move up" % [floors, index])


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
				var where := "skill %d, seed %d, floor %d" % [skill, building_seed, index]
				assert_true(spots.has(x), "%s: x=%.2f is not a slot" % [where, x])
				var open := RespawnSpot._off_pockets(plan, rules, index, spots)
				if not open.is_empty():
					assert_true(open.has(x), "%s: x=%.2f in a pocket" % [where, x])


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
					"skill %d, seed %d: not at a red door" % [skill, building_seed]
				)
				checked += 1
	assert_gt(checked, 0, "no red doors found - the test checked nothing")


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
	assert_eq(opened.size(), AgentSpawn.SLOTS, "not all slots opened")
	for index in opened.size():
		var due := Arcade.seconds(Arcade.RESPAWN_WAIT_TICKS[index])
		assert_almost_eq(opened[index], due, Arcade.TICK, "slot %d" % index)


## Crowd: from three agents on a floor the extra ones leave, two stay; below the ROM's
## eighth floor — nobody.
func test_the_crowd_sends_the_extra_agents_away() -> void:
	assert_eq(Arcade.crowd_leavers(20, 2), 0, "two is not a crowd")
	assert_eq(Arcade.crowd_leavers(20, 3), 1, "one of three leaves")
	assert_eq(Arcade.crowd_leavers(20, 4), 2, "of four - two")
	assert_eq(
		Arcade.crowd_leavers(Arcade.LEAVE_FROM_FLOOR - 1, 4),
		0,
		"the bottom of the building does not count"
	)


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
		assert_false(agent.is_emerging(), "the agent never came out of the opening")
	var otto_x := WorldSpace.to_scene(Vector2(1.0, surface)).x
	var extras := AgentCrowd.extras(crowd, rules, here, otto_x)
	assert_eq(extras.size(), 1, "one of three leaves")
	assert_true(extras.has(crowd[2]), "the one farthest from Otto leaves")
	assert_true(AgentCrowd.extras(crowd, rules, here + 2, otto_x).is_empty(), "not next to Otto")
	# A leaving agent stays leaving even if it becomes one of the nearest on the way:
	# otherwise leaving would pass from agent to agent every frame, and the crowd would
	# not thin out.
	var still := AgentCrowd.extras(crowd, rules, here, otto_x, {crowd[0]: true})
	assert_eq(still.size(), 1, "still just one leaves")
	assert_true(still.has(crowd[0]), "the leaver was recalled in favour of the farther one")


## Just after Otto's return a door on his floor does not release an agent closer than
## [member BuildingRules.agent_respawn_gap]; when the calm is over, the usual gap holds
## (fix/bot-determinism, user's choice — the ROM has no distance check).
func test_doors_near_otto_stay_shut_just_after_his_return() -> void:
	var rules := BuildingRules.new()
	var spawn := AgentSpawn.new()
	var otto := Node3D.new()
	add_child_autofree(otto)
	var middle := (rules.agent_release_gap + rules.agent_respawn_gap) * 0.5
	assert_false(spawn.hugs(rules, 3, 3, middle, otto), "in play the usual gap")
	spawn.after_death(rules.agent_respawn_calm)
	assert_true(spawn.is_calm())
	assert_true(spawn.hugs(rules, 3, 3, middle, otto), "after the return the wider gap")
	assert_false(spawn.hugs(rules, 2, 3, middle, otto), "other floors are not held back")
	assert_false(spawn.hugs(rules, 3, 3, rules.agent_respawn_gap + 0.5, otto), "a far door opens")
	spawn.tick(rules.agent_respawn_calm + 0.1)
	assert_false(spawn.is_calm())
	assert_false(spawn.hugs(rules, 3, 3, middle, otto), "after the calm the usual gap")


## A frozen building — the demo fading to black — does not bring Otto back: the return
## timer runs on the tree, not on the building, and the revival with its sound would play
## under the fade (ADR-0060).
func test_a_frozen_building_does_not_bring_otto_back() -> void:
	GameState.instance().start_game()
	var level := preload("res://src/levels/greybox_level.tscn").instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = 1
	level.spawn_agents = false
	add_child_autofree(level)
	await wait_physics_frames(2)
	level.skip_the_intro()
	await wait_physics_frames(2)
	level.otto.kill()
	assert_true(level.otto.is_dead(), "Otto is down")
	level.process_mode = Node.PROCESS_MODE_DISABLED
	await wait_seconds(GreyboxLevel.OTTO_RESPAWN_DELAY + 0.3)
	assert_true(level.otto.is_dead(), "the frozen building did not revive Otto")
	GameState.instance().reset()
