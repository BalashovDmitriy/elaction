extends Node3D

## M18b close-up shots: the escalator, the light column in the shaft, the two-deck pair.
##
## Milestone capture ([code]capture.py[/code]) and layout shots ([code]layout_shot.gd[/code])
## shoot a whole floor: in such a shot the escalator fits as a strip a quarter of the
## height, and neither steps nor balustrade can be seen on it. Here the camera is its own
## and close: the shot is about the construction, not about the floor.
##
## This is the M18b DoD check ([ADR-0025](res://docs/adr/0025-shafts-escalators-and-riders.md)):
## the escalator looks like an escalator, the shaft reads on an unlit floor, and the pair
## of decks moves together.
##
## The render is real, not headless: a screen is needed.
##
## Run:
##     godot --path . res://tools/geometry_shot.tscn

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

## Where the shots go.
const FOLDER := "res://screens/M18b"

## How many frames to give the building, light and reflections to settle.
const SETTLE_FRAMES: int = 45

## Wait cap, in physics steps, for knocked-down lamps to reach the floor.
const FALL_STEPS: int = 240

## The seed is the same as for the milestone's other tools: the layout for it is analyzed
## in the status, and the shots are compared with it, not with a new building.
const BUILDING_SEED: int = 1

## How far the camera stands from the play plane and how much it is tilted. The numbers
## of [SideCamera]: the shot must be the same as what the player sees, only closer.
const DISTANCE: float = 20.0
const TILT_DEGREES: float = 10.0

var _level: GreyboxLevel = null
var _camera: Camera3D = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	GameState.instance().start_game()
	_level = LEVEL_SCENE.instantiate() as GreyboxLevel
	_level.rules = BuildingRules.new()
	_level.building_seed = BUILDING_SEED
	# The shot is about the construction: a walking figure covers what it is taken for.
	_level.spawn_agents = false
	add_child(_level)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.rotation = Vector3(-deg_to_rad(TILT_DEGREES), 0.0, 0.0)
	_camera.near = 0.05
	_camera.far = DISTANCE * 2.0
	add_child(_camera)
	_run()


func _run() -> void:
	var spot := _escalator_under_a_lamp()
	if spot == null:
		push_error("на сиде %d эскалаторов нет — кадр снять не с чего" % BUILDING_SEED)
		get_tree().quit(1)
		return

	var rules := _level.rules
	# The shot covers both spans and both floors the escalator connects.
	var middle := Vector2(
		spot.x + spot.towards * rules.escalator_run * 0.5,
		rules.floor_surface(spot.floor_index) + rules.floor_height * 0.5
	)
	_stand_otto_on_the_top_pad(spot)
	await _shoot("01_escalator", middle, 7.2)

	await _shoot_the_dark_shaft("02_shaft_dark")
	# A shot not taken is a failure of the run, and we must exit with an error. A second
	# [method SceneTree.quit] in the same frame overrides the first one's code, so
	# the refusal is raised up here instead of exiting on the spot.
	var shot := await _shoot_the_pair("03_double_deck")
	if not shot:
		get_tree().quit(1)
		return

	print("  кадры геометрии в %s" % FOLDER)
	get_tree().quit(0)


## Shot of the two-deck pair: both decks and the rods between them.
##
## The shot takes two floors at once: otherwise one deck is visible, and the pair is no
## different from an ordinary cab.
func _shoot_the_pair(label: String) -> bool:
	var rules := _level.rules
	var shaft := _double_deck_shaft()
	if shaft == null:
		push_error("на сиде %d пара не выпала — кадр снять не с чего" % BUILDING_SEED)
		return false

	var span := shaft.ride_span()
	var index := span.x
	_level.otto.global_position = WorldSpace.to_scene(
		Vector2(shaft.x + rules.shaft_width, rules.floor_surface(index))
	)
	_level.otto.velocity = Vector3.ZERO
	# The middle between the upper deck's floor and the lower deck's floor: the pair stands
	# a floor apart, and both must get into the shot.
	var middle := rules.floor_surface(index) + rules.floor_height * 0.5
	await _shoot(label, Vector2(shaft.x, middle), 4.2)
	return true


