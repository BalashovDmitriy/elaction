class_name DoorWatch
extends RefCounted

## An agent at the door Otto is hiding behind: who goes to wait and where he stands.
##
## The ROM does not have this; it is the user's decision (ADR-0038, decision 2): agents
## who lost Otto on his floor sometimes walk up to his door and wait while he is inside.
## Once he is out, the agent lives as before again and most likely shoots right away:
## that is the whole point.
##
## No nodes, no physics: facts about the agent come from outside, the answer is the
## coordinate where to wait, or NAN. So the rule is checked without a scene, like
## [EnemyBrain] and [AgentLifts]. The level keeps one such object per building: Otto
## hides behind only one door at a time.
##
## An agent gets one draw per visit: at the first look at him while Otto is
## inside. If it came up "no", this agent will not go to this door this time, however
## many frames pass; otherwise a draw per frame would give everyone a "sometimes" within
## a second. The generator is its own, not the agent release one: if it drew from that,
## the bot run would change even where Otto never entered any door.

## Chance of an agent going to the door. Chosen, not measured: "sometimes" means every
## second one.
const CHANCE: float = 0.5

## How far from the middle of the door the agent stands to wait, m: the mat edge, half
## a body and a gap. He does not stand on the mat, since Otto steps out there, and with
## a 1.8 m grid step he does not reach the neighboring spot's mat either.
const STANDOFF: float = Proportions.DOOR_MAT * 0.5 + Proportions.BODY_WIDTH * 0.5 + 0.15

## Draw generator. The level seeds it from the building seed: the run repeats to the step.
var rng := RandomNumberGenerator.new()

## The floor and the middle of the door Otto is behind; floor −1 means Otto is behind none.
var _floor: int = -1
var _door_x: float = NAN
## Who waits at the door: the agent's instance id, 0 means nobody.
var _watcher: int = 0
## Whether the waiting one was seen this frame. If not, he was killed, left or removed by
## the level: the spot at the door frees up, and nobody outside needs to remember it.
var _watcher_seen: bool = false
## Whom the draw has already been made for in this visit: id → true.
var _rolled: Dictionary = {}


## Otto has hidden behind the door with middle [param door_x] on floor [param floor_index].
func begin(floor_index: int, door_x: float) -> void:
	_floor = floor_index
	_door_x = door_x
	_watcher = 0
	_watcher_seen = false
	_rolled.clear()


## Otto has come out: there is nobody left to wait for.
func end() -> void:
	_floor = -1
	_door_x = NAN
	_watcher = 0
	_rolled.clear()


## Whether Otto is hidden on floor [param floor_index]. The level asks before computing
## the floor's obstacles: they are not needed for other floors.
func covers(floor_index: int) -> bool:
	return _floor >= 0 and floor_index == _floor


## The middle of the door Otto is behind, or NAN.
func door_x() -> float:
	return _door_x


## Who waits at the door: the agent's instance id, or 0.
func watcher() -> int:
	return _watcher


## Start of a frame: the level will then ask [method post_for] about every living agent.
func start_frame() -> void:
	if not _watcher_seen:
		_watcher = 0
	_watcher_seen = false


## Where agent [param agent] on floor [param floor_index] at point [param x] should wait,
## or NAN if there is no point in him waiting.
##
## [param blocks] is what cuts the floor for walking ([method BuildingPlan.blocks_on]):
## the agent does not walk past an opening or a wall between him and the door, and a spot
## in an opening is no good for waiting.
func post_for(agent: int, floor_index: int, x: float, blocks: Array[Vector2]) -> float:
	if agent == _watcher and _watcher != 0:
		if floor_index != _floor:
			# Rode off or fell off the floor: the spot is free, he will not go a second time.
			_watcher = 0
			return NAN
		_watcher_seen = true
		return spot(x)
	if not covers(floor_index) or _watcher != 0 or _rolled.has(agent):
		return NAN
	var post := spot(x)
	if not _walks(blocks, x, post):
		return NAN
	_rolled[agent] = true
	if rng.randf() >= CHANCE:
		return NAN
	_watcher = agent
	_watcher_seen = true
	return post


## The waiting spot for an agent standing at [param x]: on his side of the door.
func spot(x: float) -> float:
	var side := 1.0 if x >= _door_x else -1.0
	return _door_x + side * STANDOFF


## Whether the agent gets from [param x] to spot [param post] and whether the door is
## visible from there: no opening or wall on the whole segment from the agent to the door
## via the spot.
func _walks(blocks: Array[Vector2], x: float, post: float) -> bool:
	var low := minf(minf(x, post), _door_x)
	var high := maxf(maxf(x, post), _door_x)
	for block: Vector2 in blocks:
		if maxf(block.x, block.y) > low and minf(block.x, block.y) < high:
			return false
	return true
