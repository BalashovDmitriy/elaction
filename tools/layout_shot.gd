extends Node3D

## Кадры раскладки M18a: узкая башня целиком в кадре, стилобат — шире кадра,
## полоса эскалаторов и этаж, разрезанный глухой стеной.
##
## Съёмка вехи ([code]capture.py[/code]) водит Otto по времени и до нижних этажей
## не доходит: до двадцатого спускаться дольше, чем длится любой разумный
## сценарий. А стены и эскалаторы стоят по сиду, и выдержкой до них не дойти.
## Здесь кадр ставится по раскладке: нашли нужный этаж — поставили Otto — сняли.
##
## Эти кадры и есть проверка DoD M18a: выше порога этаж влезает в кадр целиком,
## ниже — не влезает, и на этаже тем больше путей, чем он ниже
## ([ADR-0024](res://docs/adr/0024-building-geometry.md)).
##
## С M18e здесь же кадры здания по карте: тёмный этаж и башня с дверями ROM
## (ADR-0028). Папку задаёт [code]--folder=[/code], по умолчанию — M18a.
##
## Рендер настоящий, не headless — нужен экран.
##
## Запуск:
##     godot --path . res://tools/layout_shot.tscn
##     godot --path . res://tools/layout_shot.tscn -- --folder=M18e

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")

## Куда складываются кадры по умолчанию.
const FOLDER := "res://screens/M18a"

## Сколько кадров дать зданию, свету и отражениям устояться.
const SETTLE_FRAMES: int = 45

## Сид взят тот же, что у остальных инструментов вехи: раскладка по нему уже
## разобрана в статусе, и кадры сравниваются с ней, а не с новым зданием.
const BUILDING_SEED: int = 1

var _level: GreyboxLevel = null
var _folder: String = FOLDER


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--folder="):
			_folder = "res://screens/" + argument.trim_prefix("--folder=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_folder))
	GameState.instance().start_game()
	_level = LEVEL_SCENE.instantiate() as GreyboxLevel
	_level.rules = BuildingRules.new()
	_level.building_seed = BUILDING_SEED
	# Агентов выпускает только кадр про стену: в остальных ходящая фигура
	# закрывает собой то, ради чего кадр снят.
	_level.spawn_agents = false
	add_child(_level)
	_run()


func _run() -> void:
	var rules := _level.rules
	await _shoot_floor("01_tower", rules.wide_from - 1)
	await _shoot_floor("02_podium", rules.floors - 2)
	await _shoot_floor("03_escalator_band", rules.single_shaft_until)

	var walled := _floor_with_a_wall()
	if walled == BuildingRules.ROOF:
		push_error("на сиде %d стен не выпало — кадр стены снять не с чего" % BUILDING_SEED)
		get_tree().quit(1)
		return
	await _shoot_the_wall("04_inner_wall", walled)
	await _shoot_floor("05_tower_doors", 2)
	await _shoot_floor("06_dark_floor", _first_unlit_floor())

	print("  кадры раскладки в %s" % _folder)
	get_tree().quit(0)


## Ставит Otto посреди этажа и снимает кадр. Камера едет за ним, поэтому кадр
## показывает ровно то, что увидит игрок, стоящий на этом этаже.
func _shoot_floor(label: String, index: int) -> void:
	var spots := _level.plan().safe_spots(_level.rules, index)
	if spots.is_empty():
		push_error("этаж %d: вставать некуда" % index)
		return
	_place(spots[spots.size() / 2], index)
	await _shoot(label, index)


## Кадр стены: Otto по одну сторону, агент по другую. Агент обязан стоять и не
## стрелять — он Otto не видит, и кадр именно об этом.
func _shoot_the_wall(label: String, index: int) -> void:
	var wall_x := _wall_x(index)
	var spots := _level.plan().safe_spots(_level.rules, index)
	if spots.is_empty():
		push_error("этаж %d: вставать некуда" % index)
		return
	# Шаг сетки, а не координата места: [method BuildingRules.slot_x] отдаёт «где»,
	# а тут нужно «насколько в сторону».
	var step := _level.rules.slot_x(1) - _level.rules.slot_x(0)
	var left := _nearest_spot(spots, wall_x - step)
	var right := _nearest_spot(spots, wall_x + step)
	_place(left, index)
	_stand_an_agent_at(right, index)
	await _shoot(label, index)


func _shoot(label: String, index: int) -> void:
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_folder, label]
	image.save_png(path)
	var rules := _level.rules
	print("  %s — этаж %d, ширина %.1f м" % [path, index, rules.floor_width(index)])


## Первый сверху этаж, на котором раскладка поставила стену. [constant
## BuildingRules.ROOF] — стен на этом сиде не выпало вовсе.
func _floor_with_a_wall() -> int:
	var highest := BuildingRules.ROOF
	for wall in _level.plan().walls:
		if highest == BuildingRules.ROOF or wall.floor_index < highest:
			highest = wall.floor_index
	return highest


## Первый сверху тёмный этаж карты (ADR-0028, решение 4).
func _first_unlit_floor() -> int:
	for index in _level.rules.floors:
		if _level.rules.is_unlit(index):
			return index
	return 0


func _wall_x(index: int) -> float:
	for wall in _level.plan().walls:
		if wall.floor_index == index:
			return wall.x
	return 0.0


func _nearest_spot(spots: PackedFloat64Array, x: float) -> float:
	var best := spots[0]
	for spot in spots:
		if absf(spot - x) < absf(best - x):
			best = spot
	return best


func _place(x: float, index: int) -> void:
	_level.otto.global_position = WorldSpace.to_scene(Vector2(x, _level.rules.floor_surface(index)))
	_level.otto.velocity = Vector3.ZERO


func _stand_an_agent_at(x: float, index: int) -> void:
	var agent := ENEMY_SCENE.instantiate() as Enemy
	# Стоит на месте и безоружен: кадр про стену, а не про бой.
	var peaceful := BuildingRules.new()
	peaceful.agents_hold_fire = true
	peaceful.agent_dark_fire_range = 0.0
	agent.apply_rules(peaceful)
	agent.walk_speed = 0.0
	_level.add_child(agent)
	agent.global_position = WorldSpace.to_scene(Vector2(x, _level.rules.floor_surface(index)))
	agent.setup(_level.otto, -1.0)
