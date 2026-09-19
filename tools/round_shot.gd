extends Node2D

## Кадры раунда: как здание меняет цвет и как начинается спуск.
##
## DoD вехи M12 — «здания подряд отличаются на глаз» — проверяется глазами, и
## этот инструмент даёт материал: по кадру на каждую палитру набора, снятых
## с одного и того же места одного и того же здания. Отличается на них только
## цвет, и сравнивать их поэтому честно.
##
## Отдельно снимается крыша: надстройка машинного отделения и трос, по которому
## Otto съезжает вниз. Трос живёт меньше секунды, и поймать его выдержкой
## нельзя — кадр снимается по состоянию, пока спуск идёт
## ([ADR-0017](../docs/adr/0017-spectrum-palette-and-shafts.md), решение 4).
##
## Запуск:
##     godot --path . res://tools/round_shot.tscn
##     godot --path . res://tools/round_shot.tscn -- --folder=M12 --floor=12 --seed=2

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")

const DEFAULT_FOLDER := "M12"

## Сколько кадров дать камере доехать до Otto: сглаживание у неё 8.0.
const SETTLE_FRAMES: int = 45

## Сколько кадров ждать, прежде чем сдаться. Не наступившее состояние ждётся
## вечно, и однажды инструмент уже висел вместо того, чтобы сказать об этом.
const PATIENCE: int = 240

var _seed: int = 1
var _floor: int = 12
var _folder: String = DEFAULT_FOLDER


func _ready() -> void:
	_read_arguments()
	DirAccess.make_dir_recursive_absolute(_folder_path())
	SCREENSHOTTER.mark_ignored_by_engine(
		ProjectSettings.globalize_path(_folder_path().get_base_dir())
	)
	_run()


func _folder_path() -> String:
	return "res://screens/%s" % (_folder if not _folder.is_empty() else DEFAULT_FOLDER)


func _read_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			_seed = argument.trim_prefix("--seed=").to_int()
		elif argument.begins_with("--folder="):
			_folder = argument.trim_prefix("--folder=").strip_edges()
		elif argument.begins_with("--floor="):
			_floor = argument.trim_prefix("--floor=").to_int()


func _run() -> void:
	await _shoot_the_arrival()
	for round_number: int in range(1, BuildingPalette.count() + 1):
		await _shoot_the_round(round_number)
	get_tree().quit()


## Крыша: надстройка над шахтой и спуск по тросу.
##
## Кадр снимается, пока Otto ещё висит над крышей: трос уходит вместе с
## вступлением, и «сниму потом» показало бы пустую крышу.
func _shoot_the_arrival() -> void:
	var level := _build(1)
	if level == null:
		return
	var roof := BuildingRules.ROOF
	var landing := level.rules.floor_surface(roof)

	var left := PATIENCE
	while level.otto.global_position.y < landing - 1.0 and left > 0:
		await get_tree().physics_frame
		left -= 1
		# Кадр на полпути: видно и трос, и надстройку, и саму крышу.
		if level.otto.global_position.y >= landing - GreyboxLevel.ROPE_DROP * 0.5:
			break
	await _shoot(level, "00_the_rope")

	left = PATIENCE
	while not level.otto.is_grounded() and left > 0:
		await get_tree().physics_frame
		left -= 1
	await _shoot(level, "01_the_roof")
	await _drop(level)


## Этаж одного и того же здания в палитре очередного раунда.
func _shoot_the_round(round_number: int) -> void:
	var level := _build(round_number)
	if level == null:
		return
	var spot := level.plan().safe_x(level.rules, _floor)
	level.otto.global_position = Vector2(spot, level.rules.floor_surface(_floor))
	for _frame: int in SETTLE_FRAMES:
		await get_tree().physics_frame

	await _shoot(level, "%02d_round%d" % [round_number + 1, round_number])
	await _drop(level)


## Здание с палитрой нужного раунда. Сид один на все кадры: меняться от кадра
## к кадру должен цвет, а не раскладка, — иначе сравнивать нечего.
func _build(round_number: int) -> GreyboxLevel:
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	if level == null:
		# Чаще всего это незарегистрированный class_name: лечится godot_check.py.
		push_error("сцена уровня не собралась — проверьте импорт проекта")
		get_tree().quit(1)
		return null

	level.rules = BuildingRules.for_building(round_number)
	level.building_seed = _seed
	# Агенты в кадре не нужны: они ходят, и два кадра подряд вышли бы разными.
	level.spawn_agents = false
	add_child(level)
	return level


## Убирает здание и даёт кадр на то, чтобы оно ушло: [method Node.queue_free]
## освобождает узел лишь в конце кадра, и следующее здание собиралось бы рядом
## с уходящим — два Otto и вся геометрия дважды в одном физическом мире.
## Зовётся только через await, иначе этот кадр никто не ждёт.
func _drop(level: GreyboxLevel) -> void:
	remove_child(level)
	level.queue_free()
	await get_tree().physics_frame


func _shoot(level: GreyboxLevel, label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s_seed%d.png" % [_folder_path(), label, level.building_seed]
	image.save_png(path)
	print("  %s" % path)
