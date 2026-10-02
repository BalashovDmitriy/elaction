extends SceneTree

## Прохожие крупно, в студии (M24l, ADR-0054, решение 11): ровный пол, свет
## дня, ортокамера сбоку — видно, во что каждый одет, нет ли открытого тела не
## по погоде и как он несёт зонт. По кадру на погоду и время суток: одежда
## зависит от них ([method Passerby.dress_for]).
##
## Запуск (нужен экран):
##     godot --path . --script res://tools/people_shot.gd
##     godot --path . --script res://tools/people_shot.gd -- --weather=2 --time=1

const FOLDER := "res://screens/M24l/people"
const TIME_NAMES: PackedStringArray = ["morning", "day", "evening", "night"]
const WEATHER_NAMES: PackedStringArray = ["clear", "fog", "rain", "snow"]

var _times: Array[int] = [0, 1, 2, 3]
var _weathers: Array[int] = [0, 1, 2, 3]


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--time="):
			_times = [argument.trim_prefix("--time=").to_int()]
		elif argument.begins_with("--weather="):
			_weathers = [argument.trim_prefix("--weather=").to_int()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	root.size = Vector2i(1920, 1080)
	_run.call_deferred()


func _run() -> void:
	for weather in _weathers:
		for time in _times:
			await _shoot(weather, time)
	quit(0)


func _shoot(weather: int, time: int) -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var air := WorldEnvironment.new()
	air.environment = Environment.new()
	air.environment.background_mode = Environment.BG_COLOR
	air.environment.background_color = Color(0.55, 0.57, 0.6)
	air.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	air.environment.ambient_light_color = Color(0.75, 0.75, 0.78)
	air.environment.ambient_light_energy = 0.6
	stage.add_child(air)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0.0)
	sun.light_cull_mask = 0xFFFFFFFF
	stage.add_child(sun)
	var people := StreetPeople.new()
	stage.add_child(people)
	people.build(-6.0, 6.0, 0.0, 7, time as TimeOfDay.Kind, weather as Weather.Kind)
	people.set_process(false)
	# Строем у камеры: по прохожему на полтора метра, лицом вбок.
	var index := 0
	var first := 0.6 - (people.get_child_count() - 1) * 0.8
	for walker in people.get_children():
		var node := walker as Node3D
		node.position = Vector3(first + index * 1.6, 0.0, -9.2 + (index % 2) * 0.6)
		index += 1
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.2
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.position = Vector3(0.6, 1.0, 0.0)
	stage.add_child(camera)
	camera.make_current()
	for _frame: int in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var name := "%s/%d%s_%s.png" % [FOLDER, time, TIME_NAMES[time], WEATHER_NAMES[weather]]
	image.save_png(name)
	print("  %s" % name)
	stage.queue_free()
	await process_frame
