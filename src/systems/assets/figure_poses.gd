class_name FigurePoses
extends RefCounted

## Figure poses: what plays each [ActorPose] pose.
##
## Since M21 (ADR-0032, decision 1) poses are of two kinds. Where the ROM does not
## dictate heights, a clip moves, since M24c from the Universal Animation Library
## (ADR-0039): stance, walk, shot, death, push-off, flight and landing, blows and
## reactions of takedown scenes (ADR-0040). Where it does dictate, a pose in code from
## this table: the crouch and lying down under ROM bullets, the crushed one; and takedown
## poses that no free library has: a grab, a choke, a broken neck.
##
## A pose in code is built not from the skeleton rest but from the first frame of the
## stance: the pack's rest is a T-pose with arms out to the sides. Angles are in degrees,
## **positive moves a limb forward**, in the direction of the gaze; a knee bends with a
## positive angle (the shin goes back), so does an elbow (the forearm goes forward). Torso
## and body forward tilts are positive; an agent lying down under a bullet is tilted
## forward.
##
## No nodes, no scene: checked with the same technique as [OttoStateMachine].


## One pose in code.
class Pose:
	extends RefCounted

	## Hips, knees, shoulders, elbows: left, right.
	var legs := Vector2.ZERO
	var knees := Vector2.ZERO
	var arms := Vector2.ZERO
	var elbows := Vector2.ZERO
	## Forward tilt of the torso from the pelvis.
	var lean: float = 0.0
	## Forward tilt of the head relative to the torso.
	var head: float = 0.0
	## Sideways head turn, around the vertical: a broken neck (ADR-0040).
	var twist: float = 0.0
	## Tilt of the whole body around the heels: 90 means lying face forward.
	var tilt: float = 0.0
	## Lift of the whole body above the floor, in fractions of height, beyond grounding: the
	## rig itself puts any pose on the floor by its bounds, and this is an addition to that.
	var lift: float = 0.0
	## Height squash: the crushed one is 0.3.
	var squash: float = 1.0
	## Spreading the legs sideways from the stance, degrees: below zero means together. The
	## pack's stance has the legs apart, while one hanging on the rope keeps the legs together.
	var spread: float = 0.0
	## Bringing the arms toward the body's middle, degrees: one hanging holds the rope with
	## his hands above the head, while the pack's stance spreads the arms.
	var reach_in: float = 0.0

	static func make(leg_angles: Vector2, arm_angles: Vector2) -> Pose:
		var pose := Pose.new()
		pose.legs = leg_angles
		pose.arms = arm_angles
		return pose

	## Bend of the knees and elbows. Returns itself: poses are built as a chain.
	func bent_at(knee_angles: Vector2, elbow_angles: Vector2 = Vector2.ZERO) -> Pose:
		knees = knee_angles
		elbows = elbow_angles
		return self

	## Torso and head tilt.
	func leaned(torso_lean: float, head_tilt: float = 0.0) -> Pose:
		lean = torso_lean
		head = head_tilt
		return self

	## Sideways head turn.
	func twisted(head_twist: float) -> Pose:
		twist = head_twist
		return self

	## Legs apart or together.
	func spread_by(degrees: float) -> Pose:
		spread = degrees
		return self

	## Arms toward the body's middle.
	func reached_in(degrees: float) -> Pose:
		reach_in = degrees
		return self

	## Tilt of the whole body around the heels.
	func tilted(body_tilt: float) -> Pose:
		tilt = body_tilt
		return self

	## Lift above the floor.
	func lifted(body_lift: float) -> Pose:
		lift = body_lift
		return self

	## Height squash.
	func squashed(height_squash: float) -> Pose:
		squash = height_squash
		return self

	## Its own copy: the pose table is shared, and an actor works with its own.
	func copy() -> Pose:
		var twin := Pose.make(legs, arms).bent_at(knees, elbows).leaned(lean, head)
		return (
			twin
			. twisted(twist)
			. tilted(tilt)
			. lifted(lift)
			. squashed(squash)
			. spread_by(spread)
			. reached_in(reach_in)
		)


