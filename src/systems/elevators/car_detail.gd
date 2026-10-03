class_name CarDetail
extends Node3D

## Elevator cab dressing: walls, a ceiling with a fixture, a handrail, a control panel,
## and in the shaft — ropes and a counterweight (ADR-0031, decision 1).
##
## Looks only: the cab's bodies — floor, roof, passenger and crush zones — stay in
## [ElevatorCar] and do not change (ADR-0025). The cab is open at the front, as in the
## original: the player sees who is inside. The fixture is emission, not a light source:
## the cab does not touch the frame's lamp budget.

## Cab depth, m: the same as its floor in the scene.
const DEPTH: float = 1.0

## Wall: thickness and how far the back one stands off the floor's edge.
const WALL: float = 0.05

## Posts at the corners of the open front.
const POST := Vector2(0.07, 0.07)

## Side walls — only corner panels at the back: Otto enters the cab from the side, and a
## full-depth wall would look like a wall he walks through.
const SIDE_DEPTH: float = 0.3

## Handrail on the back wall: height above the floor, cross-section.
const RAIL_RISE: float = 0.95
const RAIL := Vector2(0.04, 0.06)

## Control panel on the back wall at the right post: size and how many buttons.
const PANEL := Vector3(0.16, 0.42, 0.03)
const PANEL_RISE: float = 1.05
const BUTTONS: int = 5
const BUTTON: float = 0.035

## Ceiling fixture: a full-width strip without edges.
const LIGHT := Vector3(0.0, 0.05, 0.3)

## Ropes: how many, thickness, spread from the cab's middle, m.
const CABLES: int = 3
const CABLE: float = 0.025
const CABLE_SPREAD: float = 0.14

## Counterweight: bounds and where it travels — behind the cab's back wall, at the left edge.
const WEIGHT := Vector3(0.3, 1.1, 0.16)
const WEIGHT_Z: float = -DEPTH * 0.5 - 0.14
## Counterweight offset from the shaft's edge, m: farther left it passed through the
## rail ([constant BuildingShafts.RAIL_WIDTH], 0.18 m) — they overlap in depth.
const WEIGHT_INSET: float = 0.22

const STEEL := Color(0.42, 0.43, 0.45)
const STEEL_DARK := Color(0.2, 0.21, 0.23)
const BRUSHED := Color(0.55, 0.53, 0.5)
const CABIN_LIGHT := Color(1.0, 0.95, 0.85)
const BUTTON_LIT := Color(1.0, 0.75, 0.35)
const CABLE_COLOR := Color(0.12, 0.12, 0.13)

## Cab by building kind (ADR-0057, decision 6). Hotel — brass and wood, warm light, a
## mirror above the handrail; office — brushed stainless steel and cold light;
## residential — a freight cab of painted steel, a bump rail, a caged lamp and a
## folding scissor gate at the front. The bodies are the same for all (ADR-0025).
const WOOD := Color(0.3, 0.17, 0.1)
const BRASS := Color(0.78, 0.6, 0.3)
const MIRROR := Color(0.2, 0.22, 0.23)
const WARM_LIGHT := Color(1.0, 0.8, 0.55)
const PAINTED := Color(0.34, 0.39, 0.34)
const BUMPER := Color(0.35, 0.25, 0.15)
const GATE := Color(0.1, 0.1, 0.1)
## Hotel mirror above the handrail: bottom and height, share of the back wall's width.
const MIRROR_RISE: float = 1.05
const MIRROR_HEIGHT: float = 0.9
const MIRROR_SHARE: float = 0.6
## Freight cab bump rail: height of the middle, cross-section.
const BUMPER_RISE: float = 0.4
const BUMPER_SIZE := Vector2(0.12, 0.06)

## Freight cab gate: bar step, their cross-section, share of the cab's height, width of
## the folded gate at the right post, m, and folding time, s. Closed while one cannot
## step out and folded while one can — by the ROM's step-out window
## ([method ElevatorMotion.can_step_out], @36F2): a look of the rule, not a new rule.
## The bars are thin and dark — Otto reads behind them.
const GATE_STEP: float = 0.13
const GATE_BAR := Vector2(0.014, 0.014)
const GATE_SHARE: float = 0.88
const GATE_FOLDED: float = 0.2
const GATE_TIME: float = 0.35
## Gate sound: a clang of steel, heard nearby.
const GATE_REACH: float = 12.0
const GATE_DB: float = -6.0

