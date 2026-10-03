extends GutTest

## Readability on a dark floor (ADR-0023, decision 6): a door has an indicator board, a
## cab has indicators, the exit has a sign, a lamp fixture glows by itself, actors are
## lit by the camera light on their layer. None of this obeys lamp light, so the
## check is structural: a frame with the lamps out must show it.
##
## The building is real, with the default rules, on several seeds: doors and
## cabs stand by seed, and one building is not enough.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const SEEDS: Array[int] = [1, 2, 3]

## How many frames the building gets to settle into place.
const SETTLE_FRAMES: int = 4


func before_all() -> void:
	Engine.time_scale = 4.0


func after_all() -> void:
	Engine.time_scale = 1.0
	GameState.instance().reset()


func _build(building_seed: int) -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = building_seed
	level.spawn_agents = false
	add_child_autofree(level)
	return level


## Indicator light colour if the node is a glowing box, otherwise transparent.
static func _glow_of(node: Node) -> Color:
	var part := node as MeshInstance3D
	if part == null:
		return Color.TRANSPARENT
	var material := part.material_override as StandardMaterial3D
	if material == null or not material.emission_enabled:
		return Color.TRANSPARENT
	return material.emission


## How many direct children of the node glow in colour [param colour].
static func _lights_of(node: Node, colour: Color) -> int:
	var count := 0
	for child: Node in node.get_children():
		if _glow_of(child) == colour:
			count += 1
	return count


func test_every_door_carries_a_sign_that_tells_red_from_plain() -> void:
	for building_seed: int in SEEDS:
		var level := _build(building_seed)
		await wait_physics_frames(SETTLE_FRAMES)
		var red := 0
		for door in level.doors():
			var wanted := GreyboxLook.SIGN_RED if door.has_document else GreyboxLook.SIGN_WARM
			assert_eq(
				_lights_of(door, wanted),
				1,
				"сид %d: у двери одно табло своего цвета" % building_seed
			)
			if door.has_document:
				red += 1
			# The leaf itself does not ignore scene light: the indicator light is the board, not the
			# door.
			assert_eq(
				_glow_of(door.get_node("Leaf")),
				Color.TRANSPARENT,
				"сид %d: створка не светится" % building_seed
			)
		assert_eq(
			red,
			BuildingDocuments.count(level.rules, level.building_seed),
			"сид %d: красных табло столько же, сколько документов" % building_seed
		)
		remove_child(level)


## A taken document turns off the red indicator board: the door became ordinary, and the
## board is warm.
func test_a_taken_document_turns_the_sign_warm() -> void:
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)
	var red: Door = null
	for door in level.doors():
		if door.has_document:
			red = door
			break
	assert_not_null(red, "в здании есть красная дверь")
	if red == null:
		return
	red.has_document = false
	await wait_physics_frames(1)
	assert_eq(_lights_of(red, GreyboxLook.SIGN_WARM), 1, "табло стало тёплым")
	assert_eq(_lights_of(red, GreyboxLook.SIGN_RED), 0, "красного не осталось")
	remove_child(level)


func test_every_car_shows_two_indicators() -> void:
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)
	var cars := level.find_children("*", "ElevatorCar", false, false)
	assert_gt(cars.size(), 0, "в здании есть кабины")
	for car in cars:
		assert_eq(_lights_of(car, GreyboxLook.INDICATOR), 2, "у кабины два индикатора")
	remove_child(level)


func test_the_exit_wears_a_green_sign() -> void:
	for building_seed: int in SEEDS:
		var level := _build(building_seed)
		await wait_physics_frames(SETTLE_FRAMES)
		# Since M24b the sign is above the garage gate in the left end wall ([GarageGate]).
		var board := level.get_node_or_null("Garage/Gate/ExitSign")
		assert_not_null(board, "сид %d: над выходом вывеска" % building_seed)
		if board != null:
			assert_eq(
				_glow_of(board), GreyboxLook.SIGN_GREEN, "сид %d: и она зелёная" % building_seed
			)
			var at := WorldSpace.to_plane((board as Node3D).global_position)
			var bottom := level.rules.floors - 1
			assert_between(
				at.y,
				level.rules.story_top(bottom),
				level.rules.floor_surface(bottom),
				"сид %d: под потолком нижнего этажа" % building_seed
			)
			var left := level.rules.floor_span(bottom).x
			assert_between(at.x, left, left + 1.0, "сид %d: над воротами" % building_seed)
		remove_child(level)


## The fixture is the light source itself, and it is visible while it hangs.
func test_lamps_glow_themselves() -> void:
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)
	var lamps := level.find_children("*", "Lamp", false, false)
	assert_gt(lamps.size(), 0, "в здании есть лампы")
	for lamp in lamps:
		assert_eq(_glow_of(lamp.get_node("Visual")), GreyboxLook.LAMP, "светильник светится")
	remove_child(level)


## Actors are models: since M24f they have no outline, the camera light on the figure
## layer holds them (ADR-0042, decision 7). The figure's meshes are under its rig,
## [code]Body[/code]: the agent's aiming beam is a mesh too, but a glowing thread, not a body.
func test_actors_are_lit_by_the_camera_fill() -> void:
	var level := _build(1)
	var agent := ENEMY_SCENE.instantiate() as Enemy
	level.add_child(agent)
	await wait_physics_frames(SETTLE_FRAMES)
	for actor: Node in [level.otto, agent]:
		var meshes := actor.get_node("Body").find_children("*", "MeshInstance3D", true, false)
		assert_gt(meshes.size(), 0, "у актёра есть меши")
		for node in meshes:
			var mesh := node as MeshInstance3D
			assert_null(mesh.material_overlay, "обводки нет")
			assert_ne(mesh.layers & FigureRig.RENDER_LAYER, 0, "меш на слое фигур")
	var fill := level.otto.get_viewport().get_camera_3d().get_node("ActorFill") as Light3D
	assert_eq(fill.light_cull_mask, FigureRig.RENDER_LAYER, "свет камеры — только на фигуры")
	remove_child(level)
