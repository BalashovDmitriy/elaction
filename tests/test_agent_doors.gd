extends GutTest

## Tests for an agent coming out of a door.
##
## Before M14 the level placed an agent right on the mat of a closed door, and the door
## leaf did not move at all. Here the opposite is checked: first the door, then the
## agent, and while he is in the doorway he cannot be hit (ADR-0020).
##
## The building is assembled by the real rules, as in
## [code]test_building_architecture[/code]: reduced buildings once already hid a broken
## agent release from us.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const DOOR_SCENE := preload("res://src/systems/doors/door.tscn")
const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")

## How many frames to give the doors for someone to manage to come out.
const CROWD_FRAMES: int = 240

## How far from his door an agent still counts as "just came out", m.
##
## He cannot be caught exactly on the mat: leaving the doorway ends one step from the
## door, and the agent ends up a meter and a bit away. A check for exact match relied on
## chance and fell apart as soon as the fine M18 grid shifted the doors.
const JUST_LEFT: float = 2.0

## How many frames to hold "up" at a lone door: enough both for the leaf and for Otto to
## get in, if the door takes him.
const KNOCK_FRAMES: int = 30


func before_all() -> void:
	Engine.time_scale = 4.0


func after_all() -> void:
	Engine.time_scale = 1.0
	GameState.instance().reset()


func _build(building_seed: int) -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = building_seed
	level.spawn_agents = true
	add_child_autofree(level)
	return level


## Waits until Otto rides down the rope and stands on the roof.
func _wait_for_the_landing(level: GreyboxLevel) -> void:
	await level.wait_for_the_landing()


func _live_agents(level: GreyboxLevel) -> Array[Enemy]:
	var live: Array[Enemy] = []
	for agent in level.agents():
		if is_instance_valid(agent) and not agent.is_dead():
			live.append(agent)
	return live


## A lone red door on a solid floor: there is no point in raising a building for it.
## Red because only such a door lets Otto in (ADR-0044, decision 3), and
## otherwise the "will it let him in" checks would pass on a door that lets nobody in.
func _bare_door() -> Door:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 0.4, WorldSpace.CORRIDOR_DEPTH)
	shape.shape = box
	shape.position = Vector3(0.0, -0.2, 0.0)
	ground.add_child(shape)
	add_child_autofree(ground)

	var door := DOOR_SCENE.instantiate() as Door
	door.has_document = true
	add_child_autofree(door)
	return door


## Puts Otto on the door mat.
func _guest_at(door: Door) -> Otto:
	var otto := OTTO_SCENE.instantiate() as Otto
	add_child_autofree(otto)
	otto.global_position = WorldSpace.to_scene(door.mat_position())
	return otto


## Whether Otto has gone behind the door. From outside this shows in the input: hidden
## by a door, he does not hear input at all, and a held "up" does not reach him.
func _is_indoors(otto: Otto) -> bool:
	return is_zero_approx(otto.vertical_intent())


## Otto does not enter a door that is opening for an agent.
##
## Letting him in there would lock him in forever: the leaf behind the agent who came out
## is closed by the level, and a guest's stay runs only while the door is open: behind a
## closed one it never ends.
func test_a_door_opening_for_an_agent_does_not_take_otto_in() -> void:
	var door := _bare_door()
	var otto := _guest_at(door)
	assert_true(door.summon_agent(), "a free door opens for an agent")

	Input.action_press(&"move_up")
	await wait_physics_frames(KNOCK_FRAMES)
	Input.action_release(&"move_up")
	assert_false(_is_indoors(otto), "the door is taken by an agent and did not let Otto in")


## A free one does let him in: otherwise the previous check would pass even on a door
## that never lets anyone in.
func test_a_free_door_still_takes_otto_in() -> void:
	var door := _bare_door()
	var otto := _guest_at(door)

	Input.action_press(&"move_up")
	await wait_physics_frames(KNOCK_FRAMES)
	Input.action_release(&"move_up")
	assert_true(_is_indoors(otto), "Otto enters a free door as before")


## The building was thrown away while Otto is behind a door: "restart" from the pause,
## exit to the menu. The door's muffled music is removed by the door itself: making
## everyone who throws a building away remember it means forgetting it one day (M23 code
## review).
func test_a_door_gone_with_otto_inside_brings_the_music_back() -> void:
	var director := AudioDirector.instance()
	if director == null:
		return
	director.reset()
	var door := _bare_door()
	var otto := _guest_at(door)

	Input.action_press(&"move_up")
	await wait_physics_frames(KNOCK_FRAMES)
	Input.action_release(&"move_up")
	assert_true(_is_indoors(otto), "Otto is behind the door")
	assert_true(director.music_muffled(), "music from behind the wall")
	remove_child(door)
	assert_false(director.music_muffled(), "the door left: the sound returned")


