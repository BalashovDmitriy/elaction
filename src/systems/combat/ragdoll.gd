class_name Ragdoll
extends RefCounted

## A jointed body: each part is its own physics body (ADR-0043, decision 12).
##
## A single block in place of a body lay on another corpse like a plank. The ragdoll is built
## from [PhysicalBone3D] on the skeleton of the pack figure: pelvis, torso, head, arms and
## legs in two parts each and the feet — thirteen bodies linked by cones with limits.
## The other bones (fingers, neck, shoulder girdle) follow their part.
##
## The pack's feet hang not from the shins but from the skeleton root (it is rigged for IK):
## they have no parent body of their own, and a separate hinge attaches them to the shin.
##
## The parts lie on the corpse layer ([constant Corpse.LAYER]) and see the floor and other
## corpses; the living do not see them. Parts of one body do not collide with each other —
## the joints hold them. Each part is locked to the play plane along Z: the arms and legs
## lie into the corridor depth at their own depth, and the body does not roll towards the
## camera.

## Body parts: bone, the bone to measure length to (empty — [code]length[/code]),
## capsule radius and length, m, mass, kg, and the joint. [code]swing[/code] — the cone
## of the shoulder and elbow, degrees. [code]bend[/code] — a joint like a human's, not
## equal in all directions: tilt around the model's X axis from and to (forward for the back
## and head is plus, for the thigh minus, the knee bends only into plus), rotation
## around the vertical and sideways — equally both ways. The axes are the model's, not the
## bone's: the pack bones have their own axes rotated every which way.
const PARTS: Array[Dictionary] = [
	{"bone": "Body", "to": "", "length": 0.2, "radius": 0.13, "mass": 12.0},
	{
		"bone": "Torso",
		"to": "Neck",
		"radius": 0.14,
		"mass": 20.0,
		"bend": [-60.0, 20.0, 25.0, 20.0]
	},
	{
		"bone": "Head",
		"to": "",
		"length": 0.22,
		"radius": 0.11,
		"mass": 5.0,
		"bend": [-50.0, 35.0, 50.0, 30.0]
	},
	{"bone": "UpperArm.L", "to": "LowerArm.L", "radius": 0.05, "mass": 2.5, "swing": 80.0},
	{"bone": "UpperArm.R", "to": "LowerArm.R", "radius": 0.05, "mass": 2.5, "swing": 80.0},
	{"bone": "LowerArm.L", "to": "", "length": 0.3, "radius": 0.045, "mass": 2.0, "swing": 70.0},
	{"bone": "LowerArm.R", "to": "", "length": 0.3, "radius": 0.045, "mass": 2.0, "swing": 70.0},
	{
		"bone": "UpperLeg.L",
		"to": "LowerLeg.L",
		"radius": 0.075,
		"mass": 8.0,
		"bend": [-20.0, 110.0, 20.0, 35.0]
	},
	{
		"bone": "UpperLeg.R",
		"to": "LowerLeg.R",
		"radius": 0.075,
		"mass": 8.0,
		"bend": [-20.0, 110.0, 20.0, 35.0]
	},
	{
		"bone": "LowerLeg.L",
		"to": "Foot.L",
		"radius": 0.06,
		"mass": 4.0,
		"bend": [-140.0, 0.0, 5.0, 5.0]
	},
	{
		"bone": "LowerLeg.R",
		"to": "Foot.R",
		"radius": 0.06,
		"mass": 4.0,
		"bend": [-140.0, 0.0, 5.0, 5.0]
	},
	{"bone": "Foot.L", "to": "", "length": 0.16, "radius": 0.045, "mass": 1.0},
	{"bone": "Foot.R", "to": "", "length": 0.16, "radius": 0.045, "mass": 1.0},
]
## A foot and the shin the hinge attaches it to.
const ANKLES := {"Foot.L": "LowerLeg.L", "Foot.R": "LowerLeg.R"}

