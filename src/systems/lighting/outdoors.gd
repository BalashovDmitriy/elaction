class_name Outdoors
extends RefCounted

## What stands outside the building and catches the sun (ADR-0051).
##
## The sun is a directional light, and it shines through everything at any depth: the
## building is shown in cutaway, and the corridors it would fall on are lit by lamps and
## the building's general light. So the sun is given its own layer, and only what is
## outside goes into it: the roof and its equipment, the sign, the helicopter, the exit
## street.
##
## The layer is set at night too: there is no sun then, and an extra bit changes
## nothing — but the building is not assembled differently at different times of day.

## Render layer the sun sees. Next to it — dressing
## ([constant PropCatalog.RENDER_LAYER]) and figures ([constant FigureRig.RENDER_LAYER]).
const LAYER: int = 1 << 12


## Gives the sun everything visible under [param root].
static func mark(root: Node) -> void:
	for node in _visuals(root):
		node.layers |= LAYER


## Gives the sun everything visible under [param root] that is entirely above
## [param bottom] — a scene height, m: that way the roof is taken from the building's
## builders, while the floors under it, built by the same builders, stay without sun.
static func mark_above(root: Node, bottom: float) -> void:
	for node in _visuals(root):
		var box := node.global_transform * node.get_aabb()
		if box.position.y >= bottom:
			node.layers |= LAYER


static func _visuals(root: Node) -> Array[VisualInstance3D]:
	var found: Array[VisualInstance3D] = []
	var own := root as VisualInstance3D
	if own != null:
		found.append(own)
	for node in root.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		# A light is also a VisualInstance3D, but it has no render layer. Cabs and actors
		# move around the building: sun caught on the roof would ride with them into the
		# corridors.
		if visual != null and not (visual is Light3D) and not _moves(visual, root):
			found.append(visual)
	return found


static func _moves(node: Node, root: Node) -> bool:
	var up := node.get_parent()
	while up != null and up != root.get_parent():
		if up is AnimatableBody3D or up is CharacterBody3D:
			return true
		up = up.get_parent()
	return false
