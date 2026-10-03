class_name MoveLocks
extends RefCounted

## Short control pauses: turning and landing (ADR-0039, decision 4).
##
## In the arcade turning and starting are instant; the pauses are the user's decision for the
## weight of movement. While the body turns, the actor does not walk; after a jump or
## a fall he briefly recovers — does not walk and does not jump. Shooting and
## crouching are always allowed: the pauses are about legs, not arms.
##
## A rule without nodes: Otto and an agent call it the same way, and a test checks it without
## a scene, like [OttoStateMachine].

## How long a turn lasts, s. The body turns for the same time in [FigureRig].
const TURN_TIME: float = 0.1
## How long recovery after landing lasts, s.
const LAND_TIME: float = 0.15
## A pause remainder that is no longer a pause, s. 0.1 minus six frames of 1/60 in
## float is not zero but 3e-17, and the turn would hold the legs a seventh frame.
const SPENT: float = 1e-6

var _turn: float = 0.0
var _land: float = 0.0


## The actor started turning in place.
func turn() -> void:
	_turn = TURN_TIME


## The actor landed.
func land() -> void:
	_land = LAND_TIME


## [param delta] seconds pass.
func tick(delta: float) -> void:
	_turn = maxf(_turn - delta, 0.0)
	_land = maxf(_land - delta, 0.0)


## Whether one can walk: not turning and not recovering.
func can_walk() -> bool:
	return _turn < SPENT and _land < SPENT


## Whether one can jump: not recovering after landing. A jump out of
## a turn is allowed — one jumps where one is already looking.
func can_jump() -> bool:
	return _land < SPENT


## Removes both pauses: returning to play, being moved by the level.
func clear() -> void:
	_turn = 0.0
	_land = 0.0
