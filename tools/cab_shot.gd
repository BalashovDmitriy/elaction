extends Node3D

## Cabs of the three kinds side by side (ADR-0057, decision 6): hotel brass, office
## stainless steel, residential freight — with the gate folded and closed. An Otto
## model stands in each: whether he reads behind the bars.
##
## Run:
##     godot --path . res://tools/cab_shot.tscn
##     godot --path . res://tools/cab_shot.tscn -- --folder=M24o

const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")
const OTTO := preload("res://src/actors/otto/otto.tscn")

## Cab step, m, width and clearance — as in the default building.
const STEP: float = 2.6
const WIDTH: float = 1.8
const CLEAR: float = 3.0

var _folder: String = "M24o"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--folder="):
			_folder = argument.trim_prefix("--folder=")
	DirAccess.make_dir_recursive_absolute("res://screens/%s" % _folder)
	SCREENSHOTTER.mark_ignored_by_engine(ProjectSettings.globalize_path("res://screens"))
	get_window().size = Vector2i(1920, 1080)
	_stage()
	_run.call_deferred()


func _stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.06, 0.07, 0.09)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.35, 0.36, 0.4)
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(STEP * 1.5, 2.6, 2.5)
	lamp.omni_range = 12.0
	lamp.light_energy = 2.0
	add_child(lamp)
	# Hotel, office, residential with the gate folded, residential with it closed.
	var looks: Array[Array] = [
		[BuildingIdentity.Kind.HOTEL, 1.0],
		[BuildingIdentity.Kind.OFFICE, 1.0],
		[BuildingIdentity.Kind.RESIDENTIAL, 1.0],
		[BuildingIdentity.Kind.RESIDENTIAL, 0.0],
	]
	for index: int in looks.size():
		var detail := CarDetail.new()
		detail.dress_as(looks[index][0] as BuildingIdentity.Kind)
		detail.position = Vector3(index * STEP, 0.0, 0.0)
		add_child(detail)
		detail.build(WIDTH, CLEAR)
		var open := float(looks[index][1])
		if open < 1.0:
			detail.tend_gate(false, CarDetail.GATE_TIME * 2.0)
		var floor_slab := GreyboxLook.box(
			Vector3(WIDTH, 0.18, 1.0), GreyboxLook.metal(Color(0.3, 0.3, 0.3))
		)
		floor_slab.position = Vector3(index * STEP, -0.09, 0.0)
		add_child(floor_slab)
		var otto := OTTO.instantiate() as Node3D
		otto.position = Vector3(index * STEP, 0.0, 0.0)
		otto.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(otto)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.5
	camera.rotation_degrees.x = -SideCamera.TILT_DEGREES
	camera.position = Vector3(
		STEP * 1.5, 1.6 + 20.0 * tan(deg_to_rad(SideCamera.TILT_DEGREES)), 20.0
	)
	add_child(camera)
	camera.make_current()


func _run() -> void:
	for _frame: int in 6:
		await RenderingServer.frame_post_draw
	var path := "res://screens/%s/cabs.png" % _folder
	get_viewport().get_texture().get_image().save_png(path)
	print("  %s" % path)
	get_tree().quit()
