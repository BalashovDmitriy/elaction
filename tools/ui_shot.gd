extends Node

## Снимки интерфейса — по состоянию, а не по выдержке.
##
## Игровой сценарий съёмки (`capture.py`) водит Otto игровыми действиями и до
## меню не добирается вовсе: кнопки он нажимать не умеет. Поэтому экраны снимает
## этот инструмент — он берёт живое меню и просит его показать нужную страницу.
##
## Запуск:
##     godot --path . res://tools/ui_shot.tscn
##     godot --path . res://tools/ui_shot.tscn -- --folder=M8b --locale=en
##
## Кадры ложатся в screens/<веха>/. Папка локальная, в репозиторий не идёт.

const MAIN_SCENE := preload("res://src/main.tscn")
const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")

const DEFAULT_FOLDER := "M8b"

## Сколько кадров дать сцене собраться и странице перерисоваться.
const SETTLE_FRAMES: int = 20
const PAGE_FRAMES: int = 6
## Запас сверх въезда страницы, с: пункты загораются чуть позже, чем она встаёт.
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
		push_error("в главной сцене нет меню — проверьте импорт проекта")
		get_tree().quit(1)
		return

	if not _locale.is_empty():
		TranslationServer.set_locale(_locale)

	# Экран конца партии показывает счёт и место, поэтому ему их надо задать:
	# иначе он снимется пустым и соврёт про то, как выглядит на деле.
	menu.remember(24500, 0)
	# Вывеска мигает по жребию: без этого буква на снимке то горит, то нет.
	menu.title().flicker_letter = -1

	var pages: Array[Array] = [
		[Menu.Page.MAIN, "menu"],
		[Menu.Page.SETTINGS, "settings"],
		[Menu.Page.RECORDS, "records"],
		[Menu.Page.CONTROLS, "controls"],
		[Menu.Page.PAUSE, "pause"],
		[Menu.Page.GAME_OVER, "game_over"],
	]
	for page: Array in pages:
		menu.show_page(page[0] as Menu.Page)
		# Страница въезжает [constant Menu.PAGE_TIME] по часам, а не по кадрам:
		# шесть кадров — это десятая доля секунды, и колонка снималась бы
		# полупрозрачной и сдвинутой.
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