## A pack clip: which one and how to play it.
class Clip:
	extends RefCounted

	## Plays in a loop, by the rig's clock.
	const LOOP := 0
	## Plays once from the start of the pose and freezes on the last frame.
	const ONCE := 1
	## Stays on the last frame.
	const END := 2
	## Follows the actor's walk phase.
	const WALK := 3

	var name: String
	var mode: int
	## From which moment of the clip to start, s: the UAL push-off starts with a crouch
	## windup, and a jump in the game is instant.
	var start: float = 0.0
	## How many times faster than recorded to play.
	var rate: float = 1.0

	static func make(
		clip_name: String, clip_mode: int, from: float = 0.0, speed: float = 1.0
	) -> Clip:
		var clip := Clip.new()
		clip.name = clip_name
		clip.mode = clip_mode
		clip.start = from
		clip.rate = speed
		return clip


## Clip names in the `.glb`, as written by `tools/build_actors.py`.
## Since M24c the clips are from the Universal Animation Library, retargeted to the
## pack skeleton (ADR-0039, decision 1).
##
## A neutral stance, arms down: the base of poses in code. It is not played in the frame:
## the in-game stance holds the pistol with both hands, and arm angles relative to it
## would mean nothing.
const CLIP_STAND := "stand"
const CLIP_IDLE := "idle"
const CLIP_WALK := "walk"
const CLIP_SHOOT := "shoot"
const CLIP_DEATH := "death"
const CLIP_JUMP_START := "jump_start"
const CLIP_JUMP_AIR := "jump_air"
const CLIP_JUMP_LAND := "jump_land"
## Takedown scene clips (ADR-0040): Otto's blows and the agent's reactions.
const CLIP_PUNCH_JAB := "punch_jab"
const CLIP_PUNCH_CROSS := "punch_cross"
const CLIP_HIT_HEAD := "hit_head"
const CLIP_HIT_CHEST := "hit_chest"
const CLIP_KNOCKBACK := "knockback"
const CLIP_NAMES: PackedStringArray = [
	CLIP_STAND,
	CLIP_IDLE,
	CLIP_WALK,
	CLIP_SHOOT,
	CLIP_DEATH,
	CLIP_JUMP_START,
	CLIP_JUMP_AIR,
	CLIP_JUMP_LAND,
	CLIP_PUNCH_JAB,
	CLIP_PUNCH_CROSS,
	CLIP_HIT_HEAD,
	CLIP_HIT_CHEST,
	CLIP_KNOCKBACK,
]

## The speed of the walk clip relative to the recorded one. The pack walks at
## a strolling pace, while Otto and the agent walk at 2.2 m/s (`Arcade.WALK_PX`): at the
## native speed the soles would slide over the floor. The multiplier is the actor's speed
## divided by the speed of the planted foot in the clip: it moves back at 1.27 m/s,
## measured by `tools/walk_stride.gd`.
const WALK_CLIP_RATE: float = 1.75

## UAL push-off: the first three frames (0.125 s) are a crouch before lift-off. A jump in
## the game is instant, and the clip starts from lift-off.
const JUMP_FROM: float = 0.125
## UAL landing sits in a deep crouch until 0.45 s and straightens up by 0.9 s:
## the very "knees" and "straightens up slowly" the player complained about.
## The clip runs from a half crouch and twice as fast: the floor contact is visible, but
## Otto does not sit on his knees. M24C shots: under a low ceiling the jump is short, and
## from the start of the clip Otto landed almost on his knees.
const LAND_FROM: float = 0.45
const LAND_RATE: float = 2.0
## How long to show the landing, s: as long as the clip runs from [constant LAND_FROM]
## to the stance. Longer means the stance, earlier means a step, if the pause has ended.
const LAND_SHOW: float = 0.225

## How long a transition into a pose lasts, s (ADR-0039, decision 5). The blend goes by
## time, not by a fading exponential: the transition ends instead of creeping closer.
## Into a landing and a shot almost at once: they are about the moment; into the stance,
## softer.
const BLEND_DEFAULT: float = 0.12
const BLEND_TIMES: Dictionary = {
	"idle": 0.15,
	"walk": 0.1,
	"shoot": 0.05,
	"jump": 0.06,
	"fall": 0.15,
	"land": 0.04,
	"crouch": 0.08,
	"prone": 0.12,
	"dead_0": 0.08,
	"dead_1": 0.3,
	"crushed": 0.05,
	"whip_raise": 0.16,
	"whip_strike": 0.06,
	"punch_jab": 0.06,
	"punch_cross": 0.06,
}

