class_name Sparks
extends Node3D

## Искры от пули, попавшей в лампу (ADR-0031, решение 3; просьба пользователя).
##
## Один выброс: горячие штрихи, вытянутые по скорости, разлетаются во все
## стороны с уклоном вниз, падают под тяжестью, желтеют, краснеют и тают.
## Вместе с ними — вспышка света на десятую долю секунды. Картинка, а не
## правило: на бой и темноту не влияет. Убирает себя сама.

## Сколько искр и сколько они живут, с.
const COUNT: int = 70
const LIFETIME: float = 0.75

## Скорость вылета, м/с, и тяжесть.
const SPEED := Vector2(2.5, 6.5)
const GRAVITY: float = 9.8

## Штрих искры: ширина и длина, м.
## Крупнее тонкой нити: на светлой стене под лампой первые искры в 1 см
## терялись вовсе (кадры M20).
const STREAK := Vector2(0.025, 0.18)

## Вспышка: цвет, сила, радиус и длительность, с.
const FLASH_COLOR := Color(1.0, 0.82, 0.5)
const FLASH_ENERGY: float = 5.0
const FLASH_RANGE: float = 3.0
const FLASH_TIME: float = 0.1

## Насколько искры ближе к камере, чем лампа, м: перед стеной, а не в ней.
const FRONT: float = 0.3

var _flash: OmniLight3D = null
var _age: float = 0.0


## Выбрасывает искры в точке [param at] сцены под узлом [param host].
static func burst(host: Node, at: Vector3) -> Sparks:
	var sparks := Sparks.new()
	sparks.name = "Sparks"
	host.add_child(sparks)
	sparks.global_position = at + Vector3(0.0, 0.0, FRONT)
	return sparks


func _ready() -> void:
	add_child(_particles())
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
	# Вниз и в стороны, в плоскости игры: лампа висит у потолка, и искры,
	# летящие вверх и вглубь, прятались в плите и за стеной (кадры M20).
	process.direction = Vector3(0.0, -1.0, 0.0)
	process.spread = 75.0
	process.particle_flag_disable_z = true
	process.initial_velocity_min = SPEED.x
	process.initial_velocity_max = SPEED.y
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
	particles.amount = COUNT
	particles.lifetime = LIFETIME
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.local_coords = false
	particles.process_material = process
	particles.draw_pass_1 = streak
	particles.visibility_aabb = AABB(Vector3(-4.0, -5.0, -4.0), Vector3(8.0, 8.0, 8.0))
	particles.emitting = true
	return particles
