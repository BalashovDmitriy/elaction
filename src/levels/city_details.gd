class_name CityDetails
extends RefCounted

## Детали ночного города за зданием (M22, замечание пользователя — «больше
## детализации заднему фону»): верхи домов, мигающие огни, неон, зарево улиц,
## звёзды и луна, полосы тумана.
##
## Город размыт глубиной резкости своей камеры, поэтому детали такие, что
## читаются и в размытии: силуэт, огонёк, пятно цвета. Всё мультимешами и без
## источников света — огни и неон светятся сами, как окна (ADR-0029).
##
## Строит узлы; раскладку по сиду держит [CityPlan].

## Верх: уступ — доля ширины и высоты дома, шпиль, бак и антенна, м.
const SETBACK := Vector2(0.62, 0.12)
const SPIRE := Vector2(0.6, 14.0)
const TANK := Vector2(2.2, 3.4)
const TANK_LEGS: float = 2.0
const ANTENNA := Vector2(0.35, 9.0)

## Огонь на верху дома: размер, цвет, период мигания, с.
const BEACON: float = 1.6
const BEACON_COLOUR := Color(1.0, 0.12, 0.08)
const BEACON_PERIOD: float = 1.8

## Зарево улиц: высота полосы над землёй и её цвет у земли.
const GLOW_HEIGHT: float = 26.0
const GLOW_COLOUR := Color(1.0, 0.55, 0.25, 0.55)

## Звёзды и луна ясной ночи.
const STARS: int = 260
const MOON: float = 16.0
const MOON_COLOUR := Color(0.9, 0.92, 1.0)

## Полосы тумана: сколько, какой высоты и насколько плотные.
const FOG_BANKS: int = 7
const FOG_BANK_HEIGHT: float = 22.0
const FOG_BANK_COLOUR := Color(0.55, 0.58, 0.66, 0.16)
const FOG_DRIFT: float = 1.4

