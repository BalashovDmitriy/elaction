class_name EscalatorSpot
extends RefCounted

## The escalator leads from [member floor_index] to the next floor down.
##
## In its own file since M24h: [BuildingPlan] hit the line limit, and before that this
## was its inner class.

## How far the polyline bend steps back inside the opening from its near edge, m.
##
## What passes through the hole is not the path line but a passenger: he is half a torso wider,
## and the offset must be larger. The margin is 0.15 m, and it is guarded by
## [code]test_escalator_carries_its_rider_through_the_gap[/code].
const BEND_CLEARANCE: float = Proportions.BODY_WIDTH * 0.5 + 0.15
## Headroom above the rider while the flight goes under the slab, m.
const HEAD_CLEARANCE: float = 0.25

var x: float = 0.0
var floor_index: int = 0
## Where the belt goes down: -1 left, +1 right. Since M24g — always toward the edge
## of the floor (ADR-0043, decision 15).
var towards: float = -1.0
## The floor edge the escalator goes down toward: the opening ends there.
var edge: float = 0.0


## The opening in the slab under the belt: a pair "left edge, right edge".
##
## The hole is not under the landing but beside it, in the direction of descent, and runs to the
## floor edge: a 45° flight goes under the slab for more than two metres, and the rest
## of the floor beyond it would be an island one cannot reach. Computed here so that
## the level and [method BuildingPlan.safe_x] see the same opening.
func gap(rules: BuildingRules) -> Vector2:
	var near := x + towards * rules.escalator_gap_offset
	return Vector2(minf(near, edge), maxf(near, edge))


## The hole in the slab the flight passes through: a pair "left edge,
## right edge", in the back strip of the corridor (ADR-0044, decision 10).
##
## Shorter than [method gap]: that one is the space the layout keeps under the
## escalator, from the landing to the floor edge, and doors, lamps and furniture still
## stand by it. Since M24h the floor is solid, and the hole is needed only where
## the flight passes through the slab: until the rider's head has gone under it.
##
## The head has to go down by height, slab and margin; horizontally — that divided
## by the rules slope ([member BuildingRules.escalator_angle]), not 45° silently
## (code review M24h). The flight from the bend is steeper than the rules slope — margin comes free.
func hole(rules: BuildingRules) -> Vector2:
	var near := x + towards * rules.escalator_gap_offset
	var drop := Proportions.BODY + rules.slab_height + HEAD_CLEARANCE
	var reach := BEND_CLEARANCE + drop * rules.escalator_run / rules.floor_height
	var far := near + towards * minf(reach, absf(edge - near))
	return Vector2(minf(near, far), maxf(near, far))


## The lower landing — on the floor below, at the edge.
func landing(rules: BuildingRules) -> float:
	return x + towards * rules.escalator_run


## The polyline bend in its own coordinates: where the landing ends and the
## flight begins.
##
## Before M18b the bend stood in the middle of the opening and below the slab, and the polyline went
## in two flights of different steepness — in the frame it read as a chute, not
## an escalator (ADR-0025, decision 4). Now up to the opening there is a landing along the
## floor, and from its near edge — one straight flight down.
##
## Computed here, next to the opening it passes through: the level places
## the structure by this number, and the test checks by it that the passenger goes
## through the hole, not through the slab.
func bend(rules: BuildingRules) -> Vector2:
	return Vector2(towards * (rules.escalator_gap_offset + BEND_CLEARANCE), 0.0)
