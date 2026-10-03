class_name FigureRig
extends Node3D

## Actor skeleton: pack clips and code poses (ADR-0032, decision 1).
##
## The model comes from a `.glb` built by `tools/build_actors.py` from the
## Quaternius pack: a 62-bone skeleton and four clips. Which pose plays what is decided by
## [FigurePoses]; the rig turns a pose of any origin into the same thing — a frame,
## a set of bone rotations and offsets — and every frame leads the skeleton towards it
## with per-bone spherical interpolation. So a transition from a clip to a code
## pose is the same kind of motion as the angle smoothing was since M16.
##
## A clip is read directly, `Animation.rotation_track_interpolate` at the needed
## moment, without [AnimationPlayer] and [AnimationTree]: this way `snap()` sets the pose
## at once, and the bounds from skinned vertices are computed from the same frame.
##
## The node origin is at the actor's feet: the actor puts the rig on its floor, and turning
## towards the camera and tilting the body are the rig's business.
##
## There is no outline since M24f (ADR-0042, decision 7): in light it read unnaturally.
## Readability in the dark is kept by light — the figure's meshes are on their own layer
## [constant RENDER_LAYER], lit by a weak camera light
## ([method SideCamera.actor_fill]) that the surroundings do not receive.

## Render layer of the figures: the camera light shines on it and only on it.
const RENDER_LAYER: int = 1 << 11

## Pack bones moved by code poses. All pack characters have the same names.
const HIPS := "Hips"
const ABDOMEN := "Abdomen"
const TORSO := "Torso"
const CHEST := "Chest"
const NECK := "Neck"
const HEAD := "Head"
const ARM_L := "UpperArm.L"
const ARM_R := "UpperArm.R"
const ELBOW_L := "LowerArm.L"
const ELBOW_R := "LowerArm.R"
const LEG_L := "UpperLeg.L"
const LEG_R := "UpperLeg.R"
const KNEE_L := "LowerLeg.L"
const KNEE_R := "LowerLeg.R"
## The pack's feet are attached not to the shins but to the root: the skeleton is rigged
## for IK. In clips the rotation is baked, and in a code pose the rig puts the foot on the
## end of the shin.
const FOOT_L := "Foot.L"
const FOOT_R := "Foot.R"
## Hand with the pistol: the barrel lies along the fingers (`build_actors.py`, `_gun`).
const GUN_HAND := "Wrist.R"
## The second hand that holds the grip from below, and how much lower it is than the first, m.
const SUPPORT_HAND := "Wrist.L"
const SUPPORT_DROP: float = 0.04
const BONES: PackedStringArray = [
	HIPS,
	ABDOMEN,
	TORSO,
	CHEST,
	NECK,
	HEAD,
	ARM_L,
	ARM_R,
	ELBOW_L,
	ELBOW_R,
	LEG_L,
	LEG_R,
	KNEE_L,
	KNEE_R,
	FOOT_L,
	FOOT_R,
]

## How the torso tilt is split between vertebrae: the back bends, not a hinge.
const LEAN_SHARE := {ABDOMEN: 0.45, TORSO: 0.35, CHEST: 0.2}
const HEAD_SHARE := {NECK: 0.5, HEAD: 0.5}

## Directions along which the extreme vertices of each bone are picked for
## grounding: six axes and eight cube corners.
const HULL_DIRECTIONS: Array[Vector3] = [
	Vector3.RIGHT,
	Vector3.LEFT,
	Vector3.UP,
	Vector3.DOWN,
	Vector3.FORWARD,
	Vector3.BACK,
	Vector3(1, 1, 1),
	Vector3(1, 1, -1),
	Vector3(1, -1, 1),
	Vector3(1, -1, -1),
	Vector3(-1, 1, 1),
	Vector3(-1, 1, -1),
	Vector3(-1, -1, 1),
	Vector3(-1, -1, -1),
]
## Twelve more — midpoints of the cube edges: for rigid parts on a single bone
## ([method SkinnedSurface._pick_hull]).
const HULL_EDGES: Array[Vector3] = [
	Vector3(1, 1, 0),
	Vector3(1, -1, 0),
	Vector3(-1, 1, 0),
	Vector3(-1, -1, 0),
	Vector3(1, 0, 1),
	Vector3(1, 0, -1),
	Vector3(-1, 0, 1),
	Vector3(-1, 0, -1),
	Vector3(0, 1, 1),
	Vector3(0, 1, -1),
	Vector3(0, -1, 1),
	Vector3(0, -1, -1),
]

## Shader of a torn figure (ADR-0043, decisions 8 and 11).
const CARVE_SHADER := preload("res://src/systems/combat/carve.gdshader")

## Where the model faces when turned right and left: a quarter turn puts
## the gaze along the floor, while at rest it faces the camera (+Z).
const FACE_RIGHT: float = PI * 0.5


