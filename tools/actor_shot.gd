extends Node3D

## Actor poses side by side: Otto and an agent in every pose, from the side and at three
## quarters.
##
## A gameplay capture scenario cannot catch all the poses: crouching, lying, a hit and
## death happen in combat and last fractions of a second. Here every actor stands in its
## pose played to the end (`FigureRig.snap`), and the shot shows what became of the
## figure, which is exactly what gets argued about against the original (ADR-0032).
##
## Run:
##     godot --path . res://tools/actor_shot.tscn
##     godot --path . res://tools/actor_shot.tscn -- --folder=M21
##
## Shots go to screens/<folder>/actors_*.png. The folder is local.

const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")
const OTTO_MODEL := preload("res://assets/models/otto.glb")

const DEFAULT_FOLDER := "M21"

## Step between figures in a row, m.
const STEP: float = 1.6

## How much higher the agents' row is than Otto's row, m: it has its own floor and its
## own bullet lines.
const ROW_RISE: float = 2.6

## Poses in the shot: shared ones, then Otto-only, then agent-only.
const POSES: PackedStringArray = [
	"idle",
	"walk_0",
	"walk_1",
	"shoot",
	"crouch",
	"jump",
	"land",
	"fall",
	"prone",
	"rope",
	"dead_0",
	"dead_1",
	"crushed",
	"whip_raise",
	"whip_strike",
	"choke_hold",
	"choked",
	"snap_broken",
	"pounce_strike",
]

## ROM bullet heights, m: lines in the shot to see who is under which bullet.
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

	# Rows from bottom to top: Otto, then agents by building kind (ADR-0055, decision 7).
	var models: Array[PackedScene] = [OTTO_MODEL]
	models.append_array(AgentWardrobe.MODELS)
	for row in models.size():
		_row_marks(row * ROW_RISE)

	for row in models.size():
		var model := models[row]
		for column in POSES.size():
			var rig := FigureRig.new()
			rig.model = model
			# Rows above one another, not one behind another: from the side the back one would hide.
			rig.position = Vector3(column * STEP, row * ROW_RISE, 0.0)
			add_child(rig)
			_rigs.append(rig)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	add_child(_camera)


## A row's floor and the bullet lines above it.
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
		# "Play once" clips are shot in the middle: falling, not lying.
		# Landing in the game lasts only [constant FigurePoses.LAND_SHOW]: in 0.4 s a clip
		# sped up twice would reach its end, and the shot would show the stance.
		if pose == "land":
			rig.advance(FigurePoses.LAND_SHOW * 0.5)
		elif pose == "dead_0" or pose == "shoot" or pose == "jump":
			rig.advance(0.4)
		rig.snap()
		rig.set_process(false)

	var middle := STEP * (POSES.size() - 1) * 0.5
	# From the side, as in the game: figures face right, the agent rows above Otto's row.
	var rows := _rigs.size() / POSES.size()
	var centre_y := ROW_RISE * (rows - 1) * 0.5 + 0.9
	_camera.position = Vector3(middle, centre_y, 12.0)
	# Shot width is all the poses of a row with a margin: the orthographic camera keeps the
	# height, and the 1920×1000 window is 1.92 times wider than it.
	_camera.size = maxf(ROW_RISE * rows + 0.6, (STEP * POSES.size() + 1.0) / 1.92)
	_camera.look_at(Vector3(middle, centre_y, 0.0))
	await _shoot("actors_side")

	# From the front at three quarters: the face, hat, glasses and pistol are visible.
	for rig in _rigs:
		rig.rotation.y = deg_to_rad(35.0)
	await _shoot("actors_front")

	# Close-up of the two in the stance.
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
