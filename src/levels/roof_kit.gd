class_name RoofKit
extends Node3D

## Roof equipment: a tank, air conditioners, a dish, solar panels, the roof
## exit, a ladder and an antenna with a blinking light (ADR-0031, decision 2; since M21b —
## pack models, ADR-0033, decision 8). The tall thing above the roof since M24p is the building's
## crown ([BuildingCrown]).
##
## All without bodies or light sources: the antenna light is emission. Stands at the back
## wall of the roof and behind it, on its roof steps, and does not stand in front of the shaft:
## above it is the machine room, where the descent begins. The neon sign
## since M21b lives on the facade corner ([VerticalSign]): on the roof the equipment covered it.

## The equipment stands behind the roof's back wall, on the roof steps, m.
const DEPTH_Z: float = WorldSpace.BACK_WALL_Z - 1.8
## The equipment does not protrude closer than this to the camera: the front face of the machine
## room, behind Otto.
const FRONT_Z: float = WorldSpace.BACK_WALL_Z + BuildingShafts.MACHINE_ROOM_DEPTH
## The equipment does not stand closer to the roof edge, and the gap between items, m.
const EDGE_GAP: float = 0.3
const GAP: float = 0.35

## Ladder to the machine room.
const STEEL := Color(0.3, 0.31, 0.33)
const STEEL_LIGHT := Color(0.52, 0.53, 0.55)

## The light on top of the antenna: size, period and the fraction when it is on.
const BEACON: float = 0.16
const BEACON_PERIOD: float = 1.4
const BEACON_ON: float = 0.35
const BEACON_RED := Color(1.0, 0.12, 0.08)

## What is placed along the long side of the roof — in order from the edge, while
## it fits — and how far each item is pushed out from [constant DEPTH_Z]:
## tall ones further, low ones closer, otherwise the tower would cover the air conditioners.
##
## The water tower is gone since M24p: the tall thing above the roof is the building's crown
## ([BuildingCrown]), the residential building has its own tank on legs. The tank is at the edge.
const LONG_SIDE: Array[String] = [
	"water_tank", "satellite_dish", "air_conditioner", "air_conditioner", "solar_panel"
]
const FORWARD := {
	"water_tank": 0.0,
	"satellite_dish": 0.9,
	"air_conditioner": 1.1,
	"solar_panel": 0.5,
	"roof_exit": 0.8,
	"antenna": 0.7,
	"antenna_small": 0.6,
}

var _beacon: MeshInstance3D = null
var _clock: float = 0.0


## Places the equipment by rules and plan. [param building_seed] decides what is at the
## edge — a tank or an air conditioner: building roofs do not repeat each other.
func build(rules: BuildingRules, plan: BuildingPlan, building_seed: int = 1) -> void:
	var shaft := plan.roof_shaft()
	if shaft == null:
		return
	var steps := BuildingRoof.steps(rules, plan)
	var surface := rules.floor_surface(BuildingRules.ROOF)
	var bounds := rules.floor_span(BuildingRules.ROOF)
	var half_room := BuildingShafts.MACHINE_ROOM_SIZE.x * 0.5
	var left := Vector2(bounds.x + BuildingShell.WALL_WIDTH, shaft.x - half_room)
	var right := Vector2(shaft.x + half_room, bounds.y - BuildingShell.WALL_WIDTH)
	var on_the_left := left.y - left.x >= right.y - right.x
	var long := left if on_the_left else right
	var short := right if on_the_left else left

	var line := LONG_SIDE.duplicate()
	# A draw by seed: a tank or an air conditioner at the edge — roofs do not repeat each other.
	if building_seed % 2 == 0:
		line[0] = "air_conditioner"
	# From the parapet inward: at the edge the tallest, toward the machine room the low ones.
	var cursor := long.x + EDGE_GAP if on_the_left else long.y - EDGE_GAP
	var inward := 1.0 if on_the_left else -1.0
	var limit := long.y - GAP if on_the_left else long.x + GAP
	for prop_name: String in line:
		var width := PropCatalog.footprint(prop_name).x
		var far_edge := cursor + inward * width
		if (far_edge - limit) * inward > 0.0:
			break
		_place(prop_name, cursor + inward * width * 0.5, steps, surface)
		cursor = far_edge + inward * GAP

	var room := short.y - short.x - EDGE_GAP * 2.0
	for prop_name: String in ["roof_exit", "antenna", "antenna_small"]:
		if PropCatalog.footprint(prop_name).x <= room:
			_place(prop_name, (short.x + short.y) * 0.5, steps, surface)
			break
	_ladder(shaft.x - half_room - 0.2, surface)
	_antenna(shaft.x, surface - BuildingShafts.MACHINE_ROOM_SIZE.y)


