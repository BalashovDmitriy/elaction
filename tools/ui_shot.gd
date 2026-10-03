extends Node

## Interface shots — by state, not by delay.
##
## The game shooting scenario (`capture.py`) drives Otto with game actions and never reaches the
## menu: it cannot press buttons. So the screens are shot by this tool — it takes the live menu and
## asks it to show the needed page.
##
## Run:
##     godot --path . res://tools/ui_shot.tscn
##     godot --path . res://tools/ui_shot.tscn -- --folder=M8b --locale=en
##
## Shots go to screens/<milestone>/. The folder is local, it does not go into the repository.

const MAIN_SCENE := preload("res://src/main.tscn")
const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")

const DEFAULT_FOLDER := "M8b"

## How many frames to give the scene to assemble and the page to redraw.
const SETTLE_FRAMES: int = 20
const PAGE_FRAMES: int = 6
## Margin on top of the page slide-in, s: the items light up slightly later than it settles.
const PAGE_MARGIN: float = 0.2

var _folder: String = DEFAULT_FOLDER
var _locale: String = ""


func _ready() -> void:
	_read_arguments()
	DirAccess.make_dir_recursive_absolute(_folder_path())
	SCREENSHOTTER.mark_ignored_by_engine(
		ProjectSettings.globalize_path(_folder_path().get_base_dir())
	)
	_run()


func _read_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--folder="):
			_folder = argument.trim_prefix("--folder=").strip_edges()
		elif argument.begins_with("--locale="):
			_locale = argument.trim_prefix("--locale=").strip_edges()


func _folder_path() -> String:
	return "res://screens/%s" % (_folder if not _folder.is_empty() else DEFAULT_FOLDER)


func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame

	var menu := main.get_node_or_null("Menu") as Menu
	if menu == null:
		push_error("no menu in the main scene — check the project import")
		get_tree().quit(1)
		return

	if not _locale.is_empty():
		TranslationServer.set_locale(_locale)

	# The game over screen shows the score and the place, so they have to be set for it: otherwise it
	# is shot empty and lies about how it really looks.
	menu.remember(24500, 0)
	# The sign blinks by a draw: without this a letter in the shot is sometimes lit and sometimes not.
	menu.title().flicker_letter = -1

	var pages: Array[Array] = [
		[Menu.Page.MAIN, "menu"],
		[Menu.Page.SETTINGS, "settings"],
		[Menu.Page.RECORDS, "records"],
		[Menu.Page.CONTROLS, "controls"],
		[Menu.Page.CREDITS, "credits"],
		[Menu.Page.PAUSE, "pause"],
		[Menu.Page.GAME_OVER, "game_over"],
	]
	for page: Array in pages:
		menu.show_page(page[0] as Menu.Page)
		# The page slides in over [constant Menu.PAGE_TIME] by the clock, not by frames: six frames are a
		# tenth of a second, and the column would be shot semi-transparent and shifted.
		await get_tree().create_timer(Menu.PAGE_TIME + PAGE_MARGIN).timeout
		for _frame: int in PAGE_FRAMES:
			await get_tree().process_frame
		await _shoot("%s_%s" % [page[1], TranslationServer.get_locale()])

	get_tree().quit()


func _shoot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_folder_path(), label]
	image.save_png(ProjectSettings.globalize_path(path))
	print("  ", path)
