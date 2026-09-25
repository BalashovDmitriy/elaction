extends GutTest

## Одежда шахт без совпадающих граней (ADR-0037, решение 2).
##
## Две грани разных материалов в одной плоскости и с одной нормалью мерцают:
## глубина у них одна, и какая ближе, решает округление — от кадра к кадру
## по-разному, стоит камере сдвинуться на долю пикселя. На неподвижном кадре
## этого не видно, поэтому проверка идёт по геометрии, а не по картинке, и на
## нескольких сидах: шахты, их концы и машинное отделение стоят по раскладке.
##
## Грани, обращённые друг к другу, не в счёт: это две коробки встык, и обе
## такие грани спрятаны внутри. Боковые, по x, — тоже: камера ортографическая
## и наклонена только вокруг x ([SideCamera]), боковую грань она видит ребром.

const SEEDS: Array[int] = [1, 2, 3, 5, 8]

## Допуск «в одной плоскости», м.
const COPLANAR: float = 0.001


func test_no_two_materials_share_a_face_in_any_shaft() -> void:
	var rules := BuildingRules.new()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		var shafts := BuildingShafts.new()
		add_child_autofree(shafts)
		shafts.dress(rules, plan)
		var boxes := _boxes(shafts)
		assert_gt(boxes.size(), 10, "сид %d: у шахт нет деталей" % building_seed)
		var clashes := _clashes(boxes)
		assert_eq(
			clashes,
			[] as Array[String],
			"сид %d: грани в одной плоскости — %s" % [building_seed, clashes]
		)


## Коробки одежды: [AABB, материал]. Все детали шахты — коробки без поворота.
func _boxes(root: Node) -> Array[Array]:
	var found: Array[Array] = []
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		var mesh := part.mesh as BoxMesh
		if mesh == null:
			continue
		var size := mesh.size * part.global_basis.get_scale()
		var box := AABB(part.global_position - size * 0.5, size)
		found.append([box, part.material_override])
	return found


## Пары коробок разных материалов с гранью в одной плоскости и одной нормалью,
## которые перекрываются по площади.
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


## Лежат ли грани [param a] и [param b] с одной нормалью по оси [param axis] в
## одной плоскости и перекрываются ли они.
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
