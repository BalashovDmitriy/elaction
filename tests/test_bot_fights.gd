extends GutTest

## The bot can fight: meeting an agent on its line, it kills him.
##
## The test is about the measuring tool itself, not the game — and yet the most important of
## the new ones. Single actions, shot and jump, the engine reports by the press
## edge: releasing and pressing them in one frame is not enough, there will be no edge. The bot
## did exactly that, and for the whole M11 milestone the measurements showed a game in which Otto
## never once fired and never once jumped. The figures in ADR-0016 were collected by that bot,
## and they were rewritten only after this check.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")

## How many frames are given to the duel. The bullet flies 6.6 m/s, the agent stands a couple of
## metres away — that is a fraction of a second; the rest is margin for wind-up and a miss.
const DUEL_FRAMES: int = 300

## How many frames the building is given to settle into place.
const SETTLE_FRAMES: int = 4

## A floor in the middle of the building: neither the roof nor the exit.
const FLOOR: int = 5


func before_all() -> void:
	Engine.time_scale = 4.0


func after_all() -> void:
	Engine.time_scale = 1.0
	GameState.instance().reset()


## The building is real, but it does not release its own agents: the duel must have
## exactly one opponent, otherwise it is unclear whom the bot got.
func _build() -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = 1
	level.spawn_agents = false
	add_child_autofree(level)
	return level


func test_the_bot_shoots_the_agent_in_its_way() -> void:
	var level := _build()
	await wait_physics_frames(SETTLE_FRAMES)

	var rules := level.rules
	var spots := level.plan().safe_spots(rules, FLOOR)
	assert_gt(spots.size(), 1, "the floor has room for both to stand")

	# Not the first two slots but the two nearest each other: between neighbouring slots there can
	# be an occupied one — a shaft, an escalator opening — and the first pair would be half a floor
	# apart. From that edge the agent is no longer a target for the bot, and there would be no duel
	# at all.
	var pair := _closest_pair(spots)
	var gap := pair.y - pair.x
	assert_lt(gap, OttoBot.ENGAGE, "the agent stands in the bot's field of view")

	var surface := rules.floor_surface(FLOOR)
	level.otto.global_position = WorldSpace.to_scene(Vector2(pair.x, surface))
	var agent := ENEMY_SCENE.instantiate() as Enemy
	level.add_child(agent)
	agent.global_position = WorldSpace.to_scene(Vector2(pair.y, surface))
	agent.apply_rules(rules)
	agent.setup(level.otto, -1.0)
	await wait_physics_frames(SETTLE_FRAMES)

	var bot := OttoBot.new(level)
	var frames := 0
	# Two frames per decision, as in all bot runs: this is an M13 rule, not
	# an oversight. Details — `tests/test_building_playthrough.gd`, method `_tick`,
	# and `docs/testing.md`, point 4.
	while not agent.is_dead() and frames < DUEL_FRAMES:
		bot.step()
		await wait_physics_frames(1)
		frames += 1
	bot.release()

	assert_true(
		agent.is_dead(), "the bot did not get the agent at %.2f m in %d frames" % [gap, DUEL_FRAMES]
	)
	assert_false(level.otto.is_dead(), "and stayed alive himself")
	remove_child(level)


