extends GutTest

## Tests of the door with Otto inside — with the node, the door leaf, input and sound (ADR-0038,
## decision 2).
##
## Visit rules without a scene are in [code]test_door_visit.gd[/code]. Here is what cannot be
## checked there: that the player's input really does not reach the door in any way, that the leaf
## is visibly closed, that the document is counted on exit in a real building and that the floor's
## agents wait at the door no more than one at a time — on several seeds, not on one convenient
## floor.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const DOOR_SCENE := preload("res://src/systems/doors/door.tscn")
const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")

## Time speed-up: a visit is almost five seconds, and there are several buildings in the test.
const TIME_SCALE: float = 4.0

## How many frames to wait for Otto to go in or come out before giving up.
const PATIENCE: int = 240

## Everything the player could use to ask to get out: nothing lets him out early.
const ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_down", &"move_up", &"jump", &"shoot"
]

## Building seeds for level checks.
const SEEDS: Array[int] = [1, 2, 3]

## How far from the door to place agents, m: farther than the waiting spot offset and close enough
## to arrive while Otto is inside.
const AGENT_NEAR: float = 1.9
const AGENT_FAR: float = 4.2


func before_all() -> void:
	Engine.time_scale = TIME_SCALE


func after_all() -> void:
	Engine.time_scale = 1.0
	_release_all()
	GameState.instance().reset()


func after_each() -> void:
	_release_all()


func _release_all() -> void:
	for action: StringName in ACTIONS:
		Input.action_release(action)


## A physics step in game seconds: under speed-up it is longer.
func _step() -> float:
	return Engine.time_scale / float(Engine.physics_ticks_per_second)


## Waits [param seconds] seconds of game time in physics steps: under speed-up the wall clock does
## not count.
func _wait_game(seconds: float) -> void:
	for _frame: int in int(ceilf(seconds / _step())):
		await get_tree().physics_frame


## A lone door on a solid floor, as in [code]test_agent_doors.gd[/code].
func _bare_door(red: bool) -> Door:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 0.4, WorldSpace.CORRIDOR_DEPTH)
	shape.shape = box
	shape.position = Vector3(0.0, -0.2, 0.0)
	ground.add_child(shape)
	add_child_autofree(ground)

	var door := DOOR_SCENE.instantiate() as Door
	door.has_document = red
	add_child_autofree(door)
	return door


func _guest_at(door: Door) -> Otto:
	var otto := OTTO_SCENE.instantiate() as Otto
	add_child_autofree(otto)
	otto.global_position = WorldSpace.to_scene(door.mat_position())
	return otto


## Presses "up" until the door takes Otto. Returns whether it took him.
func _knock(otto: Otto) -> bool:
	Input.action_press(&"move_up")
	for _frame: int in PATIENCE:
		await get_tree().physics_frame
		if not otto.is_on_foot():
			return true
	return false


## Waits until Otto hides behind the leaf.
func _wait_hidden(otto: Otto) -> bool:
	for _frame: int in PATIENCE:
		if otto.is_hidden():
			return true
		await get_tree().physics_frame
	return otto.is_hidden()


## Waits until the door releases the hidden Otto: he is in view again.
func _wait_out(otto: Otto) -> void:
	var frames := 0
	while otto.is_hidden() and frames < PATIENCE * 2:
		await get_tree().physics_frame
		frames += 1


func test_the_leaf_shuts_behind_otto_and_opens_to_let_him_out() -> void:
	var door := _bare_door(true)
	var otto := _guest_at(door)
	assert_true(await _knock(otto), "the door took Otto")
	assert_false(otto.is_hidden(), "while the leaf moves, he is still in the doorway")
	assert_true(await _wait_hidden(otto), "the leaf opened - he is inside")
	# A second: the leaf has had time to close behind him, and the exit is still far off.
	await _wait_game(1.0)
	assert_true(otto.is_hidden(), "he is still inside")
	assert_eq(door.openness(), 0.0, "the leaf is closed behind him")
	await _wait_out(otto)
	assert_false(otto.is_hidden(), "came out")
	assert_gt(door.openness(), 0.9, "he steps out into the open leaf")
	assert_false(otto.is_on_foot(), "while it closes, he is still coming out")
	await _wait_game(1.0)
	assert_eq(door.openness(), 0.0, "and it closes behind him")
	assert_true(otto.is_on_foot(), "closed - the player has control again")


