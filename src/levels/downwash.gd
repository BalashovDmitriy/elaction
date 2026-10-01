class_name Downwash
extends GPUParticles3D

## Пыль под винтом вертолёта (ADR-0052, решение 6): поток от винта гонит её по
## крыше кольцом, пока вертолёт висит низко, и она оседает, когда он уходит.
## Кольцо — на крыше под осью винта, у плоскости игры.

## Сколько частиц, их жизнь, с, кольцо, откуда их поднимает, м, скорость
## разлёта, м/с, и цвет.
## Пыль встаёт, пока вертолёт висит не выше [constant DUST_REACH] над крышей.
const DUST_COUNT: int = 70
const DUST_LIFE: float = 1.4
const DUST_RING := Vector2(0.6, 2.6)
const DUST_SPEED := Vector2(2.5, 5.0)
const DUST_SIZE: float = 0.5
const DUST_COLOR := Color(0.55, 0.52, 0.48, 0.32)
const DUST_REACH: float = 7.0

## Высота крыши под вертолётом, сцена; NAN — крыши под ним нет.
var deck: float = NAN


func _init() -> void:
	name = "Downwash"
	amount = DUST_COUNT
	lifetime = DUST_LIFE
	local_coords = false
	emitting = false
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_aabb = AABB(Vector3(-8.0, -1.0, -8.0), Vector3(16.0, 4.0, 16.0))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = DUST_RING.y
	process.emission_ring_inner_radius = DUST_RING.x
	process.emission_ring_height = 0.05
	process.direction = Vector3(0.0, 0.15, 0.0)
	process.spread = 10.0
	process.radial_velocity_min = DUST_SPEED.x
	process.radial_velocity_max = DUST_SPEED.y
	process.gravity = Vector3(0.0, 0.3, 0.0)
	process.damping_min = 1.5
	process.damping_max = 2.5
	process.scale_min = 0.6
	process.scale_max = 1.5
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	fade.colors = PackedColorArray([Color(DUST_COLOR, 0.0), DUST_COLOR, Color(DUST_COLOR, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * DUST_SIZE
	var look := StandardMaterial3D.new()
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.vertex_color_use_as_albedo = true
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	look.disable_receive_shadows = true
	quad.material = look
	draw_pass_1 = quad


## Ставит кольцо под ось винта в [param x] и поднимает пыль, пока вертолёт
## на высоте [param height] сцены ниже [constant DUST_REACH] над крышей и
## [param hovering].
func follow(x: float, height: float, hovering: bool) -> void:
	if is_nan(deck):
		return
	global_position = Vector3(x, deck + 0.05, WorldSpace.PLAY_Z - 0.6)
	var low := hovering and height - deck < DUST_REACH
	if emitting != low:
		emitting = low