## The bot dodges a shot by the aim laser, not by the bullet (ADR-0037, decision 5):
## under a high one it crouches at once, over a low one it jumps only when the bullet is about
## to arrive — jumping earlier, it would land right on it.
##
## The laser is lit by hand and the agent is frozen: what is checked is how the bot reads the laser,
## not the draw of the shooting pose.
func test_the_bot_answers_the_aiming_laser() -> void:
	var level := _build()
	await wait_physics_frames(SETTLE_FRAMES)
	var rules := level.rules
	var pair := _closest_pair(level.plan().safe_spots(rules, FLOOR))
	var surface := rules.floor_surface(FLOOR)
	level.otto.global_position = WorldSpace.to_scene(Vector2(pair.x, surface))
	# The agent stands and does not shoot until the test freezes him: otherwise he would walk up
	# point-blank or shoot himself.
	rules.agents_hold_fire = true
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.walk_speed = 0.0
	level.add_child(agent)
	agent.global_position = WorldSpace.to_scene(Vector2(pair.y, surface))
	agent.apply_rules(rules)
	agent.setup(level.otto, -1.0)
	await wait_physics_frames(SETTLE_FRAMES * 4)
	# A frozen agent does not put out the laser: the test lights it.
	agent.process_mode = Node.PROCESS_MODE_DISABLED
	var bot := OttoBot.new(level)

	_aim(agent, Proportions.SHOT_HIGH, 1.0)
	bot.step()
	assert_true(Input.is_action_pressed(&"move_down"), "under a high ray - crouch")
	assert_false(Input.is_action_pressed(&"move_right"), "and do not fight while turned away")
	bot.release()
	await wait_physics_frames(2)

	_aim(agent, Proportions.SHOT_LOW, 2.0)
	bot.step()
	assert_false(Input.is_action_pressed(&"jump"), "low ray, bullet not soon - too early to jump")
	bot.release()
	await wait_physics_frames(2)

	_aim(agent, Proportions.SHOT_LOW, 0.2)
	bot.step()
	assert_true(Input.is_action_pressed(&"jump"), "bullet any moment - jump")
	bot.release()
	remove_child(level)


## Lights the agent's laser at height [param height] above the floor: the bullet leaves in
## [param shot_in] seconds.
func _aim(agent: Enemy, height: float, shot_in: float) -> void:
	agent.laser.position = Vector3(-Proportions.MUZZLE, height, 0.0)
	agent.laser.shot_in = shot_in
	agent.laser.shot_speed = Arcade.agent_shot_speed(0, false)
	agent.laser.aim(-1.0)


## The bot does not shoot an agent with his back to it, but sneaks up and takes him down from behind
## (ADR-0040): that is worth more, and that is how it shows takedowns in the demo (ADR-0041).
func test_the_bot_takes_down_an_agent_from_behind() -> void:
	var level := _build()
	await wait_physics_frames(SETTLE_FRAMES)
	var rules := level.rules
	var pair := _closest_pair(level.plan().safe_spots(rules, FLOOR))
	var surface := rules.floor_surface(FLOOR)
	level.otto.global_position = WorldSpace.to_scene(Vector2(pair.x, surface))
	rules.agents_hold_fire = true
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.walk_speed = 0.0
	level.add_child(agent)
	agent.global_position = WorldSpace.to_scene(
		Vector2(minf(pair.y, pair.x + OttoBot.TAKEDOWN_SNEAK * 0.6), surface)
	)
	agent.apply_rules(rules)
	# Back to Otto: faces away from him, to the right.
	agent.setup(level.otto, 1.0)
	await wait_physics_frames(SETTLE_FRAMES * 4)
	var before := GameState.instance().score
	var bot := OttoBot.new(level)
	var frames := 0
	var took := false
	while not agent.is_dead() and frames < DUEL_FRAMES:
		bot.step()
		took = took or level.otto.takedown != null
		await wait_physics_frames(1)
		frames += 1
	bot.release()
	assert_true(took, "the bot finished him off instead of shooting")
	assert_true(agent.is_dead(), "the agent is finished off")
	assert_eq(
		GameState.instance().score - before,
		Takedown.score(Takedown.Side.BACK, agent.is_in_the_dark()),
		"from behind"
	)
	remove_child(level)


## The two floor slots nearest each other: left and right.
func _closest_pair(spots: PackedFloat64Array) -> Vector2:
	var best := Vector2(spots[0], spots[1])
	for index in range(1, spots.size() - 1):
		if spots[index + 1] - spots[index] < best.y - best.x:
			best = Vector2(spots[index], spots[index + 1])
	return best
