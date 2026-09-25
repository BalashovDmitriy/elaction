extends GutTest

## Паркинг нижнего этажа (ADR-0038, решение 3) на любом здании.
##
## Раскладка — колонны, места, чужие машины — проверяется без сцены на многих
## сидах и навыках; сборка — на нескольких сидах: паркинг строится, машины за
## плоскостью игры, ворота у левого торца, грани разных материалов не в одной
## плоскости (подход — [code]test_shaft_faces.gd[/code]).

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

const SEEDS: Array[int] = [1, 2, 3, 5, 8, 13, 21, 34, 55, 89]
const SKILLS: Array[int] = [0, 5]
## Сиды сборки: сцена дороже раскладки.
const BUILT_SEEDS: Array[int] = [1, 2, 5]

## Допуск «в одной плоскости», м.
const COPLANAR: float = 0.001


func after_all() -> void:
	GameState.instance().reset()


func _rules(skill: int) -> BuildingRules:
	var rules := BuildingRules.new()
	rules.skill = skill
	return rules


## Чужие машины — на местах, мимо машины Otto, выхода, ядер шахт и стен, и
## внутри стен этажа; место под ними не уже машины.
func test_parked_cars_keep_clear_on_any_building() -> void:
	var total := 0
	for skill: int in SKILLS:
		var rules := _rules(skill)
		var inner := Garage.inner_span(rules)
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			var banned := Garage.keep_out(rules, plan)
			banned.append_array(Garage.busy_spans(rules, plan))
			banned.append(ExitCar.parked_span(rules))
			for car in Garage.parked(rules, plan, building_seed):
				total += 1
				var span := Vector2(car.x - Garage.CAR_WIDTH * 0.5, car.x + Garage.CAR_WIDTH * 0.5)
				var tag := "навык %d, сид %d, машина у %.2f" % [skill, building_seed, car.x]
				assert_between(span.x, inner.x, inner.y, tag)
				assert_between(span.y, inner.x, inner.y, tag)
				for zone in banned:
					assert_true(span.y <= zone.x or span.x >= zone.y, "%s в %s" % [tag, zone])
				for x in Garage.column_xs(rules, plan):
					assert_true(
						absf(car.x - x) >= Garage.CAR_WIDTH * 0.5 + Garage.COLUMN * 0.5,
						"%s на колонне %.2f" % [tag, x]
					)
	assert_gt(total, SEEDS.size(), "машин почти нет — паркинг пуст")


## Паркинг один и тот же на одном сиде и разный на разных.
func test_parked_cars_follow_the_seed() -> void:
	var rules := _rules(0)
	var plan := BuildingPlan.generate(rules, 3)
	var first := _signature(Garage.parked(rules, plan, 3))
	assert_eq(first, _signature(Garage.parked(rules, plan, 3)), "жребий не повторился")
	var other := BuildingPlan.generate(rules, 4)
	assert_ne(first, _signature(Garage.parked(rules, other, 4)), "два здания — один паркинг")


## Места не налезают друг на друга и на колонны, колонны — на ядра шахт.
func test_bays_and_columns_do_not_overlap() -> void:
	for skill: int in SKILLS:
		var rules := _rules(skill)
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			var tag := "навык %d, сид %d" % [skill, building_seed]
			var bays := Garage.bays(rules, plan)
			assert_gt(bays.size(), 3, "%s: мест почти нет" % tag)
			for index in bays.size():
				var bay := bays[index]
				assert_gte(bay.y - bay.x, Garage.BAY_MIN - 0.001, "%s: узкое место" % tag)
				if index > 0:
					assert_gte(bay.x, bays[index - 1].y - 0.001, "%s: места внахлёст" % tag)
				for x in Garage.column_xs(rules, plan):
					var reach := Garage.COLUMN * 0.5
					assert_true(
						bay.y <= x - reach + 0.001 or bay.x >= x + reach - 0.001,
						"%s: место %s на колонне %.2f" % [tag, bay, x]
					)
			for x in Garage.column_xs(rules, plan):
				for core in Garage.cores(rules, plan):
					assert_true(
						x + Garage.COLUMN * 0.5 <= core.x or x - Garage.COLUMN * 0.5 >= core.y,
						"%s: колонна %.2f в ядре шахты %s" % [tag, x, core]
					)


