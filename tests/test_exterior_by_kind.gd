extends GutTest

## The building outside by kind (ADR-0058): the crown behind the play plane, end walls and setback
## ledge outside the walls, the garage and the street entrance, the car drawn by kind. All of it is
## look without bodies and without its own light sources; checked on a building of every kind.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const SETTLE_FRAMES: int = 5
const KINDS: Array[BuildingIdentity.Kind] = [
	BuildingIdentity.Kind.HOTEL, BuildingIdentity.Kind.OFFICE, BuildingIdentity.Kind.RESIDENTIAL
]


func after_each() -> void:
	GameState.instance().start_game()


## Models with zero weight for the kind do not come up, forbidden paints do not either; on a
## residential building the paint is faded. The first building is a red sports car for any kind.
func test_cars_follow_the_kind_weights() -> void:
	for kind: BuildingIdentity.Kind in KINDS:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var weights: Array = CarModel.MODEL_WEIGHTS[kind]
		var seen := {}
		for draw: int in 400:
			var choice := CarModel.draw(rng, kind, [0])
			assert_gt(
				weights[choice.model],
				0,
				"kind %d: model %d is not from the kind" % [kind, choice.model]
			)
			assert_ne(choice.paint, 0, "kind %d: red is forbidden" % kind)
			assert_eq(choice.fade, CarModel.FADE[kind])
			seen[choice.model] = true
		assert_gt(seen.size(), 1, "kind %d: more than one model" % kind)
		var first := CarModel.choose(1, 99, kind)
		assert_eq(first.model, 0, "the first building — the sports one")
		assert_eq(first.paint, 0, "the first building — the red one")


## Every kind has its own crown: it stands behind the play plane farther than the rotor span,
## without bodies; end walls and setback ledge are outside the tower walls and above the ledge and
## do not cover the sign at the right end wall; there are no new light sources — the environment
## still has two.
func test_crown_and_flanks_of_every_kind() -> void:
	var tops := {}
	for kind: BuildingIdentity.Kind in KINDS:
		var level := await _level(kind)
		var rules := level.rules
		var crown := level.find_children("Crown", "BuildingCrown", true, false)
		assert_eq(crown.size(), 1, "kind %d: has a crown" % kind)
		if crown.is_empty():
			continue
		var built := crown[0] as BuildingCrown
		assert_gt(built.top(), 4.0, "kind %d: the crown is tall" % kind)
		tops[kind] = built.top()
		for node: Node in built.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			var box := mesh.global_transform * mesh.mesh.get_aabb()
			assert_lt(
				box.end.z,
				BuildingCrown.FRONT_Z + 0.2,
				"kind %d: the crown is behind the plane" % kind
			)
		assert_eq(built.find_children("*", "PhysicsBody3D", true, false).size(), 0, "no bodies")
		assert_eq(built.find_children("*", "Light3D", true, false).size(), 0, "no lights")

		var flanks := level.find_children("Flanks", "BuildingFlanks", true, false)
		assert_eq(flanks.size(), 1, "kind %d: has flanks" % kind)
		if flanks.is_empty():
			continue
		var sides := flanks[0] as BuildingFlanks
		assert_eq(sides.find_children("*", "Light3D", true, false).size(), 0, "no lights")
		var places := sides.placements()
		assert_gt(places.size(), 20, "kind %d: flanks and ledge are not empty" % kind)
		var tower := rules.floor_span(BuildingRules.ROOF)
		var ledge := rules.floor_surface(rules.wide_from - 1)
		for place: Transform3D in places:
			var at := WorldSpace.to_plane(place.origin)
			assert_true(
				at.x <= tower.x + 0.05 or at.x >= tower.y - 0.05,
				"kind %d: a detail at %.2f is inside the tower" % [kind, at.x]
			)
			assert_lt(at.y, ledge + 0.1, "kind %d: a detail below the ledge" % kind)
		var signs := level.find_children("VerticalSign", "VerticalSign", true, false)
		assert_eq(signs.size(), 1, "kind %d: has a sign" % kind)
		if signs.is_empty():
			continue
		var board := (signs[0] as VerticalSign).span()
		var near := tower.y + VerticalSign.STANDOFF - VerticalSign.PANEL_WIDTH * 0.5
		var blocking: Array[String] = []
		for place: Transform3D in places:
			var at := WorldSpace.to_plane(place.origin)
			var before := at.x > near and at.x < near + VerticalSign.PANEL_WIDTH
			if before and at.y > board.x and at.y < board.y:
				blocking.append("%.2f, %.2f" % [at.x, at.y])
		assert_eq(blocking, [] as Array[String], "kind %d: details in front of the sign" % kind)
	assert_eq(tops.size(), KINDS.size())


## Garage: the finish is in front of the far wall and the paint stripe on it, not behind them; the
## office has a barrier across the lane of Otto's car, and it rises together with the gate; the
## others have no barrier. Street entrance: a valet only at the hotel.
func test_garage_and_street_front_by_kind() -> void:
	# Face of the far wall and the paint stripe on it (1 cm): finish behind it is not visible.
	var band_face := Garage.FAR_Z + Garage.FAR_THICKNESS * 0.5 + 0.01
	for kind: BuildingIdentity.Kind in KINDS:
		var level := await _level(kind)
		var garage := level.garage()
		assert_not_null(garage.dressing, "kind %d: parking finishing" % kind)
		for node: Node in garage.dressing.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			var box := mesh.global_transform * mesh.mesh.get_aabb()
			assert_gt(
				box.end.z, band_face + 0.002, "kind %d: %s behind the wall" % [kind, mesh.name]
			)
		var office := kind == BuildingIdentity.Kind.OFFICE
		assert_eq(garage.dressing.has_barrier(), office, "kind %d: barrier" % kind)
		if office:
			assert_false(garage.dressing.barrier_raised(), "the arm is lowered")
			var reach := _reach(garage.dressing.find_child("Barrier", true, false) as Node3D)
			assert_lt(reach.position.z, ExitCar.Z, "the arm — across the car lane")
			assert_gt(reach.end.z, ExitCar.Z, "the post — in front of the car lane")
			assert_gt(reach.position.z, -GarageRamp.WIDTH * 0.5, "the arm — up to the tunnel wall")
			garage.open_gate(0.05)
			await wait_seconds(0.2)
			assert_true(garage.dressing.barrier_raised(), "the arm rose with the gate")
		var front := garage.gate.ramp().front
		assert_not_null(front, "kind %d: entrance from the street" % kind)
		var hotel := kind == BuildingIdentity.Kind.HOTEL
		assert_eq(front.valet != null, hotel, "kind %d: valet only at the hotel" % kind)
		assert_eq(front.find_children("*", "PhysicsBody3D", true, false).size(), 0, "no bodies")


## Bounds of the meshes under [param root] in scene coordinates.
func _reach(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var part := mesh.global_transform * mesh.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


func _level(kind: BuildingIdentity.Kind, building_seed: int = 1) -> GreyboxLevel:
	GameState.instance().start_game()
	GameState.instance().building = BuildingIdentity.first_of(kind, building_seed)
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.rules.documents_cap = 0
	level.building_seed = building_seed
	level.spawn_agents = false
	add_child_autofree(level)
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	return level
