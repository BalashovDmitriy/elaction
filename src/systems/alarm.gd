class_name Alarm
extends RefCounted

## Timer alarm.
##
## Dawdled in the building — the siren comes on: agents get angrier, the cab responds
## with a delay. Death does not clear the alarm, only a building change resets it
## (ADR-0009, point 1) — that is, it is a penalty for the whole playthrough, not for an attempt.
##
## The term is from the arcade ROM: 4096 logic ticks, ~277 s (ADR-0027, decision 7).
## Before M18d a temporary five minutes stood here (ADR-0009, point 5): the moment
## it triggers in the original had not been confirmed then.

## How much time is given for a building, s.
var time_limit: float = Arcade.seconds(Arcade.ALARM_TICKS)

var raised: bool = false

var _left: float = 0.0
## How long the building has been going, s. Counted after the alarm too: difficulty grows
## with time in the building, and the siren does not stop it but speeds it up (ADR-0027).
var _elapsed: float = 0.0


## A new building: the alarm is cleared and the countdown starts again. The only
## way to clear it — the player's death does not do this.
func enter_building() -> void:
	raised = false
	_left = time_limit
	_elapsed = 0.0


## Counts time. Returns true on the single frame the alarm
## switched on, so that everyone can be roused by it once.
func tick(delta: float) -> bool:
	_elapsed += delta
	if raised:
		return false

	_left -= delta
	if _left > 0.0:
		return false

	raised = true
	return true


## How much is left until the alarm, s. After it triggers — zero.
func time_left() -> float:
	return maxf(_left, 0.0)


## How long the building has been going, s.
func elapsed() -> float:
	return _elapsed