var _width: float = 1.2
## The cab's building kind ([method dress_as]): materials and the gate go by it.
var _kind: BuildingIdentity.Kind = BuildingIdentity.Kind.OFFICE
## Freight cab gate: bars and the top and bottom bars; 0 — closed, 1 — folded.
var _gate_bars: Array[MeshInstance3D] = []
var _gate_rails: Array[MeshInstance3D] = []
var _gate_open: float = 1.0
var _gate_wanted: bool = true
## The cab body as a separate node: [method build] rebuilds it, while the ropes and
## counterweight live longer — [method hang_cables] sets them up once.
var _body: Node3D = null
var _height: float = 3.0
var _cables: Array[MeshInstance3D] = []
var _weight_cables: Array[MeshInstance3D] = []
var _weight: MeshInstance3D = null
## How far the cab travels in the shaft: bottom and top stops and the shaft top, by scene y.
var _low: float = 0.0
var _high: float = 0.0
var _top: float = 0.0


## Dresses the cab by building kind [param kind]. Call before [method build]: it is
## called by [method ElevatorCar.fit_to_story].
func dress_as(kind: BuildingIdentity.Kind) -> void:
	_kind = kind


## Whether the cab has a gate: only the residential freight one.
func has_gate() -> bool:
	return not _gate_bars.is_empty()


## How folded the gate is: 1 — folded, 0 — closed.
func gate_openness() -> float:
	return _gate_open


## Folds the gate when one can step out of the cab and extends it when one cannot
## ([param open]), over [constant GATE_TIME] s; the clang — on the change, if
## [param audible]. The step-out window opens on every floor passed, and all the
## building's empty cabs would clang — the user rejected clanging empty cabs back in M21
## (ADR-0052, decision 7): only the cab with Otto is heard.
func tend_gate(open: bool, delta: float, audible: bool = true) -> void:
	if _gate_bars.is_empty():
		return
	if open != _gate_wanted:
		_gate_wanted = open
		if audible:
			Sounds.play_at(self, Sounds.CAB_GATE, global_position, GATE_REACH, GATE_DB)
	var target := 1.0 if open else 0.0
	var moved := move_toward(_gate_open, target, delta / GATE_TIME)
	if moved != _gate_open:
		_gate_open = moved
		_place_gate()


