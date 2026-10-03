extends GutTest

## MeshBatch: details become one multimesh per "shape, material" pair.


## A hall commits once per floor (ADR-0060, decision 10): the floors share mesh resources
## rather than each making its own.
func test_commits_share_one_mesh_per_shape_and_material() -> void:
	var batch := MeshBatch.new()
	var paint := StandardMaterial3D.new()
	var first := Node3D.new()
	var second := Node3D.new()
	add_child_autofree(first)
	add_child_autofree(second)
	batch.box(paint, Vector3.ONE, Vector3.ZERO)
	batch.commit(first)
	batch.box(paint, Vector3.ONE, Vector3(2.0, 0.0, 0.0))
	batch.commit(second)
	var a := (first.get_child(0) as MultiMeshInstance3D).multimesh.mesh
	var b := (second.get_child(0) as MultiMeshInstance3D).multimesh.mesh
	assert_same(a, b, "the second floor reuses the first floor's box")
	assert_same((a as PrimitiveMesh).material, paint, "with its material")


func test_another_material_gets_its_own_mesh() -> void:
	var batch := MeshBatch.new()
	var floor_node := Node3D.new()
	add_child_autofree(floor_node)
	batch.box(StandardMaterial3D.new(), Vector3.ONE, Vector3.ZERO)
	batch.box(StandardMaterial3D.new(), Vector3.ONE, Vector3.ZERO)
	batch.commit(floor_node)
	assert_eq(floor_node.get_child_count(), 2, "one batch per material")
	var a := (floor_node.get_child(0) as MultiMeshInstance3D).multimesh.mesh
	var b := (floor_node.get_child(1) as MultiMeshInstance3D).multimesh.mesh
	assert_ne(a, b, "different materials, different meshes")