## A mesh surface captured once: vertices, bone binding and weights.
##
## [method Mesh.surface_get_arrays] copies all surface arrays on every
## call, and vertex bounds are needed during transitions between poses. What is captured
## at birth is copied once.
class SkinnedSurface:
	extends RefCounted

	var mesh_instance: MeshInstance3D
	## Surface index in the mesh.
	var index: int = 0
	var vertices := PackedVector3Array()
	var bone_ids := PackedInt32Array()
	var weights := PackedFloat32Array()
	## Bones per vertex: 0 for an unbound surface — it stays as is.
	var per_vertex: int = 0
	## Extreme vertices of each bone: the rig grounds the pose by them at runtime.
	var hull := PackedInt32Array()

	static func of(instance: MeshInstance3D, surface: int) -> SkinnedSurface:
		var made := SkinnedSurface.new()
		made.mesh_instance = instance
		made.index = surface
		var arrays := instance.mesh.surface_get_arrays(surface)
		made.vertices = arrays[Mesh.ARRAY_VERTEX]
		# A surface without a skin has no bones and weights at all — they are null, not an empty
		# array, and it cannot go into a typed field.
		var bones: Variant = arrays[Mesh.ARRAY_BONES]
		var bone_weights: Variant = arrays[Mesh.ARRAY_WEIGHTS]
		if instance.skin == null or bones == null or bone_weights == null:
			made.hull = PackedInt32Array(range(made.vertices.size()))
			return made
		# The engine returns bone indices as ints or floats — depending on the import.
		made.bone_ids = bones if bones is PackedInt32Array else PackedInt32Array(Array(bones))
		made.weights = bone_weights
		made.per_vertex = made.bone_ids.size() / maxi(made.vertices.size(), 1)
		made.hull = made._pick_hull()
		return made

	## The main binding of a vertex — the bone with the largest weight.
	func main_bind(index: int) -> int:
		var best := 0
		var best_weight := -1.0
		for slot in per_vertex:
			var weight := weights[index * per_vertex + slot]
			if weight > best_weight:
				best_weight = weight
				best = bone_ids[index * per_vertex + slot]
		return best

	## Vertices that are extreme along [constant HULL_DIRECTIONS] among their bone.
	## A bone rotates almost rigidly, and a vertex extreme at rest stays extreme
	## in a pose: the bounds from them differ from the full ones by millimetres, with
	## ten times fewer vertices.
	func _pick_hull() -> PackedInt32Array:
		var best := {}
		for index in vertices.size():
			var bind := main_bind(index)
			if not best.has(bind):
				var fresh: Array[int] = []
				fresh.resize(HULL_DIRECTIONS.size())
				fresh.fill(index)
				best[bind] = fresh
			var picks: Array[int] = best[bind]
			for slot in HULL_DIRECTIONS.size():
				var direction := HULL_DIRECTIONS[slot]
				if vertices[index].dot(direction) > vertices[picks[slot]].dot(direction):
					picks[slot] = index
		var chosen := {}
		for picks: Array[int] in best.values():
			for index in picks:
				chosen[index] = true
		# A rigid part on a single bone — a hat, a cap — when lying touches the floor at a point
		# between the cube axes and corners: by those alone the residential cap sank into the floor
		# by a centimetre and a half (code review M24m). It gets the cube edges too: it has
		# hundreds of vertices, not thousands, and the extra extremes are a dozen.
		if best.size() == 1:
			for direction: Vector3 in HULL_EDGES:
				var pick := 0
				for index: int in vertices.size():
					if vertices[index].dot(direction) > vertices[pick].dot(direction):
						pick = index
				chosen[pick] = true
		return PackedInt32Array(chosen.keys())


## Skeleton frame: rotation and offset of each bone and what applies to the whole model.
class Frame:
	extends RefCounted

	var rotations: Array[Quaternion] = []
	var positions := PackedVector3Array()
	var tilt: float = 0.0
	var lift: float = 0.0
	var squash: float = 1.0

	## Own copy: arrays are copied whole, without per-bone interpolation.
	func copy() -> Frame:
		var twin := Frame.new()
		twin.rotations = rotations.duplicate()
		twin.positions = positions.duplicate()
		twin.tilt = tilt
		twin.lift = lift
		twin.squash = squash
		return twin

	## Blend of two frames: [param weight] 0 — this one, 1 — [param other].
	func blend(other: Frame, weight: float) -> Frame:
		var t := clampf(weight, 0.0, 1.0)
		var mixed := Frame.new()
		mixed.rotations.resize(rotations.size())
		mixed.positions.resize(positions.size())
		for bone in rotations.size():
			mixed.rotations[bone] = rotations[bone].slerp(other.rotations[bone], t)
			mixed.positions[bone] = positions[bone].lerp(other.positions[bone], t)
		mixed.tilt = lerpf(tilt, other.tilt, t)
		mixed.lift = lerpf(lift, other.lift, t)
		mixed.squash = lerpf(squash, other.squash, t)
		return mixed


## A clip split into tracks: which track drives which bone.
class ClipTracks:
	extends RefCounted

	var animation: Animation
	var rotation_tracks := PackedInt32Array()
	var rotation_bones := PackedInt32Array()
	var position_tracks := PackedInt32Array()
	var position_bones := PackedInt32Array()

	func length() -> float:
		return animation.length


## Materials of torn figures by source material: one shader per pack material, while the
## cut is per figure — via instance parameters.
static var _carve_materials: Dictionary = {}

## The actor model. Without it the rig is an empty node, and that is a scene error.
@export var model: PackedScene

## Where to aim the muzzle while the actor shoots: height above the feet and reach
## forward, m — the point where the bullet leaves by the ROM rules (ADR-0043,
## decision 16). NAN — do not aim: the arm moves by the clip.
var aim_height: float = NAN
var aim_reach: float = Proportions.MUZZLE

## How many times faster than the world the rig's clock runs. The takedown scene slows the
## world, while the two in it move at their own pace (ADR-0040).
var speed: float = 1.0

## The forward tilt "around the heels" and lift above the floor go not to bones but to the
## model itself: the skeleton has no bone that can lay the whole body down.
var _instance: Node3D = null
var _skeleton: Skeleton3D = null
var _meshes: Array[MeshInstance3D] = []
var _surfaces: Array[SkinnedSurface] = []
var _bones: Dictionary = {}
var _clips: Dictionary = {}
## Rest frame of the skeleton: the base of clip frames. Captured once — a clip is assembled
## every frame at runtime, and the rest pose does not change.
var _rest: Frame = null
## First frame of the stance: the base of code poses. Its global bone positions are
## computed once — the rotation axes are taken from them.
var _stand: Frame = null
var _stand_globals: Array[Transform3D] = []
## Code poses are immutable: the frame of each is computed once per rig.
var _code_frames: Dictionary = {}
## Height at rest, m.
var _height: float = 0.0

var _pose_name := "idle"
## How many seconds the current pose has lasted: "once" clips run by it.
var _pose_time: float = 0.0
## The rig's clock: the stance loops by it.
var _clock: float = 0.0
## Walk clock, s: accumulated from the actor's phase, not from frames — when the actor
## stops, the legs stop too.
var _walk_clock: float = 0.0
var _walk_phase: float = 0.0
var _current: Frame = null
## The frame the rig was in when the pose changed: the transition starts from it.
var _from: Frame = null
## How long the transition into the current pose lasts, s
## ([method FigurePoses.blend_time]).
var _blend: float = FigurePoses.BLEND_DEFAULT
## Turnaround (ADR-0039, decision 3): from where and to where the body turns and how many
## seconds it has been going. The turn goes through "facing the camera", not back to it.
var _yaw_from: float = FACE_RIGHT
var _yaw_to: float = FACE_RIGHT
var _turned: float = MoveLocks.TURN_TIME
## Whether the rig has already looked anywhere: the first look is set at once, no turn.
var _faced: bool = false
## The transition is over: the rig stands in the pose frame. With a still target (code pose,
## end of a clip) there is nothing more to apply — those standing and lying would walk
## vertices every frame for nothing; the stance and walk clips the rig simply keeps playing.
var _settled: bool = false
## What of the body is cut off under the cab floor: x from, x to, floor height. Empty —
## not cut.
var _carved := Vector4.ZERO
## Pistol muzzle in the space of hand [constant GUN_HAND]; NAN — no pistol.
var _muzzle := Vector3(NAN, NAN, NAN)
## Whether the arm was aimed in the last applied frame: a frozen rig applies the
## frame once more when aiming is removed — otherwise the arm would stay raised.
var _aim_shown: bool = false


func _ready() -> void:
	if model == null:
		push_error("FigureRig without a model: %s" % get_path())
		return
	_instance = model.instantiate() as Node3D
	add_child(_instance)
	# The import player is not needed: the rig reads the clips. Stopped, it does not
	# touch the skeleton and does not spend a frame.
	for player in _instance.find_children("*", "AnimationPlayer", true, false):
		(player as AnimationPlayer).stop()
		(player as AnimationPlayer).process_mode = Node.PROCESS_MODE_DISABLED

	var found := _instance.find_children("*", "Skeleton3D", true, false)
	_skeleton = found[0] as Skeleton3D if not found.is_empty() else null
	if _skeleton == null:
		push_error("the model has no skeleton: %s" % model.resource_path)
		return
	for bone_name in BONES:
		var index := _skeleton.find_bone(bone_name)
		if index < 0:
			push_error("the model has no bone %s: %s" % [bone_name, model.resource_path])
			continue
		_bones[bone_name] = index
	_rest = _read_rest()
	_read_clips()

	for node in _instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		mesh_instance.layers |= RENDER_LAYER
		_meshes.append(mesh_instance)
		for surface in mesh_instance.mesh.get_surface_count():
			_surfaces.append(SkinnedSurface.of(mesh_instance, surface))

	_muzzle = _find_muzzle()
	_stand = _clip_frame(FigurePoses.CLIP_STAND, 0.0)
	_stand_globals = _globals(_stand)
	_current = _wanted()
	_settled = true
	_apply(_current, true)
	_height = skinned_aabb().end.y


func _process(delta: float) -> void:
	advance(delta * speed)


## Transition step: the bones go from the frame the rig was in at the pose change to the
## pose frame over the transition time, along a smoothed curve — and arrive exactly on time.
## Called from [method Node._process]; exposed to tests because the frame
## length in a headless run is not 1/60 but "whatever it turns out".
func advance(delta: float) -> void:
	if _skeleton == null:
		return
	# A still target — a code pose, the end of a clip: having reached it, the rig freezes.
	# Checked before the clock step: a "once" clip manages to reach its last frame.
	# An aimed arm does not freeze: a crouching actor shoots without changing pose (ADR-0043,
	# decision 16), and lowers it when the shot is over.
	var frozen := _settled and _is_still() and not _aims() and not _aim_shown
	_pose_time += delta
	_clock += delta
	_turned += delta
	if frozen:
		return
	var wanted := _wanted()
	if not _settled:
		# A transition is a blend of the frame the rig left with the live frame of the target. The
		# clip keeps running during the transition: chasing it with smoothing, the rig
		# would trail the walk with a 15° lag and never catch up.
		var progress := _pose_time / _blend if _blend > 0.0 else 1.0
		_settled = _from == null or progress >= 1.0
		if not _settled:
			wanted = _from.blend(wanted, smoothstep(0.0, 1.0, progress))
	_current = wanted
	_apply(_current, false)


## Which pose to show. Names come from [ActorPose]; walking takes its phase from
## [method set_walk_phase] and runs as a clip.
func show_pose(pose_name: String) -> void:
	if pose_name == _pose_name:
		return
	var was_walking := _pose_name.begins_with("walk_")
	_pose_name = pose_name
	# Walk frames are one pose as a clip: a frame change does not restart the transition.
	if was_walking and pose_name.begins_with("walk_"):
		return
	_from = _current
	_pose_time = 0.0
	_blend = FigurePoses.blend_time(pose_name)
	_settled = false


## Walk phase, 0..[constant ActorPose.WALK_FRAMES]. The actor drives it itself; the rig
## accumulates its walk clock from its increments.
func set_walk_phase(phase: float) -> void:
	var step := phase - _walk_phase
	if step < 0.0:
		step += float(ActorPose.WALK_FRAMES)
	_walk_phase = phase
	_walk_clock += step / ActorPose.WALK_FPS


## Where the actor faces: -1 left, +1 right. Changing sides is a body turnaround over
## [constant MoveLocks.TURN_TIME]: the actor stands still for as long. Called
## every frame; the turn accumulates on the rig's clock and is set here so the actor
## can turn the body further on top (Otto at the car turns his back to the camera).
##
## [param instant] — face at once, without a turnaround: this is how a killed agent
## falls when [Enemy] flips him so the body drops onto the floor, not over the opening.
## A turnaround is the motion of the living, and a corpse spinning like a top as it falls
## would be a bug.
func face(direction: float, instant: bool = false) -> void:
	var wanted := FACE_RIGHT if direction >= 0.0 else -FACE_RIGHT
	if not _faced or instant:
		_faced = true
		_yaw_from = wanted
		_yaw_to = wanted
	elif not is_equal_approx(wanted, _yaw_to):
		_yaw_from = rotation.y
		_yaw_to = wanted
		_turned = 0.0
	var progress := clampf(_turned / MoveLocks.TURN_TIME, 0.0, 1.0)
	rotation.y = lerpf(_yaw_from, _yaw_to, smoothstep(0.0, 1.0, progress))


## Transparency of all meshes: 0 — solid, 1 — invisible. This is how an invulnerable blinks.
func set_transparency(value: float) -> void:
	for mesh_instance in _meshes:
		mesh_instance.transparency = value


## Cuts away everything between [param from_x] and [param to_x] above [param bottom], in
## world coordinates: this is how the cab floor cuts the body ([CarCut]).
func carve_under(from_x: float, to_x: float, bottom: float) -> void:
	_carved = Vector4(from_x, to_x, bottom, 1.0)
	_cut_materials()
	for mesh_instance in _meshes:
		mesh_instance.set_instance_shader_parameter(&"carve", _carved)


## Hides bones [param names] and everything they pull: this is how a body part cut off
## from the ragdoll ([Ragdoll]) disappears. An empty list — everything visible.
func hide_bones(names: PackedStringArray) -> void:
	if not names.is_empty():
		_cut_materials()
	for mesh_instance in _meshes:
		var mask := Vector2i.ZERO
		var skin := mesh_instance.skin
		if skin != null:
			for bind in skin.get_bind_count():
				var bone := skin.get_bind_bone(bind)
				var bone_name := (
					_skeleton.get_bone_name(bone) if bone >= 0 else String(skin.get_bind_name(bind))
				)
				if names.has(bone_name):
					if bind < 32:
						mask.x |= 1 << bind
					else:
						mask.y |= 1 << (bind - 32)
		mesh_instance.set_instance_shader_parameter(&"hidden_bones", mask)


## Where the pistol muzzle is now, in the world; NAN if there is no pistol.
func muzzle_position() -> Vector3:
	var hand := _skeleton.find_bone(GUN_HAND) if _skeleton != null else -1
	if hand < 0 or is_nan(_muzzle.x):
		return Vector3(NAN, NAN, NAN)
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(hand) * _muzzle


## The figure's skeleton: the ragdoll is built on it.
func skeleton() -> Skeleton3D:
	return _skeleton


## Returns everything cut off to the body: a respawned Otto is whole.
func heal() -> void:
	_carved = Vector4.ZERO
	for mesh_instance in _meshes:
		# The cut is an instance parameter, not a material one: removing the material does not
		# take it away, and the next body cut would bring back the old one too.
		mesh_instance.set_instance_shader_parameter(&"carve", _carved)
		for surface in mesh_instance.mesh.get_surface_count():
			mesh_instance.set_surface_override_material(surface, null)


