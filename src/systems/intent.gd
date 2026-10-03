class_name Intent
extends RefCounted

## Project-wide directions and thresholds of player intent.
##
## The "step onto a spot and press a direction" pattern repeats for the elevator cab,
## the escalator and the door. Previously each declared its own constants, and "up is -1"
## was written in two places and the press threshold in three, with different values.
## Found by the M2 code review.

## Up on the screen means decreasing y.
const UP: float = -1.0
const DOWN: float = 1.0

## A deliberate direction press: below this, a stick tilt does not count as one.
##
## Differs from [constant ElevatorMotion.COMMAND_THRESHOLD] on purpose: that one is about
## whether a command at the cab is released, and its threshold must be small.
const PRESS: float = 0.5
