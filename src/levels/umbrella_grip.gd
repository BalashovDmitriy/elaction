class_name UmbrellaGrip
extends SkeletonModifier3D

## A pedestrian carries an umbrella (ADR-0054, decision 11; user remarks:
## "a person must carry the umbrella, not have an umbrella model moving along with the
## person", "the hand does not hold the umbrella").
##
## On top of the pack's walk, one arm holds the shaft the way an umbrella is held: the
## elbow bent and pressed in, the forearm forward and slightly up, the hand at the lower
## ribs with fingers up along the shaft, the fingers clenched into a fist around it. The
## shaft passes through the middle of the fist and stands plumb; the umbrella sways with
## the step because the hand follows the chest. The left arm still swings.
##
## The modifier runs after the animation ([SkeletonModifier3D]): the pack's walk sets
## the pose, the grip fixes one arm in it. All points are in world axes, and a bone
## rotation goes from its current direction to the desired one: the skeleton axes of an
## imported model do not match the axes of the model itself.

## Where the hand is relative to the chest, fractions of height: forward, down, and what
## fraction of the distance to its shoulder sideways.
const HAND_FORWARD: float = 0.12
const HAND_DOWN: float = 0.03
## How far the hand rises when the umbrella is raised over an oncoming pedestrian,
## fractions of height, and how fast, fractions per second.
const RAISE: float = 0.17
const RAISE_RATE: float = 2.5
const HAND_SIDE: float = 0.8
## Where the elbow goes: down, back and outward, as fractions.
const ELBOW_DOWN: float = 1.0
const ELBOW_BACK: float = 0.6
const ELBOW_OUT: float = 0.3
## Where in the hand the middle of the fist is: the fraction of the way from the wrist to
## the base of the middle finger.
const PALM: float = 0.85
## How far the shaft sticks out below the fist, fractions of height.
const BELOW_FIST: float = 0.05
## Height of the pack model in its own units.
const MODEL_HEIGHT: float = 1.85

## Fingers: by joints from the palm, the last one is the fingertip; the arm side is
## given by the name suffix.
const FINGERS: Array[Array] = [
	["Index1", "Index2", "Index3", "Index4"],
	["Middle1", "Middle2", "Middle3", "Middle4"],
	["Ring1", "Ring2", "Ring3", "Ring4"],
	["Pinky1", "Pinky2", "Pinky3", "Pinky4"],
	["Thumb1", "Thumb2", "Thumb3"],
]

## The umbrella: its origin is the bottom of the shaft, below the fist.
var umbrella: Node3D = null
## Where the pedestrian is heading, world axes; set by the street.
var forward := Vector3.FORWARD
## Which hand holds it: "R" or "L". The street gives the umbrella to the hand closer to
## the camera: in the far hand the fist is hidden by the torso, and the shaft seemed to
## grow out of the shoulder.
var side: String = "R"
## Whether to raise the umbrella over an oncoming pedestrian: the sidewalk is narrow,
## and the canopies of oncoming people overlap in depth, so whoever walks by the shop
## windows raises theirs over the neighbor's, as people do. Set by the street; the arm
## moves to it smoothly.
var raised: bool = false
## Where the fist and the bottom of the shaft ended up in the last frame, world axes, for
## the test: outside the modifier the skeleton returns the animation pose without the fix.
var last_fist := Vector3.ZERO
var last_pole := Vector3.ZERO

