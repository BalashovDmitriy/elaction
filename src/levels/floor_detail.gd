class_name FloorDetail
extends Node3D

## Small floor details: a carpet runner along the corridor, tile seams, wall panel joints and a
## cornice under the ceiling (ADR-0031, decision 3).
##
## The ceiling gets no detail: the camera looks from above (ADR-0023, decision 1), and its underside
## is not visible. Details are where they are visible: the floor and the back wall. All as
## multimeshes, one per material: there are thousands of details and only a handful of nodes. No
## bodies. The exit floor is the garage, it has its own markings ([BuildingProps]).

## Runner: width across the corridor, thickness, where its middle is by depth.
const RUNNER := Vector2(1.0, 0.012)
const RUNNER_Z: float = -0.15
## Runner border — a light stripe along the edges.
const RUNNER_EDGE: float = 0.05

## Tile seams: pitch along the corridor and thickness.
const SEAM_STEP: float = 0.9
const SEAM: float = 0.012

## Back wall panel joints: pitch, width and how far up from the floor (above the skirting).
const JOINT_STEP: float = 0.9
const JOINT_WIDTH: float = 0.02
const JOINT_FROM: float = BuildingRibs.SKIRTING_HEIGHT + BuildingRibs.RAIL_HEIGHT

const RUNNER_COLOR := Color(0.26, 0.08, 0.09)
const RUNNER_EDGE_COLOR := Color(0.62, 0.5, 0.26)
const SEAM_COLOR := Color(0.09, 0.09, 0.1)
const JOINT_COLOR := Color(0.07, 0.08, 0.09)
## Checkerboard: pixels per tile in the texture and the sheen of polished tile.
const CHECKER_PIXELS: int = 32
const CHECKER_ROUGHNESS: float = 0.45

var _rules: BuildingRules = null
var _plan: BuildingPlan = null
var _parts: Dictionary = {}
## Look by building kind (ADR-0048): runner for the hotel, tile for the office, cornice.
var _style := BuildingStyle.new()


## Assembles the details of all floors except the garage. [param style] — look by building kind;
## without it — hotel, as before M24i.
func build(rules: BuildingRules, plan: BuildingPlan, style: BuildingStyle = null) -> void:
	_rules = rules
	_plan = plan
	if style != null:
		_style = style
	for index in rules.floors - 1:
		_dress_floor(index)
	# The runner matches the round's masonry tone: one more sign of which round is on (ADR-0031).
	_commit(
		"runner", GreyboxLook.surface(RUNNER_COLOR.lerp(rules.palette.masonry.darkened(0.55), 0.6))
	)
	_commit("edge", GreyboxLook.surface(RUNNER_EDGE_COLOR))
	_commit("carpet", _checker() if _style.checker else GreyboxLook.surface(_style.tile_color))
	_commit("tile_seam", GreyboxLook.surface(_style.tile_color.darkened(0.35)))
	_commit("seam", GreyboxLook.surface(SEAM_COLOR))
	_commit("joint", GreyboxLook.surface(JOINT_COLOR))
	_commit("crown", GreyboxLook.metal(_style.crown_color), true)


func _dress_floor(index: int) -> void:
	var surface := _rules.floor_surface(index)
	var bounds := _rules.floor_span(index)
	var inner := Vector2(bounds.x + BuildingShell.WALL_WIDTH, bounds.y - BuildingShell.WALL_WIDTH)
	# Over an escalator opening there is no runner and no seams: they would lie across the hole in the
	# corridor's rear strip (ADR-0044, decision 10).
	var cuts := _plan.gaps_on(_rules, index) + _plan.escalator_holes_on(_rules, index)
	for span in BuildingPlan.spans_between(cuts, inner):
		var length := span.y - span.x
		if length <= 0.2:
			continue
		var middle := (span.x + span.y) * 0.5
		var top := surface - RUNNER.y * 0.5
		if not _style.runner:
			_carpet_tiles(span, surface)
			continue
		_add("runner", Vector3(length, RUNNER.y, RUNNER.x), Vector3(middle, top, RUNNER_Z))
		for side: float in [-1.0, 1.0]:
			var edge_z := RUNNER_Z + side * (RUNNER.x * 0.5 - RUNNER_EDGE * 0.5)
			_add(
				"edge", Vector3(length, RUNNER.y + 0.002, RUNNER_EDGE), Vector3(middle, top, edge_z)
			)
		var seams := int(length / SEAM_STEP)
		for seam in seams:
			var x := span.x + SEAM_STEP * (float(seam) + 0.5)
			_add(
				"seam",
				Vector3(SEAM, 0.004, WorldSpace.CORRIDOR_DEPTH),
				Vector3(x, surface - 0.002, 0.0)
			)
	var story_top := _rules.story_top(index)
	var wall_height := surface - story_top
	var joint_height := wall_height - JOINT_FROM - _style.crown.x
	var wall_z := WorldSpace.BACK_WALL_Z + 0.004
	# There are no panel joints at the office glass (ADR-0056, decision 4): they would hang as dark
	# stripes in front of the partition, which has its own posts ([BuildingShell]). On a special floor
	# there is no wall — beyond the corridor is a hall (ADR-0057, decision 3).
	var plain := _style.glass_wall or FloorRole.hall_at(_rules, index)
	var joints := 0 if plain else int((inner.y - inner.x) / JOINT_STEP)
	for joint in joints:
		var x := inner.x + JOINT_STEP * (float(joint) + 0.5)
		if _near_opening(index, x):
			continue
		_add(
			"joint",
			Vector3(JOINT_WIDTH, joint_height, 0.008),
			Vector3(x, story_top + _style.crown.x + joint_height * 0.5, wall_z)
		)
	var crown := _style.crown
	_add(
		"crown",
		Vector3(inner.y - inner.x, crown.x, crown.y),
		Vector3(
			(inner.x + inner.y) * 0.5,
			story_top + crown.x * 0.5,
			WorldSpace.BACK_WALL_Z + crown.y * 0.5
		)
	)