## Ворота — в левом торце нижнего этажа, в толще стены.
func test_the_gate_is_at_the_left_end() -> void:
	for skill: int in SKILLS:
		var rules := _rules(skill)
		var left := rules.floor_span(rules.floors - 1).x
		var gate := Garage.gate_x(rules)
		assert_between(gate, left, left + BuildingShell.WALL_WIDTH, "навык %d" % skill)


## Паркинг собирается на каждом сиде: зал, машины за плоскостью игры, ворота у
## левого торца, вывеска EXIT над ними, светильники в зонах ламп.
func test_the_garage_builds_on_every_seed() -> void:
	for building_seed: int in BUILT_SEEDS:
		var level := _build(building_seed)
		var garage := level.garage()
		assert_not_null(garage, "сид %d: паркинга нет" % building_seed)
		if garage == null:
			remove_child(level)
			continue
		var rules := level.rules
		var tag := "сид %d" % building_seed
		assert_gt(garage.get_child_count(), 50, "%s: паркинг почти пуст" % tag)
		assert_eq(
			garage.find_children("*", "CollisionObject3D", true, false).size(),
			0,
			"%s: у паркинга есть тела" % tag
		)

		var cars := garage.get_node("ParkedCars")
		assert_eq(
			cars.get_child_count(),
			Garage.parked(rules, level.plan(), building_seed).size(),
			"%s: машин не столько, сколько по жребию" % tag
		)
		for car: Node in cars.get_children():
			var box := _bounds_of(car as Node3D)
			assert_lt(
				box.end.z,
				-WorldSpace.BODY_DEPTH * 0.5,
				"%s: машина у %.2f в плоскости игры" % [tag, box.get_center().x]
			)
			assert_gt(box.size.x, 1.0, "%s: машина сплющена" % tag)

		var sign_node := garage.gate.get_node_or_null("ExitSign") as Node3D
		assert_not_null(sign_node, "%s: над воротами нет вывески" % tag)
		if sign_node != null:
			var at := WorldSpace.to_plane(sign_node.global_position)
			var left := rules.floor_span(rules.floors - 1).x
			assert_between(at.x, left, left + 1.0, "%s: вывеска не у ворот" % tag)
			assert_between(
				at.y,
				rules.story_top(rules.floors - 1),
				rules.floor_surface(rules.floors - 1),
				"%s: вывеска не на нижнем этаже" % tag
			)
		for light in garage.lights():
			assert_false(light.shadow_enabled, "%s: свет трубки кладёт тень" % tag)
		remove_child(level)


## Ворота поднимаются: [method Garage.open_gate] доводит штору до верха шагами
## физики.
func test_the_gate_opens() -> void:
	var level := _build(1)
	var garage := level.garage()
	assert_false(garage.is_gate_open(), "ворота открыты с начала")
	var tween := garage.open_gate(0.2)
	await wait_physics_frames(30)
	assert_false(tween.is_running(), "штора всё ещё едет")
	assert_true(garage.is_gate_open(), "ворота не открылись")
	remove_child(level)


## Упавшая лампа гасит светильники своей зоны — и только их.
func test_a_fallen_lamp_puts_out_its_tubes() -> void:
	var level := _build(2)
	var garage := level.garage()
	var rules := level.rules
	var bottom := rules.floors - 1
	var lamps := PackedFloat64Array()
	for spot in level.plan().lamps:
		if spot.floor_index == bottom:
			lamps.append(spot.x)
	if lamps.size() < 2 or rules.is_unlit(bottom):
		pending("на этом сиде у паркинга меньше двух ламп")
		remove_child(level)
		return
	var tubes := _tube_xs(garage)
	assert_gt(tubes.size(), 1, "светильников почти нет")
	for x in tubes:
		assert_true(garage.tube_lit_at(x), "трубка у %.2f не горит" % x)
	garage.darken(lamps[0])
	for x in tubes:
		var nearest := lamps[0]
		for lamp_x in lamps:
			if absf(lamp_x - x) < absf(nearest - x):
				nearest = lamp_x
		assert_eq(garage.tube_lit_at(x), nearest != lamps[0], "трубка у %.2f после лампы" % x)
	remove_child(level)


