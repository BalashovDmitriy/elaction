extends Node3D

## Flicker search: 60 frames of a still floor in a row and a map of what changed
## between them.
##
## Flicker is hard to catch by eye: it lasts two or three frames and in different places.
## Here the camera stands, Otto stands, there are no agents, and everything that still changes from
## frame to frame is either intended (a sign letter blinks, the antenna light, cabs
## move) or a defect: two surfaces in one plane (z-fighting), screen-space reflection
## noise, a light that goes off and on. The map is the maximum
## difference of adjacent frames per pixel, amplified, over the frame itself.
##
## Vertical sync is on — as in the game; without it the frame tears, and
## the map would show tearing, not flicker.
##
## Run:
##     godot --path . res://tools/flicker_shot.tscn -- --folder=M22 --floor=2 --quality=2

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")

## Three seconds: during the first one the camera is still catching up after Otto is moved.
const SETTLE_FRAMES: int = 180
const FRAMES: int = 60
## Difference threshold below which a pixel counts as still: compression noise and
## dithering change the lowest bit.
const THRESHOLD: float = 0.04

var _folder: String = "res://screens/M22"
var _floor: int = 2
var _level: GreyboxLevel = null


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--folder="):
			_folder = "res://screens/" + argument.trim_prefix("--folder=")
		elif argument.begins_with("--floor="):
			_floor = argument.trim_prefix("--floor=").to_int()
		elif argument.begins_with("--quality="):
			Graphics.broadcast(
				(
					clampi(
						argument.trim_prefix("--quality=").to_int(), 0, Graphics.Quality.size() - 1
					)
					as Graphics.Quality
				)
			)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_folder))
	SCREENSHOTTER.mark_ignored_by_engine(ProjectSettings.globalize_path("res://screens"))
	GameState.instance().start_game()
	_level = LEVEL_SCENE.instantiate() as GreyboxLevel
	_level.rules = BuildingRules.new()
	_level.building_seed = 1
	_level.spawn_agents = false
	add_child(_level)
	_run()


func _run() -> void:
	await get_tree().physics_frame
	var spots := _level.plan().safe_spots(_level.rules, _floor)
	var spot := spots[spots.size() / 2]
	_level.otto.global_position = WorldSpace.to_scene(
		Vector2(spot, _level.rules.floor_surface(_floor))
	)
	for _frame in SETTLE_FRAMES:
		await get_tree().process_frame

	var previous: Image = null
	var heat: Image = null
	var changed_frames := 0
	var camera := get_viewport().get_camera_3d()
	var low := Vector3.INF
	var high := -Vector3.INF
	var otto_low := INF
	var otto_high := -INF
	for index in FRAMES:
		await RenderingServer.frame_post_draw
		if camera != null:
			low = low.min(camera.global_position)
			high = high.max(camera.global_position)
		otto_low = minf(otto_low, _level.otto.global_position.y)
		otto_high = maxf(otto_high, _level.otto.global_position.y)
		var frame := get_viewport().get_texture().get_image()
		frame.convert(Image.FORMAT_RGB8)
		if previous != null:
			if heat == null:
				heat = Image.create(frame.get_width(), frame.get_height(), false, Image.FORMAT_L8)
			changed_frames += _accumulate(previous, frame, heat)
		previous = frame
	var base := previous
	base.save_png("%s/flicker_frame_f%d.png" % [_folder, _floor])
	_overlay(base, heat).save_png("%s/flicker_map_f%d.png" % [_folder, _floor])
	print("  мерцание: пикселей с разницей хоть в одном кадре — %d" % changed_frames)
	# Camera and Otto over these frames: if they shake, all edges flicker at once.
	print("  камера ходила на %s м, Otto по высоте на %.5f м" % [high - low, otto_high - otto_low])
	get_tree().quit()


## Difference of two frames per pixel — into the map as a maximum. Returns how many
## pixels in this pair changed noticeably.
func _accumulate(a: Image, b: Image, heat: Image) -> int:
	var count := 0
	# With a step of two pixels: the map is needed for the eye, and a full pass is tens
	# of millions of accesses in GDScript.
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var diff := maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), absf(ca.b - cb.b))
			if diff > THRESHOLD:
				count += 1
				var value := minf(diff * 4.0, 1.0)
				if value > heat.get_pixel(x, y).r:
					heat.set_pixel(x, y, Color(value, value, value))
	return count


## The frame dimmed by half, and on top of it in red — where things changed.
func _overlay(base: Image, heat: Image) -> Image:
	var out := base.duplicate() as Image
	for y in range(0, out.get_height(), 2):
		for x in range(0, out.get_width(), 2):
			var shade := out.get_pixel(x, y) * 0.45
			var level := heat.get_pixel(x, y).r if heat != null else 0.0
			var marked := shade.lerp(Color(1.0, 0.1, 0.05), level)
			for dy in 2:
				for dx in 2:
					if x + dx < out.get_width() and y + dy < out.get_height():
						out.set_pixel(x + dx, y + dy, marked)
	return out
