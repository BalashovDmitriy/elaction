extends Node3D

## M18a layout shots: the narrow tower fully in frame, the podium wider than the frame,
## the escalator band and a floor cut by a blind wall.
##
## The milestone capture ([code]capture.py[/code]) drives Otto by time and does not reach
## the bottom floors: getting down to the twentieth takes longer than any reasonable
## script lasts. And the walls and escalators stand by seed, a delay will not reach them.
## Here the frame is set by the layout: found the needed floor — placed Otto — took the shot.
##
## These shots are the M18a DoD check: above the threshold a floor fits into the frame whole,
## below it does not, and the lower a floor is, the more paths it has
## ([ADR-0024](res://docs/adr/0024-building-geometry.md)).
##
## Since M18e there are also building shots by the map here: a dark floor and a tower with
## ROM doors (ADR-0028), since M19 — the roof with the city behind it (ADR-0029). The folder
## is set by [code]--folder=[/code], M18a by default; the seed by [code]--seed=[/code], and
## with it the weather: seed 1 is fog, 2 is rain, 5 is a clear night.
##
## Real rendering, not headless — a screen is needed.
##
## Run:
##     godot --path . res://tools/layout_shot.tscn
##     godot --path . res://tools/layout_shot.tscn -- --folder=M18e
##     godot --path . res://tools/layout_shot.tscn -- --folder=M19 --seed=2
##     godot --path . res://tools/layout_shot.tscn -- --folder=M21 --garage --building=3
##     godot --path . res://tools/layout_shot.tscn -- --folder=M22 --floor-only --quality=3

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")

## Where the shots go by default.
const FOLDER := "res://screens/M18a"

## How many frames to give the building, light and reflections to settle.
const SETTLE_FRAMES: int = 45

## The seed is the same as in the milestone's other tools: the layout for it is already
## analysed in the status, and the shots are compared with it, not with a new building.
const BUILDING_SEED: int = 1

## Trial tone sets (ADR-0030, decision 1): shadows, midtones, highlights, contrast,
## saturation, exposure, glow. The second was taken into the game in M22
## ([Atmosphere]); the rest are for the next tuning.
const TONES: Array[Dictionary] = [
	{},
	{
		"shadow": Color(0.0, 0.015, 0.045),
		"middle": Color(0.28, 0.33, 0.38),
		"light": Color(1.0, 0.96, 0.88),
		"contrast": 1.16,
		"saturation": 0.84,
		"exposure": 1.1,
		"glow": 0.55,
	},
	{
		"shadow": Color(0.0, 0.03, 0.08),
		"middle": Color(0.27, 0.33, 0.4),
		"light": Color(1.0, 0.93, 0.8),
		"contrast": 1.12,
		"saturation": 0.9,
		"exposure": 1.15,
		"glow": 0.6,
	},
	{
		"shadow": Color(0.01, 0.02, 0.04),
		"middle": Color(0.3, 0.33, 0.36),
		"light": Color(1.0, 0.95, 0.85),
		"contrast": 1.2,
		"saturation": 0.8,
		"exposure": 1.2,
		"glow": 0.5,
	},
]

var _level: GreyboxLevel = null
var _folder: String = FOLDER
var _seed: int = BUILDING_SEED
## Round — the building palette; zero — the default rules (first round).
var _round: int = 0
## Building number in the game: the car draw at the exit depends on it (ADR-0032, decision 7).
var _building: int = 1
## Shoot only the garage — cars of different buildings side by side.
var _garage_only: bool = false
## Shoot only a tower floor with doors — quality levels side by side.
var _floor_only: bool = false
## Shoot only the roof — the city above it and the weather.
var _roof_only: bool = false
## Tone variant for tuning (M22): 0 — as in the game, otherwise a trial set of curves.
var _tone: int = 0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--folder="):
			_folder = "res://screens/" + argument.trim_prefix("--folder=")
		elif argument.begins_with("--seed="):
			_seed = argument.trim_prefix("--seed=").to_int()
		elif argument.begins_with("--round="):
			_round = argument.trim_prefix("--round=").to_int()
		elif argument.begins_with("--building="):
			_building = argument.trim_prefix("--building=").to_int()
		elif argument == "--garage":
			_garage_only = true
		elif argument.begins_with("--quality="):
			Graphics.broadcast(
				(
					clampi(
						argument.trim_prefix("--quality=").to_int(), 0, Graphics.Quality.size() - 1
					)
					as Graphics.Quality
				)
			)
		elif argument == "--floor-only":
			_floor_only = true
		elif argument == "--roof-only":
			_roof_only = true
		elif argument.begins_with("--tone="):
			_tone = clampi(argument.trim_prefix("--tone=").to_int(), 0, TONES.size() - 1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_folder))
	GameState.instance().start_game()
	GameState.instance().building = _building
	_level = LEVEL_SCENE.instantiate() as GreyboxLevel
	_level.rules = BuildingRules.for_building(_round) if _round > 0 else BuildingRules.new()
	_level.building_seed = _seed
	# Only the wall shot releases agents: in the others a walking figure
	# covers what the shot is taken for.
	_level.spawn_agents = false
	add_child(_level)
	_run()


