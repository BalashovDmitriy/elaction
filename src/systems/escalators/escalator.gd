class_name Escalator
extends Node3D

## An escalator between two floors.
##
## In the original one does not step onto it in passing: one has to stand on the landing at
## the edge and press "up" or "down" (ADR-0004, item 8). While it carries there is no
## control, Otto's position is handled by the escalator, not by physics.
##
## The node is placed on the upper landing; the lower one and the bend point are set in
## [method setup]. The ride follows the same path the belt is laid along, and
## starts where the passenger stood: otherwise he would be jerked towards the centre of the
## landing, and the belt would cut the slab outside the opening (found by code review M2).
##
## Since M18b the escalator is a structure, not two belt boxes
## ([ADR-0025](../../../docs/adr/0025-shafts-escalators-and-riders.md), decision 4):
## relief steps, landings at the ends, a balustrade and an opening frame. Relief,
## not animation: the M17 light falls on geometry, which is what the pivot was for.
##
## Since M24g the structure is made of parts of a model built by its own Blender script
## (`tools/build_escalator.py`, ADR-0043, decision 3): ribbed steps with a yellow
## edge, a glass balustrade with a handrail, newels, landings with a comb plate,
## a truss. The span differs in every building, so the model is a set of parts, and
## the escalator places them: the steps one by one, the rest stretched
## along the length.

## Since M24h the escalator stands in the depth, by the back wall (ADR-0044, decision 10):
## the span is behind the play plane, the slab in front of it is solid, and one walks past
## the escalator on the floor. One steps onto the landing by a step into the depth, as into
## a red door, and steps off by a step back towards the camera.

## Escalator parts and their sizes in the model, m: the parts are stretched by them.
const KIT := preload("res://assets/models/escalator/escalator.glb")
const KIT_STEP_RUN: float = 0.2
const KIT_STEP_HEIGHT: float = 0.45
const KIT_LANDING_RUN: float = 0.42

## How far the clatter of the belt carries, m.
const HUM_REACH: float = 9.0

## Up to where from the camera the slab under the escalator is solid, m along Z: the opening
## is only beyond this edge, in the back strip of the corridor. The body of Otto walking
## past is in front of it.
const HOLE_FRONT_Z: float = -WorldSpace.BODY_DEPTH * 0.5 - 0.04

## Belt thickness and depth, m. The belt has no body: the escalator carries, not the floor.
const BELT_THICKNESS: float = 0.15
const BELT_DEPTH: float = 0.72

## Middle of the belt along Z: beyond the edge of the solid slab, by the back wall. The
## passenger rides along it too.
const BELT_Z: float = HOLE_FRONT_Z - BELT_DEPTH * 0.5 - 0.01

## How far the belt travels horizontally per step, m.
##
## The step is exactly what distinguishes an escalator from a ramp: on a 1.6 m span
## there are half a dozen of them, and the jagged edge reads from any floor.
const STEP_RUN: float = 0.2

## Balustrades at the edges of the belt — by the back wall and on the camera side, m along Z.
## In front since M24h it is also glass with a handrail, not a low side: the railing
## must read, and a riding Otto is visible behind the glass (ADR-0044, decision 10).
const RAIL_Z: float = BELT_Z - BELT_DEPTH * 0.5 + 0.03
const FRONT_RAIL_Z: float = BELT_Z + BELT_DEPTH * 0.5 - 0.03
const RAIL_THICKNESS: float = 0.1
const RAIL_HEIGHT: float = 0.96

## Handrail on top of the balustrade: square in section, m.
const HANDRAIL_SIZE: float = 0.1

## Indicator light at the end of the handrail: cube edge, m.
const END_LIGHT_SIZE: float = 0.16

## The span's own source: radius, energy, colour and offset in front of the steps.
##
## Without it two rails in the dark are all that remains of the structure: a measurement
## on 24 seeds gave 25 escalators out of 120 under a lamp pool, 5.7 m to a lamp on average.
## The source does not go out from a shot and takes no part in darkness zones — for the same
## reason as the light column in a shaft (ADR-0025, decision 3): darkness decides whether
## the agents see Otto, while the way down must always read.
##
## It casts no shadows: the span stands in an opening, there is nothing to cast them on,
## and they cost more than anything else in the frame.
const GLOW_RANGE: float = 3.6
const GLOW_ENERGY: float = 1.2
const GLOW_COLOR := Color(1.0, 0.88, 0.68)
const GLOW_Z: float = -0.1

## Landing at the end of the belt: length along the travel and thickness, m.
##
## Shorter than it was: the landing does not reach into the neighbouring slot, where a
## floor below a shaft may stand (ADR-0026, decision 6).
const LANDING_RUN: float = 0.42
const LANDING_THICKNESS: float = 0.12

