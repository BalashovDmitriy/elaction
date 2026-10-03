extends GutTest

## Tests of the building architecture: roof, silhouette and agent release.
##
## Everything checked here is built **by the real game rules**, not by
## reduced ones. The former level tests built buildings of 4–8 floors and every one of them
## turned agents off, so nobody checked the building the player actually plays:
## 241 tests were green while a game ended on the roof in a second and a half
## (ADR-0014, "Why this survived until release").

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

## How many frames geometry and agents get to settle into place.
const SETTLE_FRAMES: int = 4
const ENEMY := preload("res://src/actors/enemy/enemy.tscn")

## How many frames the doors get to release everyone they can.
##
## A door releases the next one no sooner than after its pause, and the level hands out
## no more than one per frame: for the whole crowd to gather takes seconds, not
## a frame or two.
const CROWD_FRAMES: int = 240

## How many frames Otto stands on the roof doing nothing.
##
## This is exactly how a player starts a game: the frame has appeared, he has not yet taken
## the controls. Before, in that time he managed to lose all three lives.
const IDLE_FRAMES: int = 180


func before_all() -> void:
	Engine.time_scale = 4.0


func after_all() -> void:
	Engine.time_scale = 1.0
	GameState.instance().reset()


## Real rules: thirty floors, five documents, agents in place.
func _build(building_seed: int, agents: bool, rules: BuildingRules = null) -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = rules if rules != null else BuildingRules.new()
	level.building_seed = building_seed
	level.spawn_agents = agents
	add_child_autofree(level)
	return level


func _drop(level: GreyboxLevel) -> void:
	remove_child(level)


## Waits until the doors release at least someone.
##
## A door opens first and only then hands out an agent (ADR-0020, decision 2),
## and the telegraph takes noticeably more than a frame or two. Looking at agents right
## after the build means looking at nothing: that is exactly how two tests here became
## empty in the very first M14 run.
func _wait_for_agents(level: GreyboxLevel) -> Array[Enemy]:
	for _frame: int in CROWD_FRAMES:
		await wait_physics_frames(1)
		var found := _agents_in(level)
		if not found.is_empty():
			return found
	return []


## Living agents of the building. Walking the children is the level's own job ([method
## GreyboxLevel.agents]); all that is left here is filtering out the dead.
##
## And those already removed past the frame edge: [method Node.queue_free] frees
## the node only at the end of the frame, while it stopped being a threat at once — without
## this filter the living cap would count an extra body and the test would fail out of
## nowhere.
func _agents_in(level: GreyboxLevel) -> Array[Enemy]:
	var found: Array[Enemy] = []
	for agent in level.agents():
		if not agent.is_dead() and not agent.is_queued_for_deletion():
			found.append(agent)
	return found


## The very bug the milestone started with: Otto stood with the top of his head above the
## frame edge and went 94 px beyond it in a jump, and the camera did not rise there.
func test_otto_and_his_jump_fit_in_frame_on_the_roof() -> void:
	var level := _build(1, false)
	await _wait_for_the_landing(level)

	var otto := level.otto
	# The top of the head is the height of the standing shape above the feet. The frame and
	# the head are measured in the rules plane, where "higher" means a smaller Y.
	var standing := otto.get_node("StandingShape") as CollisionShape3D
	var height := (standing.shape as BoxShape3D).size.y
	var head := WorldSpace.to_plane(otto.global_position).y - height
	var view := otto.camera_view()

	assert_gt(head, view.position.y, "Otto's top of head is below the top edge of the frame")
	assert_gt(head - otto.jump_height(), view.position.y, "and at the top of the jump too")
	_drop(level)


## There are no doors on the roof, and so no agents. Before, two stood there, closer than
## their firing range, and the game ended before it began.
func test_the_roof_is_empty_when_the_game_starts() -> void:
	for building_seed: int in [1, 2, 3]:
		var level := _build(building_seed, true)
		var agents := await _wait_for_agents(level)
		assert_false(agents.is_empty(), "seed %d: doors released nobody" % building_seed)

		var rules := level.rules
		for agent in agents:
			assert_gt(
				_floor_of(rules, agent),
				BuildingRules.ROOF,
				"seed %d: agent on the roof" % building_seed
			)
		_drop(level)


## The player must have time to look around. The check uses inaction on purpose: a bot
## that shoots back would hide exactly the trouble the test guards against.
func test_otto_survives_doing_nothing_at_the_start() -> void:
	for building_seed: int in [1, 2, 3]:
		var level := _build(building_seed, true)
		await wait_physics_frames(IDLE_FRAMES)

		assert_false(
			level.otto.is_dead(), "seed %d: Otto died without making a move" % building_seed
		)
		assert_eq(
			GameState.instance().lives,
			GameState.STARTING_LIVES,
			"seed %d: lives are lost at the start" % building_seed
		)
		_drop(level)