## Office carpet tile over the whole corridor floor with a grid of seams (ADR-0048).
func _carpet_tiles(span: Vector2, surface: float) -> void:
	var length := span.y - span.x
	var middle := (span.x + span.y) * 0.5
	var depth := WorldSpace.CORRIDOR_DEPTH
	_add("carpet", Vector3(length, RUNNER.y, depth), Vector3(middle, surface - RUNNER.y * 0.5, 0.0))
	# The checkerboard is drawn as a texture with grout in world coordinates: thousands of tiles as
	# boxes would cost a multimesh of tens of thousands of instances.
	if _style.checker:
		return
	var step := _style.tile_step
	for across in int(length / step):
		var x := span.x + step * (float(across) + 1.0)
		_add("tile_seam", Vector3(SEAM, 0.004, depth), Vector3(x, surface - RUNNER.y - 0.001, 0.0))
	for row in int(depth / step):
		var z := -depth * 0.5 + step * (float(row) + 1.0)
		_add(
			"tile_seam",
			Vector3(length, 0.004, SEAM),
			Vector3(middle, surface - RUNNER.y - 0.001, z)
		)


## Checkerboard tile of a residential building (ADR-0055, decision 4): two tiles by two, dark grout
## between them, layout in world coordinates — the seam runs in one line on all floors.
func _checker() -> StandardMaterial3D:
	var cells := CHECKER_PIXELS * 2
	var image := Image.create(cells, cells, false, Image.FORMAT_RGB8)
	var grout := _style.tile_color.lerp(_style.tile_alt, 0.5).darkened(0.4)
	for y: int in cells:
		for x: int in cells:
			var dark := (x / CHECKER_PIXELS + y / CHECKER_PIXELS) % 2 == 1
			var colour := _style.tile_alt if dark else _style.tile_color
			if x % CHECKER_PIXELS == 0 or y % CHECKER_PIXELS == 0:
				colour = grout
			image.set_pixel(x, y, colour)
	# The floor is seen almost at a grazing angle: two metres of corridor are a dozen and a half rows
	# of the frame, and without mips the tile ripples when the view follows an elevator (M24m code
	# review).
	image.generate_mipmaps()
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.roughness = CHECKER_ROUGHNESS
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / (_style.tile_step * 2.0)
	return material


## Whether a wall point is in a door opening or a shaft portal: a joint does not belong there.
func _near_opening(index: int, x: float) -> bool:
	var half_door := Door.LEAF_SIZE.x * 0.5 + Door.FRAME_WIDTH
	for door in _plan.doors:
		if door.floor_index == index and absf(door.x - x) < half_door:
			return true
	var half_shaft := _rules.shaft_width * 0.5 + BuildingShafts.PORTAL_JAMB
	for shaft in _plan.shafts:
		if shaft.top <= index and index <= shaft.bottom and absf(shaft.x - x) < half_shaft:
			return true
	return false


## Remembers a box: [param at] — x and y in the rules plane, scene z.
func _add(kind: String, size: Vector3, at: Vector3) -> void:
	if not _parts.has(kind):
		_parts[kind] = [] as Array[Transform3D]
	var place := WorldSpace.to_scene(Vector2(at.x, at.y))
	place.z = at.z
	(_parts[kind] as Array[Transform3D]).append(Transform3D(Basis.from_scale(size), place))


## Places the accumulated boxes of [param kind] as one multimesh. Only the cornice casts a shadow
## ([param casts_shadow]): the multimesh covers the whole building, it cannot be culled by the
## frame, and thousands of seams and joints would be drawn in every shadow pass of every lamp,
## although a flat detail has nothing to cast.
func _commit(kind: String, material: StandardMaterial3D, casts_shadow: bool = false) -> void:
	if not _parts.has(kind):
		return
	var places: Array[Transform3D] = _parts[kind]
	var box := BoxMesh.new()
	box.material = material
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.mesh = box
	many.instance_count = places.size()
	for index in places.size():
		many.set_instance_transform(index, places[index])
	var node := MultiMeshInstance3D.new()
	node.name = kind.capitalize()
	node.multimesh = many
	if not casts_shadow:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
