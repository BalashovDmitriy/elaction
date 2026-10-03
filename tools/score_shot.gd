extends Node

## Score increment as a shot: the building, the HUD, two awards — above a place in the corridor and
## a document above Otto — and a shot as the increments rise.
##
## Run:
##     godot --path . res://tools/score_shot.tscn
##     godot --path . res://tools/score_shot.tscn -- --folder=M24m

const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")
const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const HUD_SCENE := preload("res://src/ui/hud.tscn")

var _folder: String = "M24m"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--folder="):
			_folder = argument.trim_prefix("--folder=")
	DirAccess.make_dir_recursive_absolute("res://screens/%s" % _folder)
	SCREENSHOTTER.mark_ignored_by_engine(ProjectSettings.globalize_path("res://screens"))
	_run.call_deferred()


func _run() -> void:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.spawn_agents = false
	add_child(level)
	var hud := HUD_SCENE.instantiate() as Hud
	add_child(hud)
	hud.follow(level)
	var spots := level.plan().safe_spots(level.rules, 2)
	level.otto.global_position = WorldSpace.to_scene(
		Vector2(spots[spots.size() / 2], level.rules.floor_surface(2))
	)
	for _frame: int in 40:
		await get_tree().process_frame
	var kill_at := level.otto.global_position + Vector3(3.0, 0.0, 0.0) + GameState.OVER_HEAD
	GameState.instance().add_score(GameState.CRUSH_SCORE, kill_at)
	for _frame: int in 10:
		await get_tree().process_frame
	GameState.instance().collect_document()
	for _frame: int in 14:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://screens/%s/score_bursts.png" % _folder
	get_viewport().get_texture().get_image().save_png(path)
	print("  %s" % path)
	get_tree().quit()
