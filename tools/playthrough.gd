extends SceneTree

## A run of the real building by the bot: 30 floors, as in the game.
##
## The playthrough test runs a four-floor building with one shaft — that is enough to check that the
## bot can go down at all, but not what the player plays. Here exactly the building the game
## assembles is built, and it shows where the descent gets stuck.
##
## Run:
##     godot --headless --script res://tools/playthrough.gd -- --seeds=1,2,3
##     godot --headless --script res://tools/playthrough.gd -- --seeds=1 --agents
##     godot --headless --script res://tools/playthrough.gd -- --agents --at-once=8
##     godot --headless --script res://tools/playthrough.gd -- --agents --endless --skill=6
##     godot --headless --script res://tools/playthrough.gd -- --seeds=1 --trace --budget=3000
##     godot --headless --script res://tools/playthrough.gd -- --agents --endless --dark-range=2.4
##     godot --headless --script res://tools/playthrough.gd -- --agents --endless --no-lamps
##     godot --headless --script res://tools/playthrough.gd -- --agents --endless --weather=3
##
## With [code]--trace[/code], every [constant TRACE_EVERY] steps it prints where the bot is and what
## is around: floor, position, whether it stands, whether it rides, where the nearest cab is. This
## is a tool for the "stuck" case, when the summary line only gives the floor.
## [code]--budget=N[/code] shortens the run for such diagnostics, and [code]--trace-every=N[/code]
## makes the trace finer.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

## Cap for the building, in **bot steps**. One step is two physics frames, as in the tests. Thirty
## floors and five documents are minutes of game time, so the budget is large.
##
## Half of the former 24000: those were counted in frames, and a step costs two — the number left as
## it was would silently double the cap in clock time. The milestone measurement is 1992–3176 steps.
const STEP_BUDGET: int = 12000

## How many lives the bot gets in an endless run. The same as in the test: the numbers of both must
## agree (`docs/testing.md`, item 4).
const ENDLESS_LIVES: int = 99

## How often to print the trace, in bot steps.
const TRACE_EVERY: int = 300

## Building skill: difficulty level plus cleared buildings (ADR-0027). With it the bot's death rate
## is measured at every level, not only on the first building.
var _skill: int = 0
## From what distance an agent sees Otto in shadow, m; below zero — from the rules. [member
## BuildingRules.agent_dark_fire_range] was tuned with this flag (ADR-0053, decision 4).
var _dark_range: float = -1.0
## The bot does not shoot down lamps: a "no darkness" measurement next to the one with it.
var _no_lamps: bool = false
## Release ban near Otto, m; below zero — from the rules (ADR-0053, decision 3).
var _release_gap: float = -1.0
## Weather set by hand ([enum Weather.Kind]); below zero — a draw by seed. This flag was used to
## measure the slippery roof in snow (ADR-0054, decision 4).
var _weather: int = -1


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var seeds: Array[int] = [1, 2, 3]
	var agents := false
	# Lives do not run out: this shows whether the building can be passed at all, separately from
	# whether three lives are enough for it.
	var endless := false
	# Cap on living agents: 0 — take from the rules. Tuning this number is the main lever of combat
	# density, and it should be turned without editing the file.
	var at_once := 0
	var trace := false
	var trace_every := TRACE_EVERY
	var budget := STEP_BUDGET
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="):
			seeds = []
			for piece in argument.trim_prefix("--seeds=").split(","):
				seeds.append(piece.to_int())
		elif argument == "--agents":
			agents = true
		elif argument == "--endless":
			endless = true
		elif argument == "--trace":
			trace = true
		elif argument.begins_with("--skill="):
			_skill = maxi(argument.trim_prefix("--skill=").to_int(), 0)
		elif argument.begins_with("--at-once="):
			at_once = argument.trim_prefix("--at-once=").to_int()
		elif argument.begins_with("--budget="):
			budget = maxi(argument.trim_prefix("--budget=").to_int(), 1)
		elif argument.begins_with("--trace-every="):
			trace_every = maxi(argument.trim_prefix("--trace-every=").to_int(), 1)
		elif argument.begins_with("--dark-range="):
			_dark_range = argument.trim_prefix("--dark-range=").to_float()
		elif argument == "--no-lamps":
			_no_lamps = true
		elif argument.begins_with("--weather="):
			_weather = argument.trim_prefix("--weather=").to_int()
		elif argument.begins_with("--release-gap="):
			_release_gap = argument.trim_prefix("--release-gap=").to_float()

	Engine.time_scale = 4.0
	var failures := 0
	for building_seed in seeds:
		if not await _play(building_seed, agents, endless, at_once, trace, budget, trace_every):
			failures += 1
	Engine.time_scale = 1.0

	print("\nFailed buildings: %d of %d" % [failures, seeds.size()])
	quit(1 if failures > 0 else 0)


func _play(
	building_seed: int,
	agents: bool,
	endless: bool,
	at_once: int,
	trace: bool,
	budget: int,
	trace_every: int
) -> bool:
	var game := GameState.instance()
	game.reset()
	game.start_game()
	# Run log by the `--log=path` flag: `{seed}` in the path is the seed number.
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(RunLog.FLAG):
			var path := argument.trim_prefix(RunLog.FLAG).replace(
				RunLog.SEED_MARK, str(building_seed)
			)
			RunLog.open(
				ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
			)

	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.rules.skill = _skill
	if at_once > 0:
		level.rules.agents_at_once_cap = at_once
	if _dark_range >= 0.0:
		level.rules.agent_dark_fire_range = _dark_range
	if _release_gap >= 0.0:
		level.rules.agent_release_gap = _release_gap
	level.rules.forced_weather = _weather
	level.building_seed = building_seed
	level.spawn_agents = agents
	root.add_child(level)

	var cleared := [false]
	level.building_cleared.connect(func() -> void: cleared[0] = true)
	var over := [false]
	# [GameState] is a singleton and outlives the building, so the connection is removed at the end of
	# the run: otherwise on the third seed "game over" would fire three closures in a row, and each
	# would hold its own already removed building.
	var on_game_over := func() -> void: over[0] = true
	game.game_over.connect(on_game_over)

	var bot := OttoBot.new(level)
	bot.shoots_lamps = not _no_lamps
	var rules := level.rules
	var lamps_before := level.lamps().size()
	var deepest := 0
	var frames := 0
	var deaths := 0
	# Killed agents: they show whether the bot fought or ran past. Counted by bodies, not points: a
	# lamp kills no worse than a bullet, but the points differ.
	var kills := 0
	var counted: Dictionary = {}
	var was_dead := false
	# How many steps the floor has not changed: this shows getting stuck, not slowness.
	var stuck := 0
	var last_floor := -1

	print(
		(
			"\n=== Seed %d, agents: %s, at most %d at once ==="
			% [building_seed, "yes" if agents else "no", level.rules.agents_at_once(0.0)]
		)
	)

	# Lives are given all at once and with margin — exactly as in the run with combat
	# (`tests/test_building_playthrough.gd`, ENDLESS_LIVES). Topping up at zero would change the course
	# of the game at its sharpest moment, and the tool would measure a different game: on seed 1 it
	# gave two deaths where the test counted four. The tool and the test must measure the same thing
	# (`docs/testing.md`, item 4).
	if endless:
		game.lives = ENDLESS_LIVES
		game.lives_changed.emit(game.lives)

	while not cleared[0] and frames < budget:
		bot.step()
		# Two frames per decision — exactly as many as the bot gets in the tests. There this comes from
		# `wait_physics_frames(1)`, which waits two frames, and on M13 it was kept as a rule: the bot must
		# be the coarsest control loop the game will ever have (`docs/testing.md`, item 4).
		#
		# The tool must drive Otto the same way as the test. On M18a they diverged — here it was one
		# frame, there two — and seed 2 passed in the tool while failing in the test. The investigation
		# took three commits and drifted into combat balance.
		await physics_frame
		await physics_frame
		frames += 1

		var here := rules.floor_index_near(WorldSpace.to_plane(level.otto.global_position).y)
		deepest = maxi(deepest, here)
		if trace and frames % trace_every == 0:
			print(
				(
					"  [%5d] floor %d, Otto %s, riding %s, pressing %s%s; decision: %s"
					% [
						frames,
						here,
						_at(level.otto),
						level.otto.is_riding(),
						_held_keys(),
						_cars_near(level),
						bot.decision()
					]
				)
			)
		for agent in level.agents():
			if agent.is_dead() and not counted.has(agent.get_instance_id()):
				counted[agent.get_instance_id()] = true
				kills += 1
		if level.otto.is_dead() and not was_dead:
			deaths += 1
			print(
				(
					"  death #%d on floor %d, step %d, Otto %s, in cab %s%s"
					% [
						deaths,
						here,
						frames,
						WorldSpace.to_plane(level.otto.global_position),
						level.otto.is_riding(),
						_around(level) + _killer(level)
					]
				)
			)
		was_dead = level.otto.is_dead()

		if here == last_floor:
			stuck += 1
		else:
			if stuck > 900:
				print("  floor %d held the bot for %d steps" % [last_floor, stuck])
			stuck = 0
			last_floor = here
		if over[0]:
			print("  game over on floor %d, step %d" % [here, frames])
			break

	bot.release()
	var ok: bool = cleared[0] and game.documents_collected == game.documents_total
	var verdict := "passed" if ok else "FAILED"
	print(
		(
			"  %s: steps %d, floor %d/%d, documents %d/%d, deaths %d, killed %d, score %d, lamps shot %d/%d"
			% [
				verdict,
				frames,
				deepest,
				rules.floors - 1,
				game.documents_collected,
				game.documents_total,
				deaths,
				kills,
				game.score,
				lamps_before - level.lamps().size(),
				lamps_before
			]
		)
	)
	if not ok:
		print("  stuck on floor %d, standing there for %d steps" % [last_floor, stuck])

	game.game_over.disconnect(on_game_over)
	root.remove_child(level)
	level.free()
	return ok


