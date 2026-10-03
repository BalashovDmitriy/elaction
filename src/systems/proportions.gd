class_name Proportions
extends RefCounted

## Sizes of everything that stands in the building — in one table in original pixels.
##
## Up to M18c metres lived where they were used: height in the actor scene and in
## `tools/build_actors.py`, the door in [Door], the lamp in its own scene, bullets in exports,
## tolerances in the bot. Twenty numbers in a dozen files drifted apart silently: move one, and the
## neighbouring one that depends on it stays as it was. The user's decision (2026-09-23): sizes are
## set here, the rest derive them ([ADR-0026](../../docs/adr/0026-proportions.md), decision 8).
##
## The unit is a pixel of the original frame (arcade, 256×224), not a metre: this way every number
## is checked directly against the frame. [constant PX] converts a pixel to metres: a 48 px floor
## pitch is 3.6 m of our building.
##
## These are **sizes**, not the gaps between them and not speeds. The game rests on the bullet
## passing over a knee and a lamp being out of reach from a jump, and tests guard this with ratios
## ([code]test_proportions.gd[/code]). Speeds and ranges are balance numbers, they belong in
## [BuildingRules].
##
## The test keeps its own table of measurements of the original separately from this one: otherwise
## the test would compare the table with itself.

## Metres per original pixel: a floor pitch of 3.6 m over 48 px.
const PX: float = 0.075

## Floor: pitch and slab. The clearance between them is 40 px, 3.0 m.
const FLOOR: float = 48.0 * PX
const SLAB: float = 8.0 * PX
const CLEARANCE: float = FLOOR - SLAB

## Pitch of a place on a floor and shaft width: 24 px, a shaft is exactly one pitch.
const SLOT: float = 24.0 * PX
const SHAFT: float = 24.0 * PX

## Frame height: the original's building field, 176 px — 3.67 floors.
const FIELD: float = 176.0 * PX

## Width of the original building: the screen, 256 px (ADR-0028, decision 2).
const FIELD_WIDTH: float = 256.0 * PX

## The body is the same for Otto and an agent: in the original they are the same height, 22–23 px
## above the floor. Width 9.6 px versus 10 in the original: this way the body comes to exactly 0.72
## m, from which the escalator opening and the bot's tolerances are measured.
const BODY: float = 22.4 * PX
const BODY_WIDTH: float = 9.6 * PX

## Crouching Otto: 64% of height, like 15–16 px out of the original's 24-px sprite.
const CROUCH: float = 14.4 * PX

## Agent kneeling and lying — ROM hitboxes (@443F, @4533): kneeling 14 px, like a crouching one,
## lying 5 px.
const KNEEL: float = 14.0 * PX
const PRONE: float = 5.0 * PX

## Bullet heights above the floor — the ROM table (table_50D8), the same for Otto and the agent:
## standing 15 px — over a crouching one, from a crouch 9 — over a lying one, lying 3 — into a
## standing and a crouching one, only a jump saves from it (ADR-0027, decision 3).
const SHOT_HIGH: float = 15.0 * PX
const SHOT_LOW: float = 9.0 * PX
const SHOT_PRONE: float = 3.0 * PX

## The agent's standing bullet is the same as Otto's.
const AGENT_SHOT: float = SHOT_HIGH

## Gun offset forward from the middle of the body.
const MUZZLE: float = 7.0 * PX
## Gun offset when lying: the body lies forward from the heels, and the gun in outstretched arms is
## farther than when standing. At 7 px the bullet would fly out from under the chest (ADR-0043,
## decision 16).
const MUZZLE_PRONE: float = 10.0 * PX

## Door leaf: 16×28 px, the top 12 px from the ceiling. The mat is two thirds of the leaf.
const DOOR := Vector2(16.0 * PX, 28.0 * PX)
const DOOR_MAT: float = DOOR.x * 2.0 / 3.0

## Lamp: 8×6 px right under the ceiling, on a half-pixel cord. The bottom comes to 84% of the
## clearance versus 82% in the original — this is the margin on which "a lamp cannot be shot down
## from a jump" rests (ADR-0026, decision 5).
const LAMP := Vector2(8.0 * PX, 6.0 * PX)
const LAMP_CORD: float = 0.4 * PX

## Exit opening: no wider than a place without a cab of the neighbouring shaft, 22.4 px.
const EXIT_WIDTH: float = 22.4 * PX

## Floor number: a 12×7 px plate 1.4 px from the wall and the ceiling, a 5 px digit.
const FLOOR_SIGN := Vector2(12.0 * PX, 7.0 * PX)
const FLOOR_SIGN_GAP: float = 1.4 * PX
const FLOOR_DIGIT: float = 5.0 * PX

## The car at the exit, length: Otto gets into it. In the original it is 1.9 times his height; Cars
## Pack cars (ADR-0032, decision 7) are brought to length with one scale shared with height so the
## wheels stay round, and at 1.9 heights they came out toy-like — a metre tall. At 2.1 heights the
## car is half a metre lower than Otto, as in real life.
const CAR_LENGTH: float = BODY * 2.1


## Gives a box shape its size and, if [param grounded], puts its bottom at the node's zero: a
## [CollisionShape3D] has its origin in the middle, and a size change alone would sink the body into
## the floor.
##
## The shape sub-resource is shared by all copies of the scene, and it is edited in place: the
## number is the same for all, and a repeated edit changes nothing. Whoever needs its own shape — an
## agent crouching independently of the others — copies it itself.
static func fit_box(shape: CollisionShape3D, size: Vector3, grounded: bool = true) -> void:
	(shape.shape as BoxShape3D).size = size
	if grounded:
		shape.position.y = size.y * 0.5


## The same for a visible box.
static func fit_mesh(visual: MeshInstance3D, size: Vector3) -> void:
	(visual.mesh as BoxMesh).size = size
