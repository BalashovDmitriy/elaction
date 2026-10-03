extends Node3D

## Dressing models side by side: how they stand, where they face and how tall they are.
##
## Pack models come as they are: some face +Z, others face sideways, and each has its own
## height. The [PropCatalog] catalog brings them to the game, and this shot is an eye
## check of the catalog: every model stands at its height, facing the camera, with a
## label. Without the catalog (`--raw`), they are as they came from the pack, with the
## bounding size in the output.
##
## Run:
##     godot --path . res://tools/props_shot.tscn
##     godot --path . res://tools/props_shot.tscn -- --raw --folder=M21b
##     godot --path . res://tools/props_shot.tscn -- --raw --only=fridge,stove

const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")
const PROPS_DIR := "res://assets/models/props"

## Grid step, m, and how many models per row.
const STEP: float = 2.4
const PER_ROW: int = 8

var _folder: String = "M21b"
var _raw: bool = false
## Only these models: `--only=fridge,stove`. Empty means the whole catalog.
var _only := PackedStringArray()


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--folder="):
			_folder = argument.trim_prefix("--folder=")
		elif argument == "--raw":
			_raw = true
		elif argument.begins_with("--only="):
			_only = argument.trim_prefix("--only=").split(",")
	DirAccess.make_dir_recursive_absolute("res://screens/%s" % _folder)
	SCREENSHOTTER.mark_ignored_by_engine(ProjectSettings.globalize_path("res://screens"))
	get_window().size = Vector2i(1920, 1080)
	_stage()
	_run.call_deferred()


func _names() -> PackedStringArray:
	var found := PackedStringArray()
	for file in DirAccess.get_files_at(PROPS_DIR):
		if file.ends_with(".glb") and (_only.is_empty() or _only.has(file.get_basename())):
			found.append(file.get_basename())
	found.sort()
	return found


func _stage() -> void:
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

	var names := _names()
	for index in names.size():
		var prop_name := names[index]
		var spot := Vector3((index % PER_ROW) * STEP, -(index / PER_ROW) * 3.2, 0.0)
		var node: Node3D = null
		if _raw:
			# As they came from the pack, but fitted into the cell: packs use different units, and
			# without this a six-meter fire extinguisher would cover its neighbors.
			var model := (load("%s/%s.glb" % [PROPS_DIR, prop_name]) as PackedScene).instantiate()
			var box := PropCatalog.bounds_of(model as Node3D)
			print("%-18s %s" % [prop_name, box.size])
			var fit := 1.8 / maxf(maxf(box.size.x, box.size.y), maxf(box.size.z, 0.001))
			node = Node3D.new()
			node.add_child(model)
			(model as Node3D).scale = Vector3.ONE * fit
			(model as Node3D).position = (
				-box.get_center() * fit + Vector3(0.0, box.size.y * fit * 0.5, 0.0)
			)
		else:
			node = PropCatalog.make(prop_name)
		if node == null:
			continue
		node.position = spot
		add_child(node)
		var label := Label3D.new()
		label.text = prop_name
		label.font_size = 48
		label.pixel_size = 0.004
		label.position = spot + Vector3(0.0, -0.25, 0.4)
		add_child(label)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var rows := ceili(float(names.size()) / PER_ROW)
	# Shot height follows the rows, but is not narrower than a whole row: with `--only`
	# there is one row, and a shot one row high would cut the edges.
	camera.size = maxf(rows * 3.2 + 1.0, PER_ROW * STEP * 9.0 / 16.0 + 0.5)
	camera.position = Vector3((PER_ROW - 1) * STEP * 0.5, -(rows - 1) * 1.6 + 1.0, 20.0)
	add_child(camera)


func _run() -> void:
	for _frame in 4:
		await RenderingServer.frame_post_draw
	var path := "res://screens/%s/props_%s.png" % [_folder, "raw" if _raw else "catalog"]
	get_viewport().get_texture().get_image().save_png(path)
	print("  %s" % path)
	get_tree().quit()
