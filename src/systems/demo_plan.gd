class_name DemoPlan
extends RefCounted

## Demo mode (ADR-0041): when it turns on, how long it runs and from where.
##
## As in the cabinet: the demo starts in turn from three places — the top, middle and bottom of the
## building — runs about 30 s and ends with Otto's death. The test bot plays, not a recording of
## presses. A rule without nodes, like [OttoStateMachine]; the demo is driven in the game by
## [DemoRun].

## Where the demo starts from.
enum Point { ROOF, MIDDLE, BOTTOM }

## How much idleness in the main menu before the demo, s (user's decision).
const IDLE_TIME: float = 45.0
## How long the demo runs, s — between the ROM recordings (25 and 35 s).
const LENGTH: float = 30.0

## Start floors by the ROM count — from the bottom, out of thirty: 18 and 5 (`$802C`). The top
## point is the roof with the helicopter, not ROM's 28th floor: the helicopter is the best thing
## the building has.
const ROM_FLOORS: Dictionary = {Point.MIDDLE: 18, Point.BOTTOM: 5}

## How many floors from the ROM floor the demo searches for a shaft whose cab starts on that
## floor: there the bot boards at once rather than waiting for the cab half the demo.
const SHAFT_SEARCH: int = 4


## The next point round the circle.
static func next(point: int) -> int:
	return (point + 1) % Point.size()


## Start floor index for a building with [param floors] floors: ours are counted
## from the top, ROM's from the bottom. For the roof — [constant BuildingRules.ROOF].
static func floor_of(point: int, floors: int) -> int:
	if not ROM_FLOORS.has(point):
		return BuildingRules.ROOF
	return clampi(floors - int(ROM_FLOORS[point]), 0, floors - 1)
