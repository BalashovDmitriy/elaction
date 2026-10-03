class_name Shelter
extends RefCounted

## A body under precipitation (ADR-0054, decision 5): a drop and a flake die against the head,
## shoulders, car body and fuselage, rather than flying through Otto, an agent, the car or
## the helicopter. The roof catches them with a height map ([RoofCatch]), but the map is static:
## whoever walks and drives is not in it — and before M24l rain went through
## people.
##
## The catcher is a particle collision box, a child of the body: it moves with it. Invisible and
## does not touch physics — only particles.

## How much wider the catcher is than the body: shoulders and hat stick out of the collision box.
const SPREAD: float = 1.4


## A catcher on body [param body] of size [param size] with its bottom at its feet.
static func over(body: Node3D, size: Vector3) -> GPUParticlesCollisionBox3D:
	var shield := GPUParticlesCollisionBox3D.new()
	shield.name = "Shelter"
	shield.size = Vector3(size.x * SPREAD, size.y, size.z * SPREAD)
	shield.position = Vector3(0.0, size.y * 0.5, 0.0)
	body.add_child(shield)
	return shield


## Fits the catcher [param shield] to the pose: [param size] — the body extent in it,
## bottom at the feet. A crouching, kneeling or lying one is covered by their own
## height: a catcher at standing height left a dry column above them.
static func fit(shield: GPUParticlesCollisionBox3D, size: Vector3) -> void:
	var wide := Vector3(size.x * SPREAD, size.y, size.z * SPREAD)
	if shield.size.is_equal_approx(wide):
		return
	shield.size = wide
	shield.position = Vector3(0.0, size.y * 0.5, 0.0)


## A catcher by the extent of what is visible under [param body] — for the car and the helicopter,
## which have no single body box. The extent is in [param body]'s axes; computed along the node
## chain, not world axes: the car is assembled before the tree. What is under the nodes [param skip]
## does not count: the rotor disc and the rope would give a dry box the size of the whole rotor.
## Empty entries in [param skip] are skipped: the model may have no rotor.
static func over_meshes(body: Node3D, skip: Array[Node] = []) -> GPUParticlesCollisionBox3D:
	var reach := AABB()
	var first := true
	var parts := skip.filter(func(part: Node) -> bool: return part != null)
	# Geometry only: a light source's extent is its range, and the helicopter's
	# spotlight inflated the catcher to sixteen metres.
	for node: Node in body.find_children("*", "GeometryInstance3D", true, false):
		var shape := node as GeometryInstance3D
		if shape is GPUParticles3D or shape.get_aabb().size == Vector3.ZERO:
			continue
		if parts.any(func(part: Node) -> bool: return part == shape or part.is_ancestor_of(shape)):
			continue
		var box := relative(body, shape) * shape.get_aabb()
		reach = box if first else reach.merge(box)
		first = false
	var shield := GPUParticlesCollisionBox3D.new()
	shield.name = "Shelter"
	shield.size = reach.size
	shield.position = reach.get_center()
	body.add_child(shield)
	return shield


## Position of [param node] in the axes of its ancestor [param body] — along the node chain,
## and before the tree too. [Passerby] measures a pedestrian's height with it.
static func relative(body: Node3D, node: Node3D) -> Transform3D:
	var chain := Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != body:
		var spatial := at as Node3D
		if spatial != null:
			chain = spatial.transform * chain
		at = at.get_parent()
	return chain
