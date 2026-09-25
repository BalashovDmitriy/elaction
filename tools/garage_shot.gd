extends Node3D

## Кадры паркинга M24b (ADR-0038, решение 3): ворота слева, середина зала,
## ворота открытыми и паркинг с погашенной зоной.
##
## Otto ставится по раскладке, как в [code]layout_shot.gd[/code]: до нижнего
## этажа сценарий съёмки по времени не доходит. `--wide` снимает весь этаж
## общим планом — камеру отводят, чтобы увидеть паркинг целиком; игрок так его
## не видит, кадр — для проверки раскладки глазом.
##
## Рендер настоящий, не headless — нужен экран.
##
## Запуск:
##     godot --path . res://tools/garage_shot.tscn
##     godot --path . res://tools/garage_shot.tscn -- --seed=3 --folder=M24b
##     godot --path . res://tools/garage_shot.tscn -- --wide --quality=0

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

const FOLDER := "res://screens/M24b"
const SETTLE_FRAMES: int = 45
## Во сколько раз шире обычного кадр общего плана.
const WIDE_ZOOM: float = 2.6

var _level: GreyboxLevel = null
var _folder: String = FOLDER
var _seed: int = 1
var _wide: bool = false


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--folder="):
			_folder = "res://screens/" + argument.trim_prefix("--folder=")
		elif argument.begins_with("--seed="):
			_seed = argument.trim_prefix("--seed=").to_int()
		elif argument == "--wide":
			_wide = true
		elif argument.begins_with("--quality="):
			var quality := clampi(
				argument.trim_prefix("--quality=").to_int(), 0, Graphics.Quality.size() - 1
			)
			Graphics.broadcast(quality as Graphics.Quality)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_folder))
	GameState.instance().start_game()
	_level = LEVEL_SCENE.instantiate() as GreyboxLevel
	_level.rules = BuildingRules.new()
	_level.building_seed = _seed
	_level.spawn_agents = false
	add_child(_level)
	_run()


func _run() -> void:
	var rules := _level.rules
	var bottom := rules.floors - 1
	var inner := Garage.inner_span(rules)
	var tag := "seed%d_q%d" % [_seed, Graphics.quality]
	if _wide:
		var camera := get_viewport().get_camera_3d()
		_place(_clear_x((inner.x + inner.y) * 0.5), bottom)
		await _settle()
		camera.size *= WIDE_ZOOM
		await _shoot("garage_wide_%s" % tag)
		get_tree().quit(0)
		return
	_place(_clear_x(inner.x + 4.0), bottom)
	await _shoot("garage_gate_%s" % tag)
	_level.garage().gate.openness = 1.0
	await _shoot("garage_gate_open_%s" % tag)
	_place(_clear_x((inner.x + inner.y) * 0.5), bottom)
	await _shoot("garage_middle_%s" % tag)
	_place(_clear_x(inner.y - 5.0), bottom)
	await _shoot("garage_right_%s" % tag)
	get_tree().quit(0)


## Точка рядом с [param x], где Otto не встанет в зону выхода: без документов
## она отправила бы его к красной двери.
func _clear_x(x: float) -> float:
	var exit_x := _level.plan().exit_x
	if absf(x - exit_x) < BuildingShell.EXIT_WIDTH + 0.5:
		return exit_x + BuildingShell.EXIT_WIDTH + 1.0
	return x


func _place(x: float, index: int) -> void:
	_level.otto.global_position = WorldSpace.to_scene(Vector2(x, _level.rules.floor_surface(index)))
	_level.otto.velocity = Vector3.ZERO


func _settle() -> void:
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame


func _shoot(label: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_folder, label]
	image.save_png(path)
	print("  %s" % path)
