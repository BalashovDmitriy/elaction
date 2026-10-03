extends Node3D

## Combat shots on a real building, by state rather than by stopwatch.
##
## Agent stances (standing, kneeling, lying) cannot be caught by the gameplay capture
## scenario: it is driven by delays and shoots whatever has managed to happen
## (docs/testing.md). An agent drops to one knee not on a schedule but when a high bullet
## flies at him, and that is the moment the tool waits for.
##
## Run:
##     godot --path . res://tools/combat_shot.tscn
##     godot --path . res://tools/combat_shot.tscn -- --folder=M11 --seed=2 --floor=12
##
## Shots go to screens/M11/. The folder is local and does not go into the repository.
##
## For the duration of the shoot the agent's fire range and step speed are zeroed: this
## does not stop him from dodging, but Otto will not get shot on the second frame, and
## the agent will not come up close: point-blank the bullet is born already behind him,
## there is nothing to dodge, and instead of a stance you get a corpse.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")

const DEFAULT_FOLDER := "M11"

## How many frames to give the camera to reach Otto: its smoothing is 8.0.
const SETTLE_FRAMES: int = 45

## How many frames to wait for a stance before giving up. A state that never comes is
## waited for forever, and once the tool already hung instead of saying so.
const PATIENCE: int = 180

## Where the agent stands, m from Otto. Farther than the crouch but closer than his fire
## range: this way both fit into the frame.
const GAP: float = 4.5

## How many frames to give the pose to finish blending before the shot.
const POSE_SETTLE_FRAMES: int = 12

var _level: GreyboxLevel = null
var _agent: Enemy = null
var _seed: int = 1
var _floor: int = 12
var _folder: String = DEFAULT_FOLDER


func _ready() -> void:
	_read_arguments()
	DirAccess.make_dir_recursive_absolute(_folder_path())
	SCREENSHOTTER.mark_ignored_by_engine(
		ProjectSettings.globalize_path(_folder_path().get_base_dir())
	)
	_run()


func _folder_path() -> String:
	return "res://screens/%s" % (_folder if not _folder.is_empty() else DEFAULT_FOLDER)


func _read_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			_seed = argument.trim_prefix("--seed=").to_int()
		elif argument.begins_with("--folder="):
			_folder = argument.trim_prefix("--folder=").strip_edges()
		elif argument.begins_with("--floor="):
			_floor = argument.trim_prefix("--floor=").to_int()


func _run() -> void:
	var rules := BuildingRules.new()
	# The agent has nothing to shoot with, but has something to dodge with: his anger is
	# enough both for kneeling and for "lying".
	rules.agents_hold_fire = true

	_level = LEVEL_SCENE.instantiate() as GreyboxLevel
	if _level == null:
		# Most often this is an unregistered class_name: fixed by godot_check.py.
		push_error("the level scene did not build — check the project import")
		get_tree().quit(1)
		return
	_level.rules = rules
	_level.building_seed = _seed
	# The building does not release its own agents: the frame must have one, in a known
	# place. How they come out for real is shown by the last shot.
	_level.spawn_agents = false
	add_child(_level)
	await get_tree().physics_frame

	var spot := await _stand_on(_floor)
	_agent = ENEMY_SCENE.instantiate() as Enemy
	_agent.apply_rules(rules)
	_level.add_child(_agent)
	_agent.global_position = WorldSpace.to_scene(Vector2(spot + GAP, rules.floor_surface(_floor)))
	_agent.walk_speed = 0.0
	_agent.setup(_level.otto, -1.0)
	_agent.set_threat(Arcade.TOP, rules.skill, false)
	await get_tree().physics_frame
	await _shoot("01_standoff")

	# A high bullet goes 1.13 m above the floor, a knee is 1.05: the agent ducks under it.
	await _stage(EnemyBrain.Stance.KNEEL, false, "02_agent_kneels")

	# A low one, from a crouch, goes at 0.68 m: kneeling no longer lets it pass, and the
	# agent lies down.
	await _stage(EnemyBrain.Stance.PRONE, true, "03_agent_goes_prone")

	Input.action_release(&"move_down")
	await _crowd()
	await _shoot("04_as_the_game_releases_them")
	get_tree().quit()


## Puts Otto on a floor and waits for the camera to arrive. Returns his position.
func _stand_on(index: int) -> float:
	var spot := _level.plan().safe_x(_level.rules, index)
	_level.otto.global_position = WorldSpace.to_scene(
		Vector2(spot, _level.rules.floor_surface(index))
	)
	for _frame: int in SETTLE_FRAMES:
		await get_tree().physics_frame
	return spot


## Takes a shot at the moment the agent has taken the required stance.
## [param crouching]: Otto shoots from a crouch, and the bullet goes lower.
##
## Fires one bullet at a time and waits for a clear sky before each. A burst breaks
## everything here: the agent dodges the bullet nearest to him, and while an old, high
## one is passing, he does not see the new, low one. It then kills him instead of
## making him lie down.
##
## The shot is taken as soon as the stance is taken, not afterward: the agent holds it
## only while the bullet is flying, and "shoot later" would show him already upright.
func _stage(wanted: EnemyBrain.Stance, crouching: bool, label: String) -> void:
	# A dodge in the ROM is a whole action (@1C7A): while the agent is in the previous
	# stance, he will not take a new one, and the low bullet would catch him kneeling.
	while not _agent.is_dead() and _agent.stance() != EnemyBrain.Stance.STAND:
		await get_tree().physics_frame
	if crouching:
		Input.action_press(&"move_down")
		await get_tree().physics_frame

	var left := PATIENCE
	while left > 0 and not _agent.is_dead():
		left -= await _wait_for_clear_sky()
		# The shot is single, and a whole frame passes between press and release:
		# Otto reads a shot by the press edge, and a press and release in the same
		# frame do not count as an edge: the engine does not see them at all.
		Input.action_press(&"shoot")
		await get_tree().physics_frame
		Input.action_release(&"shoot")
		await get_tree().physics_frame
		left -= 2

		while left > 0 and _bullets_in_air() > 0 and not _agent.is_dead():
			await get_tree().physics_frame
			left -= 1
			if _agent.stance() == wanted:
				# The rig blends poses smoothly (ADR-0022, decision 2): shot in the same
				# frame, the agent would come out halfway between two stances.
				for _frame in POSE_SETTLE_FRAMES:
					await get_tree().physics_frame
				await _shoot(label)
				return

	push_error(
		(
			"agent did not reach stance %d within %d frames: stance %d, dead %s"
			% [wanted, PATIENCE, _agent.stance(), _agent.is_dead()]
		)
	)


## Waits until no Otto bullets are left in the air. Returns how many frames it took.
func _wait_for_clear_sky() -> int:
	var spent := 0
	while _bullets_in_air() > 0 and spent < PATIENCE:
		await get_tree().physics_frame
		spent += 1
	return spent


func _bullets_in_air() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(Bullet.GROUP):
		var bullet := node as Bullet
		if bullet != null and bullet.collision_mask == Bullet.FROM_OTTO:
			count += 1
	return count


## Returns the building its own agents and gives the doors time to release them:
## the last shot shows not one placed by hand but those the game releases.
func _crowd() -> void:
	_agent.kill()
	_level.spawn_agents = true
	for _frame: int in PATIENCE:
		await get_tree().physics_frame


func _shoot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s_seed%d_floor%d.png" % [_folder_path(), label, _seed, _floor]
	image.save_png(path)
	print("  %s" % path)