## Gravity of the parts: the game world falls faster than the Earth's (27 m/s² for the agent
## and Otto).
const GRAVITY_SCALE: float = 2.75
const FRICTION: float = 0.9
const LINEAR_DAMP: float = 0.2
const ANGULAR_DAMP: float = 2.0
## Part speed limit, m/s: faster, a body would fly through a floor slab in one physics
## step. For the living the fall limit is of the same order (12.6 m/s).
const MAX_SPEED: float = 8.0
## A part slower than this, m/s, counts as settled.
const RESTING_SPEED: float = 0.15
## How long a body lies still before freezing, s (ADR-0044, decision 11).
##
## The parts themselves fell asleep poorly: in a pile neighbours wake each other, and twenty
## settled bodies cost physics 11 ms per step (measured in M24h). A frozen body is
## static: it leaves the simulation, but its collisions stay, and others still
## lie down on it. It looks the same and lies there until the end of the building.
const FREEZE_AFTER: float = 1.0
## How far below the bottom of the building a body counts as fallen out of the world, m.
const ABYSS_MARGIN: float = 10.0

## Scene height below which a body has fallen out of the world and disappears: it would
## fall forever and forever be simulated. The level sets it from its building.
static var abyss: float = -INF

## Parts by bone, while they exist: one cut off by a cab leaves the dictionary.
var parts: Dictionary = {}
## The body the ragdoll belongs to: by it a cab learns whose part it hit.
var corpse: Corpse = null

var _figure: FigureRig
var _skeleton: Skeleton3D
var _simulator: PhysicalBoneSimulator3D
var _joints: Dictionary = {}
## Skeleton bones each part drives: itself and its descendants without a part of their
## own. They are hidden together with it.
var _owned: Dictionary = {}
var _hidden := PackedStringArray()
## Whether the body is frozen ([method freeze]).
var _frozen: bool = false


## Builds the ragdoll on figure [param figure]. [param only] — only these parts
## (a piece torn off the body); empty — all.
func _init(figure: FigureRig, only: PackedStringArray = PackedStringArray()) -> void:
	_figure = figure
	_skeleton = figure.skeleton()
	_simulator = PhysicalBoneSimulator3D.new()
	_simulator.name = "Ragdoll"
	_skeleton.add_child(_simulator)
	for spec: Dictionary in PARTS:
		var bone_name := spec["bone"] as String
		if not only.is_empty() and not only.has(bone_name):
			continue
		parts[bone_name] = _part(spec)
	for bone_name: String in parts:
		for other: String in parts:
			if other != bone_name:
				(parts[bone_name] as PhysicalBone3D).add_collision_exception_with(parts[other])
	_own_bones()


## Releases the body into physics with velocity [param velocity] and push [param impulse]:
## at point [param at] of the part closest to it, and without a point — into the torso.
## Until then the parts collide with nothing: the living walk with their own shape.
func start(velocity: Vector3, impulse: Vector3 = Vector3.ZERO, at: Variant = null) -> void:
	for part: PhysicalBone3D in parts.values():
		part.collision_layer = 1 << (Corpse.LAYER - 1)
		part.collision_mask = Corpse.GEOMETRY_MASK | (1 << (Corpse.LAYER - 1))
	_simulator.physical_bones_start_simulation()
	for ankle: String in ANKLES:
		_pin_ankle(ankle)
	var limiter := SpeedLimit.new()
	limiter.ragdoll = self
	_simulator.add_child(limiter)
	for part: PhysicalBone3D in parts.values():
		part.linear_velocity = velocity
	if impulse == Vector3.ZERO:
		return
	if not at is Vector3:
		var chest := parts.get("Torso") as PhysicalBone3D
		if chest != null:
			chest.apply_central_impulse(impulse)
		return
	var point := at as Vector3
	var struck: PhysicalBone3D = null
	for part: PhysicalBone3D in parts.values():
		if (
			struck == null
			or (
				center_of(part).distance_squared_to(point)
				< center_of(struck).distance_squared_to(point)
			)
		):
			struck = part
	# The hit is at the part itself: the point at the bullet's height and depth, but no further
	# than the capsule, otherwise the lever would spin the part like a top.
	var offset := (point - struck.global_position).limit_length(0.3)
	struck.apply_impulse(impulse, offset)


