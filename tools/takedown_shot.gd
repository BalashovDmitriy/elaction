extends Node3D

## Takedown scenes as frames (ADR-0040): each scene with the real director
## [TakedownScene] on live Otto and agent, with slowdown and close-up, as in
## the game; one frame for each fraction of the scene.
##
## Combat will not catch a scene — the agent must be brought up close and fire pressed at the right
## moment. Here each scene sets itself up, and the frame shows the staging.
##
## Run:
##     godot --path . res://tools/takedown_shot.tscn
##     godot --path . res://tools/takedown_shot.tscn -- --folder=M24D
##
## Frames go to screens/<folder>/takedown_<scene>.png — a sheet of the scene's frames
## in order. The folder is local.

const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")
const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")

const DEFAULT_FOLDER := "M24D"
## At which fractions of the scene to take frames.
const MOMENTS: Array[float] = [0.08, 0.3, 0.5, 0.7, 0.9]
## Frame size on the sheet, px.
const CELL := Vector2i(640, 400)
## What fraction of the frame height to take onto the sheet.
const TIGHT: float = 0.6

var _folder: String = DEFAULT_FOLDER


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--folder="):
			_folder = argument.trim_prefix("--folder=").strip_edges()
	DirAccess.make_dir_recursive_absolute("res://screens/%s" % _folder)
	SCREENSHOTTER.mark_ignored_by_engine(ProjectSettings.globalize_path("res://screens"))
	get_window().size = Vector2i(1600, 900)
	_stage()
	_run.call_deferred()


func _stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.2, 0.22, 0.27)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.6, 0.66)
	environment.ambient_light_energy = 0.9
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	sun.light_energy = 1.2
	add_child(sun)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 0.4, 3.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.2, 0.0)
	ground.add_child(shape)
	var look := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	look.mesh = mesh
	look.position = shape.position
	ground.add_child(look)
	add_child(ground)


func _run() -> void:
	for scene: Takedown.Scene in Takedown.all_scenes():
		await _shoot_scene(scene)
	get_tree().quit()


func _shoot_scene(scene: Takedown.Scene) -> void:
	var otto := OTTO_SCENE.instantiate() as Otto
	add_child(otto)
	var from_above := scene.side == Takedown.Side.ABOVE
	otto.global_position = Vector3(0.0, 0.05, WorldSpace.PLAY_Z)
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.emerge_time = 0.0
	var rules := BuildingRules.new()
	rules.agents_hold_fire = true
	add_child(agent)
	agent.apply_rules(rules)
	agent.global_position = Vector3(scene.offset, 0.05, WorldSpace.PLAY_Z)
	agent.setup(otto, -1.0 if scene.faces_otto else 1.0)
	while not agent.takedown_ready:
		await get_tree().physics_frame
	await get_tree().create_timer(0.3).timeout
	if from_above:
		otto.figure.show_pose("land")
	var director := TakedownScene.play(otto, agent, scene)
	var frames: Array[Image] = []
	var shown := 0.0
	for moment in MOMENTS:
		# Scene time runs at the real pace: it must be awaited bypassing the world slowdown.
		var wait := scene.duration * moment - shown
		await get_tree().create_timer(wait, true, false, true).timeout
		shown += wait
		if not is_instance_valid(director):
			break
		for _frame in 2:
			await RenderingServer.frame_post_draw
		frames.append(get_viewport().get_texture().get_image())
	await get_tree().create_timer(0.5, true, false, true).timeout
	_save_sheet(scene.name, frames)
	otto.queue_free()
	agent.queue_free()
	await get_tree().process_frame


func _save_sheet(scene_name: String, frames: Array[Image]) -> void:
	var sheet := Image.create(CELL.x * frames.size(), CELL.y, false, Image.FORMAT_RGBA8)
	for index in frames.size():
		var frame := frames[index]
		frame.convert(Image.FORMAT_RGBA8)
		# The middle of the frame, tighter than the closest close-up: the pair stands in the centre, and
		# the staging is judged by poses, not by the whole frame.
		var size := frame.get_size()
		var high := int(size.y * TIGHT)
		var wide := high * CELL.x / CELL.y
		var crop := Rect2i((size.x - wide) / 2, (size.y - high) / 2, wide, high)
		var cell := frame.get_region(crop)
		cell.resize(CELL.x, CELL.y)
		sheet.blit_rect(cell, Rect2i(Vector2i.ZERO, CELL), Vector2i(index * CELL.x, 0))
	var path := "res://screens/%s/takedown_%s.png" % [_folder, scene_name]
	sheet.save_png(path)
	print("  %s" % path)
