class_name ActorPose
extends RefCounted

## Which pose to show for an actor. A pure function of what is happening to it.
##
## Taken out of the nodes for the same reason as [OttoStateMachine] and [ElevatorMotion]: the pose
## set must cover all states, and this has to be checked without a scene, physics or a rendered
## frame. The pose lists live right here, and a test makes sure the pose choice does not go beyond
## them.
##
## Up to M15 the lists lived with the sprites: a pose was a picture. Now the pose is acted out by
## [FigureRig] from the [FigurePoses] table, and the list belongs next to the rule that chooses the
## pose, not next to the one that shows it.

## Frames in the walk cycle (ADR-0011, item 5).
const WALK_FRAMES: int = 3

## Walk frames per second. At twelve the step reads as running, while Otto walks (ADR-0011, item 5).
const WALK_FPS: float = 10.0

## Otto's poses.
const OTTO_POSES: PackedStringArray = [
	"idle",
	"walk_0",
	"walk_1",
	"walk_2",
	"crouch",
	"jump",
	"fall",
	"land",
	"shoot",
	"dead_0",
	"dead_1",
	"crushed",
	"rope",
	"peek",
	"sit_edge",
	"sit_grab",
]

## Agent poses. He does not jump or kick — [EnemyBrain] cannot do that. "Crouch" serves him as the
## "on one knee" pose, "prone" is his own (ADR-0016, item 3).
const AGENT_POSES: PackedStringArray = [
	"idle",
	"walk_0",
	"walk_1",
	"walk_2",
	"crouch",
	"prone",
	"shoot",
	"dead_0",
	"dead_1",
	"crushed",
]

## The crouch pose. One for Otto and the agent: for the agent it is "on one knee".
const CROUCH := "crouch"

## Otto hangs on the helicopter rope: arms up, legs together (ADR-0043, decision 1). It is chosen
## not by the state but by whoever carries him ([member Otto.ride_look]).
const ROPE := "rope"

## Building intro (ADR-0052, decision 6): Otto looks out of the helicopter doorway, sits on the sill
## and takes hold of the rope. Like the rope, these are chosen not by the state but by the intro
## ([member Otto.ride_pose]).
const PEEK := "peek"
const SIT_EDGE := "sit_edge"
const SIT_GRAB := "sit_grab"
const ARRIVAL_POSES: PackedStringArray = [PEEK, SIT_EDGE, SIT_GRAB]

## The agent's prone pose. The only lying pose of a living actor: in [FigurePoses] it has its own
## entry — face down, gun forward — rather than a corpse laid on its side.
const PRONE := "prone"

## Poses in which the actor lies — all kinds of death, since M24d also the corpse thrown by the blow
## of a takedown scene (ADR-0040), — and the prone dodge.
##
## In the greybox the box was laid on its side according to this list; the M16 rig reads the pose
## from the table and does not consult it. The list remains a fact about poses on which the choice
## tests rest: a corpse must lie, whoever shows it.
const DOWN: PackedStringArray = ["dead_0", "dead_1", "crushed", "knocked", PRONE]

## Pose by state for states that have only one. A constant rather than a dictionary on every call:
## the pose is recomputed every physics frame for Otto and for every agent in the frame.
##
## Since M24d there is no kick (ADR-0040): on the descent Otto just flies — the flight clip.
const BY_STATE: Dictionary = {
	OttoStateMachine.State.CROUCH: CROUCH,
	OttoStateMachine.State.JUMP: "jump",
	OttoStateMachine.State.FALL: "fall",
}


## Otto's pose.
##
## [param shooting] and [param falling_over] are not machine states but short timers: a shot is
## instant, but it has to be shown; and death is shown with two poses, the fall and the lying body
## (ADR-0011, item 12). The same with [param landing]: one who has just landed and stands still
## shows the landing (ADR-0039), once he steps — he walks.
static func of_otto(
	state: OttoStateMachine.State,
	crushed: bool,
	falling_over: bool,
	shooting: bool,
	walk_phase: float,
	landing: bool = false
) -> String:
	if state == OttoStateMachine.State.DEAD:
		return _death(crushed, falling_over)
	# From a crouch Otto shoots without standing up: the bullet flies low, and the arm aims at it in
	# the crouch itself (ADR-0043, decision 16).
	if shooting and state != OttoStateMachine.State.CROUCH:
		return "shoot"
	if landing and state == OttoStateMachine.State.IDLE:
		return "land"
	if state == OttoStateMachine.State.WALK:
		return walk_frame(walk_phase)
	return BY_STATE.get(state, "idle")


## Agent pose. He does not jump or kick — [EnemyBrain] cannot do that, and frames for non-existent
## states would be garbage. But he can dodge since M11, and kneeling and lying down have their own
## poses (ADR-0016, item 3).
##
## The stance matters more than the shot: the shot holds for 0.18 s, while the stance holds as long
## as a bullet flies at the agent, and replacing it with the shooting pose would show him standing
## where he is actually lying. The shot itself is seen by the bullet flash.
static func of_agent(
	dead: bool,
	walking: bool,
	crushed: bool,
	falling_over: bool,
	shooting: bool,
	walk_phase: float,
	stance: EnemyBrain.Stance = EnemyBrain.Stance.STAND
) -> String:
	if dead:
		return _death(crushed, falling_over)
	if stance == EnemyBrain.Stance.KNEEL:
		return CROUCH
	if stance == EnemyBrain.Stance.PRONE:
		return PRONE
	if shooting:
		return "shoot"
	return walk_frame(walk_phase) if walking else "idle"


## Advances the walk phase by one frame of time.
##
## Lives next to [method walk_frame] on purpose: only [constant WALK_FRAMES] knows the cycle length.
## With its own `fmod` in each actor the cycle would wrap not where the frame is computed, and the
## last walk frame would simply never show.
static func advance(walk_phase: float, delta: float) -> float:
	return fmod(walk_phase + delta * WALK_FPS, float(WALK_FRAMES))


## Whether the actor lies in this pose.
static func is_down(pose: String) -> bool:
	return DOWN.has(pose)


## Walk frame by phase: the integer part of the phase is the frame number.
static func walk_frame(walk_phase: float) -> String:
	var frame := int(walk_phase) % WALK_FRAMES
	return "walk_%d" % maxi(frame, 0)


## Walk frame number from the pose name: the inverse of [method walk_frame]. Needed by the rig,
## which gets the frame name as a string while the walk cycle runs by phase.
static func walk_frame_index(pose: String) -> int:
	if not pose.begins_with("walk_"):
		return 0
	return clampi(pose.trim_prefix("walk_").to_int(), 0, WALK_FRAMES - 1)


## How exactly he was killed: a crushed one is shown with its own picture, and a fall and a lying
## body with two different ones.
static func _death(crushed: bool, falling_over: bool) -> String:
	if crushed:
		return "crushed"
	return "dead_0" if falling_over else "dead_1"