## Crouch: legs forward, knees folded, torso over the knees, head forward from under the
## hat. With the knees this is finally "squatting", not "bent over" (M18c debt).
## A test holds it by the skeleton bounds: Otto is under an agent's bullet and within the
## crouch collision of 1.08 m, a kneeling agent is under a standing Otto's bullet, 1.09
## by the lower edge.
const CROUCH_LEGS: float = 100.0
const CROUCH_KNEES: float = 140.0
const CROUCH_LEAN: float = 45.0
const CROUCH_HEAD: float = -10.0

static var _table: Dictionary = _build_table()
static var _clips: Dictionary = _build_clips()


## A pose in code by name from [ActorPose]. An unknown name and a clip pose give
## "stand", the first frame of the stance: an actor with no pose in the frame is worse
## than one in the wrong pose.
##
## Returns a copy: the builder methods modify the pose in place, and a table entry that
## got out would change for all actors at once.
static func of(pose_name: String) -> Pose:
	var found: Variant = _table.get(pose_name, _table["stand"])
	return (found as Pose).copy()


## The pose's clip, or null if the pose is in code.
static func clip_of(pose_name: String) -> Clip:
	if pose_name.begins_with("walk_"):
		return _clips["walk"] as Clip
	return _clips.get(pose_name) as Clip


## Whether the pose has an entry, in code or as a clip. By this the test checks the table
## against the [ActorPose] lists.
static func knows(pose_name: String) -> bool:
	return clip_of(pose_name) != null or _table.has(pose_name)


## How long a transition into a pose lasts, s. Walk frames are a single "walk" pose.
static func blend_time(pose_name: String) -> float:
	var key := "walk" if pose_name.begins_with("walk_") else pose_name
	return float(BLEND_TIMES.get(key, BLEND_DEFAULT))


static func _build_clips() -> Dictionary:
	return {
		"idle": Clip.make(CLIP_IDLE, Clip.LOOP),
		"walk": Clip.make(CLIP_WALK, Clip.WALK),
		"shoot": Clip.make(CLIP_SHOOT, Clip.ONCE),
		# A jump in three phases (ADR-0039): push-off as a clip, a kick in flight
		# as a pose in code (in the original the jump is the kick), landing as a clip.
		"jump": Clip.make(CLIP_JUMP_START, Clip.ONCE, JUMP_FROM),
		# Since M24d there is no kick (ADR-0040): on the descent, the UAL flight clip.
		"fall": Clip.make(CLIP_JUMP_AIR, Clip.LOOP),
		"land": Clip.make(CLIP_JUMP_LAND, Clip.ONCE, LAND_FROM, LAND_RATE),
		# Takedown scenes (ADR-0040). Blows start from the stance's momentum, without a windup
		# at the start of the clip: the scene is short.
		"punch_jab": Clip.make(CLIP_PUNCH_JAB, Clip.ONCE, 0.05, 1.3),
		"punch_cross": Clip.make(CLIP_PUNCH_CROSS, Clip.ONCE, 0.05, 1.3),
		"hit_head": Clip.make(CLIP_HIT_HEAD, Clip.ONCE, 0.0, 1.2),
		"hit_chest": Clip.make(CLIP_HIT_CHEST, Clip.ONCE, 0.0, 1.2),
		"knockback": Clip.make(CLIP_KNOCKBACK, Clip.ONCE, 0.0, 1.4),
		# Lies thrown back by the blow: the end of the throw is the scene's corpse.
		"knocked": Clip.make(CLIP_KNOCKBACK, Clip.END),
		# Death is shown with two poses (ADR-0011, item 12): the fall is the clip
		# from the start, the lying body is its last frame.
		"dead_0": Clip.make(CLIP_DEATH, Clip.ONCE),
		"dead_1": Clip.make(CLIP_DEATH, Clip.END),
	}


