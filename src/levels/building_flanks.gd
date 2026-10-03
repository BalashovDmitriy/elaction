class_name BuildingFlanks
extends Node3D

## Tower end walls and the podium setback by building kind (ADR-0058, decision 3).
##
## From the tower floors the camera sees more at the sides than the tower itself: its end
## walls and the roof of the building's wide part — the setback. Before M24p there was a
## bare roof there. Now the hotel has stone quoins and flags on the end walls, and on the
## setback a terrace with umbrellas and a string of lights; the office — aluminium sun
## louvres and skylights with equipment; the residential building — a fire escape, and
## on the setback roofing felt, dishes, chimneys and laundry on lines.
##
## Looks only: no bodies, no shadows, light by emission (the surroundings have exactly two
## light sources, ADR-0029). The floor layout does not change — everything is outside
## the walls.
##
## Coordinates: x — along the building, y — the rules plane (down), z — the scene's.

## Building depth: from the corridor's front face to the hall's far wall, along z.
const FRONT_Z: float = WorldSpace.CORRIDOR_DEPTH * 0.5
const BACK_Z: float = WorldSpace.BACK_WALL_Z - WorldSpace.ROOM_DEPTH
## Nothing on the setback stands closer than this to the tower wall, m.
const WALL_GAP: float = 0.4

const STONE := Color(0.64, 0.58, 0.48)
const STONE_SHADE := Color(0.5, 0.45, 0.37)
const BRASS := Color(0.78, 0.6, 0.3)
const FLAGS: Array[Color] = [Color(0.55, 0.08, 0.1), Color(0.1, 0.18, 0.4), Color(0.7, 0.55, 0.2)]
const DECK := Color(0.36, 0.24, 0.15)
const CANVAS: Array[Color] = [Color(0.6, 0.12, 0.12), Color(0.85, 0.8, 0.68)]
const BULB := Color(1.0, 0.82, 0.5)
const HEDGE := Color(0.14, 0.26, 0.14)

const ALUMINIUM := Color(0.66, 0.68, 0.71)
const GLASS_EDGE := Color(0.08, 0.12, 0.18)
const PAVERS := Color(0.42, 0.43, 0.44)
const SKYLIGHT := Color(0.55, 0.75, 0.95)
const UNIT := Color(0.58, 0.6, 0.6)

const IRON := Color(0.3, 0.29, 0.28)
const TAR := Color(0.12, 0.12, 0.13)
const CHIMNEY := Color(0.42, 0.22, 0.16)
const WASHING: Array[Color] = [
	Color(0.85, 0.85, 0.8), Color(0.6, 0.2, 0.2), Color(0.25, 0.4, 0.6), Color(0.7, 0.6, 0.3)
]

var _rules: BuildingRules = null
var _batch := MeshBatch.new()
var _lit: bool = true
## Detail placements before handing over to multimeshes: for tests ([method placements]).
var _placed: Array[Transform3D] = []
## Fire escape flight: one mesh for all flights — one multimesh.
var _stair: BoxMesh = null
## Terrace umbrella canopies — a mesh per colour in [constant CANVAS]: a mesh per
## umbrella would be handed over as its own multimesh with a single instance.
var _canopies: Array[CylinderMesh] = []
## Where in height the sign hangs at the right end wall ([method VerticalSign.span]):
## flags and louvres are not placed in front of it — they would cover the letters.
var _sign := Vector2.ZERO


## Places the building's end walls and setback by kind from [member BuildingRules.kind].
## [param sign_span] — top and bottom of the sign at the right end wall in the rules plane.
func build(rules: BuildingRules, building_seed: int = 1, sign_span: Vector2 = Vector2.ZERO) -> void:
	name = "Flanks"
	_rules = rules
	_sign = sign_span
	_lit = TimeOfDay.sign_lit(rules.time_of_day)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, 0xF1A2])
	var tower := rules.floor_span(BuildingRules.ROOF)
	var top := rules.floor_surface(BuildingRules.ROOF) - BuildingShell.PARAPET_HEIGHT
	var ledge_index := clampi(rules.wide_from - 1, 0, rules.floors - 1)
	var ledge := rules.floor_surface(ledge_index)
	var wide := rules.slab_span(ledge_index)
	for side: float in [-1.0, 1.0]:
		var wall := tower.x if side < 0.0 else tower.y
		_flank(rules.kind, wall, side, top, ledge)
		var outer := wide.x if side < 0.0 else wide.y
		var span := Vector2(minf(wall, outer), maxf(wall, outer))
		span = Vector2(
			span.x + (WALL_GAP if side > 0.0 else 0.3), span.y - (WALL_GAP if side < 0.0 else 0.3)
		)
		if span.y - span.x > 1.5:
			_ledge(rules.kind, span, ledge, side, rng)
	_placed = _batch.places()
	_batch.commit(self)