## Builds the dressing for the cab's width and the floor's clearance. Called from
## [method ElevatorCar.fit_to_story] and rebuilds everything anew.
func build(width: float, clear_height: float) -> void:
	if _body != null:
		_body.queue_free()
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_width = width
	_height = clear_height

	var steel := GreyboxLook.metal(STEEL)
	var brushed := GreyboxLook.metal(BRUSHED)
	var lamp := CABIN_LIGHT
	match _kind:
		BuildingIdentity.Kind.HOTEL:
			steel = GreyboxLook.metal(BRASS)
			brushed = GreyboxLook.surface(WOOD)
			lamp = WARM_LIGHT
		BuildingIdentity.Kind.RESIDENTIAL:
			steel = GreyboxLook.metal(STEEL_DARK)
			brushed = GreyboxLook.metal(PAINTED)
	# The cab floor is at its origin: the floor slab lies under it, the roof slab — from
	# the clearance minus the slab thickness up to the clearance. The walls run from floor
	# to roof; counted from the top of the floor slab, they hung 18 cm above it.
	var inner := clear_height - ElevatorCar.SLAB_THICKNESS
	var middle := inner * 0.5
	var back_z := -DEPTH * 0.5 + WALL * 0.5

	# The back wall with two seams, the side ones — corner panels at the back.
	_part(Vector3(width - WALL * 2.0, inner, WALL), Vector3(0.0, middle, back_z), brushed)
	for seam: float in [-width / 6.0, width / 6.0]:
		_part(Vector3(0.012, inner, 0.01), Vector3(seam, middle, back_z + WALL * 0.5), steel)
	for side: float in [-1.0, 1.0]:
		var x := side * (width * 0.5 - WALL * 0.5)
		var side_z := -DEPTH * 0.5 + SIDE_DEPTH * 0.5
		_part(Vector3(WALL, inner, SIDE_DEPTH), Vector3(x, middle, side_z), brushed)
		var post_x := side * (width * 0.5 - POST.x * 0.5)
		_part(
			Vector3(POST.x, inner, POST.y),
			Vector3(post_x, middle, DEPTH * 0.5 - POST.y * 0.5),
			steel
		)

	# Fixture, handrail, control panel with buttons.
	var light_y := clear_height - ElevatorCar.SLAB_THICKNESS - LIGHT.y * 0.5
	_part(
		Vector3(width - WALL * 4.0, LIGHT.y, LIGHT.z),
		Vector3(0.0, light_y, 0.0),
		GreyboxLook.light(lamp)
	)
	_part(
		Vector3(width - WALL * 6.0, RAIL.x, RAIL.y),
		Vector3(0.0, RAIL_RISE, back_z + WALL * 0.5 + RAIL.y * 0.5),
		steel
	)
	_dress_by_kind(width, inner, back_z, light_y)
	var panel_x := width * 0.5 - WALL - PANEL.x * 0.5 - 0.06
	var panel_y := PANEL_RISE
	var panel_z := back_z + WALL * 0.5 + PANEL.z * 0.5
	_part(PANEL, Vector3(panel_x, panel_y, panel_z), GreyboxLook.metal(STEEL_DARK))
	for index in BUTTONS:
		var y := panel_y + PANEL.y * 0.35 - float(index) * (PANEL.y * 0.7 / float(BUTTONS - 1))
		_part(
			Vector3(BUTTON, BUTTON, 0.012),
			Vector3(panel_x, y, panel_z + PANEL.z * 0.5),
			GreyboxLook.light(BUTTON_LIT)
		)


## The kind's own: the hotel mirror, the bump rail, the caged lamp and the freight gate.
func _dress_by_kind(width: float, inner: float, back_z: float, light_y: float) -> void:
	_gate_bars.clear()
	_gate_rails.clear()
	var face_z := back_z + WALL * 0.5
	match _kind:
		BuildingIdentity.Kind.HOTEL:
			_part(
				Vector3(width * MIRROR_SHARE, MIRROR_HEIGHT, 0.01),
				Vector3(0.0, MIRROR_RISE + MIRROR_HEIGHT * 0.5, face_z + 0.005),
				GreyboxLook.metal(MIRROR)
			)
		BuildingIdentity.Kind.RESIDENTIAL:
			var dark := GreyboxLook.metal(STEEL_DARK)
			# The freight cab's ribbed floor — the same sheet as the shaft portal's threshold.
			_part(
				Vector3(width - WALL * 2.0, 0.01, DEPTH - WALL),
				Vector3(0.0, 0.005, WALL * 0.5),
				BuildingFinish.tread_plate()
			)
			_part(
				Vector3(width - WALL * 2.0, BUMPER_SIZE.x, BUMPER_SIZE.y),
				Vector3(0.0, BUMPER_RISE, face_z + BUMPER_SIZE.y * 0.5),
				GreyboxLook.surface(BUMPER)
			)
			for bar: int in 3:
				_part(
					Vector3(0.012, LIGHT.y + 0.04, LIGHT.z + 0.04),
					Vector3(-0.3 + bar * 0.3, light_y - 0.02, 0.0),
					dark
				)
			_build_gate(width, inner)