## Opening frame: width of a post along the edge of the hole, m.
const FRAME_WIDTH: float = 0.12

## Part meshes by name: shared by all escalators of the building.
static var _meshes: Dictionary = {}

## Ride speed, m/s along the path. Before M24g a ride over the short steep span
## took 1.1 s; with the gentle span of M24g the path is longer, and the time is computed
## from it ([method setup]), while the speed stays the same.
@export var ride_speed: float = 4.3

## How many seconds a ride between the landings takes.
@export var travel_time: float = 1.1

## The floor the escalator goes down from. The level sets it: the floor is not derived back
## from the coordinate — the node stands exactly on the floor, where rounding is
## a matter of chance. By it the level turns off the span's source off-frame.
var floor_index: int = 0

var _passenger: Otto = null
var _path: PackedVector3Array = PackedVector3Array()
var _progress: float = 0.0
## Belt bend in local coordinates. Empty — [method setup] was not called.
var _via := Vector3.ZERO
var _has_via: bool = false
## The span's source. Empty — [method setup] was not called.
var _glow: OmniLight3D = null

var _hum: AudioStreamPlayer3D = null
@onready var _top_pad: Area3D = $TopPad
@onready var _bottom_pad: Area3D = $BottomPad
@onready var _ramp: Node3D = $Ramp


func _ready() -> void:
	_hum = Sounds.source(self, Sounds.ESCALATOR_HUM, HUM_REACH)


func _physics_process(delta: float) -> void:
	# The belt is audible only while someone rides: in the original the escalator does
	# not hum by itself either, and the building is noisy enough.
	Sounds.keep_playing(_hum, _passenger != null)

	if _passenger != null:
		_carry(delta)
		return
	# Up is called from the lower landing, down from the upper one.
	if not _try_board(_bottom_pad, _top_pad, Intent.UP):
		_try_board(_top_pad, _bottom_pad, Intent.DOWN)


## Sets the geometry in rules coordinates. [param descent] — offset of the lower
## landing from the upper one, [param via] — the bend point in the slab opening: both
## the belt and the ride itself go through it, so the passenger passes through the hole,
## not through the slab. [param gap] — opening edges relative to the node, [param slab] —
## slab thickness: the frame is placed by them.
func setup(descent: Vector2, via: Vector2, gap: Vector2, slab: float) -> void:
	var down := WorldSpace.direction_to_scene(descent)
	_via = WorldSpace.direction_to_scene(via)
	_has_via = true
	_bottom_pad.position = down
	# The step into the depth onto the landing and back towards the camera is part of the path.
	var depth := absf(BELT_Z) * 2.0
	travel_time = (_via.length() + (down - _via).length() + depth) / ride_speed
	_build(down, gap, slab)


## Whether the escalator is carrying anyone right now.
func is_busy() -> bool:
	return _passenger != null


## Turns the span's source off or on. Called by the level when picking visible floors —
## by the same rule as for lamps and shaft columns (ADR-0010, item 8).
##
## This is not the same as "went out from a shot": the span's source takes no part
## in darkness zones and does not go out from a bullet (ADR-0025, decision 4) — but it is
## meant to shine in frame, not in the whole building at once. There are over fifty
## light sources per building, and escalators that never went dark ate the whole light budget.
func set_light_visible(on: bool) -> void:
	if _glow != null:
		_glow.visible = on


func _try_board(pad: Area3D, target: Area3D, towards: float) -> bool:
	for body: Node3D in pad.get_overlapping_bodies():
		var rider := body as Otto
		if rider == null or not rider.is_grounded():
			continue
		var intent := rider.vertical_intent()
		if absf(intent) < Intent.PRESS or signf(intent) != towards:
			continue

		_passenger = rider
		_path = _route_from(rider.global_position, target)
		_progress = 0.0
		# Otto walks on the steps, facing the direction of travel (ADR-0043, decision 2).
		rider.ride_look = Otto.LOOK_WALK
		rider.ride_facing = signf(target.global_position.x - rider.global_position.x)
		rider.ride(true)
		return true
	return false


## The ride path: from where the passenger stood, a step into the depth onto the belt, via
## the bend to the far landing and a step back into the play plane.
##
## The bend is taken from the belt, so one rides exactly where it is laid. Without
## [method setup] there is no belt — then the path is straight, just to avoid an index error.
func _route_from(start: Vector3, target: Area3D) -> PackedVector3Array:
	var finish := target.global_position
	if not _has_via:
		return PackedVector3Array([start, finish])
	var belt := Vector3(0.0, 0.0, BELT_Z - start.z)
	var bend := to_global(_via)
	bend.z = start.z + belt.z
	return PackedVector3Array(
		[start, start + belt, bend, Vector3(finish.x, finish.y, bend.z), finish]
	)


