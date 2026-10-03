class_name VisibleFloors
extends RefCounted

## Which floors get into the frame.
##
## A building has 30 floors and a light source on each, and the frame fits two
## and a half. Only visible ones should be lit — ADR-0010, point 8.
##
## Computed by floor numbers, not by the camera rectangle: the floor height
## is known, the number is a division. So it is checked without a scene and without a frame,
## with the same trick as [OttoStateMachine] and [ElevatorMotion].

## How many floors are lit beyond the visible ones, on each side.
##
## Without a margin a source would turn on exactly at the frame edge, and a floor entering from
## below would be seen dark for exactly one instant — it is noticeable and reads as flicker.
const MARGIN: int = 1
## How far beyond the frame edge along X light is still needed, m: the lamp fill range.
const BAND_REACH: float = Lamp.FILL_RANGE
## How far beyond the frame edge a lamp still needs a shadow, m: the cone points down, and its
## spot on the floor is a couple of metres; a lamp's shadow from beyond the edge hardly falls into
## the frame, while each one costs as much as drawing the scene again.
const SHADOW_REACH: float = 2.5
## The step by which band edges are rounded, m.
const BAND_STEP: float = 1.8


## First and last floor that should be lit, inclusive.
##
## [param view] — the visible piece of the world, given by [method Otto.camera_view].
static func around(rules: BuildingRules, view: Rect2) -> Vector2i:
	var first := rules.floor_index_near(view.position.y) - MARGIN
	var last := rules.floor_index_near(view.end.y) + MARGIN
	# At the bottom the band stops at the roof, not at floor zero: the roof is the same kind of
	# level with its own light, it just lies above the building (ADR-0014, point 1).
	return Vector2i(maxi(first, BuildingRules.ROOF), mini(last, rules.floors - 1))


## Floors visible in the frame at least by an edge — without margin. They get light with shadow;
## the margin ones from [method around] — only the cone down to their floor (ADR-0042,
## decision 2).
static func seen(rules: BuildingRules, view: Rect2) -> Vector2i:
	return Vector2i(
		maxi(_story_of(rules, view.position.y), BuildingRules.ROOF),
		mini(_story_of(rules, view.end.y), rules.floors - 1)
	)


## The floor whose height [param y] falls into: from the floor above down to its own floor.
static func _story_of(rules: BuildingRules, y: float) -> int:
	var raw := ceilf((y - rules.sky_height) / rules.floor_height) - 1.0
	return clampi(int(raw), BuildingRules.ROOF, rules.floors - 1)


## Whether a floor gets into the frame. The same count as [method around], only the answer
## is about one floor: it is handier for the level to ask this way when it walks all of them.
static func covers(span: Vector2i, index: int) -> bool:
	return index >= span.x and index <= span.y


## The frame band along X in which light makes sense: frame [param view] plus
## [constant BAND_REACH] on each side — beyond that a lamp does not reach the frame.
##
## Since M24h (ADR-0044, decision 11): a per-floor measurement showed that at the bottom of the
## building the frame is twice as expensive — the podium is one and a half frames wide, and floor
## lamps beyond the frame edge were lit and cast shadows: 24 shadowed sources against 8 at the top.
## Band edges follow the [constant BAND_STEP] step: the frame moved by a centimetre —
## no point recomputing the light of the whole building.
static func band(view: Rect2, reach: float = BAND_REACH) -> Vector2:
	return Vector2(
		floorf((view.position.x - reach) / BAND_STEP) * BAND_STEP,
		ceilf((view.end.x + reach) / BAND_STEP) * BAND_STEP
	)


## Whether point [param x] is in band [param strip] ([method band]).
static func in_band(strip: Vector2, x: float) -> bool:
	return x >= strip.x and x <= strip.y