## Blinks the antenna light. A picture, not a rule: by wall-clock time.
func _process(delta: float) -> void:
	if _beacon == null:
		return
	_clock = fmod(_clock + delta, BEACON_PERIOD)
	_beacon.visible = _clock < BEACON_PERIOD * BEACON_ON


## Roof top at point [param x]: the top of the highest step over it, or the deck.
static func _top_at(steps: Array[Rect2], surface: float, x: float) -> float:
	var top := surface
	for rect in steps:
		if x >= rect.position.x and x <= rect.end.x:
			top = minf(top, rect.position.y)
	return top


## A catalogue model on the roof: bottom on the step under its middle.
##
## Its front no closer than the machine room: roof models are not squashed in depth, and
## the 2.7 m deep roof exit from [constant DEPTH_Z] stood across the
## play plane — Otto walked through it, and it covered Otto (M21b code review).
func _place(prop_name: String, x: float, steps: Array[Rect2], surface: float) -> void:
	var item := PropCatalog.make(prop_name)
	if item == null:
		return
	item.position = WorldSpace.to_scene(Vector2(x, _top_at(steps, surface, x)))
	var depth := PropCatalog.footprint(prop_name).z
	item.position.z = minf(DEPTH_Z + float(FORWARD.get(prop_name, 0.5)), FRONT_Z - depth)
	add_child(item)


func _box(size: Vector3, at: Vector2, z: float, material: StandardMaterial3D) -> MeshInstance3D:
	var part := GreyboxLook.box(size, material)
	part.position = WorldSpace.to_scene(at)
	part.position.z = z
	add_child(part)
	return part


## Ladder to the machine room: two stringers and rungs.
func _ladder(x: float, surface: float) -> void:
	var steel := GreyboxLook.metal(STEEL_LIGHT)
	var height := BuildingShafts.MACHINE_ROOM_SIZE.y + 0.4
	var z := WorldSpace.BACK_WALL_Z + BuildingShafts.MACHINE_ROOM_DEPTH * 0.5
	for dx: float in [-0.18, 0.18]:
		_box(Vector3(0.04, height, 0.04), Vector2(x + dx, surface - height * 0.5), z, steel)
	var rungs := int(height / 0.3)
	for rung in rungs:
		_box(Vector3(0.36, 0.03, 0.03), Vector2(x, surface - 0.25 - float(rung) * 0.3), z, steel)


## The antenna on the machine room with a blinking light on top.
func _antenna(x: float, base: float) -> void:
	var z := WorldSpace.BACK_WALL_Z - 0.2
	var mast := PropCatalog.make("roof_antenna")
	var height := 0.0
	if mast != null:
		mast.position = WorldSpace.to_scene(Vector2(x, base))
		mast.position.z = z - PropCatalog.footprint("roof_antenna").z * 0.5
		add_child(mast)
		height = PropCatalog.footprint("roof_antenna").y
	_beacon = _box(
		Vector3(BEACON, BEACON, BEACON),
		Vector2(x, base - height - BEACON * 0.5),
		z,
		GreyboxLook.light(BEACON_RED)
	)