func _carry(delta: float) -> void:
	_progress = minf(_progress + delta / travel_time, 1.0)
	_passenger.global_position = _point_at(_progress)
	if _progress < 1.0:
		return
	_passenger.ride(false)
	_passenger = null


## A point on the polyline by fraction of the path: the length is computed from the segments
## themselves, so the speed does not jump at the bend.
func _point_at(ratio: float) -> Vector3:
	var total := 0.0
	for index in _path.size() - 1:
		total += _path[index].distance_to(_path[index + 1])
	if is_zero_approx(total):
		return _path[_path.size() - 1]

	var travelled := total * ratio
	for index in _path.size() - 1:
		var length := _path[index].distance_to(_path[index + 1])
		if travelled <= length or index == _path.size() - 2:
			var part := travelled / length if length > 0.0 else 1.0
			return _path[index].lerp(_path[index + 1], minf(part, 1.0))
		travelled -= length
	return _path[_path.size() - 1]


## Rebuilds the structure from the given geometry.
##
## The polyline is a landing along the floor up to the opening and one straight span down.
## Before M18b it was two spans of different steepness, and in the frame it read as a chute:
## a gentle 25° entry ran into a 63° drop, and the balustrades of the two spans
## fanned apart at the bend.
func _build(down: Vector3, gap: Vector2, slab: float) -> void:
	for part: Node in _ramp.get_children():
		part.queue_free()

	var towards := signf(down.x)
	_lay_landing(Vector3.ZERO, _via)
	_lay_flight(_via, down)
	# The lower landing extends along the descent: one steps off it on arrival. With its comb
	# plate it faces the steps — it is laid out from its far edge towards them.
	_lay_landing(down + Vector3(towards * LANDING_RUN, 0.0, 0.0), down)
	_frame_the_gap(gap, slab)


## The span: belt below, steps on top, balustrade and side panels at the sides.
func _lay_flight(from: Vector3, to: Vector3) -> void:
	var span := to - from
	if is_zero_approx(span.length()):
		return

	_lay_belt(from, to)
	_lay_steps(from, span)
	_lay_sides(from, to)
	_light_the_flight(from, to)


## The span truss with cladding underneath, along the polyline.
##
## From the side the steps cover it, but from below this is exactly what is seen: the
## escalator passes through the slab, and from the floor below one looks at its belly.
func _lay_belt(from: Vector3, to: Vector3) -> void:
	var span := to - from
	_add_kit(
		"Truss",
		(from + to) * 0.5 + Vector3(0.0, -BELT_THICKNESS, BELT_Z),
		atan2(span.y, span.x),
		Vector3(span.length(), 1.0, 1.0)
	)


## The span's steps: boxes with flat tops, each lower than the previous one.
##
## They are deliberately not rotated along the span — a rotated box gives a ramp again.
## The top of a step lies on the polyline, the bottom goes below it, and neighbours overlap
## each other: the silhouette comes out jagged, and there are no gaps between the steps.
func _lay_steps(from: Vector3, span: Vector3) -> void:
	var count := maxi(int(absf(span.x) / STEP_RUN), 1)
	var tread := span.x / float(count)
	var riser := span.y / float(count)
	var height := absf(riser) + BELT_THICKNESS

	# The step's yellow edge is on the descent side: the edge one steps down from.
	for index in count:
		var top := from.y + riser * float(index)
		_add_kit(
			"Step",
			Vector3(from.x + tread * (float(index) + 0.5), top, BELT_Z),
			0.0,
			Vector3(tread / KIT_STEP_RUN, height / KIT_STEP_HEIGHT, 1.0)
		)


## Span sides: glass balustrades with a handrail by the back wall and by the camera.
func _lay_sides(from: Vector3, to: Vector3) -> void:
	var span := to - from
	var angle := atan2(span.y, span.x)
	var centre := (from + to) * 0.5
	var length := span.length()
	# The span normal, always up: the balustrade stands on the belt rather than hanging
	# below it, and on a descent to the left the span sign must not flip it.
	var up := Vector3(-span.y, span.x, 0.0).normalized()
	if up.y < 0.0:
		up = -up

	var over := BELT_THICKNESS * 0.5
	var stretch := Vector3(length, 1.0, 1.0)
	for z: float in [RAIL_Z, FRONT_RAIL_Z]:
		_add_kit("Balustrade", centre + up * over + Vector3(0.0, 0.0, z), angle, stretch)
		for end: Vector3 in [from, to]:
			_add_kit("Newel", end + up * over + Vector3(0.0, 0.0, z), 0.0, Vector3.ONE)

	var cap := up * (over + RAIL_HEIGHT + HANDRAIL_SIZE * 0.5) + Vector3(0.0, 0.0, FRONT_RAIL_Z)
	_mark_end(from + cap)
	_mark_end(to + cap)


