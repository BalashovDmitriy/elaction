class_name RainLook
extends RefCounted

## Вид дождя: струи, брызги, круги на лужах, завесы и ореол лампы (M24a,
## ADR-0037, решение 3). Одни на крышу ([RoofRain]) и город ([CityBackdrop]):
## у дождя один вид, и собирать его дважды значило бы развести капли при первой
## правке.
##
## Капля светится не своим цветом, а светом (решение 3, дополнение, — выбор
## пользователя по кадрам): от ламп сцены, ярче против света, и несёт размытую
## копию того, что за ней. Перед окнами и неоном дождь искрит, перед тёмным
## небом пропадает — как дождь на фотографии ночного города.
##
## Струя — квад, повёрнутый по скорости частицы, со сдвигом назад: частица —
## голова струи. Капля, погашенная коллизией, гаснет головой о крышу, а хвост
## не уходит под настил.

const STREAK_SHADER := preload("res://src/levels/rain_streak.gdshader")
const RIPPLE_SHADER := preload("res://src/levels/rain_ripple.gdshader")
const CURTAIN_SHADER := preload("res://src/levels/rain_curtain.gdshader")
const HALO_SHADER := preload("res://src/levels/rain_halo.gdshader")

## Цвет дождя: холодный, как свет неба над городом.
const TINT := Color(0.75, 0.82, 1.0)

## Разброс направления капель, градусы: дождь не идёт строем.
const SPREAD: float = 1.5

## Под каким именем в частицах хранится число капель на «высоком»: по нему
## [method scale_amount] пересчитывает долю по уровню качества.
const FULL := &"full_amount"

## Слои дождя в городе, от камеры города вглубь (ADR-0037, решение 3): сколько
## капель, насколько дальше камеры середина слоя и полуглубина, м, размер
## струи. Ближние — крупные, дальние — тонкие, в дымке города. Капель в
## полтора раза больше, чем было у струй своего цвета: видна из них только
## часть — та, что на фоне окон.
const CITY_LAYERS: Array[Dictionary] = [
	{"drops": 420, "depth": 22.0, "reach": 10.0, "size": Vector2(0.07, 2.4)},
	{"drops": 1120, "depth": 52.0, "reach": 18.0, "size": Vector2(0.04, 1.6)},
	{"drops": 960, "depth": 110.0, "reach": 30.0, "size": Vector2(0.06, 2.2)},
]
## Струи города: ламп в городе нет, капли несут только свет за собой — вчетверо.
const CITY_DROP := {
	"lit_gain": 0.0, "back_gain": 4.0, "back_lod": 2.0, "base": 0.01, "opacity": 0.8
}
## Скорость капель в городе, м/с, и снос на метр падения.
const CITY_SPEED := Vector2(22.0, 27.0)
const CITY_SLANT: float = 0.14

## Завесы между рядами домов: глубина, сколько света за ними несут, полос на
## метр.
const CURTAINS: Array[Vector3] = [
	Vector3(86.0, 3.0, 0.9),
	Vector3(130.0, 3.0, 0.7),
	Vector3(190.0, 3.0, 0.5),
]
const CURTAIN_HEIGHT: float = 260.0

## Ореол лампы в дожде: размер квада, м, и яркость.
const HALO_SIZE := Vector2(9.0, 8.1)
const HALO_STRENGTH: float = 0.25


## Струи дождя: [param amount] капель из коробки [param extents] сыплются со
## скоростью [param speed] и сносом [param slant] и живут [param lifetime].
## Размер струи — [param size], вид — [param look] из [method drop_look].
static func streaks(
	amount: int,
	lifetime: float,
	extents: Vector3,
	speed: Vector2,
	slant: float,
	size: Vector2,
	look: ShaderMaterial
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

	var rain := GPUParticles3D.new()
	rain.amount = amount
	rain.set_meta(FULL, amount)
	rain.lifetime = lifetime
	rain.preprocess = lifetime
	rain.local_coords = false
	rain.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	rain.process_material = process
	rain.draw_pass_1 = streak_mesh(size, look)
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return rain


## Вид капли: шейдер струи с параметрами [param settings] — имена из
## [code]rain_streak.gdshader[/code], остальное по умолчанию шейдера.
static func drop_look(settings: Dictionary) -> ShaderMaterial:
	var look := ShaderMaterial.new()
	look.shader = STREAK_SHADER
	look.set_shader_parameter("tint", TINT)
	for key: String in settings:
		look.set_shader_parameter(key, settings[key])
	return look


## Квад струи: сдвинут назад на свою длину, чтобы частица была головой.
static func streak_mesh(size: Vector2, look: ShaderMaterial) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = size
	quad.center_offset = Vector3(0.0, -size.y * 0.5, 0.0)
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
			drop_look(CITY_DROP)
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


## Ореол лампы цвета [param colour] в дожде: квад размером [param size] на
## [param at], чуть позади лампы — между ней и фоном, яркость [param strength].
static func halo(
	at: Vector3, colour: Color, strength: float = HALO_STRENGTH, size: Vector2 = HALO_SIZE
) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var look := ShaderMaterial.new()
	look.shader = HALO_SHADER
	look.set_shader_parameter("colour", colour)
	look.set_shader_parameter("strength", strength)
	quad.material = look
	var glow := MeshInstance3D.new()
	glow.name = "Halo"
	glow.mesh = quad
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.position = at
	return glow


static func _curtain(spec: Vector3, ground: float, from_x: float, to_x: float) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(to_x - from_x + spec.x * 4.0 + 400.0, CURTAIN_HEIGHT)
	var look := ShaderMaterial.new()
	look.shader = CURTAIN_SHADER
	look.set_shader_parameter("tint", TINT)
	look.set_shader_parameter("gain", spec.y)
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
