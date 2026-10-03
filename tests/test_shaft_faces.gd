extends GutTest

## Shaft dress without coinciding faces (ADR-0037, decision 2).
##
## Two faces of different materials in one plane and with one normal flicker: they have the same
## depth, and which is closer is decided by rounding — differently from frame to frame, as soon as
## the camera moves by a fraction of a pixel. On a still frame this is not visible, so the check
## goes by geometry, not by picture, and on several seeds: shafts, their ends and the machine room
## stand by the layout.
##
## Faces turned toward each other do not count: these are two boxes butted together, and both
## such faces are hidden inside. Side ones, along x, do not either: the camera is orthographic
## and tilted only around x ([SideCamera]), it sees a side face edge-on.

const SEEDS: Array[int] = [1, 2, 3, 5, 8]

## "In one plane" tolerance, m.
const COPLANAR: float = 0.001


func test_no_two_materials_share_a_face_in_any_shaft() -> void:
	var rules := BuildingRules.new()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		var shafts := BuildingShafts.new()
		add_child_autofree(shafts)
		shafts.dress(rules, plan)
		var boxes := _boxes(shafts)
		assert_gt(boxes.size(), 10, "seed %d: the shafts have no details" % building_seed)
		var clashes := _clashes(boxes)
		assert_eq(
			clashes,
			[] as Array[String],
			"seed %d: faces in one plane: %s" % [building_seed, clashes]
		)


## Dress boxes: [AABB, material]. All shaft parts are boxes without rotation.
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


## Pairs of boxes of different materials with a face in one plane and one normal
## that overlap by area.
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
					clashes.append("%s and %s" % [a, b])
					if clashes.size() > 5:
						return clashes
	return clashes


## Whether faces [param a] and [param b] with one normal along axis [param axis] lie in
## one plane and whether they overlap.
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
