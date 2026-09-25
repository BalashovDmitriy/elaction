class_name RainLook
extends RefCounted

## Вид дождя: струи, брызги, круги на лужах и завесы (M24a, ADR-0037,
## решение 3). Одни на крышу ([RoofRain]) и город ([CityBackdrop]): у дождя
## один вид, и собирать его дважды значило бы развести капли при первой правке.
##
## Струя — квад, повёрнутый по скорости частицы, со сдвигом назад: частица —
## голова струи. Капля, погашенная коллизией, гаснет головой о крышу, а хвост
## не уходит под настил.

const STREAK_SHADER := preload("res://src/levels/rain_streak.gdshader")
const RIPPLE_SHADER := preload("res://src/levels/rain_ripple.gdshader")
const CURTAIN_SHADER := preload("res://src/levels/rain_curtain.gdshader")

## Цвет дождя: холодный, как свет неба над городом.
const TINT := Color(0.68, 0.76, 0.95)

## Разброс направления капель, градусы: дождь не идёт строем.
const SPREAD: float = 1.5

## Под каким именем в частицах хранится число капель на «высоком»: по нему
## [method scale_amount] пересчитывает долю по уровню качества.
const FULL := &"full_amount"

## Слои дождя в городе, от камеры города вглубь (ADR-0037, решение 3): сколько
## капель, насколько дальше камеры середина слоя и полуглубина, м, размер
## струи, прозрачность, мягкость. Ближние — крупные и мягкие, дальние —
## тонкие, в дымке города.
const CITY_LAYERS: Array[Dictionary] = [
	{"drops": 260, "depth": 22.0, "reach": 10.0, "size": Vector2(0.07, 2.4), "alpha": 0.07},
	{"drops": 700, "depth": 52.0, "reach": 18.0, "size": Vector2(0.04, 1.6), "alpha": 0.12},
	{"drops": 600, "depth": 110.0, "reach": 30.0, "size": Vector2(0.06, 2.2), "alpha": 0.1},
]
## Скорость капель в городе, м/с, и снос на метр падения.
const CITY_SPEED := Vector2(22.0, 27.0)
const CITY_SLANT: float = 0.14

## Завесы между рядами домов: глубина, прозрачность, полос на метр.
const CURTAINS: Array[Vector3] = [
	Vector3(86.0, 0.09, 0.9),
	Vector3(130.0, 0.08, 0.7),
	Vector3(190.0, 0.07, 0.5),
]
const CURTAIN_HEIGHT: float = 260.0


## Струи дождя: [param amount] капель из коробки [param extents] сыплются со
## скоростью [param speed] и сносом [param slant] и живут [param lifetime].
## Размер струи — [param size], прозрачность — [param alpha].
static func streaks(
	amount: int,
	lifetime: float,
	extents: Vector3,
	speed: Vector2,
	slant: float,
	size: Vector2,
	alpha: float,
	softness: float = 0.7
) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extents
	process.direction = Vector3(slant, -1.0, 0.0).normalized()
	process.spread = SPREAD
	process.initial_velocity_min = speed.x
	process.initial_velocity_max = speed.y
	process.gravity = Vector3.ZERO
	process.scale_min = 0.7
	process.scale_max = 1.3
	process.color_initial_ramp = ramp(Color(1.0, 1.0, 1.0, 0.45), Color.WHITE)

	var rain := GPUParticles3D.new()
	rain.amount = amount
	rain.set_meta(FULL, amount)
	rain.lifetime = lifetime
	rain.preprocess = lifetime
	rain.local_coords = false
	rain.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	rain.process_material = process
	rain.draw_pass_1 = streak_mesh(size, alpha, softness)
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return rain


## Квад струи: сдвинут назад на свою длину, чтобы частица была головой.
static func streak_mesh(size: Vector2, alpha: float, softness: float = 0.7) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = size
	quad.center_offset = Vector3(0.0, -size.y * 0.5, 0.0)
	var look := ShaderMaterial.new()
	look.shader = STREAK_SHADER
	look.set_shader_parameter("tint", Color(TINT, alpha))
	look.set_shader_parameter("softness", softness)
	quad.material = look
	return quad


## Доля капель по уровню качества: число на «высоком» — в метке [constant FULL].
static func scale_amount(particles: GPUParticles3D, share: float) -> void:
	var full := int(particles.get_meta(FULL, particles.amount))
	var wanted := maxi(int(float(full) * share), 1)
	if particles.amount != wanted:
		particles.amount = wanted


## Дождь города: слои струй у камеры и завесы между рядами домов. Слои —
## детьми [param camera]: едут с ней, а капли падают в мире.
static func city(camera: Camera3D, ground: float, from_x: float, to_x: float) -> Node3D:
	var host := Node3D.new()
	host.name = "Rain"
	for index in CITY_LAYERS.size():
		var layer := CITY_LAYERS[index]
		var reach := float(layer["depth"])
		var drops := streaks(
			int(layer["drops"]),
			2.2,
			Vector3(reach * 0.9 + 20.0, 2.0, float(layer["reach"])),
			CITY_SPEED,
			CITY_SLANT,
			layer["size"] as Vector2,
			float(layer["alpha"]),
			1.0 if index == 0 else 0.7
		)
		drops.name = "Layer%d" % index
		drops.position = Vector3(0.0, 26.0, -reach)
		drops.visibility_aabb = AABB(
			Vector3(-reach * 2.0 - 40.0, -80.0, -reach - 40.0),
			Vector3(reach * 4.0 + 80.0, 120.0, reach * 2.0 + 80.0)
		)
		camera.add_child(drops)
	for curtain in CURTAINS:
		host.add_child(_curtain(curtain, ground, from_x, to_x))
	return host


## Струи дождя города, чтобы пересчитать их долю по уровню качества.
static func city_layers(camera: Camera3D) -> Array[GPUParticles3D]:
	var found: Array[GPUParticles3D] = []
	for child in camera.get_children():
		if child is GPUParticles3D:
			found.append(child as GPUParticles3D)
	return found


static func _curtain(spec: Vector3, ground: float, from_x: float, to_x: float) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(to_x - from_x + spec.x * 4.0 + 400.0, CURTAIN_HEIGHT)
	var look := ShaderMaterial.new()
	look.shader = CURTAIN_SHADER
	look.set_shader_parameter("tint", Color(TINT, spec.y))
	look.set_shader_parameter("density", spec.z)
	look.set_shader_parameter("slant", CITY_SLANT)
	quad.material = look
	var curtain := MeshInstance3D.new()
	curtain.name = "Curtain%d" % int(spec.x)
	curtain.mesh = quad
	curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	curtain.position = Vector3((from_x + to_x) * 0.5, ground + CURTAIN_HEIGHT * 0.5, -spec.x)
	return curtain


static func ramp(from: Color, to: Color) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, from)
	gradient.set_color(1, to)
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture
