extends GutTest

## Takedowns instead of the kick (ADR-0040): the rule, the scene poses and a scene with a live Otto
## and agent.

const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const AGENT_MODEL := preload("res://assets/models/agent.glb")

## How long to wait for the end of a scene, s — with margin for the longest one.
const SCENE_WAIT: float = 3.0


func after_each() -> void:
	Input.action_release(&"shoot")
	Input.action_release(&"jump")
	Engine.time_scale = 1.0
	GameState.instance().reset()


# --- Rule ----------------------------------------------------------------------


func test_reach_is_close_ahead_on_the_same_floor() -> void:
	var otto := Vector2(0.0, 0.0)
	assert_true(Takedown.can_reach(otto, 1.0, Vector2(0.6, 0.0)), "close in front, reaches")
	assert_false(Takedown.can_reach(otto, 1.0, Vector2(-0.6, 0.0)), "behind, no")
	assert_false(Takedown.can_reach(otto, 1.0, Vector2(2.0, 0.0)), "far, shoots")
	assert_false(Takedown.can_reach(otto, 1.0, Vector2(0.6, 3.0)), "a floor above, no")
	assert_true(Takedown.can_reach(otto, -1.0, Vector2(-0.6, 0.0)), "facing left, from the left")


func test_the_side_is_where_the_agent_looks() -> void:
	assert_eq(Takedown.side_of(0.0, 0.7, -1.0), Takedown.Side.FRONT, "agent faces Otto")
	assert_eq(Takedown.side_of(0.0, 0.7, 1.0), Takedown.Side.BACK, "agent has his back to Otto")


func test_landing_next_to_an_agent_is_a_pounce() -> void:
	# ADR-0042, decision 9: close up on the same floor — from any side, from a jump or from the floor
	# above, it does not matter.
	var agent := Vector2(0.0, 0.0)
	assert_true(Takedown.lands_on(Vector2(0.2, 0.0), agent), "onto the agent, jumped on")
	assert_true(Takedown.lands_on(Vector2(-0.8, 0.05), agent), "right behind, also")
	assert_false(Takedown.lands_on(Vector2(1.5, 0.0), agent), "off to the side, no")
	assert_false(Takedown.lands_on(Vector2(0.2, 3.6), agent), "a floor above, no")


func test_scores_by_side_with_the_dark_bonus() -> void:
	# The user's decision (ADR-0040): from the front 200, from behind and from above 300, in darkness
	# +100. More than a shot (100) from any side.
	assert_eq(Takedown.score(Takedown.Side.FRONT, false), 200)
	assert_eq(Takedown.score(Takedown.Side.BACK, false), 300)
	assert_eq(Takedown.score(Takedown.Side.ABOVE, false), 300)
	assert_eq(Takedown.score(Takedown.Side.FRONT, true), 300)
	for side: int in Takedown.SCORES:
		assert_gt(Takedown.score(side, false), GameState.ENEMY_SHOT_SCORE, "worth more than a shot")


func test_every_side_has_scenes_and_the_front_and_back_vary() -> void:
	assert_eq(Takedown.scenes_for(Takedown.Side.FRONT).size(), 2, "front, a combo and a gun butt")
	assert_eq(Takedown.scenes_for(Takedown.Side.BACK).size(), 2, "behind, a choke and a neck")
	assert_eq(Takedown.scenes_for(Takedown.Side.ABOVE).size(), 1, "above, a jump-on")


func test_a_scene_does_not_repeat_in_a_row() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var last := ""
	for _round in 40:
		var scene := Takedown.pick(Takedown.Side.BACK, last, rng)
		assert_ne(scene.name, last, "the same scene is not repeated in a row")
		last = scene.name


func test_every_scene_is_playable() -> void:
	# Scene poses come from the rig table: an unknown one would play as a stance, and the scene would
	# play itself out without movement.
	for scene: Takedown.Scene in Takedown.all_scenes():
		assert_gt(scene.kill_at, 0.0, "%s: the agent does not die on the first frame" % scene.name)
		assert_lt(scene.kill_at, scene.duration, "%s: and before the end of the scene" % scene.name)
		assert_lte(scene.duration, 1.5, "%s: the scene is short" % scene.name)
		assert_true(FigurePoses.knows(scene.corpse), "%s: corpse %s" % [scene.name, scene.corpse])
		assert_true(ActorPose.is_down(scene.corpse), "%s: the corpse lies down" % scene.name)
		for track: Array[Array] in [scene.otto, scene.agent]:
			var previous := -1.0
			for key: Array in track:
				assert_true(FigurePoses.knows(String(key[1])), "%s: pose %s" % [scene.name, key[1]])
				assert_gt(float(key[0]), previous, "%s: keys in time order" % scene.name)
				previous = float(key[0])