## Takedown poses (ADR-0040): a grab, a choke, a broken neck, a finishing blow from above.
## The scene places the agent right next to Otto, and the poses are designed for that
## distance: Otto's hands are at the neck height of an agent of the same height.
static func _add_takedown_poses(table: Dictionary) -> void:
	# A choke from behind: Otto's arms forward at neck level, elbows bent, the forearms
	# wrap around the throat; torso leaning back, legs braced.
	table["choke_hold"] = (
		Pose
		. make(Vector2(15.0, -12.0), Vector2(78.0, 72.0))
		. bent_at(Vector2(20.0, 25.0), Vector2(95.0, 100.0))
		. leaned(-10.0, 5.0)
	)
	# The one being choked: hands to the throat, head thrown back, legs buckling.
	table["choked"] = (
		Pose
		. make(Vector2(12.0, -6.0), Vector2(125.0, 118.0))
		. bent_at(Vector2(25.0, 12.0), Vector2(115.0, 120.0))
		. leaned(-12.0, -28.0)
	)
	# The one being choked struggles: a leg kicks forward.
	table["choked_kick"] = (
		Pose
		. make(Vector2(40.0, -18.0), Vector2(110.0, 128.0))
		. bent_at(Vector2(45.0, 8.0), Vector2(105.0, 120.0))
		. leaned(-16.0, -32.0)
	)
	# Broken neck: Otto takes the head with both hands...
	table["snap_grab"] = (
		Pose
		. make(Vector2(12.0, -10.0), Vector2(98.0, 92.0))
		. bent_at(Vector2(15.0, 20.0), Vector2(55.0, 65.0))
		. leaned(4.0)
	)
	# ...and wrenches it sideways: the arms pass downward, the torso leans forward.
	table["snap_twist"] = (
		Pose
		. make(Vector2(15.0, -12.0), Vector2(70.0, 110.0))
		. bent_at(Vector2(20.0, 25.0), Vector2(35.0, 80.0))
		. leaned(12.0, 8.0)
	)
	# The agent in a head grab: arms jerked, head slightly thrown back.
	table["snap_held"] = (
		Pose
		. make(Vector2(5.0, -5.0), Vector2(35.0, 30.0))
		. bent_at(Vector2(10.0, 10.0), Vector2(40.0, 35.0))
		. leaned(-4.0, -12.0)
	)
	# Neck broken: head turned sideways and dropped, knees buckled.
	table["snap_broken"] = (
		Pose
		. make(Vector2(10.0, 0.0), Vector2(10.0, 5.0))
		. bent_at(Vector2(35.0, 30.0), Vector2(15.0, 10.0))
		. leaned(6.0, 22.0)
		. twisted(78.0)
	)
	# A pistol-grip blow: the pistol raised above the head, the free hand holds by the
	# collar...
	table["whip_raise"] = (
		Pose
		. make(Vector2(10.0, -8.0), Vector2(62.0, 170.0))
		. bent_at(Vector2(15.0, 15.0), Vector2(40.0, 8.0))
		. leaned(-6.0, -4.0)
	)
	# ...and comes crashing down: the arm with the grip passes in front of the chest, the
	# torso follows.
	table["whip_strike"] = (
		Pose
		. make(Vector2(28.0, -12.0), Vector2(45.0, 52.0))
		. bent_at(Vector2(32.0, 18.0), Vector2(35.0, 5.0))
		. leaned(20.0, 10.0)
	)
	# The agent manages to react (ADR-0050): from the front, he pulls the barrel, the arm
	# with the pistol goes forward, the free one shields; the torso leans back...
	table["reach_gun"] = (
		Pose
		. make(Vector2(8.0, -10.0), Vector2(35.0, 62.0))
		. bent_at(Vector2(12.0, 14.0), Vector2(85.0, 40.0))
		. leaned(-6.0, -6.0)
	)
	# ...from behind, he senses it and turns around: head over the shoulder, shoulders
	# following.
	table["look_back"] = (
		Pose
		. make(Vector2(6.0, -6.0), Vector2(15.0, 25.0))
		. bent_at(Vector2(12.0, 10.0), Vector2(30.0, 35.0))
		. leaned(-2.0, -8.0)
		. twisted(-70.0)
	)
	# One who jumped from above finishes off: crouched over the fallen one, strikes down.
	table["pounce_strike"] = (
		Pose
		. make(Vector2(75.0, 35.0), Vector2(55.0, -15.0))
		. bent_at(Vector2(110.0, 85.0), Vector2(10.0, 35.0))
		. leaned(42.0, 10.0)
	)


