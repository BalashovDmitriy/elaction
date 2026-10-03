class_name AgentPost
extends RefCounted

## A post at an agent door: the door itself, its floor and the agent it has already released.
##
## The floor is computed once per building: doors do not move, and [GreyboxLevel]
## iterates the posts every frame — no point deriving the floor from a coordinate sixty
## times a second for fifty doors.

var door: Door = null
var floor_index: int = 0
## Who stands behind the door right now. Empty — the door is free.
var agent: Enemy = null
## The door leaf is already opening for the next agent, but he has not shown up yet.
##
## A door in this state counts as occupied and takes a slot under the cap of
## living agents: otherwise any number of doors could open during the telegraph,
## and agents would pour out at once above the cap (ADR-0020).
var opening: bool = false
## Slot of the agent the door is releasing or has released; -1 — none.
var slot: int = -1
