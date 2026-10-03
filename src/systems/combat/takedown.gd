class_name Takedown
extends RefCounted

## Close-up takedown (ADR-0040): whom can be taken down, from which side, with which scene and for
## how many points.
##
## Since M24d there is no kick. The fire button shoots at a distance, and close to an agent on the
## same floor — makes a takedown; one who lands close to an agent — from a jump or from the floor
## above — makes a takedown by himself (ADR-0042, decision 9). A scene is a short staging of two:
## who is in which pose from which moment, where the agent stands, when he dies. The variant is
## picked at random from those fitting the side, without repeating in a row.
##
## A rule without nodes, like [OttoStateMachine]: checked without a scene. [TakedownScene] runs the
## scene in the game.

## From which side Otto got the agent.
enum Side { FRONT, BACK, ABOVE }

## How far horizontally an agent is still "close up", m — between body axes. Wider than the ROM kick
## (16 px, 0.53 m): close up is a step, not a touch.
const REACH: float = 0.9
## How far the floors of Otto and the agent may differ, m: one floor, not the adjacent one.
const SAME_FLOOR: float = 0.3

## Points by side (the user's decision, ADR-0040): from behind and from above — on a par with a lamp
## and an elevator, from the front — twice a shot.
const SCORES: Dictionary = {Side.FRONT: 200, Side.BACK: 300, Side.ABOVE: 300}
## Bonus in darkness and on floors 11–15 — as in the ROM for a shot and a kick, but our own.
const DARK_BONUS: int = 100


## One scene: the poses of the two over time.
class Scene:
	extends RefCounted

	var name: String
	## [enum Takedown.Side]. As a number: GDScript confuses the enum type in static class functions and
	## in external code.
	var side: int
	## How long the scene lasts, s — at its own pace, the world around is slowed down.
	var duration: float
	## When the agent dies, s: before that the scene can be interrupted, and the agent lives.
	var kill_at: float
	## Where the agent stands: this many metres in front of Otto, along his gaze.
	var offset: float
	## Whether the agent faces Otto. From the front — yes, from behind — no.
	var faces_otto: bool
	## Poses over time: [[time, pose], …], in ascending time.
	var otto: Array[Array] = []
	var agent: Array[Array] = []
	## The corpse pose after the scene: the agent lies in whatever pose he went down in.
	var corpse: String = "dead_1"

	## The actor's pose at moment [param time]: the last one that started.
	static func pose_at(track: Array[Array], time: float) -> String:
		var shown := String(track[0][1]) if not track.is_empty() else ""
		for key: Array in track:
			if float(key[0]) <= time:
				shown = String(key[1])
		return shown


## Whether Otto reaches the agent close up: the same floor, nearby, and the agent is in front of him
## — along Otto's gaze. With his back to the agent Otto shoots where he is looking.
##
## Coordinates are scene ones: X along the floor, Y — feet, upward.
static func can_reach(otto: Vector2, facing: float, agent: Vector2) -> bool:
	if absf(agent.y - otto.y) > SAME_FLOOR:
		return false
	var ahead := (agent.x - otto.x) * signf(facing)
	return ahead >= -0.05 and ahead <= REACH


## Whether the body stands on a cab — on its floor or roof. Such ones are not taken down and do not
## take down: the scene freezes both, while the cab drives on and leaves from under the pair (M24d
## code review).
static func rides_a_car(body: CharacterBody3D) -> bool:
	if not body.is_on_floor():
		return false
	for index in body.get_slide_collision_count():
		if body.get_slide_collision(index).get_collider() is ElevatorCar:
			return true
	return false


## From which side of the agent Otto is: the agent looks at him — from the front, otherwise from
## behind.
static func side_of(otto_x: float, agent_x: float, agent_facing: float) -> int:
	var towards := signf(otto_x - agent_x)
	if is_zero_approx(towards):
		return Side.FRONT
	return Side.FRONT if towards == signf(agent_facing) else Side.BACK


