class_name Lamp
extends AnimatableBody3D

## Lamp under a floor's ceiling.
##
## Shot down, it falls and kills an agent standing under it — 300 points, the most
## valuable way to kill in the original. Once fallen, it darkens its floor (ADR-0007).
##
## The lamp does not touch Otto: the sources speak only of agents, so the hit zone
## looks only at their layer.
##
## The node moves itself, hence [AnimatableBody3D] rather than [StaticBody3D] — like
## the elevator cab. The fall itself is computed by [LampFall], without nodes or physics.
##
## The lamp is the only light source of its zone (ADR-0021, decision 4;
## ADR-0023, decision 3): a downward cone with a soft shadow and a faint fill around,
## both its children. "The zone is lit" means exactly "the lamp hangs".

## The lamp hit an agent on the way down. The level kills him and scores the points.
signal crushed(agent: Enemy)

## The lamp reached the floor. On this signal the level darkens the floor: it knows
## which one itself — the floor is bound to the handler when the lamp was hung.
signal fell

## Downward cone: gives a spot on the floor and shadow edges, like the fixtures in the
## reference. Shadows are soft: the light hits the slabs and walls, and that is exactly
## what shows that the lamp is shining, not the air.
const SPOT_RANGE: float = 6.0
const SPOT_ANGLE: float = 60.0
const SPOT_ENERGY: float = 9.0
const SPOT_BLUR: float = 1.6
## How far the shadowless cone reaches into the slab under its floor, m: less than the slab.
const FLOOR_REACH: float = 0.1

## Fill around: faint and wide. A cone alone would leave blackness between lamps even
## with all of them lit — while the zone counts as lit as a whole.
##
## With a shadow, even though a shadow on each lamp's second light costs money.
## Without it, a fill with a radius larger than the floor height (3 m) shines through
## the slabs: in the frame of a darkened floor its floor was lit by the lamps of the
## floor below, and darkness stopped being darkness (code review M17). The radius
## cannot be cut — it is needed to reach the edges of the zone.
const FILL_RANGE: float = 7.0
## Shadowless fill radius — on low and medium quality: no farther than the floor.
const FILL_RANGE_UNSHADOWED: float = 3.0
## How many lamps in the frame cast a fill shadow at once: as many as appear in the
## frame at the top of the building, where the frame is within budget.
const FILL_SHADOW_CAP: int = 4
const FILL_ENERGY: float = 1.5
## Flicker: pause between bursts and length of one dropout, s, how much the light
## dims in a dropout, and the salt of the draw for which lamp flickers.
const FLICKER_PAUSE := Vector2(2.5, 7.0)
const FLICKER_BLINK := Vector2(0.04, 0.12)
const FLICKER_LOW: float = 0.15
const FLICKER_SALT: int = 0xF11C

## Warm lamp colour against the cold overall tone of the palette (ADR-0023, decision 3)
## — for a lamp without a building style. Light by kind — [constant BuildingAir.LAMP_LIGHT].
const LIGHT_COLOR := Color(1.0, 0.9, 0.7)

## Hanging cord, m: thickness. The length is from the socket to the ceiling, and the level knows it.
const CORD_WIDTH: float = 0.03

