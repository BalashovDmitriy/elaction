extends GutTest

## The bottom floor garage (ADR-0038, decision 3) on any building.
##
## The layout — columns, bays, other cars — is checked without a scene on many
## seeds and skills; the build — on several seeds: the garage is built, cars are behind
## the play plane, the gate is at the left end wall, faces of different materials are not
## in one plane (approach — [code]test_shaft_faces.gd[/code]).

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

const SEEDS: Array[int] = [1, 2, 3, 5, 8, 13, 21, 34, 55, 89]
const SKILLS: Array[int] = [0, 5]
## Build seeds: a scene costs more than a layout.
const BUILT_SEEDS: Array[int] = [1, 2, 5]

## "In one plane" tolerance, m.
const COPLANAR: float = 0.001


func after_all() -> void:
	GameState.instance().reset()


func _rules(skill: int) -> BuildingRules:
	var rules := BuildingRules.new()
	rules.skill = skill
	return rules


## Other cars are in bays, clear of Otto's car, the exit, shaft cores and walls, and
## inside the floor walls; the bay under them is not narrower than a car.
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
				var tag := "skill %d, seed %d, car at %.2f" % [skill, building_seed, car.x]
				assert_between(span.x, inner.x, inner.y, tag)
				assert_between(span.y, inner.x, inner.y, tag)
				for zone in banned:
					assert_true(span.y <= zone.x or span.x >= zone.y, "%s in %s" % [tag, zone])
				for x in Garage.column_xs(rules, plan):
					assert_true(
						absf(car.x - x) >= Garage.CAR_WIDTH * 0.5 + Garage.COLUMN * 0.5,
						"%s on a column %.2f" % [tag, x]
					)
	assert_gt(total, SEEDS.size(), "almost no cars - the garage is empty")


## The garage is the same on the same seed and different on different ones.
func test_parked_cars_follow_the_seed() -> void:
	var rules := _rules(0)
	var plan := BuildingPlan.generate(rules, 3)
	var first := _signature(Garage.parked(rules, plan, 3))
	assert_eq(first, _signature(Garage.parked(rules, plan, 3)), "the draw did not repeat")
	var other := BuildingPlan.generate(rules, 4)
	assert_ne(first, _signature(Garage.parked(rules, other, 4)), "two buildings - one garage")


## Bays do not overlap each other or the columns, columns do not overlap shaft cores.
func test_bays_and_columns_do_not_overlap() -> void:
	for skill: int in SKILLS:
		var rules := _rules(skill)
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			var tag := "skill %d, seed %d" % [skill, building_seed]
			var bays := Garage.bays(rules, plan)
			assert_gt(bays.size(), 3, "%s: almost no bays" % tag)
			for index in bays.size():
				var bay := bays[index]
				assert_gte(bay.y - bay.x, Garage.BAY_MIN - 0.001, "%s: narrow bay" % tag)
				if index > 0:
					assert_gte(bay.x, bays[index - 1].y - 0.001, "%s: overlapping bays" % tag)
				for x in Garage.column_xs(rules, plan):
					var reach := Garage.COLUMN * 0.5
					assert_true(
						bay.y <= x - reach + 0.001 or bay.x >= x + reach - 0.001,
						"%s: bay %s on a column %.2f" % [tag, bay, x]
					)
			for x in Garage.column_xs(rules, plan):
				for core in Garage.cores(rules, plan):
					assert_true(
						x + Garage.COLUMN * 0.5 <= core.x or x - Garage.COLUMN * 0.5 >= core.y,
						"%s: column %.2f in the shaft core %s" % [tag, x, core]
					)


## The gate is in the left end wall of the bottom floor, inside the wall.
func test_the_gate_is_at_the_left_end() -> void:
	for skill: int in SKILLS:
		var rules := _rules(skill)
		var left := rules.floor_span(rules.floors - 1).x
		var gate := Garage.gate_x(rules)
		assert_between(gate, left, left + BuildingShell.WALL_WIDTH, "skill %d" % skill)


## The garage is built on every seed: the hall, cars behind the play plane, the gate at the
## left end wall, the EXIT sign above it, fixtures in lamp zones.
func test_the_garage_builds_on_every_seed() -> void:
	for building_seed: int in BUILT_SEEDS:
		var level := _build(building_seed)
		var garage := level.garage()
		assert_not_null(garage, "seed %d: no garage" % building_seed)
		if garage == null:
			remove_child(level)
			continue
		var rules := level.rules
		var tag := "seed %d" % building_seed
		assert_gt(garage.get_child_count(), 50, "%s: the garage is almost empty" % tag)
		assert_eq(
			garage.find_children("*", "CollisionObject3D", true, false).size(),
			0,
			"%s: the garage has bodies" % tag
		)

		var cars := garage.get_node("ParkedCars")
		assert_eq(
			cars.get_child_count(),
			Garage.parked(rules, level.plan(), building_seed).size(),
			"%s: the car count differs from the draw" % tag
		)
		for car: Node in cars.get_children():
			var box := _bounds_of(car as Node3D)
			assert_lt(
				box.end.z,
				-WorldSpace.BODY_DEPTH * 0.5,
				"%s: car at %.2f is in the play plane" % [tag, box.get_center().x]
			)
			assert_gt(box.size.x, 1.0, "%s: the car is flattened" % tag)

		var sign_node := garage.gate.get_node_or_null("ExitSign") as Node3D
		assert_not_null(sign_node, "%s: no sign above the gate" % tag)
		if sign_node != null:
			var at := WorldSpace.to_plane(sign_node.global_position)
			var left := rules.floor_span(rules.floors - 1).x
			assert_between(at.x, left, left + 1.0, "%s: the sign is not at the gate" % tag)
			assert_between(
				at.y,
				rules.story_top(rules.floors - 1),
				rules.floor_surface(rules.floors - 1),
				"%s: the sign is not on the bottom floor" % tag
			)
		for light in garage.lights():
			assert_false(light.shadow_enabled, "%s: the tube light casts a shadow" % tag)
		remove_child(level)


