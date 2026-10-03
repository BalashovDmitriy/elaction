class_name MeshBatch
extends RefCounted

## Набор примитивов без тел и теней: копит коробки, цилиндры и шары по
## материалу, а потом сдаёт по одному мультимешу на пару «форма — материал».
##
## Так собраны open space офиса (ADR-0056, решение 4) и залы особых этажей
## (ADR-0057, решение 5): деталей тысячи, а вызовов отрисовки — десятки. В
## проходе теней ламп набор не участвует — бюджет кадра внизу здания
## (ADR-0042, решение 2).
##
## Координаты — x и y в плоскости правил (y вниз), z сцены.

enum Shape { BOX, CYLINDER, SPHERE }

## Места деталей по ключу "форма:материал" или "меш:id" и чем их рисовать.
var _places: Dictionary = {}
var _materials: Dictionary = {}
var _meshes: Dictionary = {}


## Коробка габарита [param size] серединой в [param at].
func box(material: Material, size: Vector3, at: Vector3) -> void:
	_put(Shape.BOX, material, Transform3D(Basis.from_scale(size), scene_of(at)))


## Коробка, стоящая на полу [param surface]: [param at] — x, высота низа над
## полом и z.
func box_on(material: Material, size: Vector3, surface: float, at: Vector3) -> void:
	box(material, size, Vector3(at.x, surface - at.y - size.y * 0.5, at.z))


## Вертикальный цилиндр радиусом [param radius] и высотой [param height]: [param
## at] — x, высота низа над полом [param surface] и z оси.
func cylinder_on(
	material: Material, radius: float, height: float, surface: float, at: Vector3
) -> void:
	var basis := Basis.from_scale(Vector3(radius * 2.0, height, radius * 2.0))
	var place := scene_of(Vector3(at.x, surface - at.y - height * 0.5, at.z))
	_put(Shape.CYLINDER, material, Transform3D(basis, place))


## Лежачий цилиндр вдоль X: труба длиной [param length] серединой в [param at].
func pipe_x(material: Material, radius: float, length: float, at: Vector3) -> void:
	var basis := (
		Basis(Vector3.BACK, PI * 0.5)
		* Basis.from_scale(Vector3(radius * 2.0, length, radius * 2.0))
	)
	_put(Shape.CYLINDER, material, Transform3D(basis, scene_of(at)))


## Шар диаметром [param size] серединой в [param at].
func sphere(material: Material, size: float, at: Vector3) -> void:
	_put(Shape.SPHERE, material, Transform3D(Basis.from_scale(Vector3.ONE * size), scene_of(at)))


## Готовый меш (мебель пака) на месте [param place] сцены.
func mesh(source: Mesh, place: Transform3D) -> void:
	var key := "mesh:%d" % source.get_instance_id()
	if not _places.has(key):
		_places[key] = [] as Array[Transform3D]
		_meshes[key] = source
	(_places[key] as Array[Transform3D]).append(place)


## Места всех накопленных деталей, до [method commit]. Тестам: под
## headless-движком мультимеш места не хранит и отдаёт единичные — проверка
## по нему не видела бы ни одной детали.
func places() -> Array[Transform3D]:
	var all: Array[Transform3D] = []
	for each: Array in _places.values():
		all.append_array(each as Array[Transform3D])
	return all


## Сдаёт накопленное узлами в [param parent] на слой обстановки.
func commit(parent: Node3D) -> void:
	for key: String in _places:
		var places: Array[Transform3D] = _places[key]
		var many := MultiMesh.new()
		many.transform_format = MultiMesh.TRANSFORM_3D
		if _meshes.has(key):
			many.mesh = _meshes[key] as Mesh
		else:
			var primitive := _mesh(int(key.get_slice(":", 0)) as Shape)
			primitive.material = _materials[key] as Material
			many.mesh = primitive
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


## Точка сцены по x и y плоскости правил и z сцены.
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