## Новые коробки паркинга не делят грань с коробкой другого материала — ни
## своей, ни оболочки, ни шахт, ни рёбер.
func test_no_two_materials_share_a_face_in_the_garage() -> void:
	for building_seed: int in BUILT_SEEDS:
		var level := _build(building_seed)
		var garage := level.garage()
		var own := _boxes(garage, garage)
		assert_gt(own.size(), 50, "сид %d: у паркинга нет деталей" % building_seed)
		var region := _bottom_region(level.rules)
		var others: Array[Array] = []
		for root: Node in level.get_children():
			if not (root is BuildingShell or root is BuildingShafts or root is BuildingRibs):
				continue
			for box in _boxes(root, garage):
				if (box[0] as AABB).intersects(region):
					others.append(box)
		var clashes := _clashes(own, own, true)
		clashes.append_array(_clashes(own, others, false))
		assert_eq(
			clashes,
			[] as Array[String],
			"сид %d: грани в одной плоскости — %s" % [building_seed, clashes]
		)
		remove_child(level)


func _build(building_seed: int) -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = building_seed
	level.spawn_agents = false
	add_child_autofree(level)
	return level


func _signature(cars: Array[Garage.Parked]) -> String:
	var parts := PackedStringArray()
	for car in cars:
		parts.append("%.2f/%d/%d/%s" % [car.x, car.choice.model, car.choice.paint, car.nose_in])
	return ",".join(parts)


## Где висят светильники: x трубок.
func _tube_xs(garage: Garage) -> PackedFloat64Array:
	var found := PackedFloat64Array()
	var tube_color := Garage.TUBE
	for node: Node in garage.find_children("*", "MeshInstance3D", false, false):
		var part := node as MeshInstance3D
		var material := part.material_override as StandardMaterial3D
		if material != null and material.emission_enabled and material.emission == tube_color:
			found.append(part.position.x)
	return found


## Объём нижнего этажа в сцене: от пола до потолка и чуть за ними.
func _bottom_region(rules: BuildingRules) -> AABB:
	var bottom := rules.floors - 1
	var top := WorldSpace.height_to_scene(rules.story_top(bottom))
	var floor_y := WorldSpace.height_to_scene(rules.floor_surface(bottom))
	return AABB(
		Vector3(-1.0, floor_y - 0.1, -10.0), Vector3(rules.width + 2.0, top - floor_y + 0.2, 12.0)
	)


## Объём модели по её мешам в координатах сцены.
func _bounds_of(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var part := mesh.global_transform * mesh.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


## Коробки без поворота: [AABB, материал]. Пандус за воротами — наклонный и
## за кадром — не в счёт; штора, пока закрыта, без масштаба.
func _boxes(root: Node, garage: Garage) -> Array[Array]:
	var ramp := garage.gate.get_node_or_null("Ramp")
	var found: Array[Array] = []
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		if ramp != null and ramp.is_ancestor_of(node):
			continue
		var part := node as MeshInstance3D
		var mesh := part.mesh as BoxMesh
		if mesh == null:
			continue
		var size := mesh.size * part.global_basis.get_scale()
		found.append([AABB(part.global_position - size * 0.5, size), part.material_override])
	return found


## Пары коробок разных материалов с гранью в одной плоскости и одной нормалью,
## которые перекрываются по площади. [param same] — [param a] и [param b] один
## список: пара не проверяется дважды.
func _clashes(a: Array[Array], b: Array[Array], same: bool) -> Array[String]:
	var clashes: Array[String] = []
	for i in a.size():
		var from := i + 1 if same else 0
		for j in range(from, b.size()):
			if a[i][1] == b[j][1]:
				continue
			var one := a[i][0] as AABB
			var two := b[j][0] as AABB
			for axis: int in [Vector3.AXIS_Y, Vector3.AXIS_Z]:
				if _share_face(one, two, axis):
					clashes.append("%s и %s" % [one, two])
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