func test_otto_is_out_exactly_after_seventy_ticks_whatever_he_presses() -> void:
	var door := _bare_door(true)
	var otto := _guest_at(door)
	assert_true(await _knock(otto), "the door took Otto")
	var frames := 0
	var hid := false
	while frames < PATIENCE * 2:
		# Every frame a different button, with release: both held and fresh.
		_release_all()
		Input.action_press(ACTIONS[frames % ACTIONS.size()])
		await get_tree().physics_frame
		frames += 1
		hid = hid or otto.is_hidden()
		if hid and not otto.is_hidden():
			break
		assert_false(otto.is_on_foot(), "not released early, frame %d" % frames)
	_release_all()
	var inside := float(frames) * _step()
	var rom := Arcade.seconds(Arcade.ROOM_TICKS)
	assert_almost_eq(inside, rom, _step() * 2.0, "exactly 70 ROM ticks")


## An ordinary door does not let Otto in: as in the ROM (@3BDA), only a red one lets him inside
## (ADR-0044, decision 3). Before, an ordinary door served as cover.
func test_a_plain_door_does_not_take_otto_in() -> void:
	var door := _bare_door(false)
	var otto := _guest_at(door)
	assert_false(await _knock(otto), "an ordinary door did not take Otto")
	_release_all()
	assert_eq(door.openness(), 0.0, "and did not open")


## A cleared red door becomes ordinary — and also no longer lets him in.
func test_an_emptied_red_door_does_not_take_otto_in_again() -> void:
	var door := _bare_door(true)
	var otto := _guest_at(door)
	assert_true(await _knock(otto), "the red door took Otto")
	_release_all()
	assert_true(await _wait_hidden(otto), "went in")
	await _wait_out(otto)
	await _wait_game(1.0)
	assert_false(door.has_document, "the document is taken")
	assert_true(otto.is_on_foot(), "came out, the player has control")
	assert_false(await _knock(otto), "a cleared door does not let him in a second time")
	_release_all()


func test_the_document_is_counted_on_the_way_out() -> void:
	var door := _bare_door(true)
	var otto := _guest_at(door)
	watch_signals(door)
	assert_true(await _knock(otto), "the door took Otto")
	assert_true(await _wait_hidden(otto))
	assert_signal_not_emitted(door, "document_taken", "no document is given for entering")
	assert_true(door.is_pending(), "while he is inside, the door is still red")
	await _wait_out(otto)
	assert_signal_emit_count(door, "document_taken", 1, "the document - on exit")
	assert_false(door.is_pending(), "came out - the door is ordinary")


## A bullet that reaches Otto in the same step the door takes him does not kill him: his
## shapes go off only deferred, and a death in the doorway would be undone by the door
## putting him back on the mat with the document (ADR-0060).
func test_otto_taken_by_the_door_cannot_be_killed() -> void:
	var door := _bare_door(true)
	var otto := _guest_at(door)
	assert_true(await _knock(otto), "the door took Otto")
	_release_all()
	otto.kill()
	assert_false(otto.is_dead(), "not killed in the doorway")
	assert_true(await _wait_hidden(otto), "and went in")
	otto.kill()
	assert_false(otto.is_dead(), "nor behind the door")


## A guest who is dead all the same is let go by the door: it closes, keeps its document
## and does not bring a dead one back out onto the mat (ADR-0060).
func test_the_door_lets_go_of_a_dead_guest() -> void:
	var door := _bare_door(true)
	var otto := _guest_at(door)
	watch_signals(door)
	assert_true(await _knock(otto), "the door took Otto")
	_release_all()
	(otto.get(&"_states") as OttoStateMachine).kill()
	await _wait_game(Arcade.seconds(Arcade.ROOM_TICKS) + 1.0)
	assert_signal_not_emitted(door, "otto_came_out", "a dead one is not let out")
	assert_signal_not_emitted(door, "document_taken", "nor given the document")
	assert_true(door.is_pending(), "the door is still red")
	assert_eq(door.openness(), 0.0, "and closed")