func test_a_snapped_neck_turns_the_head_aside() -> void:
	var rig := FigureRig.new()
	rig.model = AGENT_MODEL
	add_child_autofree(rig)
	rig.show_pose("snap_held")
	rig.snap()
	var held := rig.bone_rotation(FigureRig.HEAD)
	rig.show_pose("snap_broken")
	rig.snap()
	assert_gt(
		held.angle_to(rig.bone_rotation(FigureRig.HEAD)),
		deg_to_rad(30.0),
		"head is turned sideways, not nodded"
	)


# --- Scene with live actors ------------------------------------------------------


func _floor() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30.0, 0.4, WorldSpace.CORRIDOR_DEPTH)
	shape.shape = box
	shape.position = Vector3(0.0, -0.2, 0.0)
	ground.add_child(shape)
	add_child_autofree(ground)


func _wall(x: float) -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 0.8, WorldSpace.CORRIDOR_DEPTH)
	shape.shape = box
	shape.position = Vector3(x, 0.4, 0.0)
	wall.add_child(shape)
	add_child_autofree(wall)


func _otto_at(x: float, y: float = 0.05) -> Otto:
	var otto := OTTO_SCENE.instantiate() as Otto
	add_child_autofree(otto)
	otto.global_position = Vector3(x, y, WorldSpace.PLAY_Z)
	return otto


## An agent who came out at once and does not shoot: the scene is under test, not a duel.
func _agent_at(otto: Otto, x: float, facing: float) -> Enemy:
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.emerge_time = 0.0
	var rules := BuildingRules.new()
	rules.agents_hold_fire = true
	add_child_autofree(agent)
	agent.apply_rules(rules)
	agent.global_position = Vector3(x, 0.05, WorldSpace.PLAY_Z)
	agent.setup(otto, facing)
	return agent


func _director() -> TakedownScene:
	for child: Node in get_children():
		if child is TakedownScene:
			return child
	return null


func _press_shoot() -> void:
	Input.action_press(&"shoot")
	await wait_physics_frames(2)
	Input.action_release(&"shoot")


func _wait_for_the_end(agent: Enemy) -> void:
	var left := SCENE_WAIT
	while left > 0.0 and _director() != null:
		await wait_seconds(0.1)
		left -= 0.1
	assert_null(_director(), "the scene is over")
	assert_true(agent.is_dead(), "the agent is finished off")


func test_shooting_close_up_takes_the_agent_down_from_the_front() -> void:
	_floor()
	var otto := _otto_at(0.0)
	await wait_physics_frames(4)
	var agent := _agent_at(otto, 0.7, -1.0)
	await wait_physics_frames(3)
	var before := GameState.instance().score
	await _press_shoot()
	var director := _director()
	assert_not_null(director, "a point-blank shot — a takedown, not a shot")
	if director == null:
		return
	assert_eq(director.scene().side, Takedown.Side.FRONT, "agent faces Otto — front")
	# The slow-down is uneven (ADR-0050): the approach is faster, toward the blow — [constant
	# TakedownScene.SLOW], on the blow — a freeze frame.
	assert_between(
		Engine.time_scale,
		TakedownScene.SLOW - 0.001,
		TakedownScene.APPROACH + 0.001,
		"the world is slowed down"
	)
	assert_true(otto.takedown != null, "Otto is in the scene")
	var froze := false
	for _frame: int in 600:
		await wait_physics_frames(1)
		if not is_instance_valid(director):
			break
		if director.is_frozen():
			froze = froze or Engine.time_scale < TakedownScene.SLOW * 0.5
		if director.killed() and not director.is_frozen():
			break
	assert_true(froze, "on the blow — freeze frame: the world almost stopped")
	assert_true(agent.is_dead(), "the agent died on the blow")
	assert_false(agent.held, "the dead one is released — falls as a ragdoll, not as a pose")
	var hat := agent.figure.find_child("hat", true, false) as MeshInstance3D
	assert_not_null(hat, "the agent has a hat — its own mesh")
	if hat != null:
		assert_false(hat.visible, "the hat flew off the head")
	assert_not_null(agent.get_parent().find_child("Hat", false, false), "and flew off as a body")
	await _wait_for_the_end(agent)
	assert_eq(GameState.instance().score - before, 200, "front — 200")
	assert_almost_eq(Engine.time_scale, 1.0, 0.001, "the world is back at its own pace")
	assert_null(otto.takedown, "Otto is released")


