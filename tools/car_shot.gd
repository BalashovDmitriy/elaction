extends Node3D

## The draw's cars side by side: body, driver's door opening and interior (ADR-0046).
##
## Three rows of five models, hood to the left — the way Otto's car stands at the gate:
## closed, with the door open and the dome light on, and a view from the rear, like the
## cars in the garage bays. A side shot with an ortho camera, in even light: a model defect —
## a ceiling sticking out of the roof, a dark door, a hole in the side — is visible without
## a game.
##
## Run:
##     godot --path . res://tools/car_shot.tscn
##     godot --path . res://tools/car_shot.tscn -- --folder=M24i

const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")

## Row step horizontally and vertically, m.
const STEP_X: float = 4.2
const STEP_Y: float = 1.9
const SETTLE_FRAMES: int = 20

var _folder: String = "M24i"
## Without the interior (`--bare`): whether the interior or the opening itself sticks out of
## the body.
var _bare: bool = false


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--folder="):
			_folder = argument.trim_prefix("--folder=")
		elif argument == "--bare":
			_bare = true
	DirAccess.make_dir_recursive_absolute("res://screens/%s" % _folder)
	SCREENSHOTTER.mark_ignored_by_engine(ProjectSettings.globalize_path("res://screens"))
	get_window().size = Vector2i(1920, 1080)
	_stage()
	_run.call_deferred()


func _stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.16, 0.17, 0.2)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.45, 0.45, 0.5)
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30.0, 25.0, 0.0)
	sun.light_energy = 0.8
	add_child(sun)
	for row: int in 3:
		for index: int in CarModel.MODELS.size():
			var choice := CarModel.Choice.new()
			choice.model = index
			choice.paint = index % CarModel.PAINTS.size()
			var car := CarModel.build(choice)
			car.position = Vector3(index * STEP_X, -row * STEP_Y, 0.0)
			# Hood to the left, door to the camera — as at the gate ([ExitCar]); the third
			# row — rear to the camera, as in the garage bays.
			car.rotation.y = PI if row < 2 else -PI * 0.5
			add_child(car)
			var interior := car.find_child("CarInterior", true, false) as Node3D
			if _bare and interior != null:
				interior.visible = false
			if row == 1:
				_open(car)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = STEP_X * CarModel.MODELS.size() * 9.0 / 16.0
	camera.position = Vector3(STEP_X * 2.0, -STEP_Y + 0.6, 30.0)
	add_child(camera)
	camera.make_current()


## Opens the door and turns on the dome light, as at boarding.
func _open(car: Node3D) -> void:
	var door := car.find_child("DriverDoor", true, false) as Node3D
	if door != null:
		door.rotation.y = -deg_to_rad(ExitCar.DOOR_SWING)
	var anchor := car.find_child("DomeLight", true, false) as Node3D
	if anchor != null:
		var dome := OmniLight3D.new()
		dome.light_color = ExitCar.DOME
		dome.light_energy = ExitCar.DOME_ENERGY
		dome.omni_range = ExitCar.DOME_RANGE
		anchor.add_child(dome)


func _run() -> void:
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var path := "res://screens/%s/cars%s.png" % [_folder, "_bare" if _bare else ""]
	image.save_png(path)
	print(ProjectSettings.globalize_path(path))
	# Close-up — each car with the door open: interior and opening.
	var camera := get_viewport().get_camera_3d()
	camera.size = 2.2
	for index: int in CarModel.MODELS.size():
		camera.position = Vector3(index * STEP_X + 0.2, -STEP_Y + 0.6, 30.0)
		for _frame: int in 3:
			await get_tree().process_frame
		var close := get_viewport().get_texture().get_image()
		var close_path := "res://screens/%s/car_open_%d.png" % [_folder, index]
		close.save_png(close_path)
		print(ProjectSettings.globalize_path(close_path))
	get_tree().quit()