## Shade: top radius, bottom radius and height; the hanging cup — radius and height, m
## (ADR-0031, decision 3).
const SHADE := Vector3(0.1, 0.3, 0.26)
const CANOPY := Vector2(0.08, 0.05)
const SHADE_COLOR := Color(0.42, 0.4, 0.36)
## Diffuser bowl under the shade: radius and depth, m.
const BOWL := Vector2(0.27, 0.13)
## Office fixture (ADR-0048): a fluorescent lamp box and a diffuser under it, m. It is
## no wider than the shade — the width of the lamp's shape: the target is the same.
const PANEL_BOX := Vector3(0.6, 0.1, 0.34)
const PANEL_DIFFUSER := Vector3(0.56, 0.05, 0.38)
const PANEL_COLOR := Color(0.82, 0.84, 0.86)
## Residential ceiling dish (ADR-0055): radius and depth of the glass, a brass cup
## above it, m. No wider than the shade — the target is the same.
const DOME := Vector2(0.24, 0.1)
const DOME_CAP := Vector2(0.07, 0.04)
const DOME_CAP_COLOR := Color(0.55, 0.46, 0.28)
## Bare bulb: bulb radius and height, socket, m; salt of the draw for which lamp has
## a broken shade.
const BULB := Vector2(0.075, 0.17)
const BULB_SOCKET := Vector2(0.03, 0.07)
const BULB_SALT: int = 0xB01B
## Chandelier: ring radius, m; candles — how many and what kind (bulb radius and
## height). No wider than the shade — the width of the lamp's shape: the target is the
## same. The rod runs from the ring to the cord, like the dish's tube.
const CHANDELIER: float = 0.24
const CHANDELIER_BRASS := Color(0.72, 0.56, 0.26)
const CANDLES: int = 6
const CANDLE := Vector2(0.05, 0.13)
## A bowl with crystal under the ring — glows along with the candles: from the side the
## chandelier is thin, and without it the target read as a line under the ceiling
## (M24n shots).
const CHANDELIER_BOWL := Vector2(0.17, 0.11)

## Chandelier candles and bowl as one mesh — one for all chandeliers: rebuilding it
## for every hotel lamp would mean fifty builds while loading the building.
static var _chandelier_glow: ArrayMesh = null

@export var fall_speed: float = 7.8

## The floor the lamp hangs on. Written by the level when it hangs the lamp.
##
## The floor cannot be derived back from the coordinate: before M18c the lamp hung
## exactly midway between two floors, and [method BuildingRules.floor_index_near] at
## that midpoint decided by the last bit of the fraction — in pixels it fell on one
## floor, in metres on another. Under the ceiling it is closer to the floor above than
## to its own, and derivation from the coordinate would now always be wrong.
var floor_index: int = 0
## Fixture look by building kind: a hotel shade or an office box. Set by the level
## before adding to the tree ([BuildingStyle]).
var fixture: BuildingStyle.Fixture = BuildingStyle.Fixture.PENDANT
## The lamp flickers (ADR-0055, decision 4): the tube is about to die. Looks only —
## the zone is lit while the lamp is intact, as in the ROM; flicker makes no darkness.
var flicker: bool = false
## Light colour and strength by building kind ([BuildingAir], ADR-0056): set by
## [method dress_as] before entering the tree.
var light_colour := LIGHT_COLOR
var light_gain: float = 1.0

var _fall := LampFall.new()
var _spot: SpotLight3D = null
var _fill: OmniLight3D = null
## The lamp's floor is in the frame: light with shadow. Otherwise — the fallback,
## a cone down to the floor without shadow.
var _shadowed: bool = true
## Whether the fill casts a shadow ([method set_light_visible]).
var _fill_shadowed: bool = true
## The height above its floor at which the lamp hangs, m: [method hang].
var _above_floor: float = SPOT_RANGE
var _cord: MeshInstance3D = null
## Shade diffuser: glows while the lamp is intact (ADR-0031, decision 3).
var _diffuser: MeshInstance3D = null
## Flicker: time until the next burst, how much longer to stay dark, and the dimmed
## diffuser for while the lamp is out.
var _flicker_wait: float = 0.0
var _flicker_left: int = 0
var _flicker_rng := RandomNumberGenerator.new()
var _dim: StandardMaterial3D = null

@onready var _crush_zone: Area3D = $CrushZone
@onready var _visual: MeshInstance3D = $Visual
@onready var _shape: CollisionShape3D = $Shape


