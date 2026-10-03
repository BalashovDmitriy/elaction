class_name WorldSpace
extends RefCounted

## Conversion between the rules plane and the 3D scene.
##
## The rules count Y downward: [method BuildingRules.floor_surface] grows with the floor number,
## floor zero is the top one. That is how it was in 2D, and it must not change — the rules layer is
## not touched by the move (ADR-0019, decision 2).
##
## The scene counts Y upward, like the rest of Godot: light sources look there, and [constant
## Vector3.UP] of [CharacterBody3D] points there by default. Turning one into the other would be
## needed in every node, and the sign would diverge at the very first edit.
##
## So the conversion lives here and only here. A node takes a [Vector2] from the rules, gives the
## scene a [Vector3] — and back. If Y needed flipping somewhere else, a rule has crept into the
## presentation (ADR-0021, decision 2).

## Depth of the corridor in which the game takes place, m.
##
## Everything in play stands in the plane Z = 0; the corridor is the volume around it whose walls
## are visible in the frame. Shallow on purpose: depth comes from the room behind the back wall, not
## from spreading game objects apart (ADR-0021, decision 1).
const CORRIDOR_DEPTH: float = 2.0

## Depth of the room behind the corridor's back wall, m. The number is from the `look3d.gd` trial.
##
## This room is not part of play: you cannot enter it, it is seen through door openings and windows
## and gives the frame depth, fog and a distant plane.
const ROOM_DEPTH: float = 7.0

## The play plane by Z. Zero, and this is no coincidence: everything in play must lie in one plane,
## otherwise "reached or not" becomes a property of mesh placement, not of the rules.
const PLAY_Z: float = 0.0

## Where the corridor's back wall stands. The corridor is symmetric around the play plane, so the
## wall is half its depth behind it. Doors, windows and shaft doors hang on this wall; everything
## behind it is a room you cannot enter.
const BACK_WALL_Z: float = -CORRIDOR_DEPTH * 0.5

## Thickness of game bodies along Z, m: actors, lamps, the cab. One for all, so that shadows and
## collisions meet in one and the same plane, not each in its own.
const BODY_DEPTH: float = 0.4


## Rules plane point → scene point.
static func to_scene(point: Vector2) -> Vector3:
	return Vector3(point.x, -point.y, PLAY_Z)


## Scene point → rules plane point. Z is dropped: the game is flat.
static func to_plane(point: Vector3) -> Vector2:
	return Vector2(point.x, -point.y)


## Rules height → scene height. Separate from a point: floors and ceilings come as a single number,
## and there is no point wrapping them into a [Vector2] for the conversion.
static func height_to_scene(y: float) -> float:
	return -y


## Scene height → rules height.
static func height_to_plane(y: float) -> float:
	return -y


## Plane velocity or offset vector → scene vector.
##
## Separate from [method to_scene] on purpose, although the formula is the same: a point and a
## vector will diverge as soon as the scene gets an offset along Z, and sorting that out in one
## function will be too late.
static func direction_to_scene(delta: Vector2) -> Vector3:
	return Vector3(delta.x, -delta.y, 0.0)


## Scene vector → plane vector.
static func direction_to_plane(delta: Vector3) -> Vector2:
	return Vector2(delta.x, -delta.y)
