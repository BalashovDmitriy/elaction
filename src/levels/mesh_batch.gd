class_name MeshBatch
extends RefCounted

## A set of primitives without bodies or shadows: accumulates boxes, cylinders and
## spheres by material, then hands over one multimesh per "shape, material" pair.
##
## This is how the office open space (ADR-0056, decision 4) and the halls of special
## floors (ADR-0057, decision 5) are built: thousands of details, but only dozens of draw
## calls. The set takes no part in the lamp shadow pass: the frame budget at the bottom
## of the building (ADR-0042, decision 2).
##
## Coordinates: x and y in the rules plane (y down), scene z.

enum Shape { BOX, CYLINDER, SPHERE }

## Detail placements keyed by "shape:material" or "mesh:id", and what to draw them with.
var _places: Dictionary = {}
var _materials: Dictionary = {}
var _meshes: Dictionary = {}
## Primitive meshes already made, by "shape:material". They outlive [method commit]: a
## hall commits once per floor (ADR-0060, decision 10), and every floor reuses the same
## mesh resources instead of making its own.
var _primitives: Dictionary = {}


## A box of size [param size] centered at [param at].
func box(material: Material, size: Vector3, at: Vector3) -> void:
	_put(Shape.BOX, material, Transform3D(Basis.from_scale(size), scene_of(at)))


## A box standing on the floor [param surface]: [param at] is x, the height of the bottom
## above the floor, and z.
func box_on(material: Material, size: Vector3, surface: float, at: Vector3) -> void:
	box(material, size, Vector3(at.x, surface - at.y - size.y * 0.5, at.z))


## A vertical cylinder with radius [param radius] and height [param height]: [param
## at] is x, the height of the bottom above the floor [param surface], and the axis z.
func cylinder_on(
	material: Material, radius: float, height: float, surface: float, at: Vector3
) -> void:
	var basis := Basis.from_scale(Vector3(radius * 2.0, height, radius * 2.0))
	var place := scene_of(Vector3(at.x, surface - at.y - height * 0.5, at.z))
	_put(Shape.CYLINDER, material, Transform3D(basis, place))


## A lying cylinder along X: a pipe of length [param length] centered at [param at].
func pipe_x(material: Material, radius: float, length: float, at: Vector3) -> void:
	var basis := (
		Basis(Vector3.BACK, PI * 0.5)
		* Basis.from_scale(Vector3(radius * 2.0, length, radius * 2.0))
	)
	_put(Shape.CYLINDER, material, Transform3D(basis, scene_of(at)))


## A sphere of diameter [param size] centered at [param at].
func sphere(material: Material, size: float, at: Vector3) -> void:
	_put(Shape.SPHERE, material, Transform3D(Basis.from_scale(Vector3.ONE * size), scene_of(at)))


## A ready mesh (pack furniture) at scene placement [param place].
func mesh(source: Mesh, place: Transform3D) -> void:
	var key := "mesh:%d" % source.get_instance_id()
	if not _places.has(key):
		_places[key] = [] as Array[Transform3D]
		_meshes[key] = source
	(_places[key] as Array[Transform3D]).append(place)


## Placements of all accumulated details, before [method commit]. For tests: under the
## headless engine a multimesh does not store placements and returns identity ones, so a
## check against it would see no details at all.
func places() -> Array[Transform3D]:
	var all: Array[Transform3D] = []
	for each: Array in _places.values():
		all.append_array(each as Array[Transform3D])
	return all


## Hands over what was accumulated as nodes in [param parent] on the dressing layer.
func commit(parent: Node3D) -> void:
	for key: String in _places:
		var places: Array[Transform3D] = _places[key]
		var many := MultiMesh.new()
		many.transform_format = MultiMesh.TRANSFORM_3D
		if _meshes.has(key):
			many.mesh = _meshes[key] as Mesh
		else:
			if not _primitives.has(key):
				var primitive := _mesh(int(key.get_slice(":", 0)) as Shape)
				primitive.material = _materials[key] as Material
				_primitives[key] = primitive
			many.mesh = _primitives[key] as Mesh
		many.instance_count = places.size()
		for index: int in places.size():
			many.set_instance_transform(index, places[index])
		var node := MultiMeshInstance3D.new()
		node.name = "Batch%d" % parent.get_child_count()
		node.multimesh = many
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.layers = PropCatalog.RENDER_LAYER
		parent.add_child(node)
	_places.clear()
	_materials.clear()
	_meshes.clear()


func _put(shape: Shape, material: Material, place: Transform3D) -> void:
	var key := "%d:%d" % [shape, material.get_instance_id()]
	if not _places.has(key):
		_places[key] = [] as Array[Transform3D]
		_materials[key] = material
	(_places[key] as Array[Transform3D]).append(place)


## A scene point from x and y in the rules plane and scene z.
static func scene_of(at: Vector3) -> Vector3:
	var place := WorldSpace.to_scene(Vector2(at.x, at.y))
	place.z = at.z
	return place


static func _mesh(shape: Shape) -> PrimitiveMesh:
	match shape:
		Shape.CYLINDER:
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.5
			cylinder.bottom_radius = 0.5
			cylinder.height = 1.0
			cylinder.radial_segments = 12
			cylinder.rings = 1
			return cylinder
		Shape.SPHERE:
			var ball := SphereMesh.new()
			ball.radius = 0.5
			ball.height = 1.0
			ball.radial_segments = 12
			ball.rings = 6
			return ball
	return BoxMesh.new()