func test_no_agent_ever_shows_up_in_front_of_a_shut_door() -> void:
	var level := _build(3)
	await _wait_for_the_landing(level)
	# Every frame: if the agent is visible, the door behind him must be open.
	# This is exactly what was broken: the agent appeared at a closed leaf.
	for _frame: int in CROWD_FRAMES:
		await wait_physics_frames(1)
		for agent in _live_agents(level):
			if not agent.is_emerging():
				continue
			var door := level.door_of(agent)
			assert_not_null(door, "an agent came out of nowhere")
			if door == null:
				return
			assert_gt(door.openness(), 0.0, "agent in the opening, so the leaf is not closed")


func test_an_agent_in_the_doorway_is_not_a_target() -> void:
	var level := _build(3)
	await _wait_for_the_landing(level)
	var seen := 0
	for _frame: int in CROWD_FRAMES:
		await wait_physics_frames(1)
		for agent in _live_agents(level):
			if not agent.is_emerging():
				continue
			seen += 1
			assert_false(
				agent.get_collision_layer_value(Enemy.ENEMY_LAYER),
				"while the agent is in the opening, a bullet has nothing to hit"
			)
	assert_gt(seen, 0, "no agent came out, nothing to check")


func test_an_agent_out_of_the_doorway_becomes_a_target() -> void:
	var level := _build(3)
	await _wait_for_the_landing(level)
	var seen := 0
	for _frame: int in CROWD_FRAMES:
		await wait_physics_frames(1)
		for agent in _live_agents(level):
			if agent.is_emerging():
				continue
			seen += 1
			assert_true(
				agent.get_collision_layer_value(Enemy.ENEMY_LAYER),
				"an agent who came out is an ordinary enemy, and a bullet hits him"
			)
	assert_gt(seen, 0, "no agent ever came out of the opening")


func test_the_door_shuts_behind_the_agent_that_left_it() -> void:
	var level := _build(3)
	await _wait_for_the_landing(level)
	var closed_behind := 0
	var just_left := 0
	for _frame: int in CROWD_FRAMES:
		await wait_physics_frames(1)
		for agent in _live_agents(level):
			if agent.is_emerging():
				continue
			var door := level.door_of(agent)
			var at := WorldSpace.to_plane(agent.global_position)
			if door == null or absf(door.mat_position().x - at.x) > JUST_LEFT:
				continue
			just_left += 1
			# The agent is still at his door, but has already cleared the doorway: the leaf must
			# go back, not stand wide open (ADR-0020, decision 4).
			if door.openness() < 1.0:
				closed_behind += 1
	# "Zero" can happen both because the door did not close and because nobody came out
	# within the observation window, and these are different breakages.
	assert_gt(just_left, 0, "no agent moved away from his door")
	assert_gt(
		closed_behind, 0, "no door closed behind one who came out (moved away: %d)" % just_left
	)


## The door closes also behind an agent who was taken down as soon as he came out.
##
## The doorway is equally free whether the agent left on his own or was killed, and the
## leaf must return in both cases (ADR-0020, decision 4). There is nobody to close it
## but the level, and the level goes over the posts: a post left without a living agent
## must release the door, otherwise it stays open forever and, worse, forever
## occupied: [method Door.summon_agent] will not open it any more.
func test_a_door_shuts_even_when_its_agent_is_killed_on_the_spot() -> void:
	var level := _build(3)
	await _wait_for_the_landing(level)

	var emptied: Door = null
	for _frame: int in CROWD_FRAMES:
		await wait_physics_frames(1)
		if emptied != null:
			if emptied.openness() <= 0.0:
				pass_test("the leaf returned for a killed agent too")
				return
			continue
		for agent in _live_agents(level):
			if agent.is_emerging():
				continue
			emptied = level.door_of(agent)
			agent.kill()
			break

	assert_not_null(emptied, "nobody came out of the doors, nobody to kill")
	fail_test("the door stayed open behind the killed agent")


## A corpse lies until the end of the building (ADR-0037, decision 6), but holds neither
## a cell nor a door: the next agent comes out while the killed one lies there.
func test_a_corpse_does_not_hold_back_the_next_agent() -> void:
	var level := _build(3)
	await _wait_for_the_landing(level)

	var corpse: Enemy = null
	for _frame: int in CROWD_FRAMES * 6:
		await wait_physics_frames(1)
		var live := _live_agents(level)
		if corpse == null:
			for agent in live:
				if not agent.is_emerging():
					corpse = agent
					agent.kill()
					break
			continue
		if not live.is_empty():
			assert_true(is_instance_valid(corpse), "the corpse lies while the next one comes out")
			return

	assert_not_null(corpse, "nobody came out of the doors, nobody to kill")
	fail_test("nobody came out after the killed one: the corpse holds the release")