## The scissor gate at the front edge: bars and two rails. They are placed by
## [method _place_gate] according to how folded it is.
func _build_gate(width: float, inner: float) -> void:
	var height := inner * GATE_SHARE
	var iron := GreyboxLook.metal(GATE)
	var count := int((width - POST.x * 2.0) / GATE_STEP) + 1
	for bar: int in count:
		var part := GreyboxLook.box(Vector3(GATE_BAR.x, height, GATE_BAR.y), iron)
		part.position.y = height * 0.5
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_body.add_child(part)
		_gate_bars.append(part)
	for rise: float in [0.08, height - 0.04]:
		var rail := GreyboxLook.box(Vector3(1.0, 0.03, GATE_BAR.y), iron)
		rail.position.y = rise
		rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_body.add_child(rail)
		_gate_rails.append(rail)
	_place_gate()


## Places the gate's bars: extended — across the whole opening width, folded — in a
## bundle at the right post.
func _place_gate() -> void:
	if _gate_bars.is_empty():
		return
	var right := _width * 0.5 - POST.x
	var spread := lerpf(_width - POST.x * 2.0, GATE_FOLDED, _gate_open)
	var z := DEPTH * 0.5 - POST.y - GATE_BAR.y
	var count := _gate_bars.size()
	for bar: int in count:
		var share := float(bar) / float(maxi(count - 1, 1))
		_gate_bars[bar].position.x = right - share * spread
		_gate_bars[bar].position.z = z
	for rail: MeshInstance3D in _gate_rails:
		rail.scale.x = spread
		rail.position.x = right - spread * 0.5
		rail.position.z = z


## Sets up the ropes and counterweight: the cab travels between stops [param low] and
## [param high] (scene y of its bottom), the shaft ends at [param top].
func hang_cables(low: float, high: float, top: float) -> void:
	_low = low
	_high = high
	_top = top
	if _weight != null:
		return
	var cable := GreyboxLook.metal(CABLE_COLOR)
	for index in CABLES:
		_cables.append(_loose(cable))
	for index in 2:
		_weight_cables.append(_loose(cable))
	_weight = GreyboxLook.box(WEIGHT, GreyboxLook.metal(STEEL_DARK))
	_weight.top_level = true
	add_child(_weight)


## Moves the shaft top [param top] (scene y): how far the ropes go and above what the
## counterweight does not rise. [method hang_cables] puts it above the top stop's
## ceiling, while a shaft to the roof has sky above it — the level sets the top there.
func set_top(top: float) -> void:
	_top = top


## Places the ropes and counterweight for the cab whose bottom is now at [param car_y].
## The counterweight moves the opposite way: the cab is down — it is up.
func follow(car_y: float, car_x: float) -> void:
	if _weight == null:
		return
	var roof := car_y + _height
	for index in _cables.size():
		var x := car_x + (float(index) - float(CABLES - 1) * 0.5) * CABLE_SPREAD
		_stretch(_cables[index], x, roof, _top, -0.1)
	# The counterweight does not go above the shaft top: in a shaft to the roof the top is
	# in the machine room, and without a stop the counterweight would stick out above it
	# into the sky.
	var weight_y := minf(_low + _high - car_y + _height * 0.5, _top - WEIGHT.y * 0.5)
	var weight_x := car_x - _width * 0.5 + WEIGHT_INSET + WEIGHT.x * 0.5
	_weight.global_position = Vector3(weight_x, weight_y, WEIGHT_Z)
	for index in _weight_cables.size():
		var x := weight_x + (float(index) - 0.5) * WEIGHT.x * 0.5
		_stretch(_weight_cables[index], x, weight_y + WEIGHT.y * 0.5, _top, WEIGHT_Z)


func _part(size: Vector3, at: Vector3, material: StandardMaterial3D) -> void:
	var part := GreyboxLook.box(size, material)
	part.position = at
	_body.add_child(part)


## A rope without a place: [method follow] places it every step.
func _loose(material: StandardMaterial3D) -> MeshInstance3D:
	var line := GreyboxLook.box(Vector3.ONE, material)
	line.top_level = true
	add_child(line)
	return line


## Stretches the rope vertically from [param from] to [param to].
func _stretch(line: MeshInstance3D, x: float, from: float, to: float, z: float) -> void:
	var length := maxf(to - from, 0.01)
	line.scale = Vector3(CABLE, length, CABLE)
	line.global_position = Vector3(x, from + length * 0.5, z)