## Lamp bounds by [Proportions]. The hit zone is wider and taller than the lamp itself:
## an agent dies if the lamp catches him with its edge, not only its middle.
func _notification(what: int) -> void:
	if what != NOTIFICATION_SCENE_INSTANTIATED:
		return
	var body := Vector3(Proportions.LAMP.x, Proportions.LAMP.y, 0.4)
	Proportions.fit_box($Shape as CollisionShape3D, body, false)
	Proportions.fit_mesh($Visual as MeshInstance3D, body)
	Proportions.fit_box(
		$CrushZone/CrushShape as CollisionShape3D, body * Vector3(1.2, 1.13, 1.0), false
	)


func _ready() -> void:
	_fall.speed = fall_speed
	# The fixture is the source itself: it glows on its own and is visible from any floor.
	_visual.material_override = GreyboxLook.marker(GreyboxLook.LAMP)
	_dress_fixture()
	_spot = _make_spot()
	add_child(_spot)
	_fill = _make_fill()
	add_to_group(Graphics.GROUP)
	apply_graphics()
	add_child(_fill)
	set_process(flicker)
	if flicker:
		_flicker_rng.seed = hash([floor_index, roundi(position.x * 10.0)])
		_flicker_wait = _flicker_rng.randf_range(FLICKER_PAUSE.x, FLICKER_PAUSE.y)
		_dim = GreyboxLook.surface(GreyboxLook.LAMP.darkened(0.45))


## Lamp look by building style [param style]: the fixture and, on a share of
## residential lamps, flicker — drawn by floor and slot, one lamp always flickers.
## Call before [method Node.add_child], when [member floor_index] and the slot are set.
func dress_as(style: BuildingStyle) -> void:
	fixture = style.fixture
	if (
		hash([floor_index, roundi(position.x * 10.0), BULB_SALT]) % 1000
		< int(style.bulb_share * 1000.0)
	):
		fixture = BuildingStyle.Fixture.BULB
	light_colour = style.lamp_light
	light_gain = style.lamp_gain
	var roll := hash([floor_index, roundi(position.x * 10.0), FLICKER_SALT]) % 1000
	flicker = roll < int(style.flicker_share * 1000.0)


## Flicker: a long pause, then a burst of short dropouts. A shot-down lamp does not flicker.
func _process(delta: float) -> void:
	if not is_hanging():
		# Light at full strength until the fall ends, and the diffuser has already been
		# put out by [method shoot_down]: relit, it would glow in flight.
		_glow(true)
		set_process(false)
		return
	_flicker_wait -= delta
	if _flicker_wait > 0.0:
		return
	if _flicker_left == 0:
		_flicker_left = _flicker_rng.randi_range(2, 5) * 2
	_flicker_left -= 1
	# Even step — dark, odd — light again; the last — light and a pause.
	_show_lit(_flicker_left % 2 == 0)
	_flicker_wait = _flicker_rng.randf_range(FLICKER_BLINK.x, FLICKER_BLINK.y)
	if _flicker_left == 0:
		_flicker_wait = _flicker_rng.randf_range(FLICKER_PAUSE.x, FLICKER_PAUSE.y)


func _show_lit(lit: bool) -> void:
	_glow(lit)
	if _diffuser != null:
		_diffuser.material_override = GreyboxLook.marker(GreyboxLook.LAMP) if lit else _dim


## Lamp light strength: full or a flicker dropout.
func _glow(lit: bool) -> void:
	var gain := light_gain if lit else light_gain * FLICKER_LOW
	_spot.light_energy = SPOT_ENERGY * gain
	_fill.light_energy = FILL_ENERGY * gain


func _physics_process(delta: float) -> void:
	var step := _fall.advance(delta)
	if is_zero_approx(step):
		return

	# A fall in the rules is Y growing, in the scene — Y decreasing.
	position.y -= step
	# Checked every frame of the fall: the lamp knocks down everyone it passed through.
	_crush_agents()

	if _fall.has_landed():
		_land()


