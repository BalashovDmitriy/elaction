extends Node

## Демо-режим кадрами (ADR-0041): настоящая главная сцена, демо с каждой из трёх
## точек, по кадру каждые несколько секунд.
##
## Ждать 45 с бездействия меню незачем: демо запускается сразу, как его запустил
## бы отсчёт. Бот играет сам, и кадр показывает, что увидит тот, кто отошёл от
## экрана.
##
## Запуск:
##     godot --path . res://tools/demo_shot.tscn
##     godot --path . res://tools/demo_shot.tscn -- --folder=M24E
##
## Кадры ложатся в screens/<папка>/demo_<точка>_<секунда>.jpg. Папка локальная.

const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")
const MAIN_SCENE := preload("res://src/main.tscn")

const DEFAULT_FOLDER := "M24E"
## Когда снимать кадры демо, с от его начала.
const MOMENTS: Array[float] = [3.0, 8.0, 14.0, 20.0, 27.0]
const POINT_NAMES: Array[String] = ["roof", "middle", "bottom"]

var _folder: String = DEFAULT_FOLDER


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--folder="):
			_folder = argument.trim_prefix("--folder=").strip_edges()
	DirAccess.make_dir_recursive_absolute("res://screens/%s" % _folder)
	SCREENSHOTTER.mark_ignored_by_engine(ProjectSettings.globalize_path("res://screens"))
	get_window().size = Vector2i(1920, 1080)
	_run.call_deferred()


func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	for point in POINT_NAMES.size():
		main.set("_demo_point", point)
		main.call("_start_demo")
		var shown := 0.0
		for moment in MOMENTS:
			await get_tree().create_timer(moment - shown).timeout
			shown = moment
			if main.get("_demo") == null:
				break
			for _frame in 2:
				await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			var path := "res://screens/%s/demo_%s_%02d.jpg" % [_folder, POINT_NAMES[point], moment]
			image.save_jpg(path, 0.9)
			print("  %s" % path)
		main.call("_end_demo")
		await get_tree().create_timer(FadeCurtain.FADE_OUT + FadeCurtain.FADE_IN + 0.3).timeout
	get_tree().quit()