## Placements of all end wall and setback details in the scene: for tests — under the
## headless engine a multimesh stores no placements ([method MeshBatch.places]).
func placements() -> Array[Transform3D]:
	return _placed


## Tower end wall at wall [param wall] on side [param side] (−1 — left): from parapet
## [param top] to setback [param bottom] (rules plane).
func _flank(
	kind: BuildingIdentity.Kind, wall: float, side: float, top: float, bottom: float
) -> void:
	match kind:
		BuildingIdentity.Kind.OFFICE:
			_louvres(wall, side, top, bottom)
		BuildingIdentity.Kind.RESIDENTIAL:
			if side < 0.0:
				_fire_escape(wall, side)
		_:
			_quoins(wall, side, top, bottom)
			_flags(wall, side)


## Hotel quoins: stone blocks along the corner, alternately wider and narrower.
func _quoins(wall: float, side: float, top: float, bottom: float) -> void:
	var stone := GreyboxLook.surface(STONE)
	var shade := GreyboxLook.surface(STONE_SHADE)
	var block := 0.55
	var count := int((bottom - top) / block)
	for row: int in count:
		var out := 0.22 if row % 2 == 0 else 0.12
		var y := top + block * (row + 0.5)
		_batch.box(
			stone if row % 2 == 0 else shade,
			Vector3(out, block - 0.04, 0.6),
			Vector3(wall + side * out * 0.5, y, FRONT_Z - 0.3)
		)


## Hotel flags on brackets every few floors.
func _flags(wall: float, side: float) -> void:
	var pole := GreyboxLook.metal(BRASS)
	var turn := 0
	for index: int in range(1, mini(_rules.wide_from, _rules.floors - 1), 4):
		var y := _rules.story_top(index) + 0.4
		if _before_sign(side, y - 0.05, y + 1.4):
			continue
		var root := Vector3(wall + side * 0.05, y, FRONT_Z - 0.6)
		_batch.box(pole, Vector3(1.6, 0.04, 0.04), root + Vector3(side * 0.8, 0.0, 0.0))
		var cloth := GreyboxLook.surface(FLAGS[turn % FLAGS.size()])
		_batch.box(cloth, Vector3(0.9, 1.3, 0.02), root + Vector3(side * 1.15, 0.68, 0.0))
		turn += 1


## Office louvres: on every tower floor two aluminium shelves sticking out and the edge
## of the glass wall along the corner.
func _louvres(wall: float, side: float, top: float, bottom: float) -> void:
	var metal := GreyboxLook.metal(ALUMINIUM)
	_batch.box(
		GreyboxLook.polished(GLASS_EDGE),
		Vector3(0.12, bottom - top, 0.5),
		Vector3(wall + side * 0.06, (top + bottom) * 0.5, FRONT_Z - 0.25)
	)
	for index: int in range(0, mini(_rules.wide_from, _rules.floors - 1)):
		var head := _rules.story_top(index) + 0.35
		if _before_sign(side, head - 0.05, head + 0.55):
			continue
		for shelf: float in [0.0, 0.5]:
			_batch.box(
				metal,
				Vector3(0.7, 0.04, 0.9),
				Vector3(wall + side * 0.35, head + shelf, FRONT_Z - 0.45)
			)


## Would an end-wall detail on side [param side] from [param from] to [param to] in
## height (rules plane) stand in front of the sign: it hangs at the right end wall.
func _before_sign(side: float, from: float, to: float) -> bool:
	return side > 0.0 and to > _sign.x and from < _sign.y


