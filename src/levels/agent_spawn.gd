class_name AgentSpawn
extends RefCounted

## Agent release draw by ROM rules: slots, floor, door (ADR-0027, decision 2).
##
## Its own class, not in the level: the level knows doors, floors and Otto, while how many
## agents can live and who comes out next is a rule, and it is checked without
## a scene. ROM keeps four agent slots (@594D): three or four are
## occupied, and a freed one waits for a shift change by difficulty (@3866).

## Agent slots: as many as ROM keeps. The building's manual cap ([member
## BuildingRules.agents_at_once_cap]) may ask for more — then slots
## are added in [method open_slot], otherwise it would silently hit four.
const SLOTS: int = 4

## Draw generator: the building's own, seeded by its seed — a bot run
## repeats down to the step.
var rng := RandomNumberGenerator.new()

var _busy: Array[bool] = [false, false, false, false]
var _wait: Array[float] = [0.0, 0.0, 0.0, 0.0]
## How much has accumulated toward the next draw tick, s.
var _clock: float = 0.0


## Counts time. Returns true on the frame a logic tick comes:
## in ROM the draw is rolled once per tick, not once per frame — otherwise at 60 Hz it would go
## four times as often, and at 30 half as often.
func tick(delta: float) -> bool:
	for index in _wait.size():
		_wait[index] = maxf(_wait[index] - delta, 0.0)
	_clock += delta
	if _clock < Arcade.TICK:
		return false
	_clock = fmod(_clock, Arcade.TICK)
	return true


## A free slot among the first [param available], or -1: an occupied one or one still waiting
## for its shift change does not qualify.
##
## [param lead] — how long before the end of the shift change a slot already qualifies. That is how
## long the door leaf takes: it starts opening at the end of the shift change, and the agent comes
## out where ROM releases him, not a leaf travel later (ADR-0028, decision 7).
func open_slot(available: int, lead: float = 0.0) -> int:
	while _busy.size() < available:
		_busy.append(false)
		_wait.append(0.0)
	for index in available:
		if not _busy[index] and _wait[index] <= lead:
			return index
	return -1


## Occupies a slot: the agent in it is coming out or has come out.
func take(slot: int) -> void:
	_busy[slot] = true


## Frees a slot: its shift change will come after a pause by difficulty [param level].
func release(slot: int, level: int) -> void:
	if slot < 0 or slot >= _busy.size():
		return
	_busy[slot] = false
	_wait[slot] = Arcade.respawn_wait(level)


## Otto returned to play: all slots are free, and releases into them go with ROM
## delays — 10, 25, 40 and 55 ticks (@2F61; ADR-0053, decision 2). Slots added beyond
## four wait further at the same step.
func after_death() -> void:
	var waits := Arcade.RESPAWN_WAIT_TICKS
	var step := waits[1] - waits[0]
	for index in _busy.size():
		_busy[index] = false
		var ticks := (
			waits[index] if index < waits.size() else waits[-1] + step * (index - waits.size() + 1)
		)
		_wait[index] = Arcade.seconds(ticks)


## The draw floor: Otto's floor, above or below, and with a chance by difficulty — exactly
## Otto's floor (@5A4C).
func pick_floor(here: int, level: int) -> int:
	var floor_index := here + rng.randi_range(-1, 1)
	if rng.randf() < Arcade.own_floor_chance(level):
		floor_index = here
	return floor_index


## A random one of the eligible ones; none eligible — -1.
func pick(count: int) -> int:
	return -1 if count <= 0 else rng.randi_range(0, count - 1)


## Whether the door on floor [param floor_index] at [param door_x] is closer to Otto than
## [member BuildingRules.agent_release_gap]. By default there is no ban, as in ROM
## (ADR-0053, decision 3).
func hugs(rules: BuildingRules, floor_index: int, here: int, door_x: float, otto: Node3D) -> bool:
	if floor_index != here:
		return false
	return absf(door_x - otto.global_position.x) < rules.agent_release_gap