## Who stands near Otto: the three nearest agents with their distance to him.
##
## Printing all of them is not an option: in the real building there are about sixty, and the death
## line grows to the whole screen. Only those who can reach Otto are of interest.
func _around(level: GreyboxLevel) -> String:
	var here := _at(level.otto)
	# Corpses lie until the end of the building (ADR-0037, decision 6), and the living ones are of
	# interest.
	var near: Array[Enemy] = []
	for agent in level.agents():
		if not agent.is_dead():
			near.append(agent)
	near.sort_custom(
		func(a: Enemy, b: Enemy) -> bool: return here.distance_to(_at(a)) < here.distance_to(_at(b))
	)

	var parts := PackedStringArray()
	for index in mini(3, near.size()):
		var agent := near[index]
		parts.append("agent %s (%.2f m)" % [_at(agent), here.distance_to(_at(agent))])
	if near.is_empty():
		return ""
	return " | agents %d, nearest: %s" % [near.size(), ", ".join(parts)]


## What most likely got him: the nearest enemy bullet and the nearest cab.
##
## Without this a death "in a cab" is indistinguishable from a death under a cab, and these are
## different troubles: the first is cured by balance, the second by shaft rules.
func _killer(level: GreyboxLevel) -> String:
	var here := _at(level.otto)
	var parts := PackedStringArray()

	var closest := INF
	var aim := 0.0
	for node in level.get_tree().get_nodes_in_group(Bullet.GROUP):
		var bullet := node as Bullet
		if bullet == null or bullet.collision_mask != Bullet.FROM_ENEMY:
			continue
		var gap := here.distance_to(_at(bullet))
		if gap < closest:
			closest = gap
			aim = here.y - _at(bullet).y
	if closest < INF:
		parts.append("bullet at %.2f m, above the feet by %.2f" % [closest, aim])

	for child in level.get_children():
		var car := child as ElevatorCar
		if car == null:
			continue
		var to_car := _at(car) - here
		if to_car.length() > 0.6:
			continue
		parts.append("cab %s, aligned: %s" % [to_car, car.is_aligned()])

	if parts.is_empty():
		return " | no bullet or cab nearby"
	return " | " + ", ".join(parts)


## Where the node stands in the rules plane: the run, like the bot, thinks in the same place as the
## layout and converts from the scene in one place.
static func _at(node: Node3D) -> Vector2:
	return WorldSpace.to_plane(node.global_position)


## Cabs on Otto's floor and the one nearest to him vertically: they show whether the bot is waiting
## for a cab that does not come, or standing next to one that has arrived.
func _cars_near(level: GreyboxLevel) -> String:
	var here := _at(level.otto)
	var nearest := ""
	var gap := INF
	for child in level.get_children():
		var car := child as ElevatorCar
		if car == null:
			continue
		var at := _at(car)
		var distance := here.distance_to(at)
		if distance < gap:
			gap = distance
			nearest = "cab %s (%.2f m, aligned %s)" % [at, distance, car.is_aligned()]
	return "" if nearest.is_empty() else " | nearest " + nearest


## What the bot holds pressed after its step: this shows whether it decided to walk.
func _held_keys() -> String:
	var keys := PackedStringArray()
	for action: StringName in [
		&"move_left", &"move_right", &"move_up", &"move_down", &"jump", &"shoot"
	]:
		if Input.is_action_pressed(action):
			keys.append(String(action).trim_prefix("move_"))
	return "[%s]" % ",".join(keys)