## Residential fire escape: a landing with railings on every tower floor, a flight
## between landings and a drop ladder at the bottom.
func _fire_escape(wall: float, side: float) -> void:
	var iron := GreyboxLook.metal(IRON)
	var reach := 1.1
	var floors := mini(_rules.wide_from, _rules.floors - 1)
	for index: int in range(0, floors):
		var deck := _rules.floor_surface(index) - 0.05
		var out := wall + side * reach * 0.5
		var z := FRONT_Z - 0.9
		_batch.box(iron, Vector3(reach, 0.05, 1.4), Vector3(out, deck, z))
		_batch.box(iron, Vector3(reach, 0.04, 0.04), Vector3(out, deck - 0.95, z + 0.68))
		_batch.box(
			iron, Vector3(0.04, 0.95, 0.04), Vector3(wall + side * reach, deck - 0.47, z + 0.68)
		)
		for bar: int in 5:
			var x := wall + side * (0.2 + bar * 0.2)
			_batch.box(iron, Vector3(0.02, 0.95, 0.02), Vector3(x, deck - 0.47, z + 0.68))
		if index + 1 < floors:
			# Flight down to the landing of the floor below: in the frame — a diagonal strip.
			var drop := _rules.floor_surface(index + 1) - deck
			var stair := Vector3(0.08, Vector2(reach * 0.7, drop).length(), 0.6)
			var tilt := Basis(
				Vector3.BACK, atan2(reach * 0.7, drop) * (1.0 if index % 2 == 0 else -1.0)
			)
			var at := MeshBatch.scene_of(Vector3(out, deck + drop * 0.5, z - 0.2))
			if _stair == null:
				_stair = BoxMesh.new()
				_stair.material = iron
			_batch.mesh(_stair, Transform3D(tilt * Basis.from_scale(stair), at))


## Podium setback on span [param span] (rules plane) at height [param surface].
func _ledge(
	kind: BuildingIdentity.Kind,
	span: Vector2,
	surface: float,
	side: float,
	rng: RandomNumberGenerator
) -> void:
	match kind:
		BuildingIdentity.Kind.OFFICE:
			_plaza(span, surface, rng)
		BuildingIdentity.Kind.RESIDENTIAL:
			_tar_roof(span, surface, side, rng)
		_:
			_terrace(span, surface, side, rng)


## Hotel terrace: plank decking, a hedge at the edge, umbrellas with tables and a string
## of bulbs — lit at night and at dusk.
func _terrace(span: Vector2, surface: float, side: float, rng: RandomNumberGenerator) -> void:
	var middle := (span.x + span.y) * 0.5
	var length := span.y - span.x
	_batch.box(
		GreyboxLook.surface(DECK),
		Vector3(length, 0.06, FRONT_Z - BACK_Z - 0.6),
		Vector3(middle, surface - 0.03, (FRONT_Z + BACK_Z) * 0.5)
	)
	var hedge := GreyboxLook.surface(HEDGE)
	var edge_x := span.x + 0.3 if side < 0.0 else span.y - 0.3
	_batch.box(
		hedge, Vector3(0.5, 0.7, FRONT_Z - BACK_Z - 1.0), Vector3(edge_x, surface - 0.35, -3.5)
	)
	var pole := GreyboxLook.metal(BRASS)
	var step := 2.6
	var count := maxi(1, int((length - 1.0) / step))
	var tops: Array[Vector3] = []
	for index: int in count:
		var x := span.x + 0.8 + (length - 1.6) * (float(index) + 0.5) / float(count)
		var z := -1.2 - rng.randf_range(0.0, 3.0)
		_batch.cylinder_on(pole, 0.03, 2.2, surface, Vector3(x, 0.0, z))
		_batch.mesh(
			_canopy(index % CANVAS.size()),
			Transform3D(Basis.IDENTITY, MeshBatch.scene_of(Vector3(x, surface - 2.3, z)))
		)
		_batch.cylinder_on(
			GreyboxLook.surface(DECK.lightened(0.3)), 0.4, 0.05, surface, Vector3(x, 0.72, z)
		)
		_batch.cylinder_on(pole, 0.04, 0.72, surface, Vector3(x, 0.0, z))
		tops.append(Vector3(x, surface - 2.5, -0.6))
	# String of lights: bulbs along a sagging wire between the umbrellas.
	var bulb := GreyboxLook.light(BULB) if _lit else GreyboxLook.surface(BULB.darkened(0.5))
	for index: int in tops.size() - 1:
		var from := tops[index]
		var to := tops[index + 1]
		for step_index: int in 8:
			var share := (float(step_index) + 0.5) / 8.0
			var sag := sin(share * PI) * 0.35
			var at := from.lerp(to, share) + Vector3(0.0, sag, 0.0)
			_batch.sphere(bulb, 0.07, at)


