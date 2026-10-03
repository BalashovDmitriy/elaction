class_name BuildingRibs
extends Node3D

## Building ribs: slab edges, skirting and pilasters (ADR-0023, decision 4).
##
## A trial showed: under soft light a smooth box reads as a blob, and half the frame
## was pulled out not by sources but by ribs — something for the light to catch on. The milestone
## includes three, and only those; silhouette, shafts and dressing stay for M18 and M19.
##
## Boxes without bodies, in their own node — like the shaft dress: about fifteen parts
## per floor come out, and they must not fall under a walk of the level's children.

## Slab edge: a light strip along the front edge of the slab — a fraction of the slab
## thickness, at what fraction from the top its middle lies, and the forward overhang, m.
const EDGE_SHARE: float = 0.35
const EDGE_DROP: float = 0.2
const EDGE_DEPTH: float = 0.12

## Skirting along the bottom of the back wall: a dark panel and a light rail on top, m.
const SKIRTING_HEIGHT: float = 0.9
const SKIRTING_DEPTH: float = 0.16
const RAIL_HEIGHT: float = 0.08
const RAIL_DEPTH: float = 0.2

## Pilasters: at the edges of each wall section and between floor slots, m. They stop short
## of the floor and ceiling by a gap.
const PILASTER_WIDTH: float = 0.45
const PILASTER_DEPTH: float = 0.22
const PILASTER_GAP: float = 0.1
## An intermediate pilaster is not placed closer than this to a wall section's edge: two side by
## side read as a column, not a rhythm.
const PILASTER_CLEARANCE: float = 1.0

## Floor slots per structural bay — every this many grid boundaries stands
## an intermediate pilaster.
##
## The wall rhythm need not follow the layout grid. In M18 the grid became twice as fine
## (ADR-0024, decision 1), and a pilaster on every boundary would stand every 1.8 m:
## twice as often as before, twice as many boxes in frame and a picket fence instead of a rhythm.
## Two slots per bay restore the former pitch.
##
## **The rhythm is asymmetric, and this is accepted as is** (user's decision,
## 2026-09-22). A two-slot pitch passes boundaries 0–1, 2–3 … 14–15 and does not reach
## 15–16, so on the narrow tower the bays lie offset from the middle.
## A symmetric variant with 17 slots and a two-slot pitch does not exist at all:
## sixteen boundaries cannot be divided by two so that the middle falls on a joint.
## The choice was between an offset rhythm and an uneven central bay — the first
## was kept. Change only together with the number of slots.
const SLOTS_PER_BAY: int = 2

var _rules: BuildingRules
var _plan: BuildingPlan
var _identity: BuildingIdentity = BuildingIdentity.new()
## The look by building kind: one per building, but it is asked for on every wall section.
var _style: BuildingStyle = null


func setup(
	rules: BuildingRules, plan: BuildingPlan, identity: BuildingIdentity = BuildingIdentity.new()
) -> void:
	_rules = rules
	_plan = plan
	_identity = identity
	_style = BuildingStyle.of(identity)


## What the building is: the wall and pilaster finish depends on it.
func identity() -> BuildingIdentity:
	return _identity


## The slab edge along its front edge. [param slab] — a piece of the slab in
## the rule plane, the same one the level builds the body from.
func edge_of(slab: Rect2) -> void:
	var height := slab.size.y * EDGE_SHARE
	var strip := Rect2(
		slab.position.x,
		slab.position.y + slab.size.y * EDGE_DROP - height * 0.5,
		slab.size.x,
		height
	)
	_add_part(
		strip, GreyboxLook.metal(GreyboxLook.TRIM), WorldSpace.CORRIDOR_DEPTH * 0.5, EDGE_DEPTH
	)


