extends Node3D

## M24j shots: every combination of time of day and weather — the roof with the city,
## a tower floor, the garage at the exit (ADR-0051).
##
## Time of day and weather are set by hand, not by picking a seed: the building is the
## same, and combinations are compared side by side. The render is real — a screen is
## needed.
##
## Launch:
##     godot --path . res://tools/m24j_shot.tscn
##     godot --path . res://tools/m24j_shot.tscn -- --time=1 --weather=0
##     godot --path . res://tools/m24j_shot.tscn -- --only=roof
##     godot --path . res://tools/m24j_shot.tscn -- --only=floor --kind=2 --floor=24

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

const FOLDER := "res://screens/M24j"
const SETTLE_FRAMES: int = 50
const BUILDING_SEED: int = 1

const TIME_NAMES: PackedStringArray = ["morning", "day", "evening", "night"]
const WEATHER_NAMES: PackedStringArray = ["clear", "fog", "rain", "snow"]

var _level: GreyboxLevel = null
var _folder: String = FOLDER
var _times: Array[int] = [0, 1, 2, 3]
var _weathers: Array[int] = [0, 1, 2, 3]
## Which shots to take: roof, floor, garage, street, room; empty — all. The exit street
## (M24k, ADR-0052, decision 3) is shot by a camera without Otto: he does not go out
## there.
var _only: String = ""
var _seed: int = BUILDING_SEED
## Building kind ([enum BuildingIdentity.Kind]): `--kind=2` — residential. −1 — whatever
## the first building of the game gets, the hotel.
var _kind: int = -1
## Which floor the floor shot takes: `--floor=24` — the podium below.
var _floor: int = 2


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--time="):
			_times = [argument.trim_prefix("--time=").to_int()]
		elif argument.begins_with("--weather="):
			_weathers = [argument.trim_prefix("--weather=").to_int()]
		elif argument.begins_with("--only="):
			_only = argument.trim_prefix("--only=")
		elif argument.begins_with("--kind="):
			_kind = argument.trim_prefix("--kind=").to_int()
		elif argument.begins_with("--floor="):
			_floor = argument.trim_prefix("--floor=").to_int()
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
	print("  кадры M24j в %s" % _folder)
	get_tree().quit(0)


func _combo(time: int, weather: int) -> void:
	GameState.instance().start_game()
	if _kind >= 0:
		GameState.instance().building = BuildingIdentity.first_of(
			_kind as BuildingIdentity.Kind, _seed
		)
	_level = LEVEL_SCENE.instantiate() as GreyboxLevel
	_level.rules = BuildingRules.new()
	_level.rules.time_of_day = time as TimeOfDay.Kind
	_level.rules.forced_weather = weather
	_level.building_seed = _seed
	_level.spawn_agents = false
	add_child(_level)
	var tag := "%d%s_%s" % [time, TIME_NAMES[time], WEATHER_NAMES[weather]]
	if _only == "" or _only == "roof":
		await _shoot_floor("%s_roof" % tag, BuildingRules.ROOF)
	if _only == "walk":
		await _shoot_walk("%s_walk" % tag)
	if _only == "people":
		await _shoot_people(tag)
	if _only == "" or _only == "floor":
		await _shoot_floor("%s_floor" % tag, _floor)
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


## Otto walks across the roof and back, and the shot shows the trail of footprints in
## the snow (M24l, ADR-0054). Only with the [code]--only=walk[/code] flag: in other
## weathers there is no trail, and the common set of shots does not expect it.
func _shoot_walk(label: String) -> void:
	await _level.wait_for_the_landing()
	# The helicopter flies away: without it the whole deck is visible.
	for _frame: int in 360:
		await get_tree().physics_frame
	for action: StringName in [&"move_right", &"move_left"]:
		Input.action_press(action)
		for _frame: int in 70:
			await get_tree().physics_frame
		Input.action_release(action)
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


## The exit street: the camera releases Otto and settles over the roadway left of the
## end wall.
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


## Pedestrians at the exit in close-up (M24l, ADR-0054, decision 11): the camera closes
## in on each of the first three and follows him while the frame settles — showing what
## he wears and how he carries the umbrella. Only with the [code]--only=people[/code]
## flag.
func _shoot_people(tag: String) -> void:
	await _shoot_street("%s_street" % tag)
	var camera := get_viewport().get_camera_3d() as SideCamera
	var people := _level.find_child("People", true, false) as StreetPeople
	if camera == null or people == null:
		return
	camera.follow(null)
	for index in mini(people.get_child_count(), 3):
		var walker := people.get_child(index) as Node3D
		for _frame: int in SETTLE_FRAMES:
			var at := walker.global_position
			var centre := Vector2(at.x, at.y + 1.0)
			camera.apply_bounds(Rect2(-1000.0, -1000.0, 4000.0, 4000.0), false)
			camera.snap_to(centre)
			camera.close_up(1.0, centre)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.save_png("%s/%s_person%d.png" % [_folder, tag, index])
	camera.close_up(0.0, Vector2.ZERO)
	camera.follow(_level.otto)


## The room behind the door with the city in the window (ADR-0052, decision 5): the door
## on Otto's floor opens, as for an agent, and the shot is taken when the leaf is open.
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
	# And in close-up: the opening with the window and the city behind it.
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
