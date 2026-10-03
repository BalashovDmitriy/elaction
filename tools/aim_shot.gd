extends Node3D

## M24a shot captures — by state, not by stopwatch (ADR-0037, decision 5).
##
## The aim beam is lit only during an agent's wind-up, the tracer — for a couple of frames, sparks —
## for a fraction of a second: a capture script with delays does not catch them. The tool puts an
## agent opposite Otto and shoots by events: the beam is lit, the bullet has left, the bullet hit
## the wall, the body lay down.
##
## Run:
##     godot --path . res://tools/aim_shot.tscn
##     godot --path . res://tools/aim_shot.tscn -- --folder=M24a --floor=17 --gap=2.5
##     godot --path . res://tools/aim_shot.tscn -- --out=C:/tmp/combat
##
## Frames go to screens/<folder>/ (the folder is local, it does not go into the repository) or to
## the [code]--out[/code] directory. Floor seventeen of a real building is dark
## (ROM 13): there the beam is the only sign of a shot.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")

const DEFAULT_FOLDER := "M24a"

## How many frames to give the camera to reach Otto: its smoothing is 8.0.
const SETTLE_FRAMES: int = 45

## How many frames to wait for an event before giving up: one that never happens would be waited
## for forever.
const PATIENCE: int = 600

## Where the agent stands, m from Otto: both in the frame, and the beam is long. On a dark floor
## an agent sees Otto only up close — there he is placed closer, [code]--gap=[/code].
const GAP: float = 6.0

var _level: GreyboxLevel = null
var _agent: Enemy = null
var _seed: int = 1
var _floor: int = 12
var _folder: String = DEFAULT_FOLDER
var _out: String = ""
var _gap: float = GAP


func _ready() -> void:
	_read_arguments()
	DirAccess.make_dir_recursive_absolute(_folder_path())
	if _out.is_empty():
		SCREENSHOTTER.mark_ignored_by_engine(
			ProjectSettings.globalize_path(_folder_path().get_base_dir())
		)
	_run()


func _folder_path() -> String:
	if not _out.is_empty():
		return _out
	return "res://screens/%s" % (_folder if not _folder.is_empty() else DEFAULT_FOLDER)


func _read_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			_seed = argument.trim_prefix("--seed=").to_int()
		elif argument.begins_with("--folder="):
			_folder = argument.trim_prefix("--folder=").strip_edges()
		elif argument.begins_with("--floor="):
			_floor = argument.trim_prefix("--floor=").to_int()
		elif argument.begins_with("--gap="):
			_gap = argument.trim_prefix("--gap=").to_float()
		elif argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=").strip_edges()


func _run() -> void:
	var rules := BuildingRules.new()
	_level = LEVEL_SCENE.instantiate() as GreyboxLevel
	if _level == null:
		push_error("сцена уровня не собралась — проверьте импорт проекта")
		get_tree().quit(1)
		return
	_level.rules = rules
	_level.building_seed = _seed
	_level.spawn_agents = false
	add_child(_level)
	await get_tree().physics_frame

	var spot := await _stand_on(_floor)
	_agent = ENEMY_SCENE.instantiate() as Enemy
	_agent.apply_rules(rules)
	_level.add_child(_agent)
	_agent.global_position = WorldSpace.to_scene(Vector2(spot + _gap, rules.floor_surface(_floor)))
	_agent.walk_speed = 0.0
	_agent.setup(_level.otto, -1.0)
	# Anger zero — the longest wind-up, 10 ticks: the beam is visible the longest.
	_agent.set_threat(0, rules.skill, false)

	# The beam in the middle of the wind-up: the pistol raised, the dot on Otto.
	if await _until(func() -> bool: return _agent.laser.is_on() and _agent.laser.shot_in < 0.4):
		await _shoot("01_laser_on_otto")
	# Under a high beam Otto crouches: the beam goes over him into the wall.
	Input.action_press(&"move_down")
	for _frame: int in 3:
		await get_tree().physics_frame
	if _agent.laser.is_on():
		await _shoot("02_laser_over_crouching_otto")
	if await _until(func() -> bool: return not _agent.laser.is_on() and _enemy_bullets() > 0):
		await _shoot("03_agent_tracer")
	Input.action_release(&"move_down")

	# Otto's shot into the wall behind his back: a tracer, then sparks, dust and a mark.
	Input.action_press(&"move_left")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(&"move_left")
	await get_tree().physics_frame
	Input.action_press(&"shoot")
	await get_tree().physics_frame
	Input.action_release(&"shoot")
	await get_tree().physics_frame
	await _shoot("04_otto_tracer")
	if await _until(func() -> bool: return _otto_bullets() == 0):
		await get_tree().physics_frame
		await _shoot("05_impact")
	for _frame: int in 50:
		await get_tree().physics_frame
	await _shoot("06_bullet_hole")

	_agent.kill()
	for _frame: int in 120:
		await get_tree().physics_frame
	await _shoot("07_corpse")
	get_tree().quit()


## Puts Otto on a floor and waits until the camera arrives. Returns his position.
func _stand_on(index: int) -> float:
	var spot := _level.plan().safe_x(_level.rules, index)
	_level.otto.global_position = WorldSpace.to_scene(
		Vector2(spot, _level.rules.floor_surface(index))
	)
	for _frame: int in SETTLE_FRAMES:
		await get_tree().physics_frame
	return spot


## Waits until [param done] becomes true. Returns whether it got there.
func _until(done: Callable) -> bool:
	for _frame: int in PATIENCE:
		if done.call():
			return true
		await get_tree().physics_frame
	push_error("не дождался события за %d кадров" % PATIENCE)
	return false


func _enemy_bullets() -> int:
	return _bullets(Bullet.FROM_ENEMY)


func _otto_bullets() -> int:
	return _bullets(Bullet.FROM_OTTO)


func _bullets(mask: int) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(Bullet.GROUP):
		var bullet := node as Bullet
		if bullet != null and bullet.collision_mask == mask:
			count += 1
	return count


func _shoot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s_seed%d_floor%d.png" % [_folder_path(), label, _seed, _floor]
	image.save_png(path)
	print("  %s" % path)
