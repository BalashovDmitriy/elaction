extends Node3D

## Кадры M24j: каждое сочетание времени суток и погоды — крыша с городом,
## этаж башни, паркинг у выезда (ADR-0051).
##
## Время суток и погода ставятся руками, а не подбором сида: здание одно и то
## же, и сочетания сравниваются рядом. Рендер настоящий — нужен экран.
##
## Запуск:
##     godot --path . res://tools/m24j_shot.tscn
##     godot --path . res://tools/m24j_shot.tscn -- --time=1 --weather=0
##     godot --path . res://tools/m24j_shot.tscn -- --only=roof

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

const FOLDER := "res://screens/M24j"
const SETTLE_FRAMES: int = 50
const BUILDING_SEED: int = 1

const TIME_NAMES: PackedStringArray = ["morning", "day", "evening", "night"]
const WEATHER_NAMES: PackedStringArray = ["clear", "fog", "rain"]

var _level: GreyboxLevel = null
var _folder: String = FOLDER
var _times: Array[int] = [0, 1, 2, 3]
var _weathers: Array[int] = [0, 1, 2]
## Какие кадры снимать: roof, floor, garage, street, room; пусто — все. Улица у
## выезда (M24k, ADR-0052, решение 3) снимается камерой без Otto: он на неё не
## выходит.
var _only: String = ""
var _seed: int = BUILDING_SEED


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--time="):
			_times = [argument.trim_prefix("--time=").to_int()]
		elif argument.begins_with("--weather="):
			_weathers = [argument.trim_prefix("--weather=").to_int()]
		elif argument.begins_with("--only="):
			_only = argument.trim_prefix("--only=")
		elif argument.begins_with("--seed="):
			_seed = argument.trim_prefix("--seed=").to_int()
		elif argument.begins_with("--folder="):
			_folder = "res://screens/" + argument.trim_prefix("--folder=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_folder))
	_run()


func _run() -> void:
	for time: int in _times:
		for weather: int in _weathers:
			await _combo(time, weather)
	Weather.forced = -1
	print("  кадры M24j в %s" % _folder)
	get_tree().quit(0)


func _combo(time: int, weather: int) -> void:
	Weather.forced = weather
	GameState.instance().start_game()
	_level = LEVEL_SCENE.instantiate() as GreyboxLevel
	_level.rules = BuildingRules.new()
	_level.rules.time_of_day = time as TimeOfDay.Kind
	_level.building_seed = _seed
	_level.spawn_agents = false
	add_child(_level)
	var tag := "%d%s_%s" % [time, TIME_NAMES[time], WEATHER_NAMES[weather]]
	if _only == "" or _only == "roof":
		await _shoot_floor("%s_roof" % tag, BuildingRules.ROOF)
	if _only == "" or _only == "floor":
		await _shoot_floor("%s_floor" % tag, 2)
	if _only == "" or _only == "garage":
		var bottom := _level.rules.floors - 1
		_place(_level.plan().exit_x + 2.5, bottom)
		await _shoot("%s_garage" % tag)
	if _only == "" or _only == "street":
		await _shoot_street("%s_street" % tag)
	if _only == "" or _only == "room":
		await _shoot_room("%s_room" % tag)
	remove_child(_level)
	_level.queue_free()
	_level = null
	await get_tree().process_frame


func _shoot_floor(label: String, index: int) -> void:
	var spots := _level.plan().safe_spots(_level.rules, index)
	if spots.is_empty():
		push_error("этаж %d: вставать некуда" % index)
		return
	_place(spots[spots.size() / 2], index)
	await _shoot(label)


func _shoot(label: String) -> void:
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_folder, label]
	image.save_png(path)
	print("  %s" % path)


func _place(x: float, index: int) -> void:
	_level.otto.global_position = WorldSpace.to_scene(Vector2(x, _level.rules.floor_surface(index)))
	_level.otto.velocity = Vector3.ZERO


## Улица у выезда: камера отпускает Otto и встаёт над мостовой левее торца.
func _shoot_street(label: String) -> void:
	var camera := get_viewport().get_camera_3d() as SideCamera
	if camera == null:
		return
	var bottom := _level.rules.floors - 1
	var street := _level.rules.floor_surface(bottom) - _level.rules.floor_height
	var left := _level.rules.floor_span(bottom).x
	for node: Node in _level.find_children("*", "GarageRamp", true, false):
		(node as GarageRamp).show_light(true)
	camera.follow(null)
	camera.apply_bounds(Rect2(-1000.0, -1000.0, 4000.0, 4000.0), false)
	var point := WorldSpace.to_scene(Vector2(left - 9.0, street - 4.5))
	camera.snap_to(Vector2(point.x, point.y))
	await _shoot(label)
	camera.follow(_level.otto)


## Комната за дверью с городом в окне (ADR-0052, решение 5): дверь на этаже
## Otto открывается, как для агента, и кадр — когда створка распахнута.
func _shoot_room(label: String) -> void:
	var index := 4
	var surface := _level.rules.floor_surface(index)
	var door: Door = null
	for node: Node in _level.find_children("*", "Door", true, false):
		var candidate := node as Door
		if candidate != null and is_equal_approx(candidate.mat_position().y, surface):
			door = candidate
			break
	if door == null:
		push_error("на этаже %d нет двери" % index)
		return
	_place(door.mat_position().x + 2.5, index)
	await _settle_frames(20)
	door.summon_agent()
	for _frame: int in 240:
		if door.openness() >= 0.98:
			break
		await get_tree().physics_frame
	await _shoot(label)
	# И крупно: проём с окном и городом за ним.
	var camera := get_viewport().get_camera_3d() as SideCamera
	if camera != null:
		var at := WorldSpace.to_scene(door.mat_position())
		var otto := _level.otto.global_position
		var centre := Vector2(at.x, at.y + 1.4)
		camera.close_up(0.75, Vector2(otto.x, otto.y) + (centre - Vector2(otto.x, otto.y)) / 0.75)
		await _shoot(label + "_close")
		camera.close_up(0.0, Vector2.ZERO)


func _settle_frames(count: int) -> void:
	for _frame: int in count:
		await get_tree().physics_frame