## Removes parts [param bones]: their bones are hidden, the bodies disappear. Descendants
## stay and hang free on their joints.
func remove(bones: PackedStringArray) -> void:
	for bone_name: String in bones:
		var part := parts.get(bone_name) as PhysicalBone3D
		if part == null:
			continue
		parts.erase(bone_name)
		var joint := _joints.get(bone_name) as Joint3D
		if joint != null:
			joint.queue_free()
			_joints.erase(bone_name)
		for foot: String in ANKLES:
			if ANKLES[foot] == bone_name and _joints.has(foot):
				(_joints[foot] as Joint3D).queue_free()
				_joints.erase(foot)
		part.queue_free()
		_hidden.append_array(_owned[bone_name] as PackedStringArray)
	_figure.hide_bones(_hidden)


## Puts its parts where the same parts of [param source] are, with their
## velocities: a torn-off piece continues the body's motion.
func follow(source: Ragdoll) -> void:
	for bone_name: String in parts:
		var from := source.parts.get(bone_name) as PhysicalBone3D
		if from == null:
			continue
		var part := parts[bone_name] as PhysicalBone3D
		part.global_transform = from.global_transform
		part.linear_velocity = from.linear_velocity
		part.angular_velocity = from.angular_velocity


## Names of the parts that still exist.
func names() -> PackedStringArray:
	return PackedStringArray(parts.keys())


## Hides the bones of parts not in [param kept]: for a torn-off piece
## the rest of the body is someone else's.
func hide_all_but(kept: PackedStringArray) -> void:
	for bone_name: String in _owned:
		if not kept.has(bone_name):
			_hidden.append_array(_owned[bone_name] as PackedStringArray)
	_figure.hide_bones(_hidden)


## Takes the ragdoll apart: the figure is on its feet again, everything hidden is visible.
func dispose() -> void:
	if is_instance_valid(_simulator):
		_simulator.physical_bones_stop_simulation()
		_simulator.queue_free()
	for joint: Joint3D in _joints.values():
		joint.queue_free()
	parts.clear()
	_joints.clear()
	_hidden = PackedStringArray()
	_figure.hide_bones(_hidden)


## Middle of part [param part] in the world: the capsule goes from the bone along its Y.
static func center_of(part: PhysicalBone3D) -> Vector3:
	var shape := part.get_child(0) as CollisionShape3D
	return part.global_transform * shape.position


## Body bounds from the parts, in the world.
func bounds() -> AABB:
	var box := AABB()
	var first := true
	for part: PhysicalBone3D in parts.values():
		var shape := part.get_child(0) as CollisionShape3D
		var capsule := shape.shape as CapsuleShape3D
		var reach := Vector3.ONE * capsule.radius
		# Capsule height includes the hemispheres: the hemisphere centres are a radius closer than
		# the ends.
		var spine := capsule.height * 0.5 - capsule.radius
		for end: float in [-spine, spine]:
			var point := part.global_transform * (shape.position + Vector3(0.0, end, 0.0))
			var around := AABB(point - reach, reach * 2.0)
			box = around if first else box.merge(around)
			first = false
	return box


## Wakes the parts: support has gone from under a settled body — the basement hatch opened —
## and physics does not wake a sleeping body by itself, so it would hang in the air.
## A frozen one is simulated by physics again.
func wake() -> void:
	if _frozen:
		_frozen = false
		for part: PhysicalBone3D in parts.values():
			PhysicsServer3D.body_set_mode(part.get_rid(), PhysicsServer3D.BODY_MODE_RIGID)
		_set_limiter(true)
	for part: PhysicalBone3D in parts.values():
		PhysicsServer3D.body_set_state(part.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, false)


## A settled body freezes: the parts become static bodies — physics no longer
## simulates them, but they still collide ([constant FREEZE_AFTER]).
func freeze() -> void:
	if _frozen:
		return
	_frozen = true
	for part: PhysicalBone3D in parts.values():
		PhysicsServer3D.body_set_mode(part.get_rid(), PhysicsServer3D.BODY_MODE_STATIC)
	_set_limiter(false)


## Whether the body is frozen.
func is_frozen() -> bool:
	return _frozen


