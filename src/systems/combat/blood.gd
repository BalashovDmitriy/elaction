class_name Blood
extends Node3D

## Брызги крови при попадании пули в агента или в Otto (просьба пользователя,
## ADR-0031).
##
## Один выброс по ходу пули: капли конусом вперёд и немного вверх, падают под
## тяжестью и темнеют. Без света и без тел — картинка, а не правило. Выключается
## в настройках ([member enabled]). Убирает себя сама.

## Сколько капель и сколько они живут, с.
const COUNT: int = 48
const LIFETIME: float = 0.7

## Скорость вылета, м/с, разброс конуса, градусы, и тяжесть.
const SPEED := Vector2(1.5, 4.5)
const SPREAD: float = 32.0
const GRAVITY: float = 9.8

## Капля: размер, м.
const DROP := Vector2(0.05, 0.09)

## Показывать ли кровь. Ставят настройки игрока; по умолчанию — да.
static var enabled: bool = true

var _age: float = 0.0


## Брызги в точке [param at] сцены по ходу [param towards] (−1 влево, +1 вправо).
## Ничего не делает, если кровь выключена в настройках.
static func spray(host: Node, at: Vector3, towards: float) -> void:
	if not enabled or host == null:
		return
	var blood := Blood.new()
	blood.name = "Blood"
	host.add_child(blood)
	blood.global_position = at
	blood.add_child(blood._particles(towards))


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
