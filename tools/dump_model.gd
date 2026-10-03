extends SceneTree

## Actor model breakdown: what Godot imported from the `.glb`.
##
## Prints the node tree, the skeleton bones with their rest pose, and where the end of
## each bone goes under a positive rotation around its X axis — this is how
## the sign of angles in [FigurePoses] is verified: "forward" must be forward.
##
## Run:
##     godot --headless --script res://tools/dump_model.gd -- res://assets/models/otto.glb

## How much to rotate a bone to see the direction, degrees.
const PROBE_ANGLE: float = 30.0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var path := "res://assets/models/otto.glb"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("res://"):
			path = argument

	var packed := load(path) as PackedScene
	if packed == null:
		print("failed to load: %s" % path)
		quit(1)
		return
	var model := packed.instantiate()
	root.add_child(model)
	await process_frame

	print("=== %s ===" % path)
	_dump_tree(model, "")

	var skeleton := _skeleton_of(model)
	if skeleton == null:
		print("no skeleton")
	else:
		_dump_bones(skeleton)
		_probe_axes(skeleton)
	_dump_meshes(model)
	quit(0)


func _dump_tree(node: Node, indent: String) -> void:
	var extra := ""
	var spatial := node as Node3D
	if spatial != null:
		extra = "  @ %s" % spatial.position
	print("%s%s (%s)%s" % [indent, node.name, node.get_class(), extra])
	for child in node.get_children():
		_dump_tree(child, indent + "  ")


func _skeleton_of(model: Node) -> Skeleton3D:
	var found := model.find_children("*", "Skeleton3D", true, false)
	return found[0] as Skeleton3D if not found.is_empty() else null


func _dump_bones(skeleton: Skeleton3D) -> void:
	print("--- bones (%d) ---" % skeleton.get_bone_count())
	for index in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(index)
		var parent := skeleton.get_bone_parent(index)
		var parent_name := skeleton.get_bone_name(parent) if parent >= 0 else "-"
		print(
			(
				"%-8s parent %-8s rest %s  axes X %s Y %s Z %s"
				% [
					skeleton.get_bone_name(index),
					parent_name,
					rest.origin,
					rest.basis.x,
					rest.basis.y,
					rest.basis.z
				]
			)
		)


## Rotates each bone by +PROBE_ANGLE around its X and prints where
## its end moved relative to rest. The end is a point ten centimetres
## along the bone axis; the direction of the shift along Z is the sign of "forward".
func _probe_axes(skeleton: Skeleton3D) -> void:
	print("--- probe: +%.0f° around local X ---" % PROBE_ANGLE)
	for index in skeleton.get_bone_count():
		skeleton.reset_bone_poses()
		var rest_tip := _tip(skeleton, index)
		var rest := skeleton.get_bone_rest(index)
		var turned := (
			rest.basis.get_rotation_quaternion()
			* Quaternion(Vector3.RIGHT, deg_to_rad(PROBE_ANGLE))
		)
		skeleton.set_bone_pose_rotation(index, turned)
		var moved := _tip(skeleton, index) - rest_tip
		print("%-8s tip moved by %s" % [skeleton.get_bone_name(index), moved])
	skeleton.reset_bone_poses()


func _tip(skeleton: Skeleton3D, index: int) -> Vector3:
	skeleton.force_update_all_bone_transforms()
	var pose := skeleton.get_bone_global_pose(index)
	return pose * Vector3(0.0, 0.1, 0.0)


func _dump_meshes(model: Node) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		var skinned := mesh_instance.skin != null
		print(
			(
				"--- mesh %s: surfaces %d, AABB %s, skin %s ---"
				% [mesh_instance.name, mesh.get_surface_count(), mesh.get_aabb(), skinned]
			)
		)
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as BaseMaterial3D
			var colour := material.albedo_color if material != null else Color.MAGENTA
			print("    surface %d: %s" % [surface, colour])
