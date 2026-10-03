class_name DoorVisit
extends RefCounted

## Door visit rules: whom to let in, when to hide and when to let out.
##
## No nodes, no physics: the door node supplies facts about the guest and the leaf and
## carries out the decision, while this class decides. So the rules are checked without a
## scene — by the same technique as [OttoStateMachine] and [ElevatorMotion]. Grounds —
## ADR-0005, items 2-3, and ADR-0038, decision 2.
##
## It does not drive the leaf: that is [DoorCycle]'s job. Before, both lived here and shared
## one timer, because of which an agent's door could not be opened without bringing a guest
## in (ADR-0020, decision 1). The visit only says when it is time for the leaf to move.
##
## The visit goes as in the ROM (@3BDA, `update_in_room_timer_3c3e`): the leaf opens,
## the guest goes inside, it closes behind him; [member hide_time] after the knock
## it opens again and lets him out. One cannot leave earlier — the user's decision
## (ADR-0038, decision 2): in the ROM one can, by pushing away from the door.

## What the visit tells the door to do this frame.
## [code]HIDE[/code] — the leaf has opened, the guest went inside: hide and close;
## [code]LET_OUT[/code] — time is almost up: open, so the opening is there by the deadline;
## [code]OUT[/code] — deadline, and the leaf is open: the guest is outside.
enum Cue { NONE, HIDE, LET_OUT, OUT }

enum Phase { OUTSIDE, ENTERING, INSIDE, LEAVING }

## How long the guest spends inside, counting from the knock, s: 70 ROM ticks.
var hide_time: float = Arcade.seconds(Arcade.ROOM_TICKS)

## Leaf travel, s. Letting out starts this much in advance so that by the end of
## [member hide_time] the opening is already open: the deadline is the exit, not its start.
var leaf_time: float = 0.25

var phase: Phase = Phase.OUTSIDE

## How long the guest has been at the door, s: from the knock.
var _elapsed: float = 0.0
## Whether the guest released "up" after the door let him out. Without this the same
## held button would pull him back in again and again: put out — and taken right back.
var _entry_armed: bool = true


## Whether the guest asks to go in. Asked only about someone standing on the mat.
func knock(grounded: bool, vertical: float) -> bool:
	if vertical > -Intent.PRESS:
		# "Up" was released: the next press again counts as a request to enter.
		_entry_armed = true
		return false
	return _entry_armed and grounded


## Lets the guest in: from this moment the deadline runs, and his input is no longer heeded.
func admit() -> void:
	_elapsed = 0.0
	phase = Phase.ENTERING


## Visit step. [param leaf_open] — whether the leaf is wide open.
##
## There is no guest input here on purpose: nothing lets one leave before the deadline.
func tick(delta: float, leaf_open: bool) -> Cue:
	if phase == Phase.OUTSIDE:
		return Cue.NONE
	_elapsed += delta
	match phase:
		Phase.ENTERING:
			if leaf_open:
				phase = Phase.INSIDE
				return Cue.HIDE
		Phase.INSIDE:
			if _elapsed >= hide_time - leaf_time:
				phase = Phase.LEAVING
				return Cue.LET_OUT
		Phase.LEAVING:
			# The leaf did not make it by the deadline — the guest waits for it: nobody
			# walks through a closed one.
			if _elapsed >= hide_time and leaf_open:
				return Cue.OUT
	return Cue.NONE


## Lets the guest out.
func release() -> void:
	phase = Phase.OUTSIDE
	_entry_armed = false


## Whether the guest is hidden: went inside and has not come out yet.
func is_hiding() -> bool:
	return phase == Phase.INSIDE or phase == Phase.LEAVING


## How long the guest has been at the door, s. Needed by tests.
func elapsed() -> float:
	return _elapsed
