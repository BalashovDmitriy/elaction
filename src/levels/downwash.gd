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
## Полуглубина полосы пыли, м: в пределах настила крыши, не перед фасадом.
const DUST_DEPTH: float = 0.5
const DUST_SPEED := Vector2(2.5, 5.0)
const DUST_SIZE: float = 0.5
const DUST_COLOR := Color(0.55, 0.52, 0.48, 0.32)
const DUST_REACH: float = 7.0

## В снег поток поднимает с покрова снежную пыль (ADR-0054): гуще, белее,
## крупнее облаком и дольше висит.
const POWDER_COUNT: int = 120
const POWDER_LIFE: float = 2.4
const POWDER_SIZE: float = 0.6
const POWDER_COLOR := Color(0.9, 0.93, 0.98, 0.26)

## Поток от винта гонит и дождь: шар-отталкиватель частиц под осью винта
## разносит струи вниз и в стороны, и они ложатся косо, по скорости. Радиус
## шара, м, его сила, м/с², и какую долю высоты вертолёта над крышей он
## занимает — середина между винтом и настилом.
const GUST_RADIUS: float = 4.5
const GUST_STRENGTH: float = 60.0
const GUST_RISE: float = 0.5

## Высота крыши под вертолётом, сцена; NAN — крыши под ним нет.
var deck: float = NAN

var _gust := GPUParticlesAttractorSphere3D.new()


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
	# Полосой вдоль крыши, а не кольцом: кольцо выносило пыль вперёд за фасад,
	# и она висела перед тридцатым этажом. Разлёт — веером в плоскости кадра:
	# в стороны и вверх ([member ParticleProcessMaterial.flatness]).
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(DUST_RING.y, 0.05, DUST_DEPTH)
	process.direction = Vector3.UP
	process.spread = 80.0
	process.flatness = 1.0
	process.initial_velocity_min = DUST_SPEED.x
	process.initial_velocity_max = DUST_SPEED.y
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
	# Мягкий клуб, а не квадрат: без картинки частица рисовалась квадратом
	# цвета, и на снегу это было видно сразу (M24l).
	look.albedo_texture = _puff()
	look.vertex_color_use_as_albedo = true
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	look.disable_receive_shadows = true
	quad.material = look
	draw_pass_1 = quad
	_gust.name = "Gust"
	_gust.radius = GUST_RADIUS
	_gust.strength = 0.0
	_gust.attenuation = 1.0
	add_child(_gust)


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
	# Поток дождю — тот же, что пыли: пока вертолёт висит низко.
	_gust.position = Vector3(0.0, maxf(height - deck, 0.0) * GUST_RISE, 0.0)
	_gust.strength = -GUST_STRENGTH if low else 0.0


## Пыль становится снежной: покров на крыше лежит под винтом (ADR-0054).
## [param brightness] — яркость снега во время суток ([method SnowLook.brightness]):
## снежная пыль светится, как хлопья, а не берёт слабый свет крыши.
func lift_snow(brightness: float) -> void:
	amount = POWDER_COUNT
	lifetime = POWDER_LIFE
	var process := process_material as ParticleProcessMaterial
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	fade.colors = PackedColorArray(
		[Color(POWDER_COLOR, 0.0), POWDER_COLOR, Color(POWDER_COLOR, 0.0)]
	)
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	# Снег легче пыли: взлетает выше и опадает медленнее.
	process.gravity = Vector3(0.0, 0.6, 0.0)
	var quad := draw_pass_1 as QuadMesh
	quad.size = Vector2.ONE * POWDER_SIZE
	var look := quad.material as StandardMaterial3D
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.albedo_color = Color(SnowLook.TINT * brightness, 1.0)


## Шар, которым поток от винта разносит дождь и снег.
func gust() -> GPUParticlesAttractorSphere3D:
	return _gust


## Клуб пыли: круглое пятно, плотное в середине и тающее к краю.
static func _puff() -> GradientTexture2D:
	var spot := GradientTexture2D.new()
	spot.fill = GradientTexture2D.FILL_RADIAL
	spot.fill_from = Vector2(0.5, 0.5)
	spot.fill_to = Vector2(1.0, 0.5)
	spot.width = 64
	spot.height = 64
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	fade.colors = PackedColorArray(
		[Color.WHITE, Color(1.0, 1.0, 1.0, 0.45), Color(1.0, 1.0, 1.0, 0.0)]
	)
	spot.gradient = fade
	return spot
