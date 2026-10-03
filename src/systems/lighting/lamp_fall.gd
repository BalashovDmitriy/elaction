class_name LampFall
extends RefCounted

## Lamp fall: shot down or not, how far it has fallen, whether it reached the floor.
##
## No nodes, no physics — the node asks how far to move in this frame. The same trick
## as [DoorVisit] and [EnemyBrain]: the rules are checked without a scene, as the project
## conventions require.

## Fall speed, px/s.
var speed: float = 780.0

## How far to fall to the floor, px. Computed from the lamp's own shape.
var distance: float = 120.0

var falling: bool = false

var _fallen: float = 0.0


## Shoots the lamp down. Returns false if it is already falling or fell long ago:
## otherwise a second bullet in the same frame would raise it back — the node does not
## disappear at once.
func start() -> bool:
	if falling or _fallen > 0.0:
		return false
	falling = true
	return true


## How far the lamp moves down in this frame. Zero while it hangs or has already fallen.
func advance(delta: float) -> float:
	if not falling:
		return 0.0

	var step := minf(speed * delta, distance - _fallen)
	_fallen += step
	if _fallen >= distance:
		falling = false
	return step


## Whether the lamp has reached the floor.
func has_landed() -> bool:
	return _fallen >= distance
