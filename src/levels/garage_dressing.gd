class_name GarageDressing
extends Node3D

## Garage by building kind (ADR-0058, decisions 5 and 6).
##
## Hotel: clean, VALET signs on the columns, a VALET PARKING sign above the driveway at
## the gate; office: "Reserved" signs on the columns and a barrier on the
## platform behind the gate that rises in front of Otto's car; residential building:
## graffiti near the floor of the far wall, a trash can and bicycles in free
## spaces.
##
## The far wall is visible in the frame only near the floor, since the top is hidden by
## the slab edge, so the signs hang on the columns of the front line.
##
## Look only, no bodies: Otto's car stands at the gate and drives out the same way as
## before. The barrier rises together with the gate ([method Garage.open_gate]), so
## the exit's course and timing do not change.

## A sign on a column: at what height above the floor, and its size, m: between
## the paint stripes and the space code ([method Garage._build_columns]).
const PLATE_RISE: float = 1.18
const PLATE := Vector2(0.46, 0.2)
const PLATE_BLUE := Color(0.1, 0.22, 0.48)
const PLATE_BURGUNDY := Color(0.36, 0.08, 0.1)
const PAINT_WHITE := Color(0.82, 0.82, 0.78)

## Barrier: the post, the arm cross-section and where it stands, on the platform behind
## the gate, m. The post is in front of Otto's car lane ([constant ExitCar.Z]) by this
## much from its middle; the arm goes from the post across the lane to the tunnel wall
## ([constant GarageRamp.WIDTH]). Before the M24p code review the barrier stood at the
## depth of the garage spaces, behind the tunnel wall, and was visible neither lowered
## nor raised.
const POST := Vector3(0.24, 1.0, 0.24)
const POST_OFF_LANE: float = 0.62
const ARM := Vector2(0.08, 0.1)
const BARRIER_OFF_GATE: float = 1.1
const STRIPE_RED := Color(0.62, 0.1, 0.08)
const STRIPE_WHITE := Color(0.86, 0.86, 0.82)
const BOOTH := Color(0.55, 0.57, 0.6)

## Residential building graffiti: how many marks on the far wall and their size, m. The
## marks are in front of the paint stripe on the wall ([method Garage._build_walls],
## 1 cm thick): on its face or behind it they would flicker and disappear.
const TAGS: int = 4
const TAG_SIZE := Vector2(1.3, 0.7)
const TAG_OFF_WALL: float = 0.016
const DUMPSTER := Vector3(1.6, 1.2, 1.0)
const DUMPSTER_GREEN := Color(0.16, 0.3, 0.2)
## The trash can and bicycles are in front of the far wall, this far from its face, m;
## the second bicycle is closer by this much again: both fit before the space's wheel stop.
const CLUTTER_OFF_WALL := Vector2(0.05, 0.25)
const BIKE_STAGGER: float = 0.65

var _rules: BuildingRules = null
var _surface: float = 0.0
var _far: float = 0.0
## The barrier arm: [method raise_barrier] rotates it; null means there is no barrier.
var _arm: Node3D = null


## Dresses the building's garage by the kind from [member BuildingRules.kind].
func build(rules: BuildingRules, plan: BuildingPlan, building_seed: int) -> void:
	name = "Dressing"
	_rules = rules
	_surface = rules.floor_surface(rules.floors - 1)
	_far = Garage.FAR_Z + Garage.FAR_THICKNESS * 0.5
	var bays := Garage.bays(rules, plan)
	var columns := Garage.column_xs(rules, plan)
	match rules.kind:
		BuildingIdentity.Kind.OFFICE:
			_plates(columns, "RESERVED", PLATE_BLUE)
			_barrier()
		BuildingIdentity.Kind.RESIDENTIAL:
			_graffiti(bays, building_seed)
			_clutter(rules, plan, bays, building_seed)
		_:
			_plates(columns, "VALET", PLATE_BURGUNDY)
			_valet_sign()


## Raises the barrier arm over [param duration] s; no barrier means nothing happens.
func raise_barrier(duration: float) -> void:
	if _arm == null:
		return
	var tween := create_tween()
	tween.tween_property(_arm, "rotation:x", PI * 0.5, duration)


## Whether the arm is raised: for tests.
func barrier_raised() -> bool:
	return _arm != null and _arm.rotation.x > PI * 0.45


## Whether there is a barrier: for tests.
func has_barrier() -> bool:
	return _arm != null


## Signs on the columns [param columns]: the text [param text] on a colored plate.
func _plates(columns: PackedFloat64Array, text: String, colour: Color) -> void:
	var plate := GreyboxLook.surface(colour)
	var front := Garage.COLUMN_Z + Garage.COLUMN * 0.5
	for x: float in columns:
		var board := GreyboxLook.box(Vector3(PLATE.x, PLATE.y, 0.02), plate)
		board.position = Garage.scene_point(x, _surface - PLATE_RISE, front + 0.02)
		board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(board)
		var word := Garage.label(text, 800, PLATE.y * 0.42, PAINT_WHITE)
		word.position = board.position + Vector3(0.0, 0.0, 0.015)
		add_child(word)


## The hotel sign above the driveway at the gate: a board on hangers from the ceiling.
func _valet_sign() -> void:
	var x := Garage.inner_span(_rules).x + 2.4
	var z := WorldSpace.BACK_WALL_Z + 0.4
	var ceiling := _rules.story_top(_rules.floors - 1)
	var rise := _surface - ceiling - 0.55
	var board := GreyboxLook.box(Vector3(2.4, 0.42, 0.04), GreyboxLook.surface(PLATE_BURGUNDY))
	board.position = Garage.scene_point(x, _surface - rise, z)
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(board)
	var word := Garage.label("VALET PARKING", 800, 0.22, PAINT_WHITE)
	word.position = board.position + Vector3(0.0, 0.0, 0.025)
	add_child(word)
	# Hangers up to the ceiling: the top is 4 mm below it, not in the slab plane.
	var hang := (_surface - rise - 0.21) - ceiling - 0.004
	for side: float in [-0.9, 0.9]:
		var rod := GreyboxLook.box(Vector3(0.03, hang, 0.03), GreyboxLook.metal(BOOTH))
		rod.position = Garage.scene_point(x + side, ceiling + 0.004 + hang * 0.5, z)
		rod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(rod)


## The office barrier on the platform behind the gate: a post at the front edge of Otto's
## car lane and a striped arm across the lane. In the frame a closed arm goes into
## the depth and is barely visible; a raised one stands up as a striped pole.
func _barrier() -> void:
	var gate := Garage.gate_x(_rules) - BuildingShell.WALL_WIDTH * 0.5 - BARRIER_OFF_GATE
	var lane_front := ExitCar.Z + POST_OFF_LANE
	var arm_length := lane_front + GarageRamp.WIDTH * 0.5 - 0.05
	var post := GreyboxLook.box(POST, GreyboxLook.metal(BOOTH))
	post.position = Garage.scene_point(gate, _surface - POST.y * 0.5, lane_front)
	add_child(post)
	# The arm axis is below the top of the post: the top of the arm does not fall into the
	# plane of the post's top.
	var pivot := Node3D.new()
	pivot.name = "Barrier"
	pivot.position = Garage.scene_point(gate, _surface - POST.y + ARM.y, lane_front)
	add_child(pivot)
	var stripes := 6
	for stripe: int in stripes:
		var piece := GreyboxLook.box(
			Vector3(ARM.x, ARM.y, arm_length / stripes),
			GreyboxLook.surface(STRIPE_RED if stripe % 2 == 0 else STRIPE_WHITE)
		)
		piece.position.z = -arm_length / stripes * (stripe + 0.5)
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(piece)
	_arm = pivot


## Graffiti on the far wall of the residential building garage, as [WallWear] marks.
func _graffiti(bays: Array[Vector2], building_seed: int) -> void:
	if bays.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, 0x6A2F])
	for index: int in mini(TAGS, bays.size()):
		var bay := bays[rng.randi_range(0, bays.size() - 1)]
		var low := rng.randf_range(0.45, 0.75)
		var quad := QuadMesh.new()
		quad.size = TAG_SIZE
		quad.material = WallWear.tag_look(WallWear.TAGS[index % WallWear.TAGS.size()])
		var mark := MeshInstance3D.new()
		mark.mesh = quad
		var x := rng.randf_range(
			bay.x + TAG_SIZE.x * 0.5, maxf(bay.y - TAG_SIZE.x * 0.5, bay.x + TAG_SIZE.x * 0.5)
		)
		mark.position = Garage.scene_point(x, _surface - low, _far + TAG_OFF_WALL + index * 0.003)
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mark)


## A trash can and bicycles in the free spaces of the residential building garage.
func _clutter(
	rules: BuildingRules, plan: BuildingPlan, bays: Array[Vector2], building_seed: int
) -> void:
	var taken: Array[float] = []
	for car: Garage.Parked in Garage.parked(rules, plan, building_seed):
		taken.append(car.x)
	var banned := Garage.keep_out(rules, plan)
	var free: Array[Vector2] = []
	for bay: Vector2 in bays:
		var middle := (bay.x + bay.y) * 0.5
		var busy := false
		for x: float in taken:
			busy = busy or absf(x - middle) < 0.5
		for span: Vector2 in banned:
			busy = busy or (bay.y > span.x and bay.x < span.y)
		if not busy:
			free.append(bay)
	if free.is_empty():
		return
	var bin := free[0]
	var dumpster := GreyboxLook.box(DUMPSTER, GreyboxLook.metal(DUMPSTER_GREEN))
	# In front of the wall, not in it: the can's depth goes toward the camera from the wall
	# face.
	dumpster.position = Garage.scene_point(
		(bin.x + bin.y) * 0.5,
		_surface - DUMPSTER.y * 0.5,
		_far + CLUTTER_OFF_WALL.x + DUMPSTER.z * 0.5
	)
	add_child(dumpster)
	var lid := GreyboxLook.box(
		Vector3(DUMPSTER.x + 0.06, 0.06, DUMPSTER.z + 0.06),
		GreyboxLook.surface(Color(0.1, 0.1, 0.1))
	)
	lid.position = dumpster.position + Vector3(0.0, DUMPSTER.y * 0.5 + 0.03, 0.0)
	add_child(lid)
	if free.size() < 2:
		return
	var rack := free[1]
	# Offset in x and distance from the wall: bicycles in a row one behind another; side by
	# side at the same depth they would go into each other.
	for offset: Vector2 in [Vector2(-0.45, 0.0), Vector2(0.35, BIKE_STAGGER)]:
		var bike := PropCatalog.make("bicycle", true)
		if bike == null:
			continue
		# The origin of a catalog model is its back face ([method PropCatalog.make]):
		# the bicycle stands in front of the wall, not entirely behind it.
		bike.position = Garage.scene_point(
			(rack.x + rack.y) * 0.5 + offset.x, _surface, _far + CLUTTER_OFF_WALL.y + offset.y
		)
		add_child(bike)