## While Otto is inside, the closed red leaf glows by itself — red — and the board above it
## breathes: in the corridor shadow it does not merge with the darkness (M24b shot).
func test_the_occupied_red_door_glows_and_its_sign_breathes() -> void:
	var door := _bare_door(true)
	var leaf := door.get_node("Leaf") as MeshInstance3D
	var sign_board := door.get_node("Sign") as MeshInstance3D
	var plain := leaf.material_override as StandardMaterial3D
	assert_false(plain.emission_enabled, "an empty door does not glow")
	var otto := _guest_at(door)
	assert_true(await _knock(otto), "the door took Otto")
	assert_true(await _wait_hidden(otto))
	await _wait_game(0.4)
	var glowing := leaf.material_override as StandardMaterial3D
	assert_true(glowing.emission_enabled, "the occupied leaf glows")
	assert_true(glowing.albedo_color.is_equal_approx(GreyboxLook.DOOR_RED), "and stays red")
	var first := (sign_board.material_override as StandardMaterial3D).emission_energy_multiplier
	await _wait_game(Door.OCCUPIED_PULSE * 0.5)
	var later := (sign_board.material_override as StandardMaterial3D).emission_energy_multiplier
	assert_ne(first, later, "the board pulses")
	await _wait_out(otto)
	await _wait_game(0.1)
	assert_false(
		(leaf.material_override as StandardMaterial3D).emission_enabled, "came out - does not glow"
	)


func test_the_corridor_is_muffled_while_otto_is_inside() -> void:
	var director := AudioDirector.instance()
	if director == null:
		pass_test("no sound - nothing to muffle")
		return
	director.reset()
	var door := _bare_door(true)
	var otto := _guest_at(door)
	assert_true(await _knock(otto), "the door took Otto")
	assert_true(await _wait_hidden(otto))
	assert_true(director.world_muffled(), "corridor heard through the wall")
	assert_true(director.music_muffled(), "and the music too")
	await _wait_out(otto)
	assert_false(director.world_muffled(), "came out - the corridor is audible")
	assert_false(director.music_muffled(), "and the music")


func test_a_level_freed_with_otto_inside_brings_the_sound_back() -> void:
	var director := AudioDirector.instance()
	if director == null:
		pass_test("no sound - nothing to muffle")
		return
	director.reset()
	var level := _build(SEEDS[0])
	await level.wait_for_the_landing()
	var door := level.doors()[0]
	level.otto.global_position = WorldSpace.to_scene(door.mat_position())
	await get_tree().physics_frame
	assert_true(await _knock(level.otto), "the door took Otto")
	assert_true(await _wait_hidden(level.otto))
	assert_true(director.world_muffled(), "corridor heard through the wall")
	remove_child(level)
	level.free()
	assert_false(director.world_muffled(), "building gone - the corridor is audible")
	assert_false(director.music_muffled(), "and the music")


func _build(building_seed: int) -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = building_seed
	level.spawn_agents = false
	add_child(level)
	return level


func _drop(level: GreyboxLevel) -> void:
	if is_instance_valid(level):
		remove_child(level)
		level.free()


