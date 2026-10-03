class_name Blood
extends Node3D

## Blood spatter when a bullet hits an agent or Otto (the user's request,
## ADR-0031).
##
## One burst along the bullet's path: drops in a cone forward and slightly up, falling under
## gravity and darkening. No light and no bodies — a picture, not a rule. Can be turned off
## in the settings ([member enabled]). Removes itself.

## How many drops and how long they live, s.
const COUNT: int = 48
const LIFETIME: float = 0.7

## Launch speed, m/s, cone spread, degrees, and gravity.
const SPEED := Vector2(1.5, 4.5)
const SPREAD: float = 32.0
const GRAVITY: float = 9.8

## Drop: size, m.
const DROP := Vector2(0.05, 0.09)

## Stain under a cab (ADR-0043, decision 7): depth along the corridor and thickness
## of the layer it lies on, m; texture side, pixels.
const PUDDLE_DEPTH: float = 0.9
const PUDDLE_REACH: float = 0.12
const PUDDLE_SIZE: int = 128
const PUDDLE_COLOR := Color(0.36, 0.01, 0.02, 0.92)

## Whether to show blood. Set by the player's settings; yes by default.
static var enabled: bool = true

## Stain texture: one per game, drawn on first need.
static var _puddle_texture: ImageTexture = null

var _age: float = 0.0


## Spatter at scene point [param at] in direction [param towards] (−1 left, +1 right).
## Does nothing if blood is turned off in the settings.
static func spray(host: Node, at: Vector3, towards: float) -> void:
	if not enabled or host == null:
		return
	var blood := Blood.new()
	blood.name = "Blood"
	host.add_child(blood)
	blood.global_position = at
	blood.add_child(blood._particles(towards))


## A blood stain on the floor at point [param at], [param width] m wide along the floor.
## Lies until the end of the building: goes away together with the level it lies in.
static func puddle(host: Node, at: Vector3, width: float) -> Decal:
	if not enabled or host == null:
		return null
	var decal := Decal.new()
	decal.name = "Puddle"
	decal.size = Vector3(width, PUDDLE_REACH * 2.0, PUDDLE_DEPTH)
	decal.texture_albedo = _puddle()
	decal.modulate = PUDDLE_COLOR
	decal.albedo_mix = 1.0
	host.add_child(decal)
	decal.global_position = at
	return decal


## A stain with a ragged edge: a circle whose edge wanders by noise.
static func _puddle() -> ImageTexture:
	if _puddle_texture != null:
		return _puddle_texture
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.08
	var image := Image.create(PUDDLE_SIZE, PUDDLE_SIZE, false, Image.FORMAT_RGBA8)
	var half := PUDDLE_SIZE * 0.5
	for y: int in PUDDLE_SIZE:
		for x: int in PUDDLE_SIZE:
			var dx := (x - half) / half
			var dy := (y - half) / half
			var edge := 0.72 + 0.28 * noise.get_noise_2d(x, y)
			var alpha := 1.0 - smoothstep(edge - 0.08, edge, sqrt(dx * dx + dy * dy))
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_puddle_texture = ImageTexture.create_from_image(image)
	return _puddle_texture


func _process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME + 0.2:
		queue_free()


func _particles(towards: float) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(towards, 0.35, 0.0).normalized()
	process.spread = SPREAD
	process.initial_velocity_min = SPEED.x
	process.initial_velocity_max = SPEED.y
	process.gravity = Vector3(0.0, -GRAVITY, 0.0)
	process.particle_flag_align_y = true
	process.scale_min = 0.5
	process.scale_max = 1.3

	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	fade.colors = PackedColorArray(
		[Color(0.62, 0.02, 0.03, 1.0), Color(0.4, 0.01, 0.02, 1.0), Color(0.25, 0.0, 0.01, 0.0)]
	)
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp

	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.vertex_color_use_as_albedo = true
	var drop := QuadMesh.new()
	drop.size = DROP
	drop.material = look

	var particles := GPUParticles3D.new()
	particles.amount = COUNT
	particles.lifetime = LIFETIME
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.local_coords = false
	particles.process_material = process
	particles.draw_pass_1 = drop
	particles.visibility_aabb = AABB(Vector3(-3.0, -4.0, -3.0), Vector3(6.0, 6.0, 6.0))
	particles.emitting = true
	return particles
