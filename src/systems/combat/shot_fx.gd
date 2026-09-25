class_name ShotFx
extends Node3D

## Выстрел и удар пули: вспышка и дымок у ствола, искры, пыль и след на стене
## (ADR-0037, решение 5).
##
## Пуля с M24a втрое быстрее ROM и пересекает кадр меньше чем за секунду: сам
## трассер виден пару кадров, и выстрел читается по тому, что остаётся на месте, —
## вспышке у ствола, дымку и следу там, куда пуля пришла.
##
## Картинка, а не правило: на бой не влияет. Узел живёт до конца своих частиц и
## убирает себя сам. След — не узел эффекта: он остаётся на стене до конца
## здания, но их число ограничено ([constant HOLES_KEPT]).

## Вспышка у ствола: свет, сила, радиус и сколько она живёт, с. Короткий
## импульс — на три-четыре кадра, а не весь полёт пули: свет стоит у ствола.
const FLASH_COLOR := Color(1.0, 0.84, 0.52)
const FLASH_ENERGY: float = 4.0
const FLASH_RANGE: float = 2.4
const FLASH_TIME: float = 0.06
## Пятно вспышки у ствола, м.
const FLASH_SIZE: float = 0.42

## Дымок у ствола и пыль от удара: сколько клубков, живут, с, и размер, м.
const SMOKE_COUNT: int = 7
const SMOKE_LIFETIME: float = 0.7
const SMOKE_SIZE: float = 0.16
const DUST_COUNT: int = 10
const DUST_LIFETIME: float = 0.55
const DUST_SIZE: float = 0.12

## След пули на стене: размер, м, и сколько следов держит здание разом. Старые
## уходят первыми — в долгой перестрелке стены иначе обрастали бы сотнями
## декалей, а каждая — это работа кластера света на каждом кадре.
const HOLE_SIZE: float = 0.18
const HOLES_KEPT: int = 40
## Насколько вглубь стены от точки удара ложится след, м: на переднюю грань у
## самого края, которую видно камере, а не на торец, который к ней ребром.
const HOLE_INSET: float = 0.07

## Слой геометрии: по нему ищется передняя грань того, во что попала пуля.
const GEOMETRY: int = 1

static var _holes: Array[Decal] = []
static var _hole_texture: Texture2D = null
static var _flash_material: StandardMaterial3D = null

var _light: OmniLight3D = null
var _flash: MeshInstance3D = null
var _age: float = 0.0
var _lifetime: float = 0.0


## Выстрел в точке [param at] под узлом [param host], в сторону [param towards]
## (−1 влево, +1 вправо): вспышка со светом и дымок.
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
	# Тень от импульса в три кадра не нужна и дорога.
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


## Удар пули в стену, дверь или кабину в точке [param at]: искры, пыль и след.
## [param towards] — ход пули; [param surface] — во что она попала: след
## вешается на него, чтобы ехать с кабиной.
static func impact(host: Node, at: Vector3, towards: float, surface: Node3D) -> ShotFx:
	var fx := ShotFx.new()
	fx.name = "Impact"
	fx._lifetime = DUST_LIFETIME
	host.add_child(fx)
	fx.global_position = at
	Sparks.ricochet(host, at, towards)
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


## Сколько следов пуль сейчас на стенах. Тестам: потолок держится.
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


## След на передней грани того, во что попала пуля.
##
## Пуля летит в плоскости игры и бьёт в торец стены, а торец камере виден
## ребром. След поэтому ложится на переднюю грань у самого края — там, где торец
## с ней сходится: её глубину находит луч от камеры в стену.
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
	# Декаль бьёт вдоль своей −Y; поворот на четверть оборота по X направляет
	# её в стену, от камеры. Боковые грани — торец — её не берут.
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


## Выбрасывает из учёта следы, ушедшие вместе со зданием.
static func _forget_freed_holes() -> void:
	var kept: Array[Decal] = []
	for hole in _holes:
		if is_instance_valid(hole) and not hole.is_queued_for_deletion():
			kept.append(hole)
	_holes = kept


## Клубок частиц: дым у ствола или пыль у стены. Медленные мягкие пятна,
## всплывают и тают.
static func _puff(
	count: int, lifetime: float, size: float, heading: Vector3, colour: Color
) -> GPUParticles3D:
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

	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.vertex_color_use_as_albedo = true
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.albedo_texture = _soft_dot()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = look

	var particles := GPUParticles3D.new()
	particles.amount = count
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.local_coords = false
	particles.process_material = process
	particles.draw_pass_1 = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-2.0, -2.0, -2.0), Vector3(4.0, 4.0, 4.0))
	particles.emitting = true
	return particles


## Мягкое круглое пятно: белое в середине, прозрачное к краю.
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


## След пули: тёмная середина, обожжённый край, прозрачно снаружи.
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


## Пятно вспышки: мягкое к краю, всегда лицом к камере.
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