## Doors release agents near the player, not all at once. Before, the building
## had 55 bodies with physics and AI from the first frame to the end of the game.
func test_only_the_doors_near_otto_let_agents_out() -> void:
	var level := _build(1, true)
	await wait_physics_frames(SETTLE_FRAMES)

	var agent_doors := 0
	for spot in level.plan().doors:
		if not spot.has_document:
			agent_doors += 1

	var alive := _agents_in(level).size()
	assert_gt(agent_doors, 30, "the building really has many agent doors")
	assert_lt(alive, 10, "and only a few in frame")
	_drop(level)


## An agent far below is needed by neither the player nor physics: the floor left the frame.
func test_no_agent_walks_a_floor_far_from_otto() -> void:
	var level := _build(1, true)
	var agents := await _wait_for_agents(level)
	assert_false(agents.is_empty(), "doors released nobody")

	var rules := level.rules
	var here := _floor_of(rules, level.otto)
	for agent in agents:
		var floor_index := _floor_of(rules, agent)
		assert_lt(
			absi(floor_index - here), 10, "agent on floor %d, Otto on %d" % [floor_index, here]
		)
	_drop(level)


## Returning to play by the ROM (ADR-0053, decision 2): the agent who killed Otto leaves
## together with all the living, and Otto stands up at the ROM point of his floor, not where
## he died. The body of an agent killed earlier stays lying.
##
## The agent stands still ([code]walk_speed[/code] = 0): this way he is certainly still on
## the floor when Otto returns, and the leaving is checked, not where he walked to.
func test_otto_comes_back_to_the_rom_spot_and_the_agents_leave() -> void:
	var level := _build(1, false)
	await wait_physics_frames(SETTLE_FRAMES)
	# On the intro rope Otto is carried and cannot die (ADR-0060): he is killed on his feet.
	assert_true(await level.wait_for_the_landing(), "Otto landed on the roof")

	var rules := level.rules
	var floor_index := 3
	var surface := rules.floor_surface(floor_index)
	var spots := level.plan().safe_spots(rules, floor_index)
	assert_gt(spots.size(), 1, "the floor has spots to choose from")

	var shooter := ENEMY.instantiate() as Enemy
	shooter.walk_speed = 0.0
	level.add_child(shooter)
	shooter.global_position = WorldSpace.to_scene(Vector2(spots[0], surface))
	shooter.setup(level.otto, 1.0)
	var body := ENEMY.instantiate() as Enemy
	level.add_child(body)
	body.global_position = WorldSpace.to_scene(Vector2(spots[-1], surface))
	body.setup(level.otto, -1.0)
	# An agent comes out of an opening invulnerable ([method Enemy.is_emerging]).
	var emerged := 0
	while body.is_emerging() and emerged < 120:
		await wait_physics_frames(1)
		emerged += 1
	body.kill()
	assert_true(body.is_dead(), "the second agent cannot be killed")

	level.otto.global_position = WorldSpace.to_scene(Vector2(spots[0], surface))
	level.otto.kill()
	var waited := 0
	while level.otto.is_dead() and waited < 120:
		await wait_physics_frames(1)
		waited += 1
	await wait_physics_frames(1)

	assert_false(is_instance_valid(shooter), "the agent who killed Otto did not leave")
	assert_true(is_instance_valid(body), "agent body was removed along with the living")
	# The third floor of a thirty-storey building is ROM's twenty-seventh: Otto stays on it.
	assert_eq(_floor_of(rules, level.otto), floor_index, "Otto did not return to his own floor")
	var back := WorldSpace.to_plane(level.otto.global_position).x
	var red_x := RespawnSpot.red_door_x(level.doors(), rules, floor_index)
	var spot := RespawnSpot.choose(level.plan(), rules, floor_index, red_x)
	assert_almost_eq(back, spot, 0.01, "Otto did not return to the ROM spot")
	_drop(level)


## A breather after returning to play: without it the second death comes before
## the player manages to press anything at all.
func test_otto_is_untouchable_right_after_coming_back() -> void:
	var level := _build(1, false)
	await wait_physics_frames(SETTLE_FRAMES)

	level.otto.kill()
	# We wait for exactly the return, not "with a margin": the breather is short, and extra
	# frames would eat it before the test had a chance to check it.
	var waited := 0
	while level.otto.is_dead() and waited < 120:
		await wait_physics_frames(1)
		waited += 1
	assert_false(level.otto.is_dead(), "Otto is back in the game")

	level.otto.kill()
	assert_false(level.otto.is_dead(), "and he cannot be killed a second time right away")
	_drop(level)