var _chest: int = -1
var _upper: int = -1
var _lower: int = -1
var _wrist: int = -1
var _middle: int = -1
var _fingers: Array[PackedInt32Array] = []
var _lift: float = 0.0


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_chest = skeleton.find_bone("Chest")
	_upper = skeleton.find_bone("UpperArm." + side)
	_lower = skeleton.find_bone("LowerArm." + side)
	_wrist = skeleton.find_bone("Wrist." + side)
	_middle = skeleton.find_bone("Middle1." + side)
	for chain: Array in FINGERS:
		var bones := PackedInt32Array()
		for bone_name: String in chain:
			bones.append(skeleton.find_bone(bone_name + "." + side))
		if not bones.has(-1):
			_fingers.append(bones)


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if mini(mini(_chest, _upper), mini(mini(_lower, _wrist), _middle)) < 0:
		return
	var to_bones := skeleton.global_transform.affine_inverse()
	var tall := skeleton.global_transform.basis.get_scale().y * MODEL_HEIGHT
	var chest := _at(skeleton, _chest)
	var shoulder := _at(skeleton, _upper)
	var upper_length := shoulder.distance_to(_at(skeleton, _lower))
	var lower_length := _at(skeleton, _lower).distance_to(_at(skeleton, _wrist))
	var ahead := Vector3(forward.x, 0.0, forward.z).normalized()
	var aside := shoulder - chest
	aside = Vector3(aside.x, 0.0, aside.z)
	aside -= ahead * aside.dot(ahead)
	var step := RAISE_RATE * get_process_delta_time()
	_lift = move_toward(_lift, 1.0 if raised else 0.0, step)
	var down := HAND_DOWN - RAISE * smoothstep(0.0, 1.0, _lift)
	var target := (
		chest + ahead * HAND_FORWARD * tall + Vector3.DOWN * down * tall + aside * HAND_SIDE
	)
	var reach := clampf(shoulder.distance_to(target), 0.01, (upper_length + lower_length) * 0.999)
	var along := (target - shoulder).normalized()
	var across := upper_length * upper_length - lower_length * lower_length + reach * reach
	var to_elbow := across / (2.0 * reach)
	var lift := sqrt(maxf(upper_length * upper_length - to_elbow * to_elbow, 0.0))
	var pole := Vector3.DOWN * ELBOW_DOWN - ahead * ELBOW_BACK + aside.normalized() * ELBOW_OUT
	pole -= along * pole.dot(along)
	var elbow := shoulder + along * to_elbow + pole.normalized() * lift
	var wrist := shoulder + along * reach
	_aim(skeleton, _upper, _lower, to_bones * elbow)
	_aim(skeleton, _lower, _wrist, to_bones * wrist)
	# The hand with fingers up along the shaft, slightly forward: this is how an umbrella
	# handle is held.
	var hand_length := _at(skeleton, _wrist).distance_to(_at(skeleton, _middle))
	var up_the_pole := (Vector3.UP + ahead * 0.25).normalized()
	_aim(skeleton, _wrist, _middle, to_bones * (wrist + up_the_pole * hand_length))
	var fist := wrist + (_at(skeleton, _middle) - wrist) * PALM
	# Fingers into a fist: each joint reaches for the shaft, on its axis below the fist.
	var hold := fist + Vector3.DOWN * hand_length * 0.15
	for chain in _fingers:
		for index in chain.size() - 1:
			_aim(skeleton, chain[index], chain[index + 1], to_bones * hold)
	last_fist = fist
	last_pole = fist + Vector3.DOWN * BELOW_FIST * tall
	if umbrella != null:
		umbrella.global_position = last_pole


func _at(skeleton: Skeleton3D, bone: int) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin


## Rotates bone [param bone] so that its child [param child] comes to [param point],
## skeleton axes. The rotation goes from the bone's current direction to the desired
## one: this way it does not depend on which axis the pack lays bones along.
func _aim(skeleton: Skeleton3D, bone: int, child: int, point: Vector3) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var now := (skeleton.get_bone_global_pose(child).origin - pose.origin).normalized()
	var wanted := (point - pose.origin).normalized()
	if now.is_zero_approx() or wanted.is_zero_approx():
		return
	var turn := Quaternion(now, wanted)
	skeleton.set_bone_global_pose(bone, Transform3D(Basis(turn) * pose.basis, pose.origin))