func _run() -> void:
	var rules := _level.rules
	if _round > 0:
		# Round shot: one floor in the round palette — rounds are compared side by side.
		await _shoot_floor("round%d" % _round, 2)
		get_tree().quit(0)
		return
	if _tone > 0:
		_apply_tone(TONES[_tone])
	if _roof_only:
		await _shoot_floor("roof_seed%d" % _seed, BuildingRules.ROOF)
		get_tree().quit(0)
		return
	if _floor_only:
		var tag := "tone%d" % _tone if _tone > 0 else "q%d" % Graphics.quality
		await _shoot_floor("floor_%s" % tag, 2)
		if _tone > 0:
			await _shoot_floor("dark_%s" % tag, _first_unlit_floor())
		get_tree().quit(0)
		return
	if _garage_only:
		await _shoot_garage("garage_building%d" % _building)
		get_tree().quit(0)
		return
	await _shoot_floor("00_roof_seed%d" % _seed, BuildingRules.ROOF)
	await _shoot_floor("01_tower", rules.wide_from - 1)
	await _shoot_floor("02_podium", rules.floors - 2)
	await _shoot_floor("03_escalator_band", rules.single_shaft_until)

	var walled := _floor_with_a_wall()
	if walled == BuildingRules.ROOF:
		push_error("no walls on seed %d — nothing to shoot" % _seed)
		get_tree().quit(1)
		return
	await _shoot_the_wall("04_inner_wall", walled)
	await _shoot_floor("05_tower_doors", 2)
	await _shoot_floor("06_dark_floor", _first_unlit_floor())
	await _shoot_garage("07_garage")
	await _shoot_effects("08_effects", 2)

	print("  layout shots in %s" % _folder)
	get_tree().quit(0)


## Trial tone on top of the building's atmosphere: curves, contrast, saturation,
## exposure and glow.
func _apply_tone(tone: Dictionary) -> void:
	var air := (_level.get_node("Scenery/Air") as WorldEnvironment).environment
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, Atmosphere.NOIR_MIDDLE_AT, 1.0])
	gradient.colors = PackedColorArray([tone["shadow"], tone["middle"], tone["light"]])
	var curve := GradientTexture1D.new()
	curve.gradient = gradient
	air.adjustment_color_correction = curve
	air.adjustment_contrast = tone["contrast"]
	air.adjustment_saturation = tone["saturation"]
	air.tonemap_exposure = tone["exposure"]
	air.glow_intensity = tone["glow"]


## Garage by the exit: the car and markings (ADR-0031, decision 4; the car — ADR-0032).
func _shoot_garage(label: String) -> void:
	var bottom := _level.rules.floors - 1
	# Not in the doorway itself: without documents the exit would send Otto to a red door.
	_place(_level.plan().exit_x + 2.5, bottom)
	await _shoot(label, bottom)


## Puts Otto in the middle of a floor and takes a shot. The camera follows him, so the shot
## shows exactly what a player standing on this floor will see.
func _shoot_floor(label: String, index: int) -> void:
	var spots := _level.plan().safe_spots(_level.rules, index)
	if spots.is_empty():
		push_error("floor %d: nowhere to stand" % index)
		return
	_place(spots[spots.size() / 2], index)
	await _shoot(label, index)


## Wall shot: Otto on one side, an agent on the other. The agent must stand and not
## shoot — he does not see Otto, and that is what the shot is about.
func _shoot_the_wall(label: String, index: int) -> void:
	var wall_x := _wall_x(index)
	var spots := _level.plan().safe_spots(_level.rules, index)
	if spots.is_empty():
		push_error("floor %d: nowhere to stand" % index)
		return
	# A grid step, not a slot coordinate: [method BuildingRules.slot_x] returns "where",
	# and here we need "how far to the side".
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
	print("  %s — floor %d, width %.1f m" % [path, index, rules.floor_width(index)])


## The first floor from the top on which the layout placed a wall. [constant
## BuildingRules.ROOF] — no walls came up on this seed at all.
func _floor_with_a_wall() -> int:
	var highest := BuildingRules.ROOF
	for wall in _level.plan().walls:
		if highest == BuildingRules.ROOF or wall.floor_index < highest:
			highest = wall.floor_index
	return highest


## Sparks and blood (ADR-0031): a burst at the lamp and spatter at Otto, shot at the peak
## of the spread — a few frames later, not after a long delay: sparks live
## less than a second.
func _shoot_effects(label: String, index: int) -> void:
	var spots := _level.plan().safe_spots(_level.rules, index)
	_place(spots[spots.size() / 2], index)
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	var lamp: Lamp = null
	for node in _level.find_children("*", "Lamp", true, false):
		var candidate := node as Lamp
		if candidate != null and candidate.floor_index == index:
			lamp = candidate
			break
	if lamp != null:
		Sparks.burst(_level, lamp.global_position)
	var chest := _level.otto.global_position + Vector3(0.4, 1.1, 0.0)
	Blood.spray(_level, chest, 1.0)
	for _frame: int in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_folder, label]
	image.save_png(path)
	print("  %s — sparks and blood, floor %d" % [path, index])


## The first dark floor of the map from the top (ADR-0028, decision 4).
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
	# Stands still and unarmed: the shot is about the wall, not about combat.
	var peaceful := BuildingRules.new()
	peaceful.agents_hold_fire = true
	peaceful.agent_dark_fire_range = 0.0
	agent.apply_rules(peaceful)
	agent.walk_speed = 0.0
	_level.add_child(agent)
	agent.global_position = WorldSpace.to_scene(Vector2(x, _level.rules.floor_surface(index)))
	agent.setup(_level.otto, -1.0)
