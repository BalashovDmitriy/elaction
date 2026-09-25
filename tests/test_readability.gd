extends GutTest

## Читаемость на погашенном этаже (ADR-0023, решение 6): у двери табло, у
## кабины индикаторы, у выхода вывеска, светильник лампы светится сам, актёры в
## обводке. Всё это эмиссия и обводка — свету сцены не подчиняются, поэтому
## проверка структурная: кадр с погашенными лампами обязан это показывать.
##
## Здание настоящее, по правилам по умолчанию, на нескольких сидах: двери и
## кабины стоят по сиду, и одного здания мало.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const SEEDS: Array[int] = [1, 2, 3]

## Сколько кадров даётся зданию, чтобы встать на места.
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


## Цвет огонька, если узел — светящаяся коробка, иначе прозрачный.
static func _glow_of(node: Node) -> Color:
	var part := node as MeshInstance3D
	if part == null:
		return Color.TRANSPARENT
	var material := part.material_override as StandardMaterial3D
	if material == null or not material.emission_enabled:
		return Color.TRANSPARENT
	return material.emission


## Сколько прямых детей узла горят цветом [param colour].
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
			# Сама створка светом сцены не пренебрегает: огонёк — табло, не дверь.
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


## Взятый документ гасит красное табло: дверь стала обычной, и табло тёплое.
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
		var board := level.get_node_or_null("ExitSign")
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
			assert_almost_eq(
				at.x, level.plan().exit_x, 0.001, "сид %d: над проёмом" % building_seed
			)
		remove_child(level)


## Светильник — сам источник, и он виден, пока висит.
func test_lamps_glow_themselves() -> void:
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)
	var lamps := level.find_children("*", "Lamp", false, false)
	assert_gt(lamps.size(), 0, "в здании есть лампы")
	for lamp in lamps:
		assert_eq(_glow_of(lamp.get_node("Visual")), GreyboxLook.LAMP, "светильник светится")
	remove_child(level)


## Актёры — модели: их держит обводка вторым проходом на каждом меше. Меши
## фигуры — под её ригом, [code]Body[/code]: луч прицела агента тоже меш, но
## светящаяся нить, а не тело, и обводка ему не нужна.
func test_actors_wear_an_outline() -> void:
	var level := _build(1)
	var agent := ENEMY_SCENE.instantiate() as Enemy
	level.add_child(agent)
	await wait_physics_frames(SETTLE_FRAMES)
	for actor: Node in [level.otto, agent]:
		var meshes := actor.get_node("Body").find_children("*", "MeshInstance3D", true, false)
		assert_gt(meshes.size(), 0, "у актёра есть меши")
		for node in meshes:
			var mesh := node as MeshInstance3D
			assert_eq(mesh.material_overlay, GreyboxLook.outline(), "на каждом меше обводка")
	remove_child(level)