## A floor's skirting and pilasters — along the back wall sections between openings.
##
## [param inner] — wall to wall, [param openings] — door and exit openings;
## shaft openings are added here: the shaft leaves stand on the same wall.
func line_the_wall(index: int, inner: Vector2, openings: Array[Vector2]) -> void:
	# Office — floor-to-ceiling glass (ADR-0056, decision 4): neither a bottom panel nor
	# pilasters in front of it, the wall itself places the mullions ([BuildingShell]).
	if _style.glass_wall:
		return
	var surface := _rules.floor_surface(index)
	var top := _rules.story_top(index)
	var gaps := openings.duplicate()
	# A shaft opening comes with the portal trim: a pilaster at the edge of the wall section would
	# otherwise stand over the chrome frame and hide it (M21b code review).
	var half := _rules.shaft_width * 0.5 + BuildingShafts.PORTAL_JAMB
	for shaft in _plan.shafts:
		if index >= shaft.top and index <= shaft.bottom:
			gaps.append(Vector2(shaft.x - half, shaft.x + half))

	# Sconces are on the hotel's pilasters (ADR-0048); on a dark floor the light is off
	# by ROM rules, and a glowing sconce would argue with the darkness.
	var sconces := _style.sconces and not _rules.is_unlit(index)
	# Special floor (ADR-0057, decision 3): no bottom panel — there is no wall; the pilasters
	# remain as columns between the corridor and the hall, and in front of glass and mesh even they
	# are not needed.
	var hall := FloorRole.at(_rules, index)
	if (
		FloorRole.is_hall(hall)
		and FloorRole.screen_of(hall, _rules.kind) != FloorRole.Screen.COLUMNS
	):
		return
	for span in BuildingPlan.spans_between(gaps, inner):
		if not FloorRole.is_hall(hall):
			_skirting(span, surface)
		_pilasters(span, top, surface, sconces)


func _skirting(span: Vector2, surface: float) -> void:
	var width := span.y - span.x
	var height := _style.wainscot_height
	_add_part(
		Rect2(span.x, surface - height, width, height),
		BuildingFinish.wainscot(_identity, _rules.palette.story),
		WorldSpace.BACK_WALL_Z,
		SKIRTING_DEPTH
	)
	_add_part(
		Rect2(span.x, surface - height - RAIL_HEIGHT, width, RAIL_HEIGHT),
		GreyboxLook.metal(_style.rail_tone),
		WorldSpace.BACK_WALL_Z,
		RAIL_DEPTH
	)


## Pilasters of a wall section: one at each of its edges and one between neighbouring
## floor slots, if the edges are far. The rhythm follows slots, not metres:
## doors and shafts stand on slots, and pilasters between them fall evenly.
##
## [param sconces] — whether to hang a sconce on each ([WallSconce]).
func _pilasters(span: Vector2, top: float, surface: float, sconces: bool = false) -> void:
	var width := span.y - span.x
	if width < PILASTER_WIDTH:
		return
	var centres := PackedFloat64Array()
	if width < PILASTER_WIDTH * 2.0 + PILASTER_GAP:
		centres.append((span.x + span.y) * 0.5)
	else:
		centres.append(span.x + PILASTER_WIDTH * 0.5)
		centres.append(span.y - PILASTER_WIDTH * 0.5)
		for slot in range(0, _rules.slots - 1, SLOTS_PER_BAY):
			var middle := (_rules.slot_x(slot) + _rules.slot_x(slot + 1)) * 0.5
			if middle > span.x + PILASTER_CLEARANCE and middle < span.y - PILASTER_CLEARANCE:
				centres.append(middle)

	var height := surface - top - PILASTER_GAP * 2.0
	for centre in centres:
		_add_part(
			Rect2(centre - PILASTER_WIDTH * 0.5, top + PILASTER_GAP, PILASTER_WIDTH, height),
			BuildingFinish.pilaster(
				_identity, GreyboxLook.PILASTER.lerp(_rules.palette.masonry, 0.1)
			),
			WorldSpace.BACK_WALL_Z,
			PILASTER_DEPTH
		)
		if sconces:
			var at := WorldSpace.to_scene(Vector2(centre, surface - WallSconce.HEIGHT))
			at.z = WorldSpace.BACK_WALL_Z + PILASTER_DEPTH
			add_child(WallSconce.hang(at))


## A part of depth [param depth], back face at [param face]: ribs stand
## on the wall or the slab edge and protrude from them forward, toward the camera.
func _add_part(rect: Rect2, material: StandardMaterial3D, face: float, depth: float) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var part := GreyboxLook.box(Vector3(rect.size.x, rect.size.y, depth), material)
	part.position = WorldSpace.to_scene(rect.get_center())
	part.position.z = face + depth * 0.5
	add_child(part)
