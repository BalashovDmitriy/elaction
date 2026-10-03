class_name CarCut
extends RefCounted

## A body cut by the cab's floor (ADR-0043, decisions 7–9).
##
## The cab, coming down, cuts the figure along its walls: everything between them and
## above the cab floor disappears, and the cut moves down with the cab. The shader cuts
## ([method FigureRig.carve]), not the geometry: the pack figure is skinned, and cutting
## its mesh on the fly means recomputing vertices every frame. The cut keeps the lowest
## height of the cab floor: a cab that went back up does not restore what was cut off.
##
## While the cut passes through the body, blood sprays from it; having reached the floor,
## the cab leaves a pool under itself. Which body parts disappeared is decided by [Corpse].

## Every how many metres of the cab floor's travel through the body the spray repeats.
const SPRAY_STEP: float = 0.08

var left: float = 0.0
var right: float = 0.0
## The cab floor height the cut has reached, scene m.
var top: float = INF
## The body's bounds in the world at the moment of first contact.
var body := AABB()
## The cab reached the floor under the body: the cut is over, the pool lies.
var done: bool = false

var _sprayed_at: float = INF


## Drives the cut of [param figure] by a cab with walls [param from_x]..[param to_x] and
## floor at height [param bottom]; the body lies within bounds [param reach]. Puts the
## spray and the pool into [param host]. Returns true if the cut went down.
func advance(
	figure: FigureRig, host: Node, from_x: float, to_x: float, bottom: float, reach: AABB
) -> bool:
	if top == INF:
		left = from_x
		right = to_x
		body = reach
	if bottom >= top:
		return false
	top = bottom
	figure.carve_under(left, right, top)
	var low := maxf(body.position.x, left)
	var high := minf(body.end.x, right)
	if high <= low:
		done = true
		return true
	if top < body.end.y and _sprayed_at - top >= SPRAY_STEP:
		_sprayed_at = top
		_spray(host, low, high)
	if not done and top <= body.position.y + SPRAY_STEP:
		done = true
		Blood.puddle(
			host, Vector3((low + high) * 0.5, body.position.y, body.get_center().z), high - low
		)
	return true


## Spray from the cut: at the wall beyond which the body continues — outward, from under
## the cab floor — both ways.
func _spray(host: Node, low: float, high: float) -> void:
	var z := body.get_center().z
	var at := clampf(top, body.position.y, body.end.y)
	if body.position.x < left:
		Blood.spray(host, Vector3(left, at, z), -1.0)
	if body.end.x > right:
		Blood.spray(host, Vector3(right, at, z), 1.0)
	if body.position.x >= left and body.end.x <= right:
		var middle := (low + high) * 0.5
		Blood.spray(host, Vector3(middle, at, z), -1.0)
		Blood.spray(host, Vector3(middle, at, z), 1.0)
