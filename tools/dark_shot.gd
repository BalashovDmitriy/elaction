extends Node3D

## Darkness shots: a wide floor with three lamps — whole, with a darkened zone, and
## fully darkened.
##
## The milestone capture ([code]capture.py[/code]) drives Otto by time and does not reach
## the lower floors, and lamps are placed by seed — timing will not get there. Here the
## shot waits for a state: the lamp is shot down and has reached the floor.
##
## These three shots are the check of the M17 DoD: on a dark floor the player must see
## what he is shooting at, and the neighbouring zone must stay lit (ADR-0023, decision 2).
##
## The render is real, not headless — a screen is needed.
##
## Launch:
##     godot --path . res://tools/dark_shot.tscn

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")

## Where the shots are stored.
const FOLDER := "res://screens/M17"

## How many frames to give the building, light and reflections to settle.
const SETTLE_FRAMES: int = 45

## How many physics steps to wait for the lamp to fall before giving up.
const FALL_STEPS: int = 240

var _level: GreyboxLevel = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	GameState.instance().start_game()
	_level = LEVEL_SCENE.instantiate() as GreyboxLevel
	_level.rules = BuildingRules.new()
	_level.building_seed = 1
	# No agents here: the shot is about light, and a walking figure covers the zone.
	_level.spawn_agents = false
	add_child(_level)
	_run()


func _run() -> void:
	# A wide floor lower down: it has three lamps, that is three darkness zones.
	var index := _level.rules.floors - 3
	var spots := _level.plan().safe_spots(_level.rules, index)
	var lamps := _lamps_on(index)
	if spots.is_empty() or lamps.size() < 2:
		push_error(
			"этаж %d не годится для кадра: мест %d, ламп %d" % [index, spots.size(), lamps.size()]
		)
		get_tree().quit(1)
		return

	# Otto stands under the outermost lamp, not in the middle: both his zone and the
	# neighbouring one must get into the frame — otherwise "one went out" has nothing to
	# compare with.
	var under := _nearest_spot(spots, _lamp_x(lamps[0]))
	_place(under, index)
	# An agent at the neighbouring lamp: shows that in a lit zone he reads by himself,
	# while in a dark one only the outline holds him.
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


## Shoots down the lamp if given, waits and takes the shot.
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


## Waits until the shot-down lamps reach the floor: by state, not by timing.
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
	# Stands still and unarmed: the shot is about light, not combat. Under normal rules he
	# managed to shoot Otto between the second and third shot, and a corpse lay in the
	# darkness shot.
	var peaceful := BuildingRules.new()
	peaceful.agents_hold_fire = true
	peaceful.agent_dark_fire_range = 0.0
	agent.apply_rules(peaceful)
	agent.walk_speed = 0.0
	_level.add_child(agent)
	agent.global_position = WorldSpace.to_scene(Vector2(x, _level.rules.floor_surface(index)))
	agent.setup(_level.otto, -1.0)