## Hangs the lamp: [param hang_height] — how far its middle is above the floor,
## [param headroom] — floor height from floor to ceiling: the cord runs up to it.
##
## The lamp computes how far to fall from its own height: otherwise the level would have
## to keep a copy of the size from lamp.tscn and make sure it does not diverge.
## Call after adding to the tree — the shape is taken from the node.
func hang(hang_height: float, headroom: float = 0.0) -> void:
	_above_floor = hang_height
	var box := _shape.shape as BoxShape3D
	_fall.distance = maxf(hang_height - box.size.y * 0.5, 0.0)

	# The old cord is removed before the length check: a re-hung lamp must not keep a
	# leftover piece from its previous height.
	if _cord != null:
		_cord.queue_free()
		_cord = null
	var cord_length := headroom - hang_height - box.size.y * 0.5
	if cord_length <= 0.0:
		return
	_cord = GreyboxLook.box(
		Vector3(CORD_WIDTH, cord_length, CORD_WIDTH), GreyboxLook.surface(GreyboxLook.WALL)
	)
	_cord.position = Vector3(0.0, box.size.y * 0.5 + cord_length * 0.5, 0.0)
	add_child(_cord)
	# The hanging cup on the ceiling is part of the cord: it stays with it when the lamp falls.
	var canopy := _cylinder(CANOPY.x, CANOPY.y, GreyboxLook.metal(SHADE_COLOR))
	canopy.position = Vector3(0.0, cord_length * 0.5 - CANOPY.y * 0.5, 0.0)
	_cord.add_child(canopy)


## Whether the lamp hangs: not shot down. No point for the bot to aim at a shot-down one
## ([OttoBot]).
func is_hanging() -> bool:
	return not _fall.falling and not _fall.has_landed()


## Shot down. Repeated hits change nothing, including on an already fallen one:
## [method queue_free] removes it only at the end of the frame, and until then it keeps
## catching bullets.
func shoot_down() -> void:
	if not _fall.start():
		return
	# Sparks at the hit point: they stay there while the lamp falls (ADR-0031).
	if get_parent() != null:
		Sparks.burst(get_parent(), global_position)
	# A shot-down lamp stops glowing on its own: the body is the same, but no longer a
	# fixture. The cord stays on the ceiling — torn — rather than falling or vanishing
	# with it.
	_visual.material_override = GreyboxLook.surface(GreyboxLook.LAMP)
	if _diffuser != null:
		_diffuser.material_override = GreyboxLook.surface(GreyboxLook.LAMP.darkened(0.5))
	if _cord != null:
		_cord.reparent(get_parent())
		_cord = null
	Sounds.play(Sounds.LAMP_BREAK)


## Turns the lamp's light off or on. Called by the level when picking visible floors:
## the cone casts shadows and is expensive, so there is no point in it burning off
## screen (ADR-0010, point 8). The lamp itself stays as it was.
##
## [param shadowed] — the floor is in the frame. A fallback floor beyond the frame's edge
## burns only the cone, without shadow and no farther than its floor: nobody sees its
## shadows, and at the bottom of the building the fallback lamps made up a third of the
## shadow passes (ADR-0042, decision 2). The fill is off there: without a shadow it
## would shine through the ceiling onto the floor above.
##
## [param fill_shadowed] — whether the fill casts a shadow too. The fill shadow is cubic
## — six passes over the scene — and at the bottom of the building, with up to eight
## lamps in the frame, it alone cost 7.7 ms of 18 (M24h measurement, ADR-0044,
## decision 11). So the fill shadow is only for the [constant FILL_SHADOW_CAP] lamps
## nearest the middle of the frame; the rest light the fill without shadow and no
## farther than their floor.
func set_light_visible(on: bool, shadowed: bool = true, fill_shadowed: bool = true) -> void:
	_spot.visible = on
	_fill.visible = on and shadowed
	var fill := shadowed and fill_shadowed
	# The level calls this on all lamps at once as soon as the frame changed floors.
	# Writing the range or shadow, even the same value, marks the shadow map dirty, and
	# lamps where nothing changed would redraw their shadows in the same frame.
	if shadowed == _shadowed and fill == _fill_shadowed:
		return
	_shadowed = shadowed
	_fill_shadowed = fill
	apply_graphics()