## Takes the pose of [param other] bone for bone, with its cut, and freezes: this way a
## torn-off piece starts as what it was in the body.
func copy_pose_of(other: FigureRig) -> void:
	if _skeleton == null or other._skeleton == null:
		return
	for bone in _skeleton.get_bone_count():
		_skeleton.set_bone_pose(bone, other._skeleton.get_bone_pose(bone))
	rotation = other.rotation
	if other._carved.w > 0.0:
		carve_under(other._carved.x, other._carved.y, other._carved.z)
	set_process(false)


## Gives the meshes cut-capable materials instead of the pack ones — once.
func _cut_materials() -> void:
	for mesh_instance in _meshes:
		if mesh_instance.get_surface_override_material(0) != null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.get_active_material(surface)
			mesh_instance.set_surface_override_material(surface, _carve_material(source))


static func _carve_material(source: Material) -> ShaderMaterial:
	if _carve_materials.has(source):
		return _carve_materials[source] as ShaderMaterial
	var material := ShaderMaterial.new()
	material.shader = CARVE_SHADER
	var standard := source as BaseMaterial3D
	if standard != null:
		material.set_shader_parameter(&"albedo", standard.albedo_color)
		material.set_shader_parameter(&"use_vertex_color", standard.vertex_color_use_as_albedo)
		material.set_shader_parameter(&"roughness", standard.roughness)
		material.set_shader_parameter(&"specular", standard.metallic_specular)
	_carve_materials[source] = material
	return material


## Brings the rig to the target pose at once, without smoothing. Needed by tests and capture:
## a frame must show the pose, not the way to it.
func snap() -> void:
	if _skeleton == null:
		return
	_current = _wanted()
	_settled = true
	_turned = MoveLocks.TURN_TIME
	if _faced:
		rotation.y = _yaw_to
	_apply(_current, true)


## Whether the transition to the current pose is over. For tests: a rig that never arrives
## would walk bones and vertices every frame until the actor's end.
func settled() -> bool:
	return _settled


## Bone rotation in the current frame, as the skeleton sees it. For tests: it shows
## that a transition is motion, not a swap.
func bone_rotation(bone_name: String) -> Quaternion:
	if _skeleton == null or _skeleton.find_bone(bone_name) < 0:
		return Quaternion.IDENTITY
	return _skeleton.get_bone_pose_rotation(_skeleton.find_bone(bone_name))


## Bone rotation in the target pose frame — where the rig leads the skeleton.
func target_rotation(bone_name: String) -> Quaternion:
	var bone := _skeleton.find_bone(bone_name) if _skeleton != null else -1
	if bone < 0:
		return Quaternion.IDENTITY
	return _wanted().rotations[bone]


## Figure height at rest, m.
func height() -> float:
	return _height


## Figure bounds in its current pose, in node coordinates.
##
## Computed from the vertices themselves, run through the skeleton:
## [method MeshInstance3D.get_aabb] of a skinned mesh returns the rest pose, not the
## current one, and by it a crouching actor would stand at full height. This is exactly
## how the test checks that the crouch fits under a bullet.
## [param hull_only] — only the extreme bone vertices: this is how the rig grounds at runtime.
## The bottom by them matches the full one to a centimetre, the top does not (hat brim), and
## only the bottom of such bounds may be used.
func skinned_aabb(hull_only: bool = false) -> AABB:
	var box := AABB()
	var first := true
	for surface in _surfaces:
		var to_rig := global_transform.affine_inverse() * surface.mesh_instance.global_transform
		var binds: Array[Transform3D] = []
		if surface.per_vertex > 0:
			binds = _bind_poses(surface.mesh_instance.skin)
		var indices := surface.hull if hull_only else PackedInt32Array()
		var count := indices.size() if hull_only else surface.vertices.size()
		for slot in count:
			var index := indices[slot] if hull_only else slot
			var vertex := surface.vertices[index]
			if surface.per_vertex > 0:
				vertex = _skinned(vertex, index, surface, binds)
			var placed := to_rig * vertex
			if first:
				box = AABB(placed, Vector3.ZERO)
				first = false
			else:
				box = box.expand(placed)
	return box


## Skin matrices for this frame: bone pose × binding, one per binding.
## Computed once per surface, not for each of its hundreds of vertices.
func _bind_poses(skin: Skin) -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	for bind in skin.get_bind_count():
		# glTF import binds by bone index; the name is a fallback for a
		# hand-built skin. A binding without a bone leaves the vertex at rest.
		var bone := skin.get_bind_bone(bind)
		if bone < 0:
			bone = _skeleton.find_bone(skin.get_bind_name(bind))
		var pose := _skeleton.get_bone_global_pose(bone) if bone >= 0 else Transform3D.IDENTITY
		poses.append(pose * skin.get_bind_pose(bind))
	return poses


## A vertex run through the skeleton: sum over bones of weight × (pose × binding).
func _skinned(
	vertex: Vector3, index: int, surface: SkinnedSurface, binds: Array[Transform3D]
) -> Vector3:
	var result := Vector3.ZERO
	var per_vertex := surface.per_vertex
	for slot in per_vertex:
		var weight := surface.weights[index * per_vertex + slot]
		if weight <= 0.0:
			continue
		result += (binds[surface.bone_ids[index * per_vertex + slot]] * vertex) * weight
	return result