## Intro poses (ADR-0052, decision 6) and the helicopter pilot's.
##
## The helicopter doorway is lower than Otto's height: looking out, he ducks, knees
## bent, torso forward, head toward the roof below, hands on the frame. He sits on the
## threshold facing the camera: thighs forward, shins hanging, hands braced on the
## threshold; taking the rope, he stretches both arms up and forward, toward the winch boom.
static func _add_arrival_poses(table: Dictionary) -> void:
	table["peek"] = (
		Pose
		. make(Vector2(38.0, 30.0), Vector2(70.0, 25.0))
		. bent_at(Vector2(55.0, 48.0), Vector2(55.0, 20.0))
		. leaned(34.0, 18.0)
	)
	table["sit_edge"] = (
		Pose
		. make(Vector2(88.0, 82.0), Vector2(-12.0, -12.0))
		. bent_at(Vector2(84.0, 92.0), Vector2(18.0, 18.0))
		. leaned(4.0, 12.0)
		. spread_by(-6.0)
	)
	table["sit_grab"] = (
		Pose
		. make(Vector2(84.0, 80.0), Vector2(150.0, 142.0))
		. bent_at(Vector2(80.0, 88.0), Vector2(14.0, 20.0))
		. leaned(-6.0, -20.0)
		. spread_by(-6.0)
		. reached_in(22.0)
	)
	# The pilot in the seat: hands on the stick and the lever, looking forward; a nod is the
	# head going down. The rig grounds by the feet: the helicopter seats the pilot at the
	# seat's place.
	table["pilot_sit"] = (
		Pose
		. make(Vector2(85.0, 85.0), Vector2(38.0, 30.0))
		. bent_at(Vector2(80.0, 80.0), Vector2(60.0, 70.0))
		. leaned(-4.0, 0.0)
	)
	table["pilot_nod"] = (
		Pose
		. make(Vector2(85.0, 85.0), Vector2(38.0, 30.0))
		. bent_at(Vector2(80.0, 80.0), Vector2(60.0, 70.0))
		. leaned(2.0, 28.0)
	)


static func _build_table() -> Dictionary:
	var table := {}
	# The first frame of the stance as is: the base of all poses in code and the fallback
	# pose.
	table["stand"] = Pose.new()
	# A crouch is not a different figure but a skeleton pose (ADR-0022, decision 3).
	table["crouch"] = (
		Pose
		. make(Vector2(CROUCH_LEGS, CROUCH_LEGS), Vector2(20.0, 25.0))
		. bent_at(Vector2(CROUCH_KNEES, CROUCH_KNEES), Vector2(30.0, 30.0))
		. leaned(CROUCH_LEAN, CROUCH_HEAD)
	)
	_add_takedown_poses(table)
	# Crushed by a cab or a lamp: legs and arms apart, flattened in height.
	table["crushed"] = (
		Pose
		. make(Vector2(-30.0, 30.0), Vector2(60.0, -60.0))
		. bent_at(Vector2(40.0, 40.0))
		. squashed(0.3)
	)
	# Hanging on the helicopter rope (ADR-0043, decision 1): arms straight up (the arm
	# angle as for the one lying down, only the body stands), legs together and slightly
	# forward, knees softly bent, head tilted up toward the hook.
	table["rope"] = (
		Pose
		. make(Vector2(8.0, 4.0), Vector2(165.0, 160.0))
		. bent_at(Vector2(14.0, 10.0), Vector2(6.0, 10.0))
		. leaned(0.0, -18.0)
		. spread_by(-18.0)
		. reached_in(25.0)
	)
	_add_arrival_poses(table)
	# An agent lying down under a bullet (ADR-0016, item 2). Lies face down, arms with the
	# gun stretched forward along the floor: instantly distinct from a corpse on its back.
	# The arm angle is the body tilt plus 90: this way the arm lies along the floor. The head
	# is tilted back, toward the gun: the hat brim lies on the nape instead of standing up
	# like a wall.
	table["prone"] = (
		Pose
		. make(Vector2(-4.0, 4.0), Vector2(170.0, 176.0))
		. bent_at(Vector2(10.0, 10.0), Vector2(-10.0, -10.0))
		. leaned(0.0, -40.0)
		. tilted(90.0)
	)
	return table
