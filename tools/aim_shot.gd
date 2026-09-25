extends Node3D

## Снимки выстрела M24a — по состоянию, а не по секундомеру (ADR-0037, решение 5).
##
## Луч прицела горит только замах агента, трассер — пару кадров, искры — долю
## секунды: сценарий съёмки с выдержками их не застаёт. Инструмент ставит агента
## напротив Otto и снимает по событиям: луч горит, пуля вылетела, пуля ударила в
## стену, тело легло.
##
## Запуск:
##     godot --path . res://tools/aim_shot.tscn
##     godot --path . res://tools/aim_shot.tscn -- --folder=M24a --floor=17 --gap=2.5
##     godot --path . res://tools/aim_shot.tscn -- --out=C:/tmp/combat
##
## Кадры ложатся в screens/<папка>/ (папка локальная, в репозиторий не идёт) или в
## каталог [code]--out[/code]. Семнадцатый этаж настоящего здания — тёмный
## (ROM 13): там луч — единственный знак выстрела.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")

const DEFAULT_FOLDER := "M24a"

## Сколько кадров дать камере доехать до Otto: сглаживание у неё 8.0.
const SETTLE_FRAMES: int = 45

## Сколько кадров ждать события, прежде чем сдаться: не наступившее ждалось бы
## вечно.
const PATIENCE: int = 600

## Где стоит агент, м от Otto: оба в кадре, и луч длинный. На тёмном этаже
## агент видит Otto только вблизи — там его ставят ближе, [code]--gap=[/code].
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
	# Злость ноль — замах самый долгий, 10 тиков: луч виден дольше всего.
	_agent.set_threat(0, rules.skill, false)

	# Луч в середине замаха: пистолет вскинут, точка на Otto.
	if await _until(func() -> bool: return _agent.laser.is_on() and _agent.laser.shot_in < 0.4):
		await _shoot("01_laser_on_otto")
	# Под высокий луч Otto приседает: луч уходит над ним в стену.
	Input.action_press(&"move_down")
	for _frame: int in 3:
		await get_tree().physics_frame
	if _agent.laser.is_on():
		await _shoot("02_laser_over_crouching_otto")
	if await _until(func() -> bool: return not _agent.laser.is_on() and _enemy_bullets() > 0):
		await _shoot("03_agent_tracer")
	Input.action_release(&"move_down")

	# Выстрел Otto в стену за спиной: трассер, потом искры, пыль и след.
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


## Ставит Otto на этаж и ждёт, пока камера доедет. Возвращает его место.
func _stand_on(index: int) -> float:
	var spot := _level.plan().safe_x(_level.rules, index)
	_level.otto.global_position = WorldSpace.to_scene(
		Vector2(spot, _level.rules.floor_surface(index))
	)
	for _frame: int in SETTLE_FRAMES:
		await get_tree().physics_frame
	return spot


## Ждёт, пока [param done] не станет истинным. Возвращает, дождался ли.
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
