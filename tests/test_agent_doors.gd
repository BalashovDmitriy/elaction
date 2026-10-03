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
	assert_true(door.summon_agent(), "свободная дверь открывается под агента")

	Input.action_press(&"move_up")
	await wait_physics_frames(KNOCK_FRAMES)
	Input.action_release(&"move_up")
	assert_false(_is_indoors(otto), "дверь занята агентом и Otto внутрь не пустила")


## A free one does let him in: otherwise the previous check would pass even on a door
## that never lets anyone in.
func test_a_free_door_still_takes_otto_in() -> void:
	var door := _bare_door()
	var otto := _guest_at(door)

	Input.action_press(&"move_up")
	await wait_physics_frames(KNOCK_FRAMES)
	Input.action_release(&"move_up")
	assert_true(_is_indoors(otto), "в свободную дверь Otto заходит как прежде")


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
	assert_true(_is_indoors(otto), "Otto за дверью")
	assert_true(director.music_muffled(), "музыка из-за стены")
	remove_child(door)
	assert_false(director.music_muffled(), "дверь ушла — звук вернулся")


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
			assert_not_null(door, "агент вышел неизвестно откуда")
			if door == null:
				return
			assert_gt(door.openness(), 0.0, "агент в проёме — значит створка не закрыта")


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
				"пока агент в проёме, пуле не во что попадать"
			)
	assert_gt(seen, 0, "ни один агент не выходил — проверять было нечего")


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
				"вышедший агент — обычный противник, и его берёт пуля"
			)
	assert_gt(seen, 0, "ни один агент так и не вышел из проёма")


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
	assert_gt(just_left, 0, "ни один агент не отходил от своей двери")
	assert_gt(
		closed_behind, 0, "ни одна дверь за вышедшим не закрывалась (отошедших %d)" % just_left
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
				pass_test("створка вернулась и за убитым")
				return
			continue
		for agent in _live_agents(level):
			if agent.is_emerging():
				continue
			emptied = level.door_of(agent)
			agent.kill()
			break

	assert_not_null(emptied, "из дверей никто не вышел — убивать было некого")
	fail_test("дверь так и осталась открытой за убитым агентом")


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
			assert_true(is_instance_valid(corpse), "труп лежит, пока выходит следующий")
			return

	assert_not_null(corpse, "из дверей никто не вышел — убивать было некого")
	fail_test("после убитого не вышел никто: труп держит выпуск")


func test_an_emptied_red_door_starts_letting_agents_out() -> void:
	var level := _build(3)
	var red: Door = null
	for door in level.doors():
		if door.is_pending():
			red = door
			break
	assert_not_null(red, "в здании обязаны быть красные двери")
	if red == null:
		return

	# The document is taken directly, not by Otto entering: the milestone is about doors,
	# not about the visit.
	assert_false(level.agent_doors().has(red), "красная дверь засад не держит")
	red.has_document = false
	red.document_taken.emit()
	assert_true(
		level.agent_doors().has(red), "опустевшая дверь выглядит обычной и ведёт себя как обычная"
	)


## An open leaf does not go beyond its doorway.
##
## The spot step is 1.8 m, the leaf 1.2: 0.6 is left for the neighboring spot. Sliding
## sideways by its width, as it did before M18c, it would overlap the neighboring door or
## shaft, so it swings on a hinge into the room (ADR-0026, decision 3).
func test_an_open_leaf_stays_inside_its_doorway() -> void:
	var door := _bare_door()
	assert_true(door.summon_agent(), "дверь открывается")
	var frames := 0
	while door.openness() < 1.0 and frames < 240:
		await wait_physics_frames(1)
		frames += 1
	assert_almost_eq(door.openness(), 1.0, 0.001, "дверь открылась до конца")

	var leaf := door.get_node("Leaf") as MeshInstance3D
	var bounds := leaf.global_transform * leaf.get_aabb()
	var half := Door.LEAF_SIZE.x * 0.5
	var centre := door.global_position.x
	assert_gte(bounds.position.x, centre - half - 0.05, "створка не вышла за проём слева")
	assert_lte(bounds.end.x, centre + half + 0.05, "и справа")
	assert_lt(bounds.position.z, WorldSpace.BACK_WALL_Z, "она ушла в комнату, за стену")