## Model clips by the names [constant FigurePoses.CLIP_NAMES], split into
## bone tracks. A missing clip is an error: the pose falls back to the stance, but it must
## be visible.
func _read_clips() -> void:
	var players := _instance.find_children("*", "AnimationPlayer", true, false)
	var player := players[0] as AnimationPlayer if not players.is_empty() else null
	for clip_name in FigurePoses.CLIP_NAMES:
		if player == null or not player.has_animation(clip_name):
			push_error("the model has no clip %s: %s" % [clip_name, model.resource_path])
			continue
		var tracks := ClipTracks.new()
		tracks.animation = player.get_animation(clip_name)
		for track in tracks.animation.get_track_count():
			var bone := _skeleton.find_bone(
				String(tracks.animation.track_get_path(track).get_concatenated_subnames())
			)
			if bone < 0:
				continue
			match tracks.animation.track_get_type(track):
				Animation.TYPE_ROTATION_3D:
					tracks.rotation_tracks.append(track)
					tracks.rotation_bones.append(bone)
				Animation.TYPE_POSITION_3D:
					tracks.position_tracks.append(track)
					tracks.position_bones.append(bone)
		_clips[clip_name] = tracks


## Rest frame of the skeleton: the base the clip tracks are layered on.
func _read_rest() -> Frame:
	var frame := Frame.new()
	var count := _skeleton.get_bone_count()
	frame.rotations.resize(count)
	frame.positions.resize(count)
	for bone in count:
		var rest := _skeleton.get_bone_rest(bone)
		frame.rotations[bone] = rest.basis.get_rotation_quaternion()
		frame.positions[bone] = rest.origin
	return frame


## Clip frame at moment [param time], s.
func _clip_frame(clip_name: String, time: float) -> Frame:
	var frame := _rest.copy()
	if not _clips.has(clip_name):
		return frame
	var tracks := _clips[clip_name] as ClipTracks
	var animation := tracks.animation
	var at := clampf(time, 0.0, animation.length)
	for slot in tracks.rotation_tracks.size():
		frame.rotations[tracks.rotation_bones[slot]] = animation.rotation_track_interpolate(
			tracks.rotation_tracks[slot], at
		)
	for slot in tracks.position_tracks.size():
		frame.positions[tracks.position_bones[slot]] = animation.position_track_interpolate(
			tracks.position_tracks[slot], at
		)
	return frame


## The frame the rig is leading the skeleton to now.
func _wanted() -> Frame:
	var clip := FigurePoses.clip_of(_pose_name)
	if clip == null or not _clips.has(clip.name):
		return _code_frame(_pose_name)
	var length := (_clips[clip.name] as ClipTracks).length()
	var time := 0.0
	match clip.mode:
		FigurePoses.Clip.LOOP:
			time = fmod(_clock * clip.rate, length)
		FigurePoses.Clip.ONCE:
			time = minf(clip.start + _pose_time * clip.rate, length)
		FigurePoses.Clip.END:
			time = length
		FigurePoses.Clip.WALK:
			time = fmod(_walk_clock * FigurePoses.WALK_CLIP_RATE, length)
	return _clip_frame(clip.name, time)


## Whether the target is still: a code pose, the end of a clip, a "once" clip played
## to its last frame. Stance and walk always run.
func _is_still() -> bool:
	var clip := FigurePoses.clip_of(_pose_name)
	if clip == null or not _clips.has(clip.name):
		return true
	match clip.mode:
		FigurePoses.Clip.END:
			return true
		FigurePoses.Clip.ONCE:
			return clip.start + _pose_time * clip.rate >= (_clips[clip.name] as ClipTracks).length()
	return false


## Whether the pose stands on the floor by itself: stance and walk do. Since M24c
## `build_actors.py` grounds every frame of every clip by vertices (ADR-0039), but does it
## before the agent gets the fedora: standing, it is on top and changes nothing, but
## an agent lying on his back sank 9 cm into the floor with the brim (code review M24c).
## "Once" clips and the end of a clip are grounded like a code pose: at runtime by the
## extreme vertices, and a finished clip is not applied by the rig at all anymore.
func _grounded_by_the_clip() -> bool:
	var clip := FigurePoses.clip_of(_pose_name)
	if clip == null or not _clips.has(clip.name):
		return false
	return clip.mode == FigurePoses.Clip.LOOP or clip.mode == FigurePoses.Clip.WALK


## Frame of a code pose: the stance with the angles of [FigurePoses.Pose] applied.
func _code_frame(pose_name: String) -> Frame:
	var key := pose_name if FigurePoses.clip_of(pose_name) == null else "stand"
	if _code_frames.has(key):
		return _code_frames[key]
	var pose := FigurePoses.of(key)
	var frame := _stand.copy()
	_swing(frame, LEG_L, pose.legs.x)
	_swing(frame, LEG_R, pose.legs.y)
	# Sideways — around the model's gaze axis: the left leg goes left, the right one right.
	_turn(frame, LEG_L, Vector3.BACK, pose.spread)
	_turn(frame, LEG_R, Vector3.BACK, -pose.spread)
	# The knee bends backwards: for a bone growing downwards this is "forward" with a minus.
	_swing(frame, KNEE_L, -pose.knees.x)
	_swing(frame, KNEE_R, -pose.knees.y)
	_swing(frame, ARM_L, pose.arms.x)
	_swing(frame, ARM_R, pose.arms.y)
	_swing(frame, ELBOW_L, pose.elbows.x)
	_swing(frame, ELBOW_R, pose.elbows.y)
	_turn(frame, ARM_L, Vector3.BACK, -pose.reach_in)
	_turn(frame, ARM_R, Vector3.BACK, pose.reach_in)
	for bone_name: String in LEAN_SHARE:
		_swing(frame, bone_name, pose.lean * float(LEAN_SHARE[bone_name]))
	for bone_name: String in HEAD_SHARE:
		_swing(frame, bone_name, pose.head * float(HEAD_SHARE[bone_name]))
		_turn(frame, bone_name, Vector3.UP, pose.twist * float(HEAD_SHARE[bone_name]))
	_follow_feet(frame)
	frame.tilt = pose.tilt
	frame.lift = pose.lift
	frame.squash = pose.squash
	_code_frames[key] = frame
	return frame


