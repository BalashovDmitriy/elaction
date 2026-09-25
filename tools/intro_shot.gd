extends Node3D

## Снимки вступления M24b: вертолёт привозит Otto на крышу (ADR-0038, решение 1).
##
## Сценарий съёмки начинает с приземления — ждёт, пока Otto встанет, — и сама
## сценка в него не попадает. Инструмент собирает здание и снимает вступление по
## состоянию, а не секундомером: вертолёт влетает, висит, трос спущен, Otto
## на тросе, приземлился, вертолёт уходит. `--model` — модель крупно, на сером
## фоне с ровным светом: проверить, куда смотрит нос и где винт.
##
## Запуск:
##     godot --path . res://tools/intro_shot.tscn
##     godot --path . res://tools/intro_shot.tscn -- --folder=M24b --seed=3 --building=2
##     godot --path . res://tools/intro_shot.tscn -- --model
##
## Кадры ложатся в screens/<папка>/ — папка локальная, в репозиторий не идёт.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")

const DEFAULT_FOLDER := "M24b"

## Сколько кадров ждать события, прежде чем сдаться.
const PATIENCE: int = 900

var _level: GreyboxLevel = null
var _seed: int = 1
var _building: int = 1
var _folder: String = DEFAULT_FOLDER
var _model: bool = false


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			_seed = argument.trim_prefix("--seed=").to_int()
		elif argument.begins_with("--building="):
			_building = argument.trim_prefix("--building=").to_int()
		elif argument.begins_with("--folder="):
			_folder = argument.trim_prefix("--folder=").strip_edges()
		elif argument == "--model":
			_model = true
	DirAccess.make_dir_recursive_absolute("res://screens/%s" % _folder)
	SCREENSHOTTER.mark_ignored_by_engine(ProjectSettings.globalize_path("res://screens"))
	get_window().size = Vector2i(1920, 1080)
	if _model:
		_run_model.call_deferred()
	else:
		_run.call_deferred()


func _run() -> void:
	GameState.instance().start_game()
	GameState.instance().building = _building
	_level = LEVEL_SCENE.instantiate() as GreyboxLevel
	_level.rules = BuildingRules.new()
	_level.building_seed = _seed
	_level.spawn_agents = false
	add_child(_level)

	await _frames(40)
	await _shoot("01_flying_in")
	if await _until(func() -> bool: return _heli() != null and _heli().is_hovering()):
		await _frames(2)
		await _shoot("02_hovering")
	if await _until(func() -> bool: return _heli() != null and _heli().rope_is_down()):
		await _shoot("03_rope_down")
	if await _until(func() -> bool: return _falling_through()):
		await _shoot("04_on_the_rope")
	if await _until(func() -> bool: return not _level.is_in_the_intro()):
		await _frames(1)
		await _shoot("05_landed")
	if await _until(func() -> bool: return _heli() == null or _heli().position.x > _otto_x() + 5.0):
		await _shoot("06_leaving")
	get_tree().quit()


func _run_model() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.5, 0.52, 0.56)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.7, 0.72)
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 20.0, 0.0)
	add_child(sun)
	var helicopter := Helicopter.new()
	add_child(helicopter)
	helicopter.fly_in(Vector3.ZERO)
	helicopter.set_physics_process(false)
	helicopter.position = Vector3(0.0, 0.0, -1.15)
	helicopter.lower_rope(0.0)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.0
	camera.position = Vector3(0.0, 1.6, 10.0)
	add_child(camera)
	camera.make_current()
	await _frames(10)
	await _shoot("00_model_side")
	camera.position = Vector3(0.0, 8.0, 3.0)
	camera.look_at(Vector3(0.0, 1.0, -1.15))
	await _frames(4)
	await _shoot("00_model_top")
	get_tree().quit()


func _heli() -> Helicopter:
	return _level.helicopter()


func _otto_x() -> float:
	return _level.otto.global_position.x


## Otto на тросе и уже поехал: ниже крюка на рост с руками и ещё полметра.
func _falling_through() -> bool:
	var helicopter := _heli()
	if helicopter == null:
		return false
	return _level.otto.global_position.y < helicopter.hook().y - RoofArrival.REACH - 0.8


func _frames(count: int) -> void:
	for _frame: int in count:
		await get_tree().physics_frame


func _until(done: Callable) -> bool:
	for _frame: int in PATIENCE:
		if done.call():
			return true
		await get_tree().physics_frame
	push_error("не дождался события за %d кадров" % PATIENCE)
	return false


func _shoot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "res://screens/%s/intro_%s_seed%d.png" % [_folder, label, _seed]
	image.save_png(path)
	print("  %s" % ProjectSettings.globalize_path(path))
