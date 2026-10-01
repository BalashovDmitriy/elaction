extends Node3D

## Комнаты за дверью (ADR-0047): четыре номера и четыре кабинета жребием.
##
## Каждая стоит за стеной коридора с проёмом двери и открытой створкой, кадр
## — ортокамерой с наклоном игры ([constant SideCamera.TILT_DEGREES]). Первый
## кадр — все восемь в проёмах, как в игре; второй — без стены: вся комната
## целиком, чтобы видеть, что стоит и где.
##
## Запуск:
##     godot --path . res://tools/room_shot.tscn
##     godot --path . res://tools/room_shot.tscn -- --folder=M24i
##     godot --path . res://tools/room_shot.tscn -- --folder=M24k --time=1 --weather=2
##
## `--time` — время суток ([enum TimeOfDay.Kind]) и `--weather` — погода за окном
## (ADR-0052, решение 5): днём в комнате солнце из окна.

const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")

## Шаг комнат вдоль ряда, м, и сколько комнат в ряду.
const STEP: float = 5.0
const PER_ROW: int = 4
const ROW_STEP: float = Proportions.FLOOR
const SETTLE_FRAMES: int = 20

var _folder: String = "M24i"
var _walls: Array[Node3D] = []
var _time: int = TimeOfDay.Kind.NIGHT
var _weather: int = Weather.Kind.CLEAR


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--folder="):
			_folder = argument.trim_prefix("--folder=")
		elif argument.begins_with("--time="):
			_time = clampi(argument.trim_prefix("--time=").to_int(), 0, 3)
		elif argument.begins_with("--weather="):
			_weather = clampi(argument.trim_prefix("--weather=").to_int(), 0, 2)
	DirAccess.make_dir_recursive_absolute("res://screens/%s" % _folder)
	SCREENSHOTTER.mark_ignored_by_engine(ProjectSettings.globalize_path("res://screens"))
	get_window().size = Vector2i(1920, 1080)
	_stage()
	_run.call_deferred()


func _stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.03, 0.03, 0.05)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.12, 0.12, 0.16)
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var hotel := BuildingIdentity.new()
	var office := BuildingIdentity.new()
	office.kind = BuildingIdentity.Kind.OFFICE
	for index: int in PER_ROW * 2:
		var is_hotel := index < PER_ROW
		var spot := Vector3((index % PER_ROW) * STEP, -(index / PER_ROW) * ROW_STEP, 0.0)
		var room := DoorRoom.build(
			is_hotel,
			index * 7919 + 13,
			hotel if is_hotel else office,
			Vector2(-INF, INF),
			false,
			_time as TimeOfDay.Kind,
			_weather as Weather.Kind
		)
		room.position = spot
		add_child(room)
		var wall := _corridor_wall()
		wall.position = spot
		add_child(wall)
		_walls.append(wall)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = ROW_STEP * 2.0 + 0.6
	var tilt := deg_to_rad(SideCamera.TILT_DEGREES)
	var centre := Vector3(STEP * (PER_ROW - 1) * 0.5, -ROW_STEP * 0.5 + 1.2, 0.0)
	camera.position = centre + Vector3(0.0, SideCamera.DISTANCE * tan(tilt), SideCamera.DISTANCE)
	camera.rotation.x = -tilt
	camera.far = 60.0
	add_child(camera)
	camera.make_current()


## Стена коридора с проёмом двери и створкой, распахнутой в комнату, и лампа
## коридора перед ней.
func _corridor_wall() -> Node3D:
	var wall := Node3D.new()
	var look := GreyboxLook.surface(Color(0.35, 0.33, 0.4))
	var z := WorldSpace.BACK_WALL_Z - 0.05
	var half := Door.LEAF_SIZE.x * 0.5
	var height := DoorRoom.HEIGHT
	var side := (STEP - Door.LEAF_SIZE.x) * 0.5
	for sign_x: float in [-1.0, 1.0]:
		var panel := GreyboxLook.box(Vector3(side, height, 0.1), look)
		panel.position = Vector3(sign_x * (half + side * 0.5), height * 0.5, z)
		wall.add_child(panel)
	var lintel := GreyboxLook.box(Vector3(Door.LEAF_SIZE.x, height - Door.LEAF_SIZE.y, 0.1), look)
	lintel.position = Vector3(0.0, (height + Door.LEAF_SIZE.y) * 0.5, z)
	wall.add_child(lintel)
	var leaf := GreyboxLook.box(
		Vector3(Door.LEAF_SIZE.x, Door.LEAF_SIZE.y, 0.06), GreyboxLook.surface(GreyboxLook.DOOR)
	)
	leaf.rotation.y = PI * 0.5
	leaf.position = Vector3(-half, Door.LEAF_SIZE.y * 0.5, WorldSpace.BACK_WALL_Z - half)
	wall.add_child(leaf)
	var lamp := OmniLight3D.new()
	lamp.light_energy = 0.8
	lamp.omni_range = 4.0
	lamp.position = Vector3(1.2, 2.6, 0.2)
	wall.add_child(lamp)
	return wall


func _run() -> void:
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	_save("rooms_in_doors")
	for wall: Node3D in _walls:
		for child: Node in wall.get_children():
			if child is MeshInstance3D:
				(child as MeshInstance3D).visible = false
	for _frame: int in 3:
		await get_tree().process_frame
	_save("rooms_open")
	get_tree().quit()


func _save(shot: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var path := "res://screens/%s/%s_t%d_w%d.png" % [_folder, shot, _time, _weather]
	image.save_png(path)
	print(ProjectSettings.globalize_path(path))
