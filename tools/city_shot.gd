extends Node

## Close-up of the M24j city: the city camera at the near row, without defocus — you can see how the
## baked facade, windows and light came out (ADR-0051, decision 10).
##
## Run:
##     godot --path . res://tools/city_shot.tscn -- --time=1 --weather=0
##     godot --path . res://tools/city_shot.tscn -- --time=3 --distance=40

const FOLDER := "res://screens/M24j"
const SETTLE_FRAMES: int = 30

var _time: int = 1
var _weather: int = 0
## How far the camera is in front of the near row, m.
var _distance: float = 35.0
var _haze: bool = false


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--time="):
			_time = argument.trim_prefix("--time=").to_int()
		elif argument.begins_with("--weather="):
			_weather = argument.trim_prefix("--weather=").to_int()
		elif argument.begins_with("--distance="):
			_distance = argument.trim_prefix("--distance=").to_float()
		elif argument == "--haze":
			_haze = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var rules := BuildingRules.new()
	var city := CityBackdrop.new()
	add_child(city)
	city.build(rules, 1, _weather as Weather.Kind, _time as TimeOfDay.Kind)
	var camera: Camera3D = city.get("_camera")
	camera.attributes = null
	camera.fov = 50.0
	var ground := WorldSpace.height_to_scene(rules.floor_surface(rules.floors - 1))
	camera.global_position = Vector3(
		rules.width * 0.5, ground + 25.0, -CityPlan.ROWS[0].x + _distance
	)
	if not _haze:
		(city.get("_city_air") as Environment).fog_enabled = false
	var view: SubViewport = city.get("_view")
	view.size = Vector2i(1600, 900)
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/city_t%d_w%d_d%d.png" % [FOLDER, _time, _weather, int(_distance)]
	view.get_texture().get_image().save_png(path)
	print("  %s" % path)
	get_tree().quit(0)