## Span light: one lamp in the middle, in front of the steps.
##
## It stands right in the opening and lights both floors the escalator links —
## this is not a leak, but exactly what the escalator does.
func _light_the_flight(from: Vector3, to: Vector3) -> void:
	var light := OmniLight3D.new()
	light.omni_range = GLOW_RANGE
	light.light_energy = GLOW_ENERGY
	light.light_color = GLOW_COLOR
	light.shadow_enabled = false
	light.position = (from + to) * 0.5 + Vector3(0.0, 0.0, GLOW_Z)
	_ramp.add_child(light)
	_glow = light


## Indicator light at the end of the handrail.
##
## Measured on 24 seeds: of 120 escalators 25 stand under a lamp pool, the nearest
## lamp is 5.7 m away on average, 10.5 at worst. There are few slots on a floor, an escalator
## takes two — and it ends up where there is no lamp. A structure that cannot be seen gives
## nothing, and there is no reason to light it with a source: the project already answers
## this with indicator lights (ADR-0023, decision 6) — that is how the door indicator boards,
## the cab indicators and the exit sign read. Two lights at the ends of the handrail say
## "escalator here" just the same.
func _mark_end(at: Vector3) -> void:
	_add_part(
		Vector3(END_LIGHT_SIZE, END_LIGHT_SIZE, END_LIGHT_SIZE),
		at,
		0.0,
		GreyboxLook.light(GreyboxLook.SIGN_WARM)
	)


## Landing: a flat slab between two points of the same height.
##
## Sunk into the slab: its top is flush with the floor, only the end faces outwards.
## Otherwise Otto stepping onto it would be ankle-deep in the slab — he stands
## on the floor of the storey, not on the escalator.
func _lay_landing(from: Vector3, to: Vector3) -> void:
	var run := to.x - from.x
	if is_zero_approx(run):
		return

	# The landing's comb plate is at its end [param to]; for the lower landing the end is
	# where the steps leave from, and it lies right if laid out from the steps.
	_add_kit(
		"Landing",
		Vector3((from.x + to.x) * 0.5, from.y, BELT_Z),
		0.0,
		Vector3(run / KIT_LANDING_RUN, 1.0, 1.0)
	)


## Opening frame: posts along the edges of the hole in the slab.
##
## Without them the hole reads as a break in the slab — the same as a shaft pit one
## falls to death into. The posts stand on the edges of the opening through the full slab
## thickness and have no bodies: one walks through the opening, not squeezes through it.
func _frame_the_gap(gap: Vector2, slab: float) -> void:
	if slab <= 0.0:
		return

	var look := GreyboxLook.metal(GreyboxLook.TRIM)
	for edge: float in [gap.x, gap.y]:
		# The opening is only in the back strip, from the wall to the edge of the solid slab.
		var depth := HOLE_FRONT_Z - WorldSpace.BACK_WALL_Z
		_add_part(
			Vector3(FRAME_WIDTH, slab, depth),
			Vector3(edge, -slab * 0.5, WorldSpace.BACK_WALL_Z + depth * 0.5),
			0.0,
			look
		)
	# And an edge strip along the solid slab: the edge beyond which the floor ends.
	_add_part(
		Vector3(absf(gap.y - gap.x), slab, FRAME_WIDTH * 0.5),
		Vector3((gap.x + gap.y) * 0.5, -slab * 0.5, HOLE_FRONT_Z - FRAME_WIDTH * 0.25),
		0.0,
		look
	)


## Model part [param part] in its place, at its angle and with stretch
## [param stretch]: every escalator has its own span.
func _add_kit(part: String, at: Vector3, angle: float, stretch: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = Escalator._kit_mesh(part)
	mesh.position = at
	mesh.rotation.z = angle
	mesh.scale = stretch
	_ramp.add_child(mesh)


static func _kit_mesh(part: String) -> Mesh:
	if _meshes.is_empty():
		var model := KIT.instantiate()
		for node: Node in model.find_children("*", "MeshInstance3D", true, false):
			_meshes[node.name] = (node as MeshInstance3D).mesh
		model.free()
	return _meshes.get(part) as Mesh


## A piece of the structure: a bodiless box in its place and at its angle.
func _add_part(size: Vector3, at: Vector3, angle: float, material: StandardMaterial3D) -> void:
	var part := GreyboxLook.box(size, material)
	part.position = at
	part.rotation.z = angle
	_ramp.add_child(part)