## The document and 500 points — on exit, in any building of the set.
func test_a_red_door_pays_on_the_way_out_in_any_building() -> void:
	for building_seed: int in SEEDS:
		var level := _build(building_seed)
		await level.wait_for_the_landing()
		var red: Door = null
		for door in level.doors():
			if door.is_pending():
				red = door
				break
		assert_not_null(red, "no red door in the building, seed %d" % building_seed)
		if red == null:
			_drop(level)
			continue
		var game := GameState.instance()
		level.otto.global_position = WorldSpace.to_scene(red.mat_position())
		await get_tree().physics_frame
		var score := game.score
		assert_true(await _knock(level.otto), "the door took Otto, seed %d" % building_seed)
		assert_true(await _wait_hidden(level.otto))
		assert_eq(game.documents_collected, 0, "not counted for entering, seed %d" % building_seed)
		assert_eq(game.score, score, "and no points")
		await _wait_out(level.otto)
		_release_all()
		assert_eq(game.documents_collected, 1, "counted on exit, seed %d" % building_seed)
		assert_eq(game.score, score + GameState.DOCUMENT_SCORE, "and 500 points")
		_drop(level)


## Where on the door's floor to place agents so they can reach it: places where one can stand, on a
## free path to the door.
func _agent_spots(level: GreyboxLevel, door: Door) -> Array[float]:
	var mat := door.mat_position()
	var floor_index := level.rules.floor_index_near(mat.y)
	var blocks := level.plan().blocks_on(level.rules, floor_index)
	var spots: Array[float] = []
	for x: float in level.plan().safe_spots(level.rules, floor_index):
		var gap := absf(x - mat.x)
		if gap < AGENT_NEAR or gap > AGENT_FAR:
			continue
		var clear := true
		for block: Vector2 in blocks:
			var low := minf(x, mat.x)
			var high := maxf(x, mat.x)
			if maxf(block.x, block.y) > low and minf(block.x, block.y) < high:
				clear = false
		if clear:
			spots.append(x)
	return spots


func _spawn_agent(level: GreyboxLevel, x: float, y: float, towards: float, index: int) -> Enemy:
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.apply_rules(level.rules)
	agent.seed_decisions(1000 + index)
	level.add_child(agent)
	agent.global_position = WorldSpace.to_scene(Vector2(x, y))
	agent.setup(level.otto, towards)
	return agent


## The floor's agents wait at the door with Otto no more than one at a time, the one who arrived
## stands at the mat facing the door, and once Otto has come out — there is nobody to wait for.
func test_agents_wait_at_otto_s_door_one_at_most_and_let_go_when_he_is_out() -> void:
	var watched := 0
	for building_seed: int in SEEDS:
		var level := _build(building_seed)
		await level.wait_for_the_landing()
		var door: Door = null
		var spots: Array[float] = []
		for candidate in level.doors():
			# Only a red door lets Otto in (ADR-0044, decision 3).
			if not candidate.has_document:
				continue
			spots = _agent_spots(level, candidate)
			if spots.size() >= 2:
				door = candidate
				break
		if door == null:
			_drop(level)
			continue
		var mat := door.mat_position()
		level.otto.global_position = WorldSpace.to_scene(mat)
		await get_tree().physics_frame
		assert_true(await _knock(level.otto), "the door took Otto, seed %d" % building_seed)
		assert_true(await _wait_hidden(level.otto))
		_release_all()
		var agents: Array[Enemy] = []
		for index: int in spots.size():
			agents.append(_spawn_agent(level, spots[index], mat.y, mat.x - spots[index], index))

		var watcher: Enemy = null
		while level.otto.is_hidden():
			await get_tree().physics_frame
			var waiting := 0
			for agent in agents:
				if not is_nan(agent.watch_at):
					waiting += 1
					watcher = agent
			assert_lte(waiting, 1, "at most one at the door, seed %d" % building_seed)
		if watcher != null:
			watched += 1
			var x := WorldSpace.to_plane(watcher.global_position).x
			var off := absf(x - mat.x)
			assert_gt(off, Proportions.DOOR_MAT * 0.5, "not off the mat, seed %d" % building_seed)
			assert_lt(off, Proportions.DOOR.x, "but right at the door, seed %d" % building_seed)
			assert_eq(watcher.facing(), signf(mat.x - x), "facing the door")
		await get_tree().physics_frame
		await get_tree().physics_frame
		for agent in agents:
			assert_true(is_nan(agent.watch_at), "Otto came out - nobody to wait for")
		_drop(level)
	assert_gt(watched, 0, "in no building did anyone go to the door - nothing to check")