## Umbrella canopy of colour [param tone] from [constant CANVAS]: one mesh per colour.
func _canopy(tone: int) -> CylinderMesh:
	while _canopies.size() <= tone:
		var canopy := CylinderMesh.new()
		canopy.top_radius = 0.02
		canopy.bottom_radius = 1.1
		canopy.height = 0.45
		canopy.radial_segments = 10
		canopy.material = GreyboxLook.surface(CANVAS[_canopies.size()])
		_canopies.append(canopy)
	return _canopies[tone]


## Office plaza: tiles, rows of skylights — glowing at night — and supply equipment with
## fans.
func _plaza(span: Vector2, surface: float, rng: RandomNumberGenerator) -> void:
	var middle := (span.x + span.y) * 0.5
	var length := span.y - span.x
	_batch.box(
		GreyboxLook.surface(PAVERS),
		Vector3(length, 0.04, FRONT_Z - BACK_Z - 0.6),
		Vector3(middle, surface - 0.02, (FRONT_Z + BACK_Z) * 0.5)
	)
	var glow := GreyboxLook.light(SKYLIGHT) if _lit else GreyboxLook.polished(GLASS_EDGE)
	var frame := GreyboxLook.metal(ALUMINIUM)
	var count := maxi(1, int(length / 2.2))
	for index: int in count:
		var x := span.x + length * (float(index) + 0.5) / float(count)
		_batch.box_on(frame, Vector3(1.4, 0.3, 1.4), surface, Vector3(x, 0.0, -1.4))
		_batch.box_on(glow, Vector3(1.2, 0.04, 1.2), surface, Vector3(x, 0.3, -1.4))
	var unit := GreyboxLook.metal(UNIT)
	var fan := GreyboxLook.metal(IRON)
	for index: int in maxi(1, int(length / 4.5)):
		var x := span.x + 1.2 + rng.randf_range(0.0, maxf(length - 2.4, 0.0))
		_batch.box_on(unit, Vector3(1.8, 1.0, 1.4), surface, Vector3(x, 0.0, -5.0))
		_batch.cylinder_on(fan, 0.4, 0.08, surface, Vector3(x, 1.0, -5.0))


## Residential roof: roofing felt, brick chimneys, dishes and laundry on a line between
## posts.
func _tar_roof(span: Vector2, surface: float, side: float, rng: RandomNumberGenerator) -> void:
	var middle := (span.x + span.y) * 0.5
	var length := span.y - span.x
	_batch.box(
		GreyboxLook.surface(TAR),
		Vector3(length, 0.04, FRONT_Z - BACK_Z - 0.6),
		Vector3(middle, surface - 0.02, (FRONT_Z + BACK_Z) * 0.5)
	)
	var brick := GreyboxLook.surface(CHIMNEY)
	for index: int in maxi(1, int(length / 4.0)):
		var x := span.x + 0.8 + rng.randf_range(0.0, maxf(length - 1.6, 0.0))
		_batch.box_on(brick, Vector3(0.6, 1.4, 0.6), surface, Vector3(x, 0.0, -6.0))
	for part: Array in HallLook.template("satellite_dish", _rules.kind):
		var x := span.x + length * (0.75 if side < 0.0 else 0.25)
		var place := Transform3D(Basis.IDENTITY, MeshBatch.scene_of(Vector3(x, surface, -3.2)))
		_batch.mesh(part[0] as Mesh, place * (part[1] as Transform3D))
	var iron := GreyboxLook.metal(IRON)
	var from := span.x + 0.5
	var to := span.y - 0.5
	for x: float in [from, to]:
		_batch.cylinder_on(iron, 0.03, 1.9, surface, Vector3(x, 0.0, -1.0))
	_batch.box(
		iron, Vector3(to - from, 0.015, 0.015), Vector3((from + to) * 0.5, surface - 1.85, -1.0)
	)
	var pegs := int((to - from) / 0.55)
	for peg: int in pegs:
		var x := from + 0.3 + peg * 0.55
		if rng.randf() < 0.3:
			continue
		var cloth := GreyboxLook.surface(WASHING[rng.randi_range(0, WASHING.size() - 1)])
		var drop := rng.randf_range(0.35, 0.7)
		_batch.box(cloth, Vector3(0.42, drop, 0.02), Vector3(x, surface - 1.85 + drop * 0.5, -1.0))