## Lamp shadows by quality level (ADR-0030, decision 5): on low no shadows, on medium
## only the cone casts a shadow. On "Ultra" the cone is visible in the corridor air
## (ADR-0034, decision 1); the fill shines into the fog at a quarter — otherwise the air
## around the lamp would glow as a ball rather than a cone.
func apply_graphics() -> void:
	_spot.shadow_enabled = Graphics.spot_shadows() and _shadowed
	# A shadowless cone is not stopped by the floor: down to the floor and slightly into
	# the slab, but not through it.
	_spot.spot_range = SPOT_RANGE if _shadowed else minf(SPOT_RANGE, _above_floor + FLOOR_REACH)
	var fill := Graphics.fill_shadows() and _fill_shadowed
	_fill.shadow_enabled = fill
	_spot.light_volumetric_fog_energy = Graphics.light_in_fog()
	_fill.light_volumetric_fog_energy = Graphics.light_in_fog() * 0.25
	# A shadowless fill is not stopped by a slab and would shine through slabs onto
	# neighbouring, darkened floors — darkness would stop being darkness (as in M17).
	# Without a shadow its radius is one floor (code review M20).
	_fill.omni_range = FILL_RANGE if fill else FILL_RANGE_UNSHADOWED


## A fixture instead of a box: a cone-shaped shade and a diffuser underneath. The body
## box stays — hits and the fall are computed by it — but it is not visible.
func _dress_fixture() -> void:
	_visual.transparency = 1.0
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var box := _shape.shape as BoxShape3D
	if fixture == BuildingStyle.Fixture.PANEL:
		_dress_panel(box)
		return
	if fixture == BuildingStyle.Fixture.DOME:
		_dress_dome(box)
		return
	if fixture == BuildingStyle.Fixture.BULB:
		_dress_bulb(box)
		return
	if fixture == BuildingStyle.Fixture.CHANDELIER:
		_dress_chandelier(box)
		return
	var shade := _cylinder(SHADE.x, SHADE.z, GreyboxLook.metal(SHADE_COLOR), SHADE.y)
	shade.position = Vector3(0.0, box.size.y * 0.5 - SHADE.z * 0.5, 0.0)
	# The fixture casts no shadow: the light source sits inside it, and the shade and
	# bowl would muffle its own light (M20 shots — the floors went darker).
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shade)
	# A glowing bowl under the shade: visible from the side, not only from below. The
	# lamp is a target, and in a frame from a camera above, a flat diffuser vanished
	# (M20 shots).
	var bowl := SphereMesh.new()
	bowl.radius = BOWL.x
	bowl.height = BOWL.y * 2.0
	bowl.is_hemisphere = true
	_diffuser = MeshInstance3D.new()
	_diffuser.mesh = bowl
	_diffuser.material_override = GreyboxLook.marker(GreyboxLook.LAMP)
	_diffuser.rotation.x = PI
	_diffuser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_diffuser.position = Vector3(0.0, box.size.y * 0.5 - SHADE.z, 0.0)
	add_child(_diffuser)


## Office fixture: a white box under the cord and a glowing diffuser under it — seen
## from the side as a strip.
func _dress_panel(box: BoxShape3D) -> void:
	# The box is in the middle of the lamp's shape on two rods: the lamp is a target, and
	# under the ceiling a flat box read as a strip (M24i shots).
	var top := PANEL_BOX.y * 0.5
	# The box is matte: metal reflected the dark corridor, and from the front the fixture
	# read as a black square.
	var metal := GreyboxLook.surface(PANEL_COLOR)
	for side: float in [-1.0, 1.0]:
		var rod := GreyboxLook.box(Vector3(0.015, box.size.y * 0.5 - top, 0.015), metal)
		rod.position = Vector3(side * PANEL_BOX.x * 0.38, (box.size.y * 0.5 + top) * 0.5, 0.0)
		add_child(rod)
	var housing := GreyboxLook.box(PANEL_BOX, metal)
	housing.position = Vector3(0.0, 0.0, 0.0)
	housing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(housing)
	var slab := BoxMesh.new()
	slab.size = PANEL_DIFFUSER
	_diffuser = MeshInstance3D.new()
	_diffuser.mesh = slab
	_diffuser.material_override = GreyboxLook.marker(GreyboxLook.LAMP)
	_diffuser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_diffuser.position = Vector3(0.0, top - PANEL_BOX.y - PANEL_DIFFUSER.y * 0.5, 0.0)
	add_child(_diffuser)


