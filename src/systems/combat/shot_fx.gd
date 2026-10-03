class_name ShotFx
extends Node3D

## A shot and a bullet hit: muzzle flash and smoke, sparks, dust and a mark on the wall
## (ADR-0037, decision 5).
##
## Since M24a the bullet is three times faster than in the ROM and crosses the frame in under a
## second: the tracer itself is visible for a couple of frames, and the shot reads by what stays in
## place — the muzzle flash, smoke and the mark where the bullet landed.
##
## Picture, not a rule: it does not affect combat. The node lives until its particles end and
## removes itself. The mark is not an effect node: it stays on the wall until the end of the
## building, but their number is limited ([constant HOLES_KEPT]).

## How far a bullet hit is heard, m.
const IMPACT_REACH: float = 22.0

## Muzzle flash: light, energy, radius and how long it lives, s. A short
## pulse — for three or four frames, not the whole bullet flight: the light stays at the muzzle.
const FLASH_COLOR := Color(1.0, 0.84, 0.52)
const FLASH_ENERGY: float = 4.0
const FLASH_RANGE: float = 2.4
const FLASH_TIME: float = 0.06
## Muzzle flash spot, m.
const FLASH_SIZE: float = 0.42

## Muzzle smoke and hit dust: how many puffs, lifetime, s, and size, m.
const SMOKE_COUNT: int = 7
const SMOKE_LIFETIME: float = 0.7
const SMOKE_SIZE: float = 0.16
const DUST_COUNT: int = 10
const DUST_LIFETIME: float = 0.55
const DUST_SIZE: float = 0.12

## Bullet mark on the wall: size, m, and how many marks a building keeps at once. Old ones
## go first — in a long shootout walls would otherwise grow hundreds of
## decals, and each one is light cluster work on every frame.
const HOLE_SIZE: float = 0.18
const HOLES_KEPT: int = 40
## How deep into the wall from the hit point the mark lands, m: on the front face at its
## very edge, which the camera sees, not on the end face, which is edge-on to it.
const HOLE_INSET: float = 0.07

## Geometry layer: used to find the front face of whatever the bullet hit.
const GEOMETRY: int = 1

static var _holes: Array[Decal] = []
static var _hole_texture: Texture2D = null
static var _flash_material: StandardMaterial3D = null
## Smoke and dust puffs ([method _puff]): the motion — by side and colour, the quad — by
## size, the spot material — one.
static var _puff_processes: Dictionary = {}
static var _puff_meshes: Dictionary = {}
static var _puff_look: StandardMaterial3D = null

var _light: OmniLight3D = null
var _flash: MeshInstance3D = null
var _age: float = 0.0
var _lifetime: float = 0.0


## A shot at point [param at] under node [param host], toward [param towards]
## (−1 left, +1 right): a flash with light and smoke.
static func muzzle(host: Node, at: Vector3, towards: float) -> ShotFx:
	var fx := ShotFx.new()
	fx.name = "Muzzle"
	fx._lifetime = SMOKE_LIFETIME
	host.add_child(fx)
	fx.global_position = at
	fx._light = OmniLight3D.new()
	fx._light.light_color = FLASH_COLOR
	fx._light.light_energy = FLASH_ENERGY
	fx._light.omni_range = FLASH_RANGE
	# A shadow from a three-frame pulse is unnecessary and expensive.
	fx._light.shadow_enabled = false
	fx.add_child(fx._light)
	fx._flash = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(FLASH_SIZE, FLASH_SIZE)
	fx._flash.mesh = quad
	fx._flash.material_override = _flash_mat()
	fx._flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(fx._flash)
	fx.add_child(
		_puff(
			SMOKE_COUNT,
			SMOKE_LIFETIME,
			SMOKE_SIZE,
			Vector3(signf(towards), 0.6, 0.0),
			Color(0.75, 0.74, 0.72, 0.45)
		)
	)
	return fx


## A bullet hit on a wall, door or cab at point [param at]: sparks, dust and a mark.
## [param towards] — bullet direction; [param surface] — what it hit: the mark
## hangs on it so it rides with the cab. [param audible] — false during shader
## warm-up ([ShaderWarmup]): there the hit is only drawn.
static func impact(
	host: Node, at: Vector3, towards: float, surface: Node3D, audible: bool = true
) -> ShotFx:
	var fx := ShotFx.new()
	fx.name = "Impact"
	fx._lifetime = DUST_LIFETIME
	host.add_child(fx)
	fx.global_position = at
	Sparks.ricochet(host, at, towards)
	# A bullet hit is heard where it landed: on cab metal — ringing, on
	# a wall and floor — dull (ADR-0052, decision 7).
	if audible:
		var metal := surface is AnimatableBody3D
		var sound := Sounds.BULLET_METAL if metal else Sounds.BULLET_WALL
		Sounds.play_at(host, sound, at, IMPACT_REACH)
	fx.add_child(
		_puff(
			DUST_COUNT,
			DUST_LIFETIME,
			DUST_SIZE,
			Vector3(-signf(towards), 0.3, 0.0),
			Color(0.62, 0.58, 0.52, 0.55)
		)
	)
	if surface != null:
		_leave_a_hole(fx, at, towards, surface)
	return fx


## How many bullet marks are on walls now. For tests: the cap holds.
static func holes() -> int:
	_forget_freed_holes()
	return _holes.size()


