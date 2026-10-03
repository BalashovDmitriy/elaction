class_name BuildingRoof
extends Node3D

## Roof slopes in steps on both sides of the shaft (ADR-0029, decision 4).
##
## In the original the roof above the thirtieth floor rises in steps toward the shaft on both sides,
## and the frame reads as the top of a building. Here it is a silhouette behind the play plane: the
## steps stand behind the corridor, without bodies, and Otto walks on the flat deck — the path, the
## bot and the traversability checks do not change.

## How many steps in a slope.
const STEPS: int = 4

## Step height, m. The top step is lower than the machine room ([constant
## BuildingShafts.MACHINE_ROOM_SIZE]): the shaft rises above the slopes, as in the original.
const STEP_RISE: float = 0.3

## Ribs of the roofing sheets on the steps: pitch and section, m.
const RIB_STEP: float = 0.45
const RIB := Vector2(0.05, 0.05)

## How far the slope stops short of the machine room, m.
const MACHINE_ROOM_GAP: float = 0.15

## Share of the round palette's masonry in the slope tone. Smaller than for the walls ([constant
## BuildingShell.PALETTE_SHARE]), and from the tone of the far wall, not the corridor wall: the
## slopes stand behind the play and should recede into the background, not compete with the parapets
## (M19 shots).
const PALETTE_SHARE: float = 0.08


## Slope steps as rules rectangles: x along the roof, y — from the top of the step to the deck. The
## left slope rises left to right, the right one right to left.
##
## Static: the geometry is checked without a scene — the steps are inside the roof and do not go
## into the machine room.
static func steps(rules: BuildingRules, plan: BuildingPlan) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var shaft := plan.roof_shaft()
	if shaft == null:
		return rects
	var bounds := rules.floor_span(BuildingRules.ROOF)
	var inner := Vector2(bounds.x + BuildingShell.WALL_WIDTH, bounds.y - BuildingShell.WALL_WIDTH)
	var half_room := BuildingShafts.MACHINE_ROOM_SIZE.x * 0.5 + MACHINE_ROOM_GAP
	var surface := rules.floor_surface(BuildingRules.ROOF)
	var sides: Array[Vector2] = [
		Vector2(inner.x, shaft.x - half_room), Vector2(shaft.x + half_room, inner.y)
	]
	for side in sides.size():
		var span := sides[side]
		var length := span.y - span.x
		if length <= 0.0:
			continue
		var run := length / float(STEPS)
		for step in STEPS:
			# A step lies from its edge to the machine room: the lower ones are wider, the upper ones
			# narrower, and together they add up to a slope.
			var rise := STEP_RISE * float(step + 1)
			var from := span.x + run * float(step) if side == 0 else span.x
			var to := span.y if side == 0 else span.y - run * float(step)
			rects.append(Rect2(from, surface - rise, to - from, rise))
	return rects


## Places the slopes by rules and plan. Colour — the round palette's masonry, muted toward grey: the
## roof is background, not a sign (ADR-0029, decision 5).
func build(rules: BuildingRules, plan: BuildingPlan) -> void:
	var tone := GreyboxLook.SKY_WALL.lerp(rules.palette.masonry, PALETTE_SHARE)
	# The roofing is gravel (ADR-0033, decision 8), the round tone as a multiplier.
	var material := BuildingFinish.roof_gravel(tone)
	var depth := WorldSpace.ROOM_DEPTH
	var rib := GreyboxLook.metal(GreyboxLook.SKY_WALL.lerp(GreyboxLook.TRIM, 0.35))
	for rect in steps(rules, plan):
		var box := GreyboxLook.box(Vector3(rect.size.x, rect.size.y, depth), material)
		box.position = WorldSpace.to_scene(rect.get_center())
		box.position.z = WorldSpace.BACK_WALL_Z - depth * 0.5
		add_child(box)
		# Ribs of the roofing sheets along the top of the step (ADR-0031, decision 2): a blank box read as
		# a wall, not a roof.
		var count := int(rect.size.x / RIB_STEP)
		for index in count:
			var x := rect.position.x + RIB_STEP * (float(index) + 0.5)
			var strip := GreyboxLook.box(Vector3(RIB.x, RIB.y, depth), rib)
			strip.position = WorldSpace.to_scene(Vector2(x, rect.position.y - RIB.y * 0.5))
			strip.position.z = box.position.z
			add_child(strip)
