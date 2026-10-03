class_name Sparks
extends Node3D

## Sparks from a bullet that hit a lamp (ADR-0031, decision 3; the user's request),
## and from a bullet that hit a wall or a door (ADR-0037, decision 5).
##
## One burst: hot streaks stretched by velocity fly in all
## directions with a downward bias, fall under gravity, turn yellow, red and fade.
## At a lamp they come with a flash of light for a tenth of a second; a ricochet has no
## light: there are many bullets in a firefight, and there are already dozens of sources per
## building. A picture, not a rule: it does not affect combat or darkness. Removes itself.

## How many sparks and how long they live, s.
const COUNT: int = 70
const LIFETIME: float = 0.75

## Launch speed, m/s, and gravity.
const SPEED := Vector2(2.5, 6.5)
const GRAVITY: float = 9.8

## Spark streak: width and length, m.
## Larger than a thin thread: on a light wall under a lamp the first 1 cm sparks
## were lost entirely (M20 shots).
const STREAK := Vector2(0.025, 0.18)

## Flash: colour, energy, radius and duration, s.
const FLASH_COLOR := Color(1.0, 0.82, 0.5)
const FLASH_ENERGY: float = 5.0
const FLASH_RANGE: float = 3.0
const FLASH_TIME: float = 0.1

## How much closer to the camera the sparks are than the lamp, m: in front of the wall, not
## in it.
const FRONT: float = 0.3

## Ricochet: how many sparks, their speed and spread, degrees. Smaller than at a lamp — a
## bullet knocks out a handful, not a sheaf.
const RICOCHET_COUNT: int = 18
const RICOCHET_SPEED := Vector2(2.0, 5.0)
const RICOCHET_SPREAD: float = 55.0

var _flash: OmniLight3D = null
var _age: float = 0.0
## Where the sparks fly, how many there are, the spread and whether there is a light flash.
var _direction := Vector3(0.0, -1.0, 0.0)
var _count: int = COUNT
var _speed := SPEED
var _spread: float = 75.0
var _lit: bool = true


## Throws sparks at scene point [param at] under node [param host].
static func burst(host: Node, at: Vector3) -> Sparks:
	var sparks := Sparks.new()
	sparks.name = "Sparks"
	host.add_child(sparks)
	sparks.global_position = at + Vector3(0.0, 0.0, FRONT)
	return sparks


## A handful of sparks from a bullet that hit a wall, at point [param at]: they fly back,
## towards the shooter ([param towards] — bullet travel, −1 left, +1 right), with an upward
## bias. Without a light flash.
static func ricochet(host: Node, at: Vector3, towards: float) -> Sparks:
	var sparks := Sparks.new()
	sparks.name = "Ricochet"
	sparks._direction = Vector3(-signf(towards), 0.35, 0.0).normalized()
	sparks._count = RICOCHET_COUNT
	sparks._speed = RICOCHET_SPEED
	sparks._spread = RICOCHET_SPREAD
	sparks._lit = false
	host.add_child(sparks)
	sparks.global_position = at
	return sparks


func _ready() -> void:
	add_child(_particles())
	if not _lit:
		return
	_flash = OmniLight3D.new()
	_flash.light_color = FLASH_COLOR
	_flash.light_energy = FLASH_ENERGY
	_flash.omni_range = FLASH_RANGE
	_flash.shadow_enabled = false
	add_child(_flash)


func _process(delta: float) -> void:
	_age += delta
	if _flash != null:
		var left := 1.0 - _age / FLASH_TIME
		if left <= 0.0:
			_flash.queue_free()
			_flash = null
		else:
			_flash.light_energy = FLASH_ENERGY * left
	if _age > LIFETIME + 0.2:
		queue_free()


func _particles() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	# Down and sideways, in the play plane: the lamp hangs at the ceiling, and sparks
	# flying up and into the depth hid in the slab and behind the wall (M20 shots).
	process.direction = _direction
	process.spread = _spread
	process.particle_flag_disable_z = true
	process.initial_velocity_min = _speed.x
	process.initial_velocity_max = _speed.y
	process.gravity = Vector3(0.0, -GRAVITY, 0.0)
	process.damping_min = 0.5
	process.damping_max = 1.5
	process.particle_flag_align_y = true
	process.scale_min = 0.6
	process.scale_max = 1.2

	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.25, 0.7, 1.0])
	fade.colors = PackedColorArray(
		[
			Color(1.0, 1.0, 0.85, 1.0),
			Color(1.0, 0.85, 0.35, 1.0),
			Color(1.0, 0.35, 0.08, 0.8),
			Color(0.6, 0.1, 0.02, 0.0),
		]
	)
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp

	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.vertex_color_use_as_albedo = true
	var streak := QuadMesh.new()
	streak.size = STREAK
	streak.material = look

	var particles := GPUParticles3D.new()
	particles.amount = _count
	particles.lifetime = LIFETIME
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.local_coords = false
	particles.process_material = process
	particles.draw_pass_1 = streak
	particles.visibility_aabb = AABB(Vector3(-4.0, -5.0, -4.0), Vector3(8.0, 8.0, 8.0))
	particles.emitting = true
	return particles