func _set_limiter(on: bool) -> void:
	for child: Node in _simulator.get_children():
		if child is SpeedLimit:
			child.set_physics_process(on)
			(child as SpeedLimit).still = 0.0


## Whether all parts are asleep: the body has settled.
func asleep() -> bool:
	for part: PhysicalBone3D in parts.values():
		if part.linear_velocity.length() > RESTING_SPEED:
			return false
	return true


## A step of the parts that physics does not do by itself: the speed limit —
## [PhysicalBone3D] has none — and riding on a cab floor. The cab is moved by code, and
## a body lying on its floor would fall onto the receding floor again and again, sliding
## off it; a part on a cab floor takes its vertical motion and rides with it.
##
## A cab going up pins a body lying on its roof under the top of the shaft —
## then there is no body anymore, as before the ragdoll (ADR-0042): physics would press it
## into both the roof and the slab at once.
class SpeedLimit:
	extends Node

	## How far below a part's surface the cab floor is searched for and how far above —
	## the ceiling, m.
	const REACH: float = 0.08

	var ragdoll: Ragdoll = null
	## How long the body has been lying still, s.
	var still: float = 0.0

	func _physics_process(delta: float) -> void:
		var space := get_viewport().world_3d.direct_space_state
		var resting := true
		for part: PhysicalBone3D in ragdoll.parts.values():
			if part.global_position.y < Ragdoll.abyss:
				ragdoll.corpse.vanish()
				return
			if part.linear_velocity.length() > RESTING_SPEED:
				resting = false
			# A part that fell asleep lies on something still: on a cab parts do not fall asleep —
			# its body is kinematic and wakes everything lying on it. There are many corpses until
			# the end of the building, and a ray under every part every step would cost the frame.
			if PhysicsServer3D.body_get_state(part.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING):
				continue
			if part.linear_velocity.length_squared() > MAX_SPEED * MAX_SPEED:
				part.linear_velocity = part.linear_velocity.limit_length(MAX_SPEED)
			var car := _car_under(space, part)
			if car != null:
				# On a cab floor the body does not freeze: the cab would drive out from under it.
				resting = false
			if car == null or is_zero_approx(car.speed_now()):
				continue
			if car.speed_now() < 0.0 and _pinned(space, part, car):
				ragdoll.corpse.vanish()
				return
			var velocity := part.linear_velocity
			velocity.y = -car.speed_now()
			velocity.x *= 0.5
			part.linear_velocity = velocity
		still = still + delta if resting else 0.0
		if still >= FREEZE_AFTER:
			ragdoll.freeze()

	## The cab a part lies on the floor of, or null.
	func _car_under(space: PhysicsDirectSpaceState3D, part: PhysicalBone3D) -> ElevatorCar:
		var shape := part.get_child(0) as CollisionShape3D
		var radius := (shape.shape as CapsuleShape3D).radius
		var from := Ragdoll.center_of(part)
		var query := PhysicsRayQueryParameters3D.create(
			from, from - Vector3(0.0, radius + REACH, 0.0), Corpse.GEOMETRY_MASK
		)
		var hit := space.intersect_ray(query)
		return hit.get("collider") as ElevatorCar if not hit.is_empty() else null

	## Whether a part carried up by cab [param car] has hit the ceiling.
	func _pinned(space: PhysicsDirectSpaceState3D, part: PhysicalBone3D, car: ElevatorCar) -> bool:
		var shape := part.get_child(0) as CollisionShape3D
		var radius := (shape.shape as CapsuleShape3D).radius
		var from := Ragdoll.center_of(part)
		var query := PhysicsRayQueryParameters3D.create(
			from, from + Vector3(0.0, radius + REACH, 0.0), Corpse.GEOMETRY_MASK
		)
		query.exclude = [car.get_rid()]
		return not space.intersect_ray(query).is_empty()