func test_from_behind_scores_more() -> void:
	_floor()
	var otto := _otto_at(0.0)
	await wait_physics_frames(4)
	var agent := _agent_at(otto, 0.7, 1.0)
	await wait_physics_frames(3)
	var before := GameState.instance().score
	await _press_shoot()
	var director := _director()
	assert_not_null(director, "behind — also a takedown")
	if director == null:
		return
	assert_eq(director.scene().side, Takedown.Side.BACK, "agent has his back — behind")
	await _wait_for_the_end(agent)
	assert_eq(GameState.instance().score - before, 300, "behind — 300")


func test_a_far_agent_is_shot_not_taken_down() -> void:
	_floor()
	var otto := _otto_at(0.0)
	await wait_physics_frames(4)
	_agent_at(otto, 4.0, -1.0)
	await wait_physics_frames(3)
	await _press_shoot()
	assert_null(_director(), "far — no scene")
	assert_gt(get_tree().get_nodes_in_group(Bullet.GROUP).size(), 0, "and the bullet flies")


func test_otto_killed_mid_scene_lets_the_agent_live() -> void:
	# Otto is vulnerable in the scene (ADR-0040, decision 5): if he dies before the key frame — the
	# agent is alive and back in combat, the world at its own pace.
	_floor()
	var otto := _otto_at(0.0)
	await wait_physics_frames(4)
	var agent := _agent_at(otto, 0.7, -1.0)
	await wait_physics_frames(3)
	await _press_shoot()
	assert_not_null(_director(), "the scene started")
	otto.kill()
	await wait_physics_frames(2)
	assert_null(_director(), "the scene was cut off")
	assert_false(agent.is_dead(), "the agent is alive")
	assert_false(agent.held, "and back in combat")
	assert_almost_eq(Engine.time_scale, 1.0, 0.001, "the world at its own pace")


func test_falling_onto_an_agent_pounces_by_itself() -> void:
	_floor()
	# A pen of two low walls: the agent walks faster than Otto falls and gets out from under the
	# falling Otto — in the game that is how it should be, but in the test he turns around in place.
	_wall(-0.9)
	_wall(0.9)
	var otto := _otto_at(-6.0)
	var agent := _agent_at(otto, 0.0, -1.0)
	# Jumping on from above onto one who has come out: in the doorway the agent is invulnerable.
	var wait := 120
	while wait > 0 and not agent.takedown_ready:
		await wait_physics_frames(1)
		wait -= 1
	assert_true(agent.takedown_ready, "the agent came out of the door")
	otto.global_position = Vector3(agent.global_position.x, 2.6, WorldSpace.PLAY_Z)
	var left := 120
	while left > 0 and _director() == null:
		await wait_physics_frames(1)
		left -= 1
	var director := _director()
	assert_not_null(director, "fell on the agent — jumped on without a button")
	if director == null:
		return
	assert_eq(director.scene().side, Takedown.Side.ABOVE, "above")
	await _wait_for_the_end(agent)


func test_a_dead_otto_does_not_pounce() -> void:
	# One killed in flight falls as a body: only a living Otto jumps on.
	_floor()
	_wall(-0.9)
	_wall(0.9)
	var otto := _otto_at(-6.0)
	var agent := _agent_at(otto, 0.0, -1.0)
	var wait := 120
	while wait > 0 and not agent.takedown_ready:
		await wait_physics_frames(1)
		wait -= 1
	otto.global_position = Vector3(agent.global_position.x, 2.6, WorldSpace.PLAY_Z)
	await wait_physics_frames(3)
	otto.kill()
	await wait_seconds(1.0)
	assert_true(otto.is_grounded(), "the body fell")
	assert_null(_director(), "the dead do not jump on")
	assert_false(agent.is_dead(), "the agent is alive")


