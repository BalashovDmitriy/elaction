class_name DoorCycle
extends RefCounted

## Door leaf travel: closed, opening, open, closing.
##
## No nodes, no physics: the door node asks what to show and does it. So the travel is
## checked without a scene — the same trick as [OttoStateMachine], [ElevatorMotion] and
## [DoorVisit]. Grounds — ADR-0020, decision 1.
##
## Separated from [DoorVisit] on purpose. That one is about the visit rules — whom to let
## in and when to let out; this one is about the leaf itself, which does not care who
## opened it: Otto, come for a document, or an agent heading for an ambush.

enum Phase { CLOSED, OPENING, OPEN, CLOSING }

## How long the leaf takes in one direction, s. Set by whoever opens it: Otto's visit is
## fast, an agent's exit is slow, because it is also a warning (ADR-0020, decision 2).
var travel_time: float = 0.25

var phase: Phase = Phase.CLOSED

## How far the leaf has moved: 0 — closed, 1 — wide open.
var _openness: float = 0.0


## Opens the leaf. Does not touch one already open.
func open() -> void:
	if phase != Phase.OPEN:
		phase = Phase.OPENING


## Closes the leaf. Does not touch one already closed.
func close() -> void:
	if phase != Phase.CLOSED:
		phase = Phase.CLOSING


## Leaf step.
func tick(delta: float) -> void:
	if phase == Phase.OPENING:
		_openness = minf(_openness + _step(delta), 1.0)
		if _openness >= 1.0:
			phase = Phase.OPEN
	elif phase == Phase.CLOSING:
		_openness = maxf(_openness - _step(delta), 0.0)
		if _openness <= 0.0:
			phase = Phase.CLOSED


## Whether the leaf is wide open: only then can one come out of the door.
func is_open() -> bool:
	return phase == Phase.OPEN


## Whether the leaf is fully closed: only such a door can be occupied again.
func is_shut() -> bool:
	return phase == Phase.CLOSED


## Leaf travel, 0..1. The node drives the picture by it (ADR-0020, decision 7).
func openness() -> float:
	return _openness


## Travel share per frame. Zero travel time means an instant leaf, not a division by
## zero: that way a door without animation stays a working door.
func _step(delta: float) -> float:
	return delta / travel_time if travel_time > 0.0 else 1.0
