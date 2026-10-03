class_name Footing
extends RefCounted

## Foot grip on the floor (ADR-0054, decision 4). On a dry floor a step is as in the ROM:
## walking speed at once, stopping at once. On a snowy roof the feet grip
## worse: Otto and the agents accelerate and brake with finite grip and
## slip when stopping and turning around.

## Otto's group: the roof snow ([SnowTracks]) finds by it who walks on the deck.
const OTTO_GROUP := &"otto"

## Acceleration and braking on snow, m/s²: the ROM step is 2.2 m/s, and at full pace on snow
## one stops in a quarter of a second, sliding about a quarter of a metre.
const SNOW_GRIP: float = 9.0


## Horizontal speed for this step: [param wanted] — what the legs ask for,
## [param current] — what there is. On dry floor — at once, on snow ([param icy]) —
## no faster than the grip allows.
static func step(current: float, wanted: float, icy: bool, delta: float) -> float:
	if not icy:
		return wanted
	return move_toward(current, wanted, SNOW_GRIP * delta)