## The bottom of the building is crowded: each floor there has two doors, and the release
## band is nine floors. Without a cap the living reached eighteen, and the bottom floors
## became a shooting gallery with fire from all sides at once (ADR-0016, item 6).
func test_no_more_live_agents_than_the_rules_allow() -> void:
	for building_seed: int in [1, 2, 3]:
		var level := _build(building_seed, true)
		var rules := level.rules
		_stand_on(level, rules.floors - 2)

		var most := 0
		for _frame in CROWD_FRAMES:
			await wait_physics_frames(1)
			most = maxi(most, _agents_in(level).size())

		assert_gt(most, 0, "seed %d: doors on the lower floors released nobody" % building_seed)
		# The ROM cap is three, and late in the building four (ADR-0027, decision 2).
		var ceiling := rules.agents_at_once(GameState.instance().alarm.elapsed())
		assert_lte(
			most,
			ceiling,
			"seed %d: live agents at once %d with a ceiling of %d" % [building_seed, most, ceiling]
		)
		_drop(level)


## The rules reach from the building all the way to the agent.
##
## Checked with the "do not shoot" switch: with it the agent does not shoot at all, and
## this shows in the bullets and in Otto being alive.
func test_agents_take_their_combat_numbers_from_the_rules() -> void:
	var toothless := BuildingRules.new()
	toothless.agents_hold_fire = true
	var harmless := _build(1, true, toothless)
	_stand_on(harmless, harmless.rules.floors - 2)
	var quiet := await _worst_moment(harmless)
	assert_gt(_agents_in(harmless).size(), 0, "agents came out")
	assert_eq(quiet, 0, "but they were told not to shoot")
	assert_false(
		harmless.otto.is_dead(), "and Otto is unharmed after standing among them like a post"
	)
	_drop(harmless)

	var armed := _build(1, true)
	_stand_on(armed, armed.rules.floors - 2)
	var shots := await _worst_moment(armed)
	assert_gt(shots, 0, "without the ban the same agents shoot")
	_drop(armed)


## Puts Otto in the middle of the floor: where a player would stand, not in an opening.
func _stand_on(level: GreyboxLevel, index: int) -> void:
	var rules := level.rules
	level.otto.global_position = WorldSpace.to_scene(
		Vector2(level.plan().safe_x(rules, index), rules.floor_surface(index))
	)


## The floor the node stands on, by the building rules.
func _floor_of(rules: BuildingRules, node: Node3D) -> int:
	return rules.floor_index_near(WorldSpace.to_plane(node.global_position).y)


## How many enemy bullets were in the air at once during [constant CROWD_FRAMES].
##
## Not "how many there are now": a bullet lives a fraction of a second, and a single sample
## would fall into a gap between shots.
func _worst_moment(level: GreyboxLevel) -> int:
	var most := 0
	for _frame in CROWD_FRAMES:
		await wait_physics_frames(1)
		var flying := 0
		for node in level.get_tree().get_nodes_in_group(Bullet.GROUP):
			var bullet := node as Bullet
			if bullet != null and bullet.collision_mask == Bullet.FROM_ENEMY:
				flying += 1
		most = maxi(most, flying)
	return most


## Waits until Otto slides down the rope to the roof
## ([method GreyboxLevel.wait_for_the_landing]).
func _wait_for_the_landing(level: GreyboxLevel) -> void:
	assert_true(await level.wait_for_the_landing(), "Otto slid down the rope and stood on the roof")


## An agent comes out where Otto is: on his floor, a floor above or below (@5A26).
##
## Before M18d the release went over the whole band of visible floors from the nearest door;
## by the ROM the draw is cast only over three floors around Otto (ADR-0027, decision 2).
func test_agents_step_out_next_to_otto() -> void:
	for building_seed: int in [1, 2, 3]:
		var level := _build(building_seed, true)
		var rules := level.rules
		var here := rules.floors - 2
		_stand_on(level, here)

		var seen: Dictionary = {}
		for _frame in CROWD_FRAMES:
			await wait_physics_frames(1)
			for agent in _agents_in(level):
				var id := agent.get_instance_id()
				if seen.has(id):
					continue
				seen[id] = true
				var floor_index := _floor_of(rules, agent)
				# Otto's floor at the moment of release: one who died below returns no lower than
				# the fifth ROM floor (ADR-0053, decision 2), and the release follows him.
				here = _floor_of(rules, level.otto)
				assert_lte(
					absi(floor_index - here),
					1,
					(
						"seed %d: agent came out on floor %d, Otto on %d"
						% [building_seed, floor_index, here]
					)
				)
		assert_gt(seen.size(), 0, "seed %d: nobody came out" % building_seed)
		_drop(level)