## Residential fixture (ADR-0055, decision 4): a glass dish on a short tube under a
## brass cup. Hangs in the middle of the lamp's shape, like the office box: the target
## is the same, and a dish right at the ceiling would hide behind the slab's edge.
func _dress_dome(box: BoxShape3D) -> void:
	var brass := GreyboxLook.metal(DOME_CAP_COLOR)
	var stem := _cylinder(0.012, box.size.y * 0.5, brass)
	stem.position = Vector3(0.0, box.size.y * 0.25, 0.0)
	stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stem)
	var cap := _cylinder(DOME_CAP.x, DOME_CAP.y, brass, DOME_CAP.x * 0.6)
	cap.position = Vector3(0.0, DOME_CAP.y * 0.5, 0.0)
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cap)
	var glass := SphereMesh.new()
	glass.radius = DOME.x
	glass.height = DOME.y * 2.0
	glass.is_hemisphere = true
	_diffuser = MeshInstance3D.new()
	_diffuser.mesh = glass
	_diffuser.material_override = GreyboxLook.marker(GreyboxLook.LAMP)
	_diffuser.rotation.x = PI
	_diffuser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_diffuser.position = Vector3.ZERO
	add_child(_diffuser)


## Residential bare bulb (ADR-0056, decision 5): a socket on a wire and a bulb — only
## the bulb glows, like the diffuser of the others.
func _dress_bulb(box: BoxShape3D) -> void:
	var socket := _cylinder(BULB_SOCKET.x, BULB_SOCKET.y, GreyboxLook.surface(Color(0.1, 0.1, 0.1)))
	socket.position = Vector3(0.0, BULB.x + BULB_SOCKET.y * 0.5, 0.0)
	_unshadowed(socket)
	var wire := _cylinder(
		0.006, box.size.y * 0.5 - BULB.x, GreyboxLook.surface(Color(0.05, 0.05, 0.05))
	)
	wire.position = Vector3(0.0, (box.size.y * 0.5 + BULB.x) * 0.5, 0.0)
	_unshadowed(wire)
	var glass := SphereMesh.new()
	glass.radius = BULB.x
	glass.height = BULB.y
	_diffuser = MeshInstance3D.new()
	_diffuser.mesh = glass
	_diffuser.material_override = GreyboxLook.marker(GreyboxLook.LAMP)
	_diffuser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_diffuser)


## Hotel chandelier (ADR-0056, decision 5): a brass ring on a rod, arms and candle bulbs
## in a circle. The candles are a single diffuser mesh: a shot-down chandelier goes out
## all at once, like a shade.
func _dress_chandelier(box: BoxShape3D) -> void:
	var brass := GreyboxLook.metal(CHANDELIER_BRASS)
	# The rod reaches the top of the shape, where the cord starts ([method hang]): shorter
	# — and the chandelier would hang in the air under a torn piece.
	var stem := _cylinder(0.015, box.size.y * 0.5, brass)
	stem.position = Vector3(0.0, box.size.y * 0.25, 0.0)
	_unshadowed(stem)
	var ring := TorusMesh.new()
	ring.inner_radius = CHANDELIER - 0.02
	ring.outer_radius = CHANDELIER
	var hoop := MeshInstance3D.new()
	hoop.mesh = ring
	hoop.material_override = brass
	_unshadowed(hoop)
	var cup := _cylinder(0.05, 0.08, brass, 0.02)
	cup.position = Vector3(0.0, -0.06, 0.0)
	_unshadowed(cup)
	for arm: int in CANDLES:
		var holder := _cylinder(0.018, 0.05, brass)
		holder.position = _candle_at(arm) - Vector3(0.0, 0.045, 0.0)
		_unshadowed(holder)
	_diffuser = MeshInstance3D.new()
	_diffuser.mesh = _chandelier_mesh()
	_diffuser.material_override = GreyboxLook.marker(GreyboxLook.LAMP)
	_unshadowed(_diffuser)


