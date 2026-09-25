extends GutTest

## Выезд из паркинга — тоннель, пандус и улица ([GarageRamp], [ExitStreet]) —
## на любом здании: ничего из выезда не залезает в здание и не стоит на пути
## машины, грани разных материалов не лежат в одной плоскости, а свет выезда —
## не больше двух источников без тени, и горят они, только пока выезд в кадре.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const SEEDS: Array[int] = [1, 2, 3, 7]

## Допуск «в одной плоскости», м.
const COPLANAR: float = 0.001
## Сколько над проездом должно быть пусто на пути машины, м: машина с запасом.
const HEADROOM: float = 1.6
## Глубина здания в сцене: от лица коридора до дальней стены паркинга с запасом.
const BUILDING_Z := Vector2(-8.4, WorldSpace.CORRIDOR_DEPTH * 0.5)


func test_the_exit_keeps_out_of_the_building_and_the_cars_way() -> void:
	for building_seed: int in SEEDS:
		var level := _build(building_seed)
		var ramp := level.garage().gate.ramp()
		assert_not_null(ramp, "сид %d: выезда нет" % building_seed)
		if ramp == null:
			continue
		var rules := level.rules
		var gate := rules.floor_span(rules.floors - 1).x
		var lane := _car_lane(level)
		var parts := _parts(ramp)
		assert_gt(parts.size(), 100, "сид %d: выезд почти пуст" % building_seed)
		var inside: Array[String] = []
		var in_the_way: Array[String] = []
		for part: Array in parts:
			var box := part[0] as AABB
			var deep := box.end.z > BUILDING_Z.x and box.position.z < BUILDING_Z.y
			if deep and box.end.x > gate + 0.001:
				inside.append(str(box))
			if not bool(part[2]) and _blocks(rules, box, lane):
				in_the_way.append(str(box))
		assert_eq(inside, [] as Array[String], "сид %d: выезд в здании" % building_seed)
		assert_eq(in_the_way, [] as Array[String], "сид %d: на пути машины" % building_seed)
		remove_child(level)


func test_no_two_materials_share_a_face_on_the_exit() -> void:
	for building_seed: int in SEEDS:
		var level := _build(building_seed)
		var boxes: Array[Array] = []
		for part: Array in _parts(level.garage().gate.ramp()):
			if bool(part[3]):
				boxes.append(part)
		var clashes := _clashes(boxes)
		assert_eq(
			clashes,
			[] as Array[String],
			"сид %d: грани в одной плоскости — %s" % [building_seed, clashes]
		)
		remove_child(level)


func test_the_exit_lights_are_few_unshadowed_and_off_in_play() -> void:
	var level := _build(2)
	var ramp := level.garage().gate.ramp()
	var lights := ramp.lights()
	assert_between(lights.size(), 1, 2, "свет выезда — один-два источника")
	for light in lights:
		assert_false(light.shadow_enabled, "%s кладёт тень" % light.name)
	await wait_process_frames(3)
	for light in lights:
		assert_false(light.is_visible_in_tree(), "%s горит, хотя выезд не в кадре" % light.name)
	var rules := level.rules
	var bottom := rules.floors - 1
	level.otto.global_position = WorldSpace.to_scene(
		Vector2(rules.floor_span(bottom).x + 4.0, rules.floor_surface(bottom))
	)
	# Вступление на первых кадрах возвращает камере границы здания — кадр
	# выезда ставится заново каждый кадр.
	for _frame in 3:
		level.otto.apply_camera_bounds(ExitBoarding.exit_frame(rules))
		await wait_process_frames(1)
	for light in lights:
		assert_true(light.is_visible_in_tree(), "%s не горит в кадре выезда" % light.name)
	remove_child(level)


func _build(building_seed: int) -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = building_seed
	level.spawn_agents = false
	add_child_autofree(level)
	level.skip_the_intro()
	return level


## Полоса машины по глубине, Z сцены: по мешам её модели.
func _car_lane(level: GreyboxLevel) -> Vector2:
	var car := level.find_child("ExitCar", true, false) as Node3D
	var low := INF
	var high := -INF
	for node: Node in car.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.is_visible_in_tree():
			continue
		var box := mesh.global_transform * mesh.mesh.get_aabb()
		low = minf(low, box.position.z)
		high = maxf(high, box.end.z)
	return Vector2(low, high)


## Стоит ли коробка [param box] на пути машины: в её полосе по глубине и ниже
## [constant HEADROOM] над проездом хоть где-то по своей длине.
func _blocks(rules: BuildingRules, box: AABB, lane: Vector2) -> bool:
	if box.end.z <= lane.x or box.position.z >= lane.y:
		return false
	var floor_scene := WorldSpace.height_to_scene(rules.floor_surface(rules.floors - 1))
	var steps := 8
	for step in steps + 1:
		var x := lerpf(box.position.x, box.end.x, float(step) / float(steps))
		var ground := floor_scene + GarageRamp.climb_at(rules, x)
		if box.end.y > ground + 0.03 and box.position.y < ground + HEADROOM:
			return true
	return false


## Меши выезда: [AABB в сцене, материал, наклонён ли (или не коробка), коробка
## ли без поворота]. Пятна света и надписи — не в счёт: они не преграда.
func _parts(root: Node) -> Array[Array]:
	var found: Array[Array] = []
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		# Клин грунта под подъёмом повторяет пандус, а коробка его — нет.
		if part.mesh is PlaneMesh or part.mesh is QuadMesh or part.mesh is PrismMesh:
			continue
		if part.get_parent() is MultiMeshInstance3D:
			continue
		var basis := part.global_basis.orthonormalized()
		var straight := basis.is_equal_approx(Basis.IDENTITY)
		var box := part.global_transform * part.mesh.get_aabb()
		var plain_box := part.mesh is BoxMesh and straight
		# Машина у бордюра — модель, и путь её не пересекает: она через дорогу.
		var tilted := not straight and part.mesh is BoxMesh
		found.append([box, part.material_override, tilted, plain_box])
	return found


## Пары коробок разных материалов с гранью в одной плоскости и одной нормалью,
## которые перекрываются по площади. Боковые грани, по x, камера видит ребром.
func _clashes(boxes: Array[Array]) -> Array[String]:
	var clashes: Array[String] = []
	for i in boxes.size():
		var a := boxes[i][0] as AABB
		for j in range(i + 1, boxes.size()):
			if boxes[i][1] == boxes[j][1]:
				continue
			var b := boxes[j][0] as AABB
			for axis: int in [Vector3.AXIS_Y, Vector3.AXIS_Z]:
				if _share_face(a, b, axis):
					clashes.append("%s и %s" % [a, b])
					if clashes.size() > 5:
						return clashes
	return clashes


func _share_face(a: AABB, b: AABB, axis: int) -> bool:
	var low := absf(a.position[axis] - b.position[axis]) < COPLANAR
	var high := absf(a.end[axis] - b.end[axis]) < COPLANAR
	if not low and not high:
		return false
	for other in 3:
		if other == axis:
			continue
		var overlap := minf(a.end[other], b.end[other]) - maxf(a.position[other], b.position[other])
		if overlap <= COPLANAR:
			return false
	return true
