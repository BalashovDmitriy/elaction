class_name ShaftHazards
extends RefCounted

## Rules of death in an elevator shaft: falling and being crushed by a cab.
##
## Nodes determine the physics, and the "alive or not" decision is made here: this way
## it is visible in one place and can be checked by tests. Grounds are in ADR-0004
## and ADR-0037, decision 7.

## How much beyond a floor a fall still counts as a one-floor fall, as a fraction of a
## floor.
##
## An exact floor almost never happens. A cab roof is lower than the floor above it by
## the slab thickness: someone falling onto a cab two floors below flies past a floor and
## a slab. A descending cab moves away from under the faller, and a roof that was one
## floor lower at the moment of the step meets him lower. Half a floor is the border
## between "one floor" and "two": closer to two than to one already means two.
const FALL_SLACK: float = 0.5
## How far a body may stick out past the cab side and still count as "entirely
## under it", m: a couple of centimeters for position rounding, no more.
const UNDER_SLACK: float = 0.04


## Whether landing after a fall of [param drop] meters is fatal.
##
## One rule for everything you can fall onto: the floor, a cab roof and the shaft
## bottom. Jumping down one floor or onto a cab one floor lower is fine; from two floors
## and deeper it is death. The former "the shaft bottom kills, a cab roof saves from any
## height" went away in M24a: it could not be understood from the game. Depth is counted
## from the last support, not from the top point of the jump: your own jump does not add
## to the fall.
static func is_deadly_fall(drop: float, floor_height: float) -> bool:
	return drop > floor_height * (1.0 + FALL_SLACK)


## Whether the cab will crush someone who has got under its bottom.
##
## The node checks the overlap of areas itself; the rest is decided here. Fatal is the
## combination of three things: the cab is going down, the victim has nowhere to go (it
## stands on the floor), and it is not a passenger, who stands on the cab floor and rides
## along with it.
##
## The [code]is_on_ceiling[/code] flags do not catch this: the cab moves the player
## through the physics server, and the flag is set only by its own move_and_slide.
##
## The fourth condition, since M24h, per the ROM (@4A30, @46E9): the victim is under the
## bottom [b]entirely[/b]. Someone caught by the edge is not crushed by the cab but pushed
## out to the shaft edge ([method push_out]); previously an accidental touch of the side
## killed (ADR-0044, decision 6).
static func crushes(
	car_speed: float, victim_grounded: bool, victim_is_passenger: bool, fully_under: bool = true
) -> bool:
	return car_speed > 0.0 and victim_grounded and not victim_is_passenger and fully_under


## Whether a body of width [param body_width] with its middle at [param body_x] stands
## entirely under a cab of width [param car_width] with its middle at [param car_x].
static func is_fully_under(
	body_x: float, body_width: float, car_x: float, car_width: float
) -> bool:
	return absf(body_x - car_x) + body_width * 0.5 <= car_width * 0.5 + UNDER_SLACK


## Where the cab pushes someone caught by the edge: the body's middle at the side on the
## side where the body's middle is (@4713/@4722 ROM, by the side of the middle).
static func push_out(body_x: float, body_width: float, car_x: float, car_width: float) -> float:
	var side := 1.0 if body_x >= car_x else -1.0
	return car_x + side * (car_width + body_width) * 0.5
