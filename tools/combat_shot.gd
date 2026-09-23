extends Node3D

## Снимки боя на настоящем здании — по состоянию, а не по секундомеру.
##
## Стойки агента (стоя, на колене, лёжа) игровым сценарием съёмки не поймать:
## тот водится выдержками и снимает то, что успело случиться (docs/testing.md).
## Агент уходит на колено не по расписанию, а когда в него летит высокая пуля,
## — вот этого мига и ждёт инструмент.
##
## Запуск:
##     godot --path . res://tools/combat_shot.tscn
##     godot --path . res://tools/combat_shot.tscn -- --folder=M11 --seed=2 --floor=12
##
## Кадры ложатся в screens/M11/. Папка локальная, в репозиторий не идёт.
##
## Агенту на время съёмки обнуляется дальность огня и скорость шага: уклоняться
## это ему не мешает, зато Otto не застрелят на втором кадре, а сам агент не
## подойдёт вплотную — в упор пуля рождается уже за ним, уклоняться не от чего,
## и вместо стойки выходит труп.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")

const DEFAULT_FOLDER := "M11"

## Сколько кадров дать камере доехать до Otto: сглаживание у неё 8.0.
const SETTLE_FRAMES: int = 45

## Сколько кадров ждать стойки, прежде чем сдаться. Не наступившее состояние
## ждётся вечно, и однажды инструмент уже висел вместо того, чтобы сказать.
const PATIENCE: int = 180

## Где стоит агент, м от Otto. Дальше приседа, но ближе дальности его огня:
## так в кадр влезают оба.
const GAP: float = 4.5

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
	# Стрелять агенту нечем, а уклоняться — есть чем: злости хватает и на колено,
	# и на «лёжа».
	rules.agents_hold_fire = true

	_level = LEVEL_SCENE.instantiate() as GreyboxLevel
	if _level == null:
		# Чаще всего это незарегистрированный class_name: лечится godot_check.py.
		push_error("сцена уровня не собралась — проверьте импорт проекта")
		get_tree().quit(1)
		return
	_level.rules = rules
	_level.building_seed = _seed
	# Своих агентов здание не выпускает: в кадре должен быть один, и на известном
	# месте. Как их выходит по-настоящему, показывает последний кадр.
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

	# Высокая пуля идёт в 1.13 м над полом, колено — 1.05: агент уходит под неё.
	await _stage(EnemyBrain.Stance.KNEEL, false, "02_agent_kneels")

	# Низкая, из приседа, идёт в 0.68 м: колено её уже не пропускает, и агент ложится.
	await _stage(EnemyBrain.Stance.PRONE, true, "03_agent_goes_prone")

	Input.action_release(&"move_down")
	await _crowd()
	await _shoot("04_as_the_game_releases_them")
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


## Снимает кадр в тот миг, когда агент встал в нужную стойку.
## [param crouching] — Otto стреляет из приседа, и пуля идёт ниже.
##
## Стреляет по одной пуле и ждёт чистого неба перед каждой. Очередь тут всё
## ломает: агент уклоняется от ближайшей к нему пули, и пока мимо идёт старая,
## высокая, новую — низкую — он не видит. Она и убивает его вместо того, чтобы
## уложить.
##
## Кадр снимается сразу, как стойка принята, а не после: агент держит её, только
## пока пуля летит, и «сниму потом» показало бы его уже выпрямившимся.
func _stage(wanted: EnemyBrain.Stance, crouching: bool, label: String) -> void:
	if crouching:
		Input.action_press(&"move_down")
		await get_tree().physics_frame

	var left := PATIENCE
	while left > 0 and not _agent.is_dead():
		left -= await _wait_for_clear_sky()
		# Выстрел одиночный, и между нажатием и отпусканием проходит целый кадр:
		# Otto читает выстрел по фронту нажатия, а нажатие и отпускание в одном
		# кадре фронтом не считаются — движок их не видит вовсе.
		Input.action_press(&"shoot")
		await get_tree().physics_frame
		Input.action_release(&"shoot")
		await get_tree().physics_frame
		left -= 2

		while left > 0 and _bullets_in_air() > 0 and not _agent.is_dead():
			await get_tree().physics_frame
			left -= 1
			if _agent.stance() == wanted:
				await _shoot(label)
				return

	push_error(
		(
			"агент не встал в стойку %d за %d кадров: стойка %d, мёртв %s"
			% [wanted, PATIENCE, _agent.stance(), _agent.is_dead()]
		)
	)


## Ждёт, пока в воздухе не останется пуль Otto. Возвращает, сколько кадров ушло.
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


## Возвращает зданию его собственных агентов и даёт дверям время их выпустить:
## последний кадр показывает не поставленного руками, а тех, кого выпускает игра.
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
