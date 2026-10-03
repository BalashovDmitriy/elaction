class_name WallSconce
extends RefCounted

## Hotel sconce on a pilaster (ADR-0048): a brass plate, an arm and a glowing
## shade, above and below it — a warm patch on the wall.
##
## The patch is a transparent gradient, not a source: there are hundreds of pilasters in a building,
## and light from each would eat the frame budget that M24h barely won back at the bottom of the
## building. One mesh for all sconces: assembled once and cached.

## Height of the shade's middle above the floor, m.
const HEIGHT: float = 2.05
const PLATE := Vector3(0.1, 0.22, 0.02)
const ARM := Vector3(0.03, 0.03, 0.12)
## Shade: bottom and top width, height, m.
const SHADE_BOTTOM: float = 0.18
const SHADE_TOP: float = 0.11
const SHADE_HEIGHT: float = 0.15
## Patch on the wall: size, m, and brightness of the middle.
const GLOW := Vector2(0.9, 1.3)
const GLOW_ALPHA: float = 0.55
const BRASS := Color(0.7, 0.54, 0.26)
const SHADE_COLOR := Color(1.0, 0.82, 0.55)
const GLOW_COLOR := Color(1.0, 0.72, 0.4)
const SHADE_GLOW: float = 2.2

static var _mesh: ArrayMesh = null


## Sconce mesh: zero is on the wall under the middle of the shade, facing +Z.
static func mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var built := ArrayMesh.new()
	var metal := SurfaceTool.new()
	metal.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(metal, PLATE, Vector3(0.0, -0.04, PLATE.z * 0.5))
	_box(metal, ARM, Vector3(0.0, -0.08, PLATE.z + ARM.z * 0.5))
	metal.generate_normals()
	metal.set_material(GreyboxLook.metal(BRASS))
	metal.commit(built)
	var shade := SurfaceTool.new()
	shade.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cone(shade, Vector3(0.0, 0.0, PLATE.z + ARM.z + SHADE_BOTTOM * 0.5))
	shade.generate_normals()
	var lit := StandardMaterial3D.new()
	lit.albedo_color = SHADE_COLOR
	lit.emission_enabled = true
	lit.emission = SHADE_COLOR
	lit.emission_energy_multiplier = SHADE_GLOW
	lit.cull_mode = BaseMaterial3D.CULL_DISABLED
	shade.set_material(lit)
	shade.commit(built)
	var glow := SurfaceTool.new()
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(glow, GLOW, Vector3(0.0, 0.0, 0.004))
	var soft := ShaderMaterial.new()
	soft.shader = preload("res://src/levels/sconce_glow.gdshader")
	soft.set_shader_parameter(&"tint", Color(GLOW_COLOR, GLOW_ALPHA))
	glow.set_material(soft)
	glow.commit(built)
	_mesh = built
	return _mesh


## A sconce on the wall: a node at scene point [param at].
static func hang(at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "Sconce"
	node.mesh = mesh()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = at
	return node


static func _box(tool: SurfaceTool, size: Vector3, centre: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	var arrays := box.get_mesh_arrays()
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var index := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	for at: int in index:
		tool.add_vertex(verts[at] + centre)


## Truncated cone of the shade: wider at the bottom, eight faces.
static func _cone(tool: SurfaceTool, centre: Vector3) -> void:
	var sides := 8
	for side: int in sides:
		var a := TAU * side / sides
		var b := TAU * (side + 1) / sides
		var low_a := centre + Vector3(cos(a), 0.0, sin(a)) * SHADE_BOTTOM * 0.5
		var low_b := centre + Vector3(cos(b), 0.0, sin(b)) * SHADE_BOTTOM * 0.5
		var up := Vector3(0.0, SHADE_HEIGHT, 0.0)
		var high_a := centre + up + Vector3(cos(a), 0.0, sin(a)) * SHADE_TOP * 0.5
		var high_b := centre + up + Vector3(cos(b), 0.0, sin(b)) * SHADE_TOP * 0.5
		for vertex: Vector3 in [low_a, high_a, high_b, low_a, high_b, low_b]:
			tool.add_vertex(vertex - Vector3(0.0, SHADE_HEIGHT * 0.5, 0.0))


## A square facing +Z, toward the camera. In Godot the front face is wound clockwise when
## looking at it: counterclockwise, the shader with `cull_back` did not draw the patch at all
## (M24i code review, as with the lightning bolt in M22).
static func _quad(tool: SurfaceTool, size: Vector2, centre: Vector3) -> void:
	var half := size * 0.5
	var corners := [
		Vector3(-half.x, -half.y, 0.0),
		Vector3(half.x, -half.y, 0.0),
		Vector3(half.x, half.y, 0.0),
		Vector3(-half.x, half.y, 0.0)
	]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for at: int in [0, 2, 1, 0, 3, 2]:
		tool.set_uv(uvs[at])
		tool.add_vertex((corners[at] as Vector3) + centre)
