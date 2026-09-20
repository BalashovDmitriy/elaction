extends Node3D

## Кадры темноты: широкий этаж с тремя лампами — целиком, с погашенной зоной и
## погашенный весь.
##
## Съёмка вехи ([code]capture.py[/code]) водит Otto по времени и до нижних этажей
## не доходит, а лампы стоят по сиду — выдержкой до них не дойти. Здесь кадр
## ждёт состояния: лампа сбита и долетела до пола.
##
## Эти три кадра и есть проверка DoD M17: на тёмном этаже игрок обязан видеть,
## во что стреляет, а соседняя зона обязана остаться светлой (ADR-0023, решение 2).
##
## Рендер настоящий, не headless — нужен экран.
##
## Запуск:
##     godot --path . res://tools/dark_shot.tscn

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")

## Куда складываются кадры.
const FOLDER := "res://screens/M17"

## Сколько кадров дать зданию, свету и отражениям устояться.
const SETTLE_FRAMES: int = 45

## Сколько шагов физики ждать падения лампы, прежде чем сдаться.
const FALL_STEPS: int = 240

var _level: GreyboxLevel = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	GameState.instance().start_game()
	_level = LEVEL_SCENE.instantiate() as GreyboxLevel
	_level.rules = BuildingRules.new()
	_level.building_seed = 1
	# Агентов здесь нет: кадр про свет, а ходящая фигура закрывает собой зону.
	_level.spawn_agents = false
	add_child(_level)
	_run()


func _run() -> void:
	# Широкий этаж пониже: на нём три лампы, то есть три зоны темноты.
	var index := _level.rules.floors - 3
	var spots := _level.plan().safe_spots(_level.rules, index)
	var lamps := _lamps_on(index)
	if spots.is_empty() or lamps.size() < 2:
		push_error(
			"этаж %d не годится для кадра: мест %d, ламп %d" % [index, spots.size(), lamps.size()]
		)
		get_tree().quit(1)
		return

	# Otto встаёт под крайнюю лампу, а не посередине: в кадр должны попасть и его
	# зона, и соседняя — иначе «погасла одна» не с чем сравнить.
	var under := _nearest_spot(spots, _lamp_x(lamps[0]))
	_place(under, index)
	# Агент у соседней лампы: видно, что в освещённой зоне он читается сам, а в
	# тёмной его держит только обводка.
	_stand_an_agent_at(_nearest_spot(spots, _lamp_x(lamps[1])), index)
	await _shoot("01_floor_lit", null)
	await _shoot("02_zone_dark", lamps[0])

	var rest: Array[Lamp] = []
	for lamp in _lamps_on(index):
		rest.append(lamp)
	for lamp in rest:
		lamp.shoot_down()
	await _settle_after_the_fall()
	await _shoot("03_floor_dark", null)

	print("  этаж %d, зон %d: кадры в %s" % [index, lamps.size(), FOLDER])
	get_tree().quit(0)


## Сбивает лампу, если дана, ждёт и снимает кадр.
func _shoot(label: String, lamp: Lamp) -> void:
	if lamp != null:
		lamp.shoot_down()
		await _settle_after_the_fall()
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [FOLDER, label]
	image.save_png(path)
	print("  %s" % path)


## Ждёт, пока сбитые лампы долетят до пола: по состоянию, а не выдержкой.
func _settle_after_the_fall() -> void:
	var left := FALL_STEPS
	while left > 0 and _falling():
		await get_tree().physics_frame
		left -= 1
	await get_tree().physics_frame


func _falling() -> bool:
	for child in _level.get_children():
		var lamp := child as Lamp
		if lamp != null and lamp.is_queued_for_deletion():
			return true
	return false


func _lamps_on(index: int) -> Array[Lamp]:
	var found: Array[Lamp] = []
	for child in _level.get_children():
		var lamp := child as Lamp
		if lamp != null and lamp.floor_index == index and not lamp.is_queued_for_deletion():
			found.append(lamp)
	found.sort_custom(
		func(a: Lamp, b: Lamp) -> bool: return a.global_position.x < b.global_position.x
	)
	return found


func _lamp_x(lamp: Lamp) -> float:
	return WorldSpace.to_plane(lamp.global_position).x


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
	# Стоит на месте и безоружен: кадр про свет, а не про бой. С обычными
	# правилами он успевал застрелить Otto между вторым и третьим кадром, и на
	# кадре темноты лежал труп.
	var peaceful := BuildingRules.new()
	peaceful.agent_fire_range = 0.0
	peaceful.agent_dark_fire_range = 0.0
	agent.apply_rules(peaceful)
	agent.walk_speed = 0.0
	_level.add_child(agent)
	agent.global_position = WorldSpace.to_scene(Vector2(x, _level.rules.floor_surface(index)))
	agent.setup(_level.otto, -1.0)
