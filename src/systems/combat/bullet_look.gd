class_name BulletLook
extends Node3D

## Bullet look: a thin long tracer (M21, user's remark — "the bullet
## looks like a little square"; M24a — the bullet is three times faster, ADR-0037, decision 5).
##
## A bullet model would not help here: a real bullet at our scale is smaller than a pixel. A bullet
## in frame is seen the same way as in films — by a tracer: a bright elongated core and a fading
## tail behind. Everything glows by emission — the bullet is visible even on a darkened floor, and
## it adds no light sources. The shot's flash and smoke stand at the muzzle and live on their own
## time — that is [ShotFx], not the look of the flying bullet.
##
## Look only: the bullet's collision is its `Shape`, and that holds the ROM heights, not the tail.
##
## The tail grows with the distance travelled: right after the shot it would stick out of the
## shooter backward. Long and thin: the bullet covers half a metre per frame, and a short tail would
## read as a dot jumping across the frame rather than a streak.

## Core: length and thickness, m.
const CORE_LENGTH: float = 0.36
const CORE_RADIUS: float = 0.024
## Tail: full length and thickness at the head, m.
const TRAIL_LENGTH: float = 2.6
const TRAIL_THICKNESS: float = 0.042

const CORE := Color(1.0, 0.96, 0.82)
const TRAIL := Color(1.0, 0.72, 0.35)
## How brightly the core glows: brighter than the frame, so grading does not dim it.
const GLOW: float = 6.0

static var _core_material: StandardMaterial3D = null
static var _trail_material: StandardMaterial3D = null

var _direction: float = 1.0
var _trail: MeshInstance3D = null


## Assembles the look of a bullet flying toward [param direction] (−1 left, +1 right).
static func make(direction: float) -> BulletLook:
	var look := BulletLook.new()
	look.name = "Look"
	look._direction = signf(direction) if not is_zero_approx(direction) else 1.0
	look._build()
	return look


## Updates the tail by the distance the bullet has travelled, m.
func follow(travelled: float) -> void:
	var length := minf(travelled, TRAIL_LENGTH)
	_trail.visible = length > 0.01
	if _trail.visible:
		_trail.scale.x = length
		_trail.position.x = -_direction * (length * 0.5 + CORE_LENGTH * 0.3)


func _build() -> void:
	var core := MeshInstance3D.new()
	core.name = "Core"
	var capsule := CapsuleMesh.new()
	capsule.radius = CORE_RADIUS
	capsule.height = CORE_LENGTH
	capsule.radial_segments = 8
	capsule.rings = 2
	core.mesh = capsule
	# The capsule grows along Y; laid along the flight.
	core.rotation.z = PI * 0.5
	core.material_override = _core()
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)

	_trail = MeshInstance3D.new()
	_trail.name = "Trail"
	var strip := QuadMesh.new()
	# Unit length: the tail stretches by X scale.
	strip.size = Vector2(1.0, TRAIL_THICKNESS)
	_trail.mesh = strip
	_trail.material_override = _trail_mat()
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The tail gradient runs along the quad's U from left to right: for a bullet flying left,
	# the head of the tail is on the right, and the quad is turned around.
	if _direction < 0.0:
		_trail.rotation.y = PI
	add_child(_trail)
	follow(0.0)


## Core: glows by emission. Not unshaded — Godot 4 unshaded does not take emission,
## and the core would glow by albedo, no brighter than one, without a halo (M21 code review).
static func _core() -> StandardMaterial3D:
	if _core_material == null:
		_core_material = StandardMaterial3D.new()
		_core_material.albedo_color = CORE
		_core_material.emission_enabled = true
		_core_material.emission = CORE
		_core_material.emission_energy_multiplier = GLOW
	return _core_material


## Tail: from the head to the end it fades and cools — a gradient along U.
static func _trail_mat() -> StandardMaterial3D:
	if _trail_material == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(TRAIL, 0.0))
		gradient.set_color(1, Color(CORE, 1.0))
		var texture := GradientTexture1D.new()
		texture.gradient = gradient
		texture.width = 64
		_trail_material = StandardMaterial3D.new()
		_trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_trail_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_trail_material.albedo_texture = texture
		_trail_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	return _trail_material