## Мигающие огни — шейдером: у каждого своя фаза, и узлов на огонь не нужно.
const BEACON_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform vec4 colour : source_color = vec4(1.0, 0.12, 0.08, 1.0);
uniform float period = 1.8;
varying float phase;
void vertex() {
	// Фаза мигания — своя у каждого огня; в фрагментный шейдер она не доходит
	// сама, только через varying.
	phase = INSTANCE_CUSTOM.x;
}
void fragment() {
	float on = step(0.62, fract(TIME / period + phase));
	vec2 centre = UV - vec2(0.5);
	float disc = smoothstep(0.5, 0.15, length(centre));
	ALBEDO = colour.rgb * (0.15 + on * 3.0);
	ALPHA = disc * (0.25 + on * 0.75);
}
"""


## Верхи домов: уступы, шпили, баки на опорах, антенны.
static func crowns(blocks: Array[CityPlan.Block], ground: float, facade: Material) -> Node3D:
	var host := Node3D.new()
	host.name = "Crowns"
	var boxes: Array[Transform3D] = []
	var tanks: Array[Transform3D] = []
	for block in blocks:
		var top := ground + block.height
		var front := block.z
		match block.crown:
			CityPlan.Crown.SETBACK:
				var size := Vector3(
					block.width * SETBACK.x, block.height * SETBACK.y, block.depth * 0.7
				)
				boxes.append(_box(size, Vector3(block.x, top + size.y * 0.5, front)))
			CityPlan.Crown.SPIRE:
				var base := Vector3(block.width * 0.3, 3.0, block.depth * 0.4)
				boxes.append(_box(base, Vector3(block.x, top + 1.5, front)))
				var spire := Vector3(SPIRE.x, SPIRE.y, SPIRE.x)
				boxes.append(_box(spire, Vector3(block.x, top + 3.0 + SPIRE.y * 0.5, front)))
			CityPlan.Crown.TANK:
				var at := block.x + block.width * 0.22
				tanks.append(
					Transform3D(
						Basis.from_scale(Vector3(TANK.x, TANK.y, TANK.x)),
						Vector3(at, top + TANK_LEGS + TANK.y * 0.5, front)
					)
				)
				for leg: float in [-0.35, 0.35]:
					var post := Vector3(0.25, TANK_LEGS, 0.25)
					boxes.append(
						_box(post, Vector3(at + leg * TANK.x, top + TANK_LEGS * 0.5, front))
					)
			CityPlan.Crown.ANTENNA:
				var mast := Vector3(ANTENNA.x, ANTENNA.y, ANTENNA.x)
				var at := block.x - block.width * 0.25
				boxes.append(_box(mast, Vector3(at, top + ANTENNA.y * 0.5, front)))
	host.add_child(_many("CrownBoxes", BoxMesh.new(), boxes, facade))
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.5
	cylinder.bottom_radius = 0.5
	cylinder.height = 1.0
	cylinder.radial_segments = 10
	host.add_child(_many("Tanks", cylinder, tanks, facade))
	return host


## Где у дома верх — для огня: над шпилем и антенной, над плоской крышей.
static func crown_top(block: CityPlan.Block, ground: float) -> Vector3:
	var top := ground + block.height
	match block.crown:
		CityPlan.Crown.SPIRE:
			return Vector3(block.x, top + 3.0 + SPIRE.y, block.z)
		CityPlan.Crown.ANTENNA:
			return Vector3(block.x - block.width * 0.25, top + ANTENNA.y, block.z)
		CityPlan.Crown.SETBACK:
			return Vector3(block.x, top + block.height * SETBACK.y, block.z)
		CityPlan.Crown.TANK:
			return Vector3(block.x + block.width * 0.22, top + TANK_LEGS + TANK.y, block.z)
	return Vector3(block.x, top, block.z)


## Красные огни на верхах домов, каждый со своей фазой мигания.
static func beacons(blocks: Array[CityPlan.Block], ground: float) -> MultiMeshInstance3D:
	var places: Array[Transform3D] = []
	var phases: Array[float] = []
	for block in blocks:
		if not block.beacon:
			continue
		var top := crown_top(block, ground)
		places.append(
			Transform3D(Basis.from_scale(Vector3.ONE * BEACON), top + Vector3(0, 0.6, 0.0))
		)
		phases.append(fposmod(block.x * 0.137, 1.0))
	var quad := QuadMesh.new()
	var shader := Shader.new()
	shader.code = BEACON_SHADER
	var look := ShaderMaterial.new()
	look.shader = shader
	look.set_shader_parameter("colour", BEACON_COLOUR)
	look.set_shader_parameter("period", BEACON_PERIOD)
	quad.material = look
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_custom_data = true
	many.mesh = quad
	many.instance_count = places.size()
	for index in places.size():
		many.set_instance_transform(index, places[index])
		many.set_instance_custom_data(index, Color(phases[index], 0.0, 0.0, 0.0))
	var node := MultiMeshInstance3D.new()
	node.name = "Beacons"
	node.multimesh = many
	return node


## Неоновые вывески на фасадах: полосы своего цвета, мимо дымки — неон режет
## туман.
static func signs(blocks: Array[CityPlan.Block], ground: float) -> MultiMeshInstance3D:
	var places: Array[Transform3D] = []
	var colours: Array[Color] = []
	var customs: Array[Color] = []
	for block in blocks:
		if block.sign_colour.a <= 0.0:
			continue
		var front := block.z + block.depth * 0.5 + 0.12
		var size := Vector3(block.sign_size.x, block.sign_size.y, 1.0)
		var at := Vector3(block.x + block.sign_x, ground + block.sign_y, front)
		places.append(Transform3D(Basis.from_scale(size), at))
		var fade := CityBackdrop.WINDOW_FADE[mini(block.row, CityBackdrop.WINDOW_FADE.size() - 1)]
		colours.append(block.sign_colour * (0.9 * fade))
		customs.append(CityLook.sign_custom(block))
	var quad := QuadMesh.new()
	# Подложка, трубка и буквы — шейдером (M24a): до того вывеска была ровным
	# прямоугольником цвета.
	quad.material = CityLook.signs()
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_colors = true
	many.use_custom_data = true
	many.mesh = quad
	many.instance_count = places.size()
	for index in places.size():
		many.set_instance_transform(index, places[index])
		many.set_instance_color(index, colours[index])
		many.set_instance_custom_data(index, customs[index])
	var node := MultiMeshInstance3D.new()
	node.name = "Signs"
	node.multimesh = many
	return node


## Зарево улиц: тёплая полоса у земли за первым рядом, гаснущая кверху. Город
## ночью подсвечен снизу, и без зарева дома стояли в темноте, как на пустыре.
static func street_glow(ground: float, from_x: float, to_x: float) -> MeshInstance3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(GLOW_COLOUR, 0.0))
	gradient.set_color(1, GLOW_COLOUR)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	look.albedo_texture = texture
	var quad := QuadMesh.new()
	quad.size = Vector2(to_x - from_x + 600.0, GLOW_HEIGHT)
	quad.material = look
	var glow := MeshInstance3D.new()
	glow.name = "StreetGlow"
	glow.mesh = quad
	glow.position = Vector3((from_x + to_x) * 0.5, ground + GLOW_HEIGHT * 0.5, -58.0)
	return glow


## Звёзды и луна над городом ясной ночи.
static func night_sky(building_seed: int, from_x: float, to_x: float, ground: float) -> Node3D:
	var host := Node3D.new()
	host.name = "NightSky"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, "stars"])
	var places: Array[Transform3D] = []
	var colours: Array[Color] = []
	for _i in STARS:
		var size := rng.randf_range(0.5, 1.4)
		var at := Vector3(
			rng.randf_range(from_x - 500.0, to_x + 500.0),
			ground + rng.randf_range(60.0, 300.0),
			-600.0
		)
		places.append(Transform3D(Basis.from_scale(Vector3.ONE * size), at))
		var warm := rng.randf() < 0.2
		var shine := rng.randf_range(0.35, 0.9)
		colours.append(Color(1.0, 0.9, 0.75) * shine if warm else Color(0.8, 0.86, 1.0) * shine)
	var quad := QuadMesh.new()
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.vertex_color_use_as_albedo = true
	look.disable_fog = true
	quad.material = look
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_colors = true
	many.mesh = quad
	many.instance_count = places.size()
	for index in places.size():
		many.set_instance_transform(index, places[index])
		many.set_instance_color(index, colours[index])
	var stars := MultiMeshInstance3D.new()
	stars.name = "Stars"
	stars.multimesh = many
	host.add_child(stars)

	var moon := MeshInstance3D.new()
	moon.name = "Moon"
	var disc := SphereMesh.new()
	disc.radius = MOON * 0.5
	disc.height = MOON
	var pale := StandardMaterial3D.new()
	pale.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pale.albedo_color = MOON_COLOUR
	pale.disable_fog = true
	disc.material = pale
	moon.mesh = disc
	moon.position = Vector3(to_x * 0.8, ground + 150.0, -590.0)
	host.add_child(moon)
	return host


## Полосы тумана между рядами домов; плывут вбок в [method drift].
static func fog_banks(building_seed: int, from_x: float, to_x: float, ground: float) -> Node3D:
	var host := Node3D.new()
	host.name = "FogBanks"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, "fog"])
	var gradient := Gradient.new()
	gradient.set_color(0, Color(FOG_BANK_COLOUR, 0.0))
	gradient.add_point(0.5, FOG_BANK_COLOUR)
	gradient.set_color(1, Color(FOG_BANK_COLOUR, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	for index in FOG_BANKS:
		var look := StandardMaterial3D.new()
		look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		look.albedo_texture = texture
		var quad := QuadMesh.new()
		quad.size = Vector2(
			rng.randf_range(160.0, 320.0), FOG_BANK_HEIGHT * rng.randf_range(0.7, 1.4)
		)
		quad.material = look
		var bank := MeshInstance3D.new()
		bank.mesh = quad
		var row := CityPlan.ROWS[index % CityPlan.ROWS.size()]
		bank.position = Vector3(
			rng.randf_range(from_x - 100.0, to_x + 100.0),
			ground + rng.randf_range(8.0, row.y),
			-row.x + 6.0
		)
		bank.set_meta(
			&"drift", rng.randf_range(0.5, 1.0) * FOG_DRIFT * (1.0 if index % 2 == 0 else -1.0)
		)
		host.add_child(bank)
	return host


## Сдвигает полосы тумана на [param delta] секунд: медленно, в разные стороны.
static func drift(banks: Node3D, delta: float, from_x: float, to_x: float) -> void:
	for child in banks.get_children():
		var bank := child as Node3D
		bank.position.x += float(bank.get_meta(&"drift", 0.0)) * delta
		# Ушла за край — возвращается с другого: туман не кончается.
		if bank.position.x > to_x + 300.0:
			bank.position.x = from_x - 300.0
		elif bank.position.x < from_x - 300.0:
			bank.position.x = to_x + 300.0


static func _box(size: Vector3, centre: Vector3) -> Transform3D:
	return Transform3D(Basis.from_scale(size), centre)


static func _many(
	title: String, mesh: Mesh, places: Array[Transform3D], look: Material
) -> MultiMeshInstance3D:
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.mesh = mesh
	many.instance_count = places.size()
	for index in places.size():
		many.set_instance_transform(index, places[index])
	var node := MultiMeshInstance3D.new()
	node.name = title
	node.multimesh = many
	node.material_override = look
	return node
