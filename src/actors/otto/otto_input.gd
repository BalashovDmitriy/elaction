class_name OttoInput
extends RefCounted

## Input snapshot for one frame.
##
## Separates [OttoStateMachine] from the [Input] singleton: in the game the snapshot is built
## from actions, in tests — filled in by hand.

## Horizontal direction: -1 left, +1 right, 0 standing.
var move: float = 0.0

## Vertical direction: -1 up, +1 down, 0 rest.
##
## On a floor "down" is a crouch, in a shaft — a command to the cab. These two
## meanings are told apart by whoever knows the context: the snapshot knows nothing about lifts.
var vertical: float = 0.0

## Whether crouch is held.
var crouch: bool = false

## Whether jump was pressed in exactly this frame.
var jump_pressed: bool = false

## Whether fire was pressed in exactly this frame. Otto's weapon is single-shot: holding
## does not fire bursts.
var shoot_pressed: bool = false


## Re-reads the snapshot from the project's action map.
##
## A method, not a factory: the snapshot is reused frame after frame so as not to
## allocate an object on every physics frame.
func read_actions() -> void:
	move = Input.get_axis("move_left", "move_right")
	vertical = Input.get_axis("move_up", "move_down")
	crouch = Input.is_action_pressed("move_down")
	jump_pressed = Input.is_action_just_pressed("jump")
	shoot_pressed = Input.is_action_just_pressed("shoot")
