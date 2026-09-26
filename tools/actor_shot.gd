extends Node3D

## Позы актёров рядом: Otto и агент в каждой позе, сбоку и на три четверти.
##
## Игровым сценарием съёмки все позы не поймать: присед, лёжа, удар и смерть
## случаются в бою и держатся доли секунды. Здесь каждый актёр стоит в своей
## позе, доведённой до конца (`FigureRig.snap`), и кадр показывает, что стало с
## фигурой, — ровно то, о чём спорят с оригиналом (ADR-0032).
##
## Запуск:
##     godot --path . res://tools/actor_shot.tscn
##     godot --path . res://tools/actor_shot.tscn -- --folder=M21
##
## Кадры ложатся в screens/<папка>/actors_*.png. Папка локальная.

const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")
const OTTO_MODEL := preload("res://assets/models/otto.glb")
const AGENT_MODEL := preload("res://assets/models/agent.glb")

const DEFAULT_FOLDER := "M21"

## Шаг между фигурами в ряду, м.
const STEP: float = 1.6

## На сколько ряд агентов выше ряда Otto, м: у него свой пол и свои линии пуль.
const ROW_RISE: float = 2.6

## Позы в кадре: общие, затем только Otto, затем только агента.
const POSES: PackedStringArray = [
	"idle",
	"walk_0",
	"walk_1",
	"shoot",
	"crouch",
	"jump",
	"land",
	"kick",
	"prone",
	"dead_0",
	"dead_1",
	"crushed"
]

## Высоты пуль ROM, м: линии на кадре, чтобы видеть, кто под какой пулей.
const BULLET_LINES: Array[float] = [1.13, 0.68, 0.23]

var _folder: String = DEFAULT_FOLDER
var _rigs: Array[FigureRig] = []
var _camera: Camera3D = null


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--folder="):
			_folder = argument.trim_prefix("--folder=").strip_edges()
	DirAccess.make_dir_recursive_absolute(_folder_path())
	SCREENSHOTTER.mark_ignored_by_engine(ProjectSettings.globalize_path("res://screens"))
	get_window().size = Vector2i(1920, 1000)
	_stage()
	_run.call_deferred()


func _folder_path() -> String:
	return "res://screens/%s" % _folder


func _stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.55, 0.58, 0.62)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	environment.ambient_light_energy = 0.8
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	sun.light_energy = 1.3
	add_child(sun)

	for row in 2:
		_row_marks(row * ROW_RISE)

	for row in 2:
		var model := OTTO_MODEL if row == 0 else AGENT_MODEL
		for column in POSES.size():
			var rig := FigureRig.new()
			rig.model = model
			# Ряды друг над другом, а не друг за другом: сбоку задний прятался бы.
			rig.position = Vector3(column * STEP, row * ROW_RISE, 0.0)
			add_child(rig)
			_rigs.append(rig)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	add_child(_camera)


## Пол ряда и линии пуль над ним.
func _row_marks(base: float) -> void:
	var floor_box := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(STEP * POSES.size() + 2.0, 0.02, 3.0)
	floor_box.mesh = plane
	floor_box.position = Vector3(STEP * (POSES.size() - 1) * 0.5, base - 0.01, 0.0)
	add_child(floor_box)

	for height in BULLET_LINES:
		var line := MeshInstance3D.new()
		var bar := BoxMesh.new()
		bar.size = Vector3(STEP * POSES.size() + 2.0, 0.012, 0.012)
		line.mesh = bar
		var red := StandardMaterial3D.new()
		red.albedo_color = Color(0.9, 0.15, 0.1)
		red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		line.material_override = red
		line.position = Vector3(STEP * (POSES.size() - 1) * 0.5, base + height, 0.9)
		add_child(line)


func _run() -> void:
	await get_tree().process_frame
	for index in _rigs.size():
		var rig := _rigs[index]
		var pose := POSES[index % POSES.size()]
		rig.show_pose(pose)
		rig.set_walk_phase(0.0 if pose == "walk_0" else 1.2)
		rig.face(1.0)
		# Клипы «один раз» снимаются на середине: падение, а не лежащий.
		if pose == "dead_0" or pose == "shoot" or pose == "jump" or pose == "land":
			rig.advance(0.4)
		rig.snap()
		rig.set_process(false)

	var middle := STEP * (POSES.size() - 1) * 0.5
	# Сбоку, как в игре: фигуры смотрят вправо, ряд агентов над рядом Otto.
	_camera.position = Vector3(middle, 2.2, 12.0)
	# Ширина кадра — все позы ряда с полем: ортокамера держит высоту, а окно
	# 1920×1000 шире её в 1.92 раза.
	_camera.size = maxf(9.4, (STEP * POSES.size() + 1.0) / 1.92)
	_camera.look_at(Vector3(middle, 2.2, 0.0))
	await _shoot("actors_side")

	# Спереди на три четверти: видно лицо, шляпу, очки и пистолет.
	for rig in _rigs:
		rig.rotation.y = deg_to_rad(35.0)
	await _shoot("actors_front")

	# Крупно двое в стойке.
	_camera.size = 4.4
	_camera.position = Vector3(0.8, 2.3, 12.0)
	_camera.look_at(Vector3(0.8, 2.3, 0.0))
	await _shoot("actors_close")
	get_tree().quit()


func _shoot(label: String) -> void:
	for _frame in 3:
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_folder_path(), label]
	image.save_png(path)
	print("  %s" % path)
