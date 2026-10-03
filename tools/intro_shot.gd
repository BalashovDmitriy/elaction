extends Node3D

## Intro shots: the helicopter brings Otto to the roof (ADR-0038, decision 1;
## M24k staging, ADR-0052, decision 6).
##
## The capture scenario starts with the landing, waiting until Otto stands up, and the
## scene itself does not get into it. The tool builds a building and shoots the intro by
## state, not by stopwatch: the helicopter flies in, hovers, the rope is lowered, Otto is
## on the rope, has landed, the helicopter leaves. `--model` shows the model close up, on
## a gray background with even light: to check where the nose points and where the rotor
## is.
##
## Since M24k there is a shot for every intro step ([enum RoofArrival.Step]) and for the
## departure: the door slides shut, the pilot nods, the helicopter banks. `--full` is the
## full intro of the first building, otherwise the short one; `--time=0..3` is the time of
## day ([enum TimeOfDay.Kind]); `--series=N` also adds a shot every N physics steps, as a
## frame-by-frame series.
##
## Run:
##     godot --path . res://tools/intro_shot.tscn
##     godot --path . res://tools/intro_shot.tscn -- --folder=M24k --seed=3 --full --time=1
##     godot --path . res://tools/intro_shot.tscn -- --model
##
## Shots go to screens/<folder>/; the folder is local and does not go into the repository.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")

const DEFAULT_FOLDER := "M24b"

## How many frames to wait for an event before giving up.
const PATIENCE: int = 900

var _level: GreyboxLevel = null
var _seed: int = 1
var _building: int = 1
var _folder: String = DEFAULT_FOLDER
var _model: bool = false
var _full: bool = false
var _time: int = TimeOfDay.Kind.NIGHT
var _series: int = 0
## Weather set by hand, or -1 for a draw by the seed.
var _weather: int = -1
var _shot_steps: Dictionary = {}
var _tick: int = 0


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
		elif argument == "--full":
			_full = true
		elif argument.begins_with("--time="):
			_time = clampi(argument.trim_prefix("--time=").to_int(), 0, 3)
		elif argument.begins_with("--weather="):
			_weather = clampi(argument.trim_prefix("--weather=").to_int(), -1, 3)
		elif argument.begins_with("--series="):
			_series = maxi(argument.trim_prefix("--series=").to_int(), 0)
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
	_level.rules.time_of_day = _time as TimeOfDay.Kind
	_level.rules.forced_weather = _weather
	_level.building_seed = _seed
	_level.spawn_agents = false
	_level.full_intro = _full
	add_child(_level)

	# Step by step: the shot is in the middle of each step, when the pose has settled.
	var names := RoofArrival.Step.keys()
	while _level.is_in_the_intro():
		var step := _level.arrival().step()
		_tick += 1
		if not _shot_steps.has(step):
			_shot_steps[step] = _tick
		elif _tick - int(_shot_steps[step]) == 24:
			await _shoot("%02d_%s" % [step + 1, String(names[step]).to_lower()])
		if _series > 0 and _tick % _series == 0:
			await _shoot("s%04d" % _tick)
		await get_tree().physics_frame
	await _frames(2)
	await _shoot("10_landed")
	if await _until(func() -> bool: return _heli() == null or _heli().door_share() < 0.5):
		await _shoot("11_door_closing")
	if await _until(func() -> bool: return _heli() == null or _heli().position.x > _otto_x() + 2.0):
		await _shoot("12_leaving")
	if await _until(func() -> bool: return _heli() == null or _heli().position.x > _otto_x() + 7.0):
		await _shoot("13_banking")
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


## Otto is on the rope and already moving: below the hook by his height with arms plus
## another half meter.
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
	push_error("event not reached within %d frames" % PATIENCE)
	return false


func _shoot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var kind := "full" if _full else "short"
	var path := "res://screens/%s/intro_%s_%s_t%d_seed%d.png" % [_folder, kind, label, _time, _seed]
	image.save_png(path)
	print("  %s" % ProjectSettings.globalize_path(path))
