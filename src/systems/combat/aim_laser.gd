class_name AimLaser
extends Node3D

## Agent's aim laser: a thin red thread from the barrel along the line of the future shot
## (ADR-0037, decision 5; user's decision).
##
## Since M24a the agent's bullet is three times faster than ROM, and dodging it on seeing the bullet
## itself is no longer possible. ROM's wind-up gives time to respond: while the agent winds up, from
## the barrel runs a laser at the height of the future bullet — high: crouch or jump, low — jump. In
## shadow the laser is the only sign, so it glows by itself.
##
## The laser does not serve as a light source: emission only, no [Light3D] — there are already
## dozens of sources per building. It ends where the bullet will arrive: at a wall, at Otto or at
## the bullet's range; at the end there is a red dot.
##
## The node stands at the barrel: the agent places it, and the laser runs along the node's +X toward
## [member direction].

## Laser thickness and the size of the dot at the end, m.
const THICKNESS: float = 0.026
const DOT_SIZE: float = 0.16

const COLOR := Color(1.0, 0.02, 0.02)
## How brightly the laser glows: noticeable even on a darkened floor.
const GLOW: float = 2.2
## Laser flicker: how much it dims in the worst frame, out of 1, and how often, Hz.
const FLICKER: float = 0.35
const FLICKER_RATE: float = 23.0

static var _beam_material: StandardMaterial3D = null
static var _dot_material: StandardMaterial3D = null

## Where the laser points: −1 left, +1 right.
var direction: float = 1.0
## What the laser stops at: the agent bullet's mask — geometry and Otto.
var mask: int = 1 | 2
## The laser does not reach beyond this: the bullet range.
var reach: float = 14.4
## How long until the bullet leaves, s, and at what speed it will fly, m/s. The agent sets
## these every wind-up frame: they show when the bullet will arrive.
var shot_in: float = 0.0
var shot_speed: float = 1.0

var _beam: MeshInstance3D = null
var _dot: MeshInstance3D = null
var _length: float = 0.0
var _clock: float = 0.0


## Assembles the laser switched off.
static func make() -> AimLaser:
	var laser := AimLaser.new()
	laser.name = "AimLaser"
	laser._build()
	laser.visible = false
	return laser


## Lights the laser toward [param towards] and stretches it to the first obstacle.
## Called every wind-up frame: Otto moves, and the end of the laser follows him.
func aim(towards: float) -> void:
	direction = signf(towards) if not is_zero_approx(towards) else 1.0
	visible = true
	set_process(true)
	_length = _trace()
	_beam.scale.x = maxf(_length, 0.001)
	_beam.position.x = direction * _length * 0.5
	_dot.position.x = direction * _length


## Puts out the laser: the shot has left, the wind-up was broken or the agent was killed. A
## switched-off laser costs no frame time: every agent and every corpse has a laser until the end of
## the building.
func put_out() -> void:
	visible = false
	set_process(false)


## Whether the laser is lit.
func is_on() -> bool:
	return visible


## In how many seconds the bullet flies [param distance] metres from the barrel:
## the rest of the wind-up plus the flight.
func time_to(distance: float) -> float:
	return shot_in + distance / maxf(shot_speed, 0.01)


## Laser length, m: to a wall, to Otto or to the bullet range.
func length() -> float:
	return _length if visible else 0.0


func _ready() -> void:
	# The engine enables [method _process] on entering the tree by itself: a laser assembled
	# switched off turns it back off.
	set_process(visible)


func _process(delta: float) -> void:
	if not visible:
		return
	_clock += delta
	# Flicker is two incommensurate sine waves: an even blink would read as
	# a signal rather than a laser.
	var wave := sin(_clock * TAU * FLICKER_RATE) * sin(_clock * TAU * FLICKER_RATE * 0.37)
	_beam.transparency = FLICKER * absf(wave)


## Laser length by a physics ray — the same thing the bullet will hit.
func _trace() -> float:
	if not is_inside_tree():
		return reach
	var from := global_position
	var to := from + Vector3(direction * reach, 0.0, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return reach
	return absf((hit["position"] as Vector3).x - from.x)


func _build() -> void:
	_beam = MeshInstance3D.new()
	_beam.name = "Beam"
	var quad := QuadMesh.new()
	# Unit length: the laser stretches by X scale.
	quad.size = Vector2(1.0, THICKNESS)
	_beam.mesh = quad
	_beam.material_override = _beam_mat()
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)

	_dot = MeshInstance3D.new()
	_dot.name = "Dot"
	var star := QuadMesh.new()
	star.size = Vector2(DOT_SIZE, DOT_SIZE)
	_dot.mesh = star
	_dot.material_override = _dot_mat()
	_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dot)


## Laser: black albedo and red emission. Scene light does not tint it, while the emission
## is visible in darkness too; not unshaded — Godot 4 unshaded does not take emission.
static func _beam_mat() -> StandardMaterial3D:
	if _beam_material == null:
		_beam_material = StandardMaterial3D.new()
		_beam_material.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
		_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_beam_material.emission_enabled = true
		_beam_material.emission = COLOR
		_beam_material.emission_energy_multiplier = GLOW
	return _beam_material


## The dot at the end: a soft red spot facing the camera, on top of the wall — the laser
## hits the end face, and the end face is seen edge-on by the camera.
static func _dot_mat() -> StandardMaterial3D:
	if _dot_material == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1.0, 0.75, 0.7, 1.0))
		gradient.set_color(1, Color(COLOR, 0.0))
		gradient.add_point(0.3, Color(COLOR, 0.9))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(0.5, 0.0)
		texture.width = 32
		texture.height = 32
		_dot_material = StandardMaterial3D.new()
		_dot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dot_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dot_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_dot_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_dot_material.no_depth_test = true
		_dot_material.render_priority = 1
		_dot_material.albedo_texture = texture
	return _dot_material