func _double_deck_shaft() -> BuildingPlan.ShaftSpot:
	for shaft in _level.plan().shafts:
		if shaft.double_deck:
			return shaft
	return null


## Shot of a shaft on an unlit floor: the lamps are knocked down, only the column shines.
##
## This is the check of decision 3: the shaft must always read, otherwise
## an unlit building stops being passable by eye.
func _shoot_the_dark_shaft(label: String) -> void:
	var rules := _level.rules
	# A wide floor lower down: it has the most shafts per floor, and three lamps too.
	var index := rules.floors - 3
	var shaft_x := _shaft_x_on(index)
	for lamp in _lamps_on(index):
		lamp.shoot_down()
	await _settle_after_the_fall(index)

	_level.otto.global_position = WorldSpace.to_scene(
		Vector2(shaft_x + rules.shaft_width, rules.floor_surface(index))
	)
	_level.otto.velocity = Vector3.ZERO
	await _shoot(label, Vector2(shaft_x, rules.floor_surface(index) - rules.floor_height), 5.4)


## Column of the first shaft serving the floor.
func _shaft_x_on(index: int) -> float:
	for shaft in _level.plan().shafts:
		if index >= shaft.top and index <= shaft.bottom:
			return shaft.x
	return 0.0


func _lamps_on(index: int) -> Array[Lamp]:
	var found: Array[Lamp] = []
	for child in _level.get_children():
		var lamp := child as Lamp
		if lamp != null and lamp.floor_index == index and not lamp.is_queued_for_deletion():
			found.append(lamp)
	return found


## Waits until knocked-down lamps reach the floor: by state, not by delay.
##
## The state is "the lamp is still on the floor": having landed, it removes itself
## ([method Lamp._land]), and an empty floor means all of them have fallen. Waiting on
## the "already being deleted" sign is not possible: it is true for exactly one frame,
## the very last one, and the wait would end before it began.
func _settle_after_the_fall(index: int) -> void:
	var left := FALL_STEPS
	while left > 0 and not _lamps_on(index).is_empty():
		await get_tree().physics_frame
		left -= 1
	if left <= 0:
		push_warning("лампы этажа %d не долетели до пола за %d шагов" % [index, FALL_STEPS])
	await get_tree().physics_frame


## The escalator closest to its floor's lamp.
##
## The shot is about the construction: steps, balustrade and handrail are visible only
## under light. There are about five escalators per building, and half of them stand in
## the unlit part of the floor: shot there, the frame would show M17 lamp zones, not
## M18b geometry.
func _escalator_under_a_lamp() -> EscalatorSpot:
	var plan := _level.plan()
	if plan.escalators.is_empty():
		return null
	var best: EscalatorSpot = plan.escalators[0]
	var best_gap := INF
	for spot in plan.escalators:
		for lamp in plan.lamps:
			if lamp.floor_index != spot.floor_index:
				continue
			var gap := absf(lamp.x - spot.x)
			if gap < best_gap:
				best_gap = gap
				best = spot
	return best


## Puts Otto on the upper landing: the shot must also show that the side on the camera
## side does not cover him (ADR-0025, decision 5).
func _stand_otto_on_the_top_pad(spot: EscalatorSpot) -> void:
	var rules := _level.rules
	_level.otto.global_position = WorldSpace.to_scene(
		Vector2(spot.x, rules.floor_surface(spot.floor_index))
	)
	_level.otto.velocity = Vector3.ZERO


## Takes a shot aimed at a rules point, with the given half height of the frame.
func _shoot(label: String, centre: Vector2, half_height: float) -> void:
	var at := WorldSpace.to_scene(centre)
	_camera.size = half_height * 2.0
	_camera.global_position = Vector3(
		at.x, at.y + DISTANCE * tan(deg_to_rad(TILT_DEGREES)), DISTANCE
	)

	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [FOLDER, label]
	image.save_png(path)
	print("  %s" % path)