## Rotates a bone by a forward angle around the figure's side axis.
##
## The axis is taken not from the bone but from the figure — the model's X — and converted
## into the bone's space by its position in the stance. The roll and axes of the pack bones
## do not matter to the pose table, and the parent's rotation around the same axis adds up
## with the child's: the knee bends from an already swung thigh.
##
## "Forward" for a bone growing upwards (torso, head) is a rotation around +X, for one
## growing downwards (legs, arms) — around −X: the same rotation would take it backwards.
func _swing(frame: Frame, bone_name: String, degrees: float) -> void:
	if not _bones.has(bone_name):
		return
	var bone: int = _bones[bone_name]
	var upward := _stand_globals[bone].basis.y.y >= 0.0
	_turn(frame, bone_name, Vector3.RIGHT if upward else Vector3.LEFT, degrees)


## Rotates a bone around the figure axis [param model_axis] — a model axis
## converted into the bone's space by its position in the stance. Forward is
## [method _swing]; around the vertical — the head turned sideways, a broken neck
## (ADR-0040).
func _turn(frame: Frame, bone_name: String, model_axis: Vector3, degrees: float) -> void:
	if not _bones.has(bone_name) or is_zero_approx(degrees):
		return
	var bone: int = _bones[bone_name]
	var axis := _stand_globals[bone].basis.inverse() * model_axis
	frame.rotations[bone] = (
		frame.rotations[bone] * Quaternion(axis.normalized(), deg_to_rad(degrees))
	)


## Puts the feet on the ends of the shins: as they stood relative to each other in the stance.
func _follow_feet(frame: Frame) -> void:
	var globals := _globals(frame)
	for pair: Array in [[KNEE_L, FOOT_L], [KNEE_R, FOOT_R]]:
		if not (_bones.has(pair[0]) and _bones.has(pair[1])):
			continue
		var knee: int = _bones[pair[0]]
		var foot: int = _bones[pair[1]]
		var held := _stand_globals[knee].affine_inverse() * _stand_globals[foot]
		var placed := globals[knee] * held
		var parent := _skeleton.get_bone_parent(foot)
		var local := globals[parent].affine_inverse() * placed if parent >= 0 else placed
		frame.rotations[foot] = local.basis.get_rotation_quaternion()
		frame.positions[foot] = local.origin


## Pistol muzzle in hand space: the end of the barrel towards the fingers. The barrel
## is built along rest −X (T-pose, fingers to −X), and the muzzle is the middle of its end.
func _find_muzzle() -> Vector3:
	var hand := _skeleton.find_bone(GUN_HAND)
	if hand < 0:
		return Vector3(NAN, NAN, NAN)
	for surface in _surfaces:
		var material := surface.mesh_instance.mesh.surface_get_material(surface.index)
		if material == null or material.resource_name != "gun":
			continue
		var tip := INF
		for vertex in surface.vertices:
			tip = minf(tip, vertex.x)
		var end := Vector3.ZERO
		var count := 0
		for vertex in surface.vertices:
			if vertex.x < tip + 0.01:
				end += vertex
				count += 1
		end /= float(maxi(count, 1))
		return _skeleton.get_bone_global_rest(hand).affine_inverse() * end
	return Vector3(NAN, NAN, NAN)


## A frame with the arm aimed at the bullet's exit point (ADR-0043, decision 16).
##
## The right upper arm and forearm turn so that the muzzle lands at the
## point [member aim_height] above the feet and [member aim_reach] ahead; the left
## holds the grip from below. Sideways the arms stay where they were: the bullet flies in
## the play plane, and the frame does not see it sideways.
func _aimed(frame: Frame) -> Frame:
	var hand := _skeleton.find_bone(GUN_HAND)
	var support := _skeleton.find_bone(SUPPORT_HAND)
	if not _bones.has(ARM_R) or not _bones.has(ELBOW_R) or hand < 0:
		return frame
	var aimed := frame.copy()
	# The exit point in skeleton space — via the world: between the rig and the skeleton lie
	# the model with its offset above the floor and the armature node.
	var to_skeleton := _skeleton.global_transform.affine_inverse() * global_transform
	var target := to_skeleton * Vector3(0.0, aim_height, aim_reach)
	_reach(aimed, _bones[ARM_R], _bones[ELBOW_R], hand, _muzzle, target)
	# The second hand holds the grip from below: hand to hand with the pistol.
	if support >= 0 and _bones.has(ARM_L) and _bones.has(ELBOW_L):
		var grip := _globals(aimed)[hand].origin + Vector3(0.0, -SUPPORT_DROP, 0.0)
		_reach(aimed, _bones[ARM_L], _bones[ELBOW_L], support, Vector3.ZERO, grip)
	return aimed