func _part(spec: Dictionary) -> PhysicalBone3D:
	var bone_name := spec["bone"] as String
	var bone := _skeleton.find_bone(bone_name)
	var length := float(spec.get("length", 0.0))
	var to := spec["to"] as String
	if not to.is_empty():
		var child := _skeleton.find_bone(to)
		length = (
			(
				_skeleton.get_bone_global_rest(child).origin
				- _skeleton.get_bone_global_rest(bone).origin
			)
			. length()
		)
	var radius := float(spec["radius"])
	var part := PhysicalBone3D.new()
	part.name = bone_name
	part.bone_name = bone_name
	part.mass = float(spec["mass"])
	part.friction = FRICTION
	part.bounce = 0.0
	part.gravity_scale = GRAVITY_SCALE
	part.linear_damp = LINEAR_DAMP
	part.angular_damp = ANGULAR_DAMP
	part.can_sleep = true
	part.collision_layer = 0
	part.collision_mask = 0
	part.axis_lock_linear_z = true
	var swing := float(spec.get("swing", 0.0))
	if spec.has("bend"):
		_bend(part, bone, spec["bend"] as Array)
	elif swing > 0.0:
		part.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
		# The cone's twist axis is the joint's X, the bone goes along Y.
		part.joint_rotation = Vector3(0.0, 0.0, PI * 0.5)
		part.set(&"joint_constraints/swing_span", swing)
		part.set(&"joint_constraints/twist_span", float(spec.get("twist", 30.0)))
	else:
		part.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = maxf(length, radius * 2.0)
	shape.shape = capsule
	shape.position = Vector3(0.0, length * 0.5, 0.0)
	part.add_child(shape)
	part.set_meta(&"ragdoll", self)
	_simulator.add_child(part)
	return part


## A joint like a human's: model axes in bone axes, limits [param limits] —
## tilt around the model's X from and to, rotation around Y and sideways around Z both
## ways, degrees.
func _bend(part: PhysicalBone3D, bone: int, limits: Array) -> void:
	part.joint_type = PhysicalBone3D.JOINT_TYPE_6DOF
	var to_bone := _skeleton.get_bone_global_rest(bone).basis.orthonormalized().inverse()
	var axis_x := (to_bone * Vector3.RIGHT).normalized()
	var axis_y := (to_bone * Vector3.UP).normalized()
	var axis_z := axis_x.cross(axis_y).normalized()
	axis_y = axis_z.cross(axis_x).normalized()
	part.joint_rotation = Basis(axis_x, axis_y, axis_z).get_euler()
	var spans := {
		"x": [float(limits[0]), float(limits[1])],
		"y": [-float(limits[2]), float(limits[2])],
		"z": [-float(limits[3]), float(limits[3])],
	}
	for axis: String in spans:
		var span := spans[axis] as Array
		part.set("joint_constraints/%s/angular_limit_enabled" % axis, true)
		part.set("joint_constraints/%s/angular_limit_lower" % axis, span[0])
		part.set("joint_constraints/%s/angular_limit_upper" % axis, span[1])


## Foot hinge to the shin: at the ankle, where the foot begins.
func _pin_ankle(foot: String) -> void:
	var leg := parts.get(ANKLES[foot]) as PhysicalBone3D
	var sole := parts.get(foot) as PhysicalBone3D
	if leg == null or sole == null:
		return
	var joint := PinJoint3D.new()
	_simulator.add_child(joint)
	joint.global_position = sole.global_position
	joint.node_a = joint.get_path_to(leg)
	joint.node_b = joint.get_path_to(sole)
	_joints[foot] = joint


## Which skeleton bones each part drives.
func _own_bones() -> void:
	var owner_of := {}
	for bone: int in _skeleton.get_bone_count():
		var walk := bone
		while walk >= 0:
			var walk_name := _skeleton.get_bone_name(walk)
			if _is_part(walk_name):
				owner_of[bone] = walk_name
				break
			walk = _skeleton.get_bone_parent(walk)
	for spec: Dictionary in PARTS:
		var owned := PackedStringArray()
		for bone: int in owner_of:
			if owner_of[bone] == spec["bone"]:
				owned.append(_skeleton.get_bone_name(bone))
		_owned[spec["bone"]] = owned


static func _is_part(bone_name: String) -> bool:
	for spec: Dictionary in PARTS:
		if spec["bone"] == bone_name:
			return true
	return false