func test_a_jump_onto_an_agent_pounces() -> void:
	# Feedback after M24e: a jump landing on an agent never made a takedown — jumping on waited for
	# support above the agent's floor. Since M24f, landed close up — jumped on (ADR-0042, decision 9).
	_floor()
	_wall(-0.9)
	_wall(0.9)
	var otto := _otto_at(0.0)
	var agent := _agent_at(otto, 0.0, -1.0)
	# Jumps are made from the floor: the placed Otto first falls down to it.
	var wait := 120
	while wait > 0 and not (agent.takedown_ready and otto.is_grounded()):
		await wait_physics_frames(1)
		wait -= 1
	Input.action_press(&"jump")
	await wait_physics_frames(2)
	Input.action_release(&"jump")
	var left := 120
	while left > 0 and _director() == null:
		await wait_physics_frames(1)
		left -= 1
	var director := _director()
	assert_not_null(director, "jumped onto the agent — jumped on")
	if director == null:
		return
	assert_eq(director.scene().side, Takedown.Side.ABOVE, "above")
	await _wait_for_the_end(agent)


func test_the_director_does_not_push_the_agent_into_a_wall() -> void:
	# An agent pressed against a wall is placed by the director at the wall, not into it (M24d code
	# review): the front scene asks for 0.62–0.72 m, and the wall is closer than that.
	_floor()
	_wall(0.75)
	var otto := _otto_at(0.0)
	await wait_physics_frames(4)
	var agent := _agent_at(otto, 0.45, -1.0)
	var wait := 120
	while wait > 0 and not agent.takedown_ready:
		await wait_physics_frames(1)
		wait -= 1
	agent.global_position.x = 0.45
	await _press_shoot()
	assert_not_null(_director(), "the scene started")
	await wait_seconds(0.2)
	assert_lt(agent.global_position.x, 0.75 - 0.3, "the agent is at the wall, not in it")


func test_a_freed_agent_ends_the_scene_quietly() -> void:
	# The agent was thrown out in the middle of the scene — the scene is removed, the world at its own
	# pace, and nobody accesses the freed node.
	_floor()
	var otto := _otto_at(0.0)
	await wait_physics_frames(4)
	var agent := _agent_at(otto, 0.7, -1.0)
	await wait_physics_frames(3)
	await _press_shoot()
	assert_not_null(_director(), "the scene started")
	agent.free()
	await wait_physics_frames(3)
	assert_null(_director(), "the scene is removed")
	assert_null(otto.takedown, "Otto is released")
	assert_almost_eq(Engine.time_scale, 1.0, 0.001, "the world at its own pace")


## Camera kick on the blow (ADR-0050): the view is shifted and tilted, and within [constant
## SideCamera.KICK_FADE] of real time it settles back.
func test_the_camera_kicks_on_the_blow_and_settles() -> void:
	var target := Node3D.new()
	add_child_autofree(target)
	var camera := SideCamera.new()
	add_child_autofree(camera)
	camera.follow(target)
	await get_tree().process_frame
	var calm := camera.global_position
	camera.kick(1.0)
	var moved := false
	var rolled := false
	for _frame: int in 6:
		await get_tree().process_frame
		moved = moved or not camera.global_position.is_equal_approx(calm)
		rolled = rolled or not is_zero_approx(camera.rotation.z)
	assert_true(moved and rolled, "the frame was kicked and tilted")
	await get_tree().create_timer(SideCamera.KICK_FADE + 0.1, true, false, true).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(camera.is_kicked(), "the kick died down")
	assert_almost_eq(camera.rotation.z, 0.0, 0.0001, "the tilt is removed")


## The whoosh sounds once, at the start of the scene: continuing from the pause slows the
## world down again, silently (ADR-0060).
func test_the_slowdown_whooshes_once_whatever_the_pauses() -> void:
	var sounds := AudioDirector.instance()
	if sounds == null:
		return
	sounds.reset()
	_floor()
	var otto := _otto_at(0.0)
	await wait_physics_frames(4)
	var agent := _agent_at(otto, 0.7, -1.0)
	await wait_physics_frames(3)
	await _press_shoot()
	var director := _director()
	assert_not_null(director, "the scene started")
	if director == null or not is_instance_valid(agent):
		return
	var whooshes := sounds.voices_playing(Sounds.SLOWMO)
	assert_gt(whooshes, 0, "the scene starts with a whoosh")
	for _pause: int in 3:
		director.notification(Node.NOTIFICATION_PAUSED)
		assert_almost_eq(Engine.time_scale, 1.0, 0.001, "the pause gives the world its pace back")
		director.notification(Node.NOTIFICATION_UNPAUSED)
		assert_lt(Engine.time_scale, 1.0, "continuing slows the world down again")
	assert_eq(sounds.voices_playing(Sounds.SLOWMO), whooshes, "and does not whoosh again")
