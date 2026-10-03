class_name CameraBounds
extends RefCounted

## Where the camera may look: the framing rule separate from the node.
##
## [Camera2D] gave this for free — `limit_left`, `limit_top`, smoothing. [Camera3D] has
## none of that, and in the move to 3D all of it would have had to be written in the
## node's [code]_process[/code]. A rule in a node is a mistake per ADR-0021, decision 5,
## so it lives here and is checked without a scene.
##
## Works in scene coordinates (Y up): [WorldSpace] converts them, and they arrive here
## already converted.

## Half of the frame vertically and horizontally, m. Set by the orthographic camera's
## size and the window's aspect ratio.
## By default — the [SideCamera] frame at 16:9: in height on the play plane this is the
## original's building field, the camera tilt already accounted for.
## Closer than this to the target the camera snaps exactly onto it, m: half a millimetre
## is a hundredth of a pixel in a FullHD frame.
const ARRIVED: float = 0.0005

var half_height: float = Proportions.FIELD * 0.5
var half_width: float = SideCamera.DEFAULT_HALF_HEIGHT * 16.0 / 9.0

## The rectangle the camera must not go beyond, in scene coordinates.
var limits := Rect2(-INF, -INF, INF, INF)


## The frame middle allowed by these bounds.
##
## If the allowed band is narrower than the frame, the camera stands at its middle: it
## cannot rest against both edges at once, and jerking between them is the worst
## possible option.
func clamp_centre(wanted: Vector2) -> Vector2:
	return Vector2(
		_clamp_axis(wanted.x, limits.position.x, limits.end.x, half_width),
		_clamp_axis(wanted.y, limits.position.y, limits.end.y, half_height)
	)


## What is in the frame now, in scene coordinates.
func view_at(centre: Vector2) -> Rect2:
	var size := Vector2(half_width, half_height) * 2.0
	return Rect2(centre - size * 0.5, size)


## Smoothing step: where the camera moves in [param delta] at speed [param speed].
##
## Exponential approach, not linear: it does not depend on frame rate and does not let
## the camera overtake the target during a frame drop. [code]speed <= 0[/code] — rigid
## attachment without smoothing, needed for tests and capturing shots.
static func smoothed(from: Vector2, towards: Vector2, speed: float, delta: float) -> Vector2:
	if speed <= 0.0 or delta <= 0.0:
		return towards
	var moved := from.lerp(towards, 1.0 - exp(-speed * delta))
	# The exponential never reaches the target: the camera would crawl toward a standing
	# Otto forever, by fractions of a pixel per frame, and the edges of doors and slabs
	# would flicker (measured with `tools/flicker_shot.tscn`, M22). Within half a
	# millimetre it snaps exactly.
	if moved.distance_to(towards) < ARRIVED:
		return towards
	return moved


func _clamp_axis(wanted: float, low: float, high: float, half: float) -> float:
	if not is_finite(low) or not is_finite(high):
		return wanted
	if high - low <= half * 2.0:
		return (low + high) * 0.5
	return clampf(wanted, low + half, high - half)