## Brings the end of the arm — point [param tip] in the space of bone [param end] — to
## [param target]: the shoulder and elbow turn in the gaze plane (Y —
## up, Z — model forward), sideways the arm stays where it was. The elbow goes below
## the shoulder–target line.
func _reach(
	frame: Frame, shoulder_bone: int, elbow_bone: int, end: int, tip: Vector3, target: Vector3
) -> void:
	var globals := _globals(frame)
	var shoulder := globals[shoulder_bone].origin
	var elbow := globals[elbow_bone].origin
	var point := globals[end] * tip
	target.x = point.x
	var upper := _flat(elbow - shoulder)
	var lower := _flat(point - elbow)
	var reach := Vector2(target.z - shoulder.z, target.y - shoulder.y)
	var span := clampf(reach.length(), absf(upper - lower) + 0.001, upper + lower - 0.001)
	var toward := reach.normalized()
	var bend := acos(
		clampf((upper * upper + span * span - lower * lower) / (2.0 * upper * span), -1.0, 1.0)
	)
	var elbow_dir := toward.rotated(-bend)
	var wanted := Vector3(
		elbow.x, shoulder.y + elbow_dir.y * upper, shoulder.z + elbow_dir.x * upper
	)
	_turn_bone(frame, globals, shoulder_bone, elbow - shoulder, wanted - shoulder)
	globals = _globals(frame)
	elbow = globals[elbow_bone].origin
	point = globals[end] * tip
	_turn_bone(frame, globals, elbow_bone, point - elbow, target - elbow)


## Length of a segment in the gaze plane: without the sideways offset.
static func _flat(offset: Vector3) -> float:
	return Vector2(offset.z, offset.y).length()


## Rotates bone [param bone] of the frame so that its segment [param from]
## points along [param to]; both in skeleton space.
func _turn_bone(
	frame: Frame, globals: Array[Transform3D], bone: int, from: Vector3, to: Vector3
) -> void:
	if from.is_zero_approx() or to.is_zero_approx():
		return
	var turn := Quaternion(from.normalized(), to.normalized())
	var parent := _skeleton.get_bone_parent(bone)
	var parent_basis := globals[parent].basis if parent >= 0 else Basis()
	var turned := Basis(turn) * globals[bone].basis
	frame.rotations[bone] = (parent_basis.inverse() * turned).get_rotation_quaternion()


## Bone positions in skeleton space for a frame — along the parent chain.
func _globals(frame: Frame) -> Array[Transform3D]:
	var globals: Array[Transform3D] = []
	globals.resize(frame.rotations.size())
	for bone in frame.rotations.size():
		var local := Transform3D(Basis(frame.rotations[bone]), frame.positions[bone])
		var parent := _skeleton.get_bone_parent(bone)
		# In a glTF skeleton the parent always comes before the child: import order.
		globals[bone] = globals[parent] * local if parent >= 0 else local
	return globals


## Applies a frame to the bones and to the model itself.
##
## [param exact] — ground by all vertices, not by the extreme ones: for shots and
## tests. At runtime the extreme ones suffice, and the stance and walk the rig has already
## reached are not grounded at all — `build_actors.py` put them on the floor. Grounded are
## a code pose, "once" clips and the end of a clip ([method _grounded_by_the_clip]) and
## a transition: a blend of two frames on the floor does not stand by itself.
func _apply(frame: Frame, exact: bool) -> void:
	_pose_bones(frame)

	# Forward tilt around the heels: the model origin is at the feet, and a rotation around X
	# puts the top of the head towards +Z, i.e. along the gaze. A crushed actor is flattened in
	# height and spreads in width: the body volume does not go anywhere.
	var widen := 1.0 + (1.0 - frame.squash) * 0.36
	_instance.rotation.x = deg_to_rad(frame.tilt)
	_instance.scale = Vector3(widen, frame.squash, widen)
	_instance.position.y = 0.0
	if not (_settled and not exact and _grounded_by_the_clip()):
		_skeleton.force_update_all_bone_transforms()
		# Grounding: the pose stands on the floor by its lowest point. Someone lying on his back
		# rests on the back, someone lying prone on the chest, a crouching one on the soles, and
		# each has its own depth.
		var low := skinned_aabb(not exact).position.y
		_instance.position.y = -low + frame.lift * _height
	# The arm is aimed after grounding: the exit point is above the floor, and the model has
	# just been put on the floor. The arm does not change the pose's lowest point.
	_aim_shown = _aims()
	if _aim_shown:
		_pose_bones(_aimed(frame))


## Whether to aim the arm: the actor is shooting, and the figure has a pistol.
func _aims() -> bool:
	return not is_nan(aim_height) and not is_nan(_muzzle.x)


func _pose_bones(frame: Frame) -> void:
	for bone in frame.rotations.size():
		_skeleton.set_bone_pose_rotation(bone, frame.rotations[bone])
		_skeleton.set_bone_pose_position(bone, frame.positions[bone])