## Where chandelier candle number [param arm] is: around the ring, slightly above it.
static func _candle_at(arm: int) -> Vector3:
	var angle := TAU * arm / CANDLES
	return Vector3(cos(angle) * CHANDELIER, 0.06, sin(angle) * CHANDELIER)


## Candles and the crystal bowl under the ring as one mesh ([member _chandelier_glow]).
static func _chandelier_mesh() -> ArrayMesh:
	if _chandelier_glow != null:
		return _chandelier_glow
	var tool := SurfaceTool.new()
	var flame := SphereMesh.new()
	flame.radius = CANDLE.x
	flame.height = CANDLE.y
	# A five-centimetre bulb: the default sixty-four faces are too many.
	flame.radial_segments = 16
	flame.rings = 8
	for arm: int in CANDLES:
		tool.append_from(flame, 0, Transform3D(Basis.IDENTITY, _candle_at(arm)))
	var bowl := SphereMesh.new()
	bowl.radius = CHANDELIER_BOWL.x
	bowl.height = CHANDELIER_BOWL.y * 2.0
	bowl.is_hemisphere = true
	var under := Basis.from_euler(Vector3(PI, 0.0, 0.0))
	tool.append_from(bowl, 0, Transform3D(under, Vector3(0.0, -0.04, 0.0)))
	_chandelier_glow = tool.commit()
	return _chandelier_glow


## A shadowless fixture part: the light source sits inside the fixture, and the rod and
## arms would cast dark arcs on the wall (M24n shots).
func _unshadowed(part: MeshInstance3D) -> void:
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)


## A cylinder or a truncated cone: top [param top], bottom [param bottom] (same as the
## top by default), height [param height].
func _cylinder(
	top: float, height: float, material: StandardMaterial3D, bottom: float = -1.0
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom if bottom >= 0.0 else top
	mesh.height = height
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	return part


func _make_spot() -> SpotLight3D:
	var light := SpotLight3D.new()
	light.light_color = light_colour
	light.light_energy = SPOT_ENERGY * light_gain
	light.spot_range = SPOT_RANGE
	light.spot_angle = SPOT_ANGLE
	light.shadow_enabled = true
	light.shadow_blur = SPOT_BLUR
	# The cone points down: in Godot, light goes along the source's -Z.
	light.rotation.x = -PI * 0.5
	return light


func _make_fill() -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = light_colour
	light.light_energy = FILL_ENERGY * light_gain
	light.omni_range = FILL_RANGE
	light.shadow_enabled = true
	# Two hemispheres, not a cube: two to three times fewer shadow passes. The fill is
	# faint and soft, the hemisphere seam does not show on it, and at the bottom of the
	# building the lamp cubes ate two thirds of the frame on "Ultra" (ADR-0042,
	# decision 2). The fill does not include the furniture in its shadow.
	light.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	light.shadow_caster_mask = ~PropCatalog.RENDER_LAYER
	return light


func _crush_agents() -> void:
	for body: Node3D in _crush_zone.get_overlapping_bodies():
		var agent := body as Enemy
		if agent == null or agent.is_dead():
			continue
		crushed.emit(agent)


func _land() -> void:
	Sounds.play(Sounds.LAMP_CRASH)
	fell.emit()
	# No debris left: the dark floor is visible anyway, and a body on the floor would
	# catch the player's bullets, which should fly on.
	queue_free()