func test_an_emptied_red_door_starts_letting_agents_out() -> void:
	var level := _build(3)
	var red: Door = null
	for door in level.doors():
		if door.is_pending():
			red = door
			break
	assert_not_null(red, "the building must have red doors")
	if red == null:
		return

	# The document is taken directly, not by Otto entering: the milestone is about doors,
	# not about the visit.
	assert_false(level.agent_doors().has(red), "a red door holds no ambushes")
	red.has_document = false
	red.document_taken.emit()
	assert_true(
		level.agent_doors().has(red), "an emptied door looks and behaves like an ordinary one"
	)


## An open leaf does not go beyond its doorway.
##
## The spot step is 1.8 m, the leaf 1.2: 0.6 is left for the neighboring spot. Sliding
## sideways by its width, as it did before M18c, it would overlap the neighboring door or
## shaft, so it swings on a hinge into the room (ADR-0026, decision 3).
func test_an_open_leaf_stays_inside_its_doorway() -> void:
	var door := _bare_door()
	assert_true(door.summon_agent(), "the door opens")
	var frames := 0
	while door.openness() < 1.0 and frames < 240:
		await wait_physics_frames(1)
		frames += 1
	assert_almost_eq(door.openness(), 1.0, 0.001, "the door opened fully")

	var leaf := door.get_node("Leaf") as MeshInstance3D
	var bounds := leaf.global_transform * leaf.get_aabb()
	var half := Door.LEAF_SIZE.x * 0.5
	var centre := door.global_position.x
	assert_gte(
		bounds.position.x, centre - half - 0.05, "the leaf did not go past the opening on the left"
	)
	assert_lte(bounds.end.x, centre + half + 0.05, "and on the right")
	assert_lt(bounds.position.z, WorldSpace.BACK_WALL_Z, "it went into the room, behind the wall")


## The first agent who has come out of his doorway, or null.
func _first_out(level: GreyboxLevel) -> Enemy:
	for _frame: int in CROWD_FRAMES * 4:
		await wait_physics_frames(1)
		for agent: Enemy in _live_agents(level):
			if not agent.is_emerging():
				return agent
	return null


## An agent who followed Otto far from his own door — by cab, five floors and more — is
## not removed next to him: the keep margin counts from the floor the agent is on now,
## and an agent in the frame never vanishes (ADR-0060).
func test_an_agent_far_from_his_door_is_kept_next_to_otto() -> void:
	var level := _build(3)
	await _wait_for_the_landing(level)
	var agent: Enemy = await _first_out(level)
	assert_not_null(agent, "nobody came out of the doors")
	if agent == null:
		return
	var home := level.rules.floor_index_near(level.door_of(agent).mat_position().y)
	var far := GreyboxLevel.AGENT_KEEP_MARGIN + 4
	var spot := Vector2.INF
	for door: Door in level.doors():
		var mat := door.mat_position()
		if absi(level.rules.floor_index_near(mat.y) - home) >= far:
			spot = mat
			break
	assert_ne(spot, Vector2.INF, "the building has no floor far enough from the door")
	if spot == Vector2.INF:
		return

	level.otto.global_position = WorldSpace.to_scene(spot)
	agent.global_position = WorldSpace.to_scene(spot)
	await wait_physics_frames(10)
	assert_true(is_instance_valid(agent), "the agent next to Otto was freed")
	if is_instance_valid(agent):
		assert_false(agent.is_queued_for_deletion(), "the agent next to Otto was removed")


## An agent the level has let go of stops at once and frees nothing: a body waiting for
## the end of the frame may still report leaving or dying, and by then his post may
## already hold the next agent and his slot (ADR-0060).
func test_a_dismissed_agent_reporting_again_frees_nothing() -> void:
	var level := _build(3)
	await _wait_for_the_landing(level)
	var agent: Enemy = await _first_out(level)
	assert_not_null(agent, "nobody came out of the doors")
	if agent == null:
		return
	var post: AgentPost = null
	for each: AgentPost in level._posts:
		if each.agent == agent:
			post = each
	assert_not_null(post, "the agent has a post")
	if post == null:
		return

	agent.left_building.emit(agent)
	assert_null(post.agent, "the agent who left is off his post")
	assert_false(agent.is_physics_processing(), "the dismissed agent no longer steps")

	# The post already holds the next agent: the old body's reports are not about him.
	var next := ENEMY_SCENE.instantiate() as Enemy
	autofree(next)
	post.agent = next
	post.slot = 1
	agent.left_building.emit(agent)
	agent.died.emit(agent)
	var slot := post.slot
	var holder := post.agent
	# Given back before the level's next step: the stand-in is not in the tree.
	post.agent = null
	assert_eq(slot, 1, "the next agent's slot is not freed")
	assert_eq(holder, next, "the next agent keeps his post")