func _process(delta: float) -> void:
	_age += delta
	if _light != null:
		var left := 1.0 - _age / FLASH_TIME
		if left <= 0.0:
			_light.queue_free()
			_light = null
			_flash.queue_free()
			_flash = null
		else:
			_light.light_energy = FLASH_ENERGY * left
			_flash.transparency = 1.0 - left
	if _age > _lifetime + 0.2:
		queue_free()


## A mark on the front face of whatever the bullet hit.
##
## The bullet flies in the play plane and hits the wall's end face, and the end face is edge-on
## to the camera. So the mark lands on the front face at its very edge — where the end face
## meets it: its depth is found by a ray from the camera into the wall.
static func _leave_a_hole(fx: ShotFx, at: Vector3, towards: float, surface: Node3D) -> void:
	var space := fx.get_world_3d().direct_space_state
	var x := at.x + signf(towards) * HOLE_INSET
	var from := Vector3(x, at.y, at.z + WorldSpace.ROOM_DEPTH)
	var query := PhysicsRayQueryParameters3D.create(from, Vector3(x, at.y, at.z - 1.0), GEOMETRY)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var face_z: float = (hit["position"] as Vector3).z
	var decal := Decal.new()
	decal.name = "BulletHole"
	decal.size = Vector3(HOLE_SIZE, 0.3, HOLE_SIZE)
	decal.texture_albedo = _hole()
	# A decal projects along its −Y; a quarter turn around X points
	# it into the wall, away from the camera. Side faces — the end face — do not take it.
	decal.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	decal.normal_fade = 0.5
	decal.upper_fade = 0.0
	decal.lower_fade = 0.0
	surface.add_child(decal)
	decal.global_position = Vector3(x, at.y, face_z)
	_forget_freed_holes()
	_holes.append(decal)
	while _holes.size() > HOLES_KEPT:
		var oldest: Decal = _holes.pop_front()
		oldest.queue_free()


## Drops from tracking the marks that went away with the building.
static func _forget_freed_holes() -> void:
	var kept: Array[Decal] = []
	for hole in _holes:
		if is_instance_valid(hole) and not hole.is_queued_for_deletion():
			kept.append(hole)
	_holes = kept


## A particle puff: smoke at the muzzle or dust at the wall. Slow soft spots
## that float up and melt.
##
## Materials and mesh are shared by all shots: they have four variants (smoke and dust,
## left and right), and building them anew would mean rasterizing textures for
## every bullet of a shootout.
static func _puff(
	count: int, lifetime: float, size: float, heading: Vector3, colour: Color
) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = count
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.local_coords = false
	particles.process_material = _puff_process(heading, colour)
	particles.draw_pass_1 = _puff_mesh(size)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-2.0, -2.0, -2.0), Vector3(4.0, 4.0, 4.0))
	particles.emitting = true
	return particles


## Puff motion: spread along [param heading], growth and fading of colour [param colour].
static func _puff_process(heading: Vector3, colour: Color) -> ParticleProcessMaterial:
	var key := "%s|%s" % [heading, colour]
	if _puff_processes.has(key):
		return _puff_processes[key] as ParticleProcessMaterial
	var process := ParticleProcessMaterial.new()
	process.direction = heading.normalized()
	process.spread = 40.0
	process.initial_velocity_min = 0.3
	process.initial_velocity_max = 1.2
	process.gravity = Vector3(0.0, 0.5, 0.0)
	process.damping_min = 1.5
	process.damping_max = 3.0
	process.scale_min = 0.7
	process.scale_max = 1.4
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.6))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	process.scale_curve = grow_texture

	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	fade.colors = PackedColorArray(
		[Color(colour, 0.0), colour, Color(colour.r, colour.g, colour.b, 0.0)]
	)
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	_puff_processes[key] = process
	return process


## Puff quad of size [param size]: a soft spot of the particle colour facing the camera.
static func _puff_mesh(size: float) -> QuadMesh:
	if _puff_meshes.has(size):
		return _puff_meshes[size] as QuadMesh
	if _puff_look == null:
		_puff_look = StandardMaterial3D.new()
		_puff_look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_puff_look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_puff_look.vertex_color_use_as_albedo = true
		_puff_look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_puff_look.albedo_texture = _soft_dot()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = _puff_look
	_puff_meshes[size] = quad
	return quad


## A soft round spot: white in the middle, transparent toward the edge.
static func _soft_dot() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 32
	texture.height = 32
	return texture


## Bullet mark: dark middle, scorched edge, transparent outside.
static func _hole() -> Texture2D:
	if _hole_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(0.03, 0.03, 0.03, 1.0))
		gradient.set_color(1, Color(0.2, 0.18, 0.16, 0.0))
		gradient.add_point(0.35, Color(0.08, 0.07, 0.06, 0.95))
		gradient.add_point(0.6, Color(0.25, 0.22, 0.2, 0.45))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(0.5, 0.0)
		texture.width = 32
		texture.height = 32
		_hole_texture = texture
	return _hole_texture


## Flash spot: soft toward the edge, always facing the camera.
static func _flash_mat() -> StandardMaterial3D:
	if _flash_material == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1.0, 1.0, 0.95, 1.0))
		gradient.set_color(1, Color(FLASH_COLOR, 0.0))
		gradient.add_point(0.35, Color(FLASH_COLOR, 0.8))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(0.5, 0.0)
		texture.width = 64
		texture.height = 64
		_flash_material = StandardMaterial3D.new()
		_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_flash_material.billboard_keep_scale = true
		_flash_material.albedo_texture = texture
	return _flash_material