## The gate rises: [method Garage.open_gate] brings the shutter to the top in physics
## steps.
func test_the_gate_opens() -> void:
	var level := _build(1)
	var garage := level.garage()
	assert_false(garage.is_gate_open(), "the gate is open from the start")
	var tween := garage.open_gate(0.2)
	await wait_physics_frames(30)
	assert_false(tween.is_running(), "the shutter is still moving")
	assert_true(garage.is_gate_open(), "the gate did not open")
	var voice := garage.gate.find_children("*", "AudioStreamPlayer3D", true, false)
	assert_eq(voice.size(), 1, "the gate has no motor")
	if voice.size() == 1:
		assert_not_null((voice[0] as AudioStreamPlayer3D).stream, "the gate motor has no recording")
	remove_child(level)


## A fallen lamp darkens the fixtures of its zone — and only them.
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
		pending("on this seed the garage has fewer than two lamps")
		remove_child(level)
		return
	var tubes := _tube_xs(garage)
	assert_gt(tubes.size(), 1, "almost no light fixtures")
	for x in tubes:
		assert_true(garage.tube_lit_at(x), "the tube at %.2f is not lit" % x)
	garage.darken(lamps[0])
	for x in tubes:
		var nearest := lamps[0]
		for lamp_x in lamps:
			if absf(lamp_x - x) < absf(nearest - x):
				nearest = lamp_x
		assert_eq(
			garage.tube_lit_at(x), nearest != lamps[0], "the tube at %.2f is lit after the lamp" % x
		)
	remove_child(level)


## New garage boxes do not share a face with a box of another material — neither
## their own, nor the shell, nor shafts, nor edges. Build seeds are of different building
## kinds: each has its own garage finish (ADR-0058, decision 5).
func test_no_two_materials_share_a_face_in_the_garage() -> void:
	for index: int in BUILT_SEEDS.size():
		var building_seed := BUILT_SEEDS[index]
		var kind := (index % BuildingIdentity.Kind.size()) as BuildingIdentity.Kind
		var level := _build(building_seed, kind)
		var garage := level.garage()
		var own := _boxes(garage, garage)
		assert_gt(own.size(), 50, "seed %d: the garage has no parts" % building_seed)
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
			"seed %d: faces in one plane - %s" % [building_seed, clashes]
		)
		remove_child(level)


## Building of seed [param building_seed] of kind [param kind]: the first such in a game.
func _build(
	building_seed: int, kind: BuildingIdentity.Kind = BuildingIdentity.Kind.HOTEL
) -> GreyboxLevel:
	GameState.instance().start_game()
	GameState.instance().building = BuildingIdentity.first_of(kind, building_seed)
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


## Where the fixtures hang: x of the tubes.
func _tube_xs(garage: Garage) -> PackedFloat64Array:
	var found := PackedFloat64Array()
	var tube_color := Garage.TUBE
	for node: Node in garage.find_children("*", "MeshInstance3D", false, false):
		var part := node as MeshInstance3D
		var material := part.material_override as StandardMaterial3D
		if material != null and material.emission_enabled and material.emission == tube_color:
			found.append(part.position.x)
	return found


## Volume of the bottom floor in the scene: from floor to ceiling and slightly beyond.
func _bottom_region(rules: BuildingRules) -> AABB:
	var bottom := rules.floors - 1
	var top := WorldSpace.height_to_scene(rules.story_top(bottom))
	var floor_y := WorldSpace.height_to_scene(rules.floor_surface(bottom))
	return AABB(
		Vector3(-1.0, floor_y - 0.1, -10.0), Vector3(rules.width + 2.0, top - floor_y + 0.2, 12.0)
	)


## Volume of a model by its meshes in scene coordinates.
func _bounds_of(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var part := mesh.global_transform * mesh.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


## Unrotated boxes: [AABB, material]. The ramp beyond the gate is tilted and
## off-frame — not counted; the shutter, while closed, has no scale.
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


## Pairs of boxes of different materials with a face in one plane and with one normal
## that overlap in area. [param same] — [param a] and [param b] are one
## list: a pair is not checked twice.
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
					clashes.append("%s and %s" % [one, two])
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