## Whether Otto landed on the agent: on his floor and close to him, from any side (ADR-0042,
## decision 9). Where he flew from — a jump or the floor above — does not matter: in the ROM a jump
## kick killed on any touch of the bodies.
static func lands_on(otto_feet: Vector2, agent_feet: Vector2) -> bool:
	return (
		absf(otto_feet.y - agent_feet.y) <= SAME_FLOOR and absf(otto_feet.x - agent_feet.x) <= REACH
	)


## Points for a takedown.
static func score(side: int, in_the_dark: bool) -> int:
	var base: int = SCORES[side]
	return base + DARK_BONUS if in_the_dark else base


## The side's scenes.
static func scenes_for(side: int) -> Array[Scene]:
	var found: Array[Scene] = []
	for scene: Scene in all_scenes():
		if scene.side == side:
			found.append(scene)
	return found


## A scene of the side at random, but not the same as the previous one — if there is another.
static func pick(side: int, last: String, rng: RandomNumberGenerator) -> Scene:
	var choices := scenes_for(side)
	if choices.size() > 1:
		choices = choices.filter(func(scene: Scene) -> bool: return scene.name != last)
	return choices[rng.randi_range(0, choices.size() - 1)]


## All scenes. Built anew on each call: there are few of them, and a shared table would change for
## everyone at once.
static func all_scenes() -> Array[Scene]:
	return [_combo(), _pistol_whip(), _choke(), _neck_snap(), _pounce()]


## Front: jab, cross — the agent is thrown onto his back.
static func _combo() -> Scene:
	var scene := _scene("combo", Side.FRONT, 1.15, 0.72, 0.72, true)
	scene.otto = [[0.0, "punch_jab"], [0.34, "punch_cross"], [0.95, "idle"]]
	scene.agent = [[0.0, "reach_gun"], [0.12, "hit_head"], [0.46, "hit_chest"], [0.66, "knockback"]]
	scene.corpse = "knocked"
	return scene


## Front: an overhead swing with the gun butt — the agent slumps. Poses in code: the UAL throw,
## tried first, is a lunge downward, and Otto dived into the agent's legs (M24D shots).
static func _pistol_whip() -> Scene:
	var scene := _scene("pistol_whip", Side.FRONT, 1.0, 0.42, 0.62, true)
	scene.otto = [[0.0, "whip_raise"], [0.3, "whip_strike"], [0.8, "idle"]]
	scene.agent = [[0.0, "reach_gun"], [0.3, "hit_head"], [0.42, "dead_0"]]
	return scene


## Behind: a neck hold, the agent struggles and goes limp.
static func _choke() -> Scene:
	var scene := _scene("choke", Side.BACK, 1.35, 1.02, 0.4, false)
	scene.otto = [[0.0, "choke_hold"], [1.12, "idle"]]
	scene.agent = [
		[0.0, "look_back"],
		[0.12, "choked"],
		[0.22, "choked_kick"],
		[0.42, "choked"],
		[0.6, "choked_kick"],
		[0.8, "choked"],
		[1.02, "dead_0"],
	]
	return scene


## Behind: hands on the head — a jerk sideways, the agent drops like a stone.
static func _neck_snap() -> Scene:
	var scene := _scene("neck_snap", Side.BACK, 0.95, 0.46, 0.32, false)
	scene.otto = [[0.0, "snap_grab"], [0.38, "snap_twist"], [0.78, "idle"]]
	scene.agent = [[0.0, "look_back"], [0.14, "snap_held"], [0.4, "snap_broken"], [0.52, "dead_0"]]
	return scene


## Above: fell on the agent — he flies onto his back, Otto finishes him off from above.
static func _pounce() -> Scene:
	var scene := _scene("pounce", Side.ABOVE, 1.0, 0.55, 0.55, true)
	scene.otto = [[0.0, "land"], [0.3, "pounce_strike"], [0.82, "idle"]]
	scene.agent = [[0.0, "knockback"]]
	scene.corpse = "knocked"
	return scene


static func _scene(
	scene_name: String, side: int, length: float, kill: float, gap: float, facing: bool
) -> Scene:
	var scene := Scene.new()
	scene.name = scene_name
	scene.side = side
	scene.duration = length
	scene.kill_at = kill
	scene.offset = gap
	scene.faces_otto = facing
	return scene
