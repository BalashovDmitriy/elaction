class_name RoofRain
extends Node3D

## Дождь над крышей (M24a, ADR-0037, решение 3; решение пользователя —
## «капли естественно попадают по крыше, и это видно»).
##
## До M24a капля умирала по таймеру, рассчитанному на высоту до настила. Время
## жизни округлялось до тиков частиц, и половина капель пролетала лишний метр —
## под плиту крыши, на тридцатый этаж. Теперь капли гаснут о саму крышу:
## коллизия частиц по карте высот, снятой сверху с настила, ступеней, парапетов,
## машинного отделения и техники. Где капля ударила, там брызги; на настиле —
## круги, сам настил мокрый: темнее, с лужами, в которых на уровнях с
## отражениями видно машинное отделение и вывеску. С отлива парапетов и
## козырька машинного отделения капает.
##
## Перед этажами дождя нет: здание в разрезе, и струи перед этажом читались бы
## дождём в комнате. Капли сыплются только над настилом, между передней гранью
## коридора и задними ступенями кровли; рядом с башней идёт дождь города
## ([RainLook.city]) — он позади здания.
##
## Карта высот снимается один раз и только со слоя [constant LAYER]: на него
## [method catch_on] переводит неподвижное на крыше. Otto и агенты в ней не
## числятся — снятые на месте, где стояли при сборке, они оставили бы в дожде
## дыру в форме человека.

## Слой, с которого снимается карта высот дождя и на который ложится мокрый
## настил. Двадцатый: остальные слои в проекте не заняты, и камеры и свет видят
## все двадцать.
const LAYER: int = 1 << 19

## Капель на «высоком» ([method Graphics.rain_share]), высота неба над
## настилом, скорость, м/с, и снос на метр падения. Падают быстрее настоящего
## дождя: при 9 м/с струя за кадр — точка, и дождь читается снегом.
const DROPS: int = 560
const HEIGHT: float = 8.0
const SPEED := Vector2(15.0, 19.0)
const SLANT: float = 0.08
const DROP := Vector2(0.022, 0.75)
const ALPHA: float = 0.34

## Где по глубине идёт дождь: от задних ступеней кровли до передней грани
## коридора — не дальше, иначе капли вставали бы перед плитой крыши.
const BACK_Z: float = -3.0
const FRONT_Z: float = WorldSpace.CORRIDOR_DEPTH * 0.5 - 0.08

## Толщина крышки над проёмом крыши, м: капля за шаг частиц проходит 15 см.
const LID_DEPTH: float = 0.4

## Шаг частиц: на 120 в секунду капля за шаг проходит 15 см, и брызги встают
## почти там, где она коснулась, а не под настилом.
const TICKS: int = 120

## Брызги: сколько капелек на удар, их размер и прозрачность, взлёт, м/с.
const SPLASH_PER_HIT: int = 4
const SPLASH := Vector2(0.024, 0.12)
const SPLASH_ALPHA: float = 0.7
const SPLASH_SPEED := Vector2(0.9, 2.1)
const SPLASH_LIFE: float = 0.3

## Круги на настиле: сколько разом, размер, жизнь.
const RIPPLES: int = 36
const RIPPLE: float = 0.24
const RIPPLE_LIFE: float = 0.65

## Капель с отлива парапетов и козырька машинного отделения: сколько капель
## разом и через сколько точек по кромке.
const DRIPS: int = 9
const DRIP_POINTS: int = 48
const DRIP := Vector2(0.02, 0.12)

## Мокрый настил: тон и шероховатость сухого и лужи. Шероховатость лужи — почти
## зеркало: отражения ([method Graphics.reflections]) ложатся только в неё.
const WET := Color(0.02, 0.022, 0.03, 0.55)
const PUDDLE := Color(0.012, 0.014, 0.02, 0.9)
const WET_ROUGHNESS: float = 0.32
const PUDDLE_ROUGHNESS: float = 0.04

var _drops: GPUParticles3D = null
var _splashes: GPUParticles3D = null
var _ripples: GPUParticles3D = null
var _drips: GPUParticles3D = null
var _catcher: GPUParticlesCollisionHeightField3D = null
var _lids: Array[GPUParticlesCollisionBox3D] = []
## Где идёт дождь, в координатах сцены: карта высот снимается с этой коробки.
var _box := AABB()


## Собирает дождь над крышей здания по правилам и плану. [param glow_at] —
## лампа над крышей: у неё капли светлеют.
func build(rules: BuildingRules, plan: BuildingPlan, glow_at: Vector3, glow_colour: Color) -> void:
	var bounds := rules.floor_span(BuildingRules.ROOF)
	var deck := WorldSpace.height_to_scene(rules.floor_surface(BuildingRules.ROOF))
	var edge := BuildingShell.COPING_OVERHANG + 0.1
	_box = AABB(
		Vector3(bounds.x - edge, deck - 0.6, BACK_Z - 0.3),
		Vector3(bounds.y - bounds.x + edge * 2.0, HEIGHT + 1.0, FRONT_Z - BACK_Z + 0.6)
	)
	_catch(rules)
	_cover_the_gaps(rules, plan, deck)
	_rain(rules, deck, glow_at, glow_colour)
	_splash()
	_ripple(rules, deck)
	_drip(rules, plan, deck)
	_wet(rules, deck)
	add_to_group(Graphics.GROUP)
	apply_graphics()


## Переводит на слой [constant LAYER] неподвижное на крыше под [param roots]:
## по нему снимается карта высот и на него ложится мокрый настил.
func catch_on(roots: Array[Node]) -> void:
	for root in roots:
		for node: Node in root.find_children("*", "GeometryInstance3D", true, false):
			var shape := node as GeometryInstance3D
			if shape is GPUParticles3D:
				continue
			if shape.get_aabb().size == Vector3.ZERO:
				continue
			var reach := shape.global_transform * shape.get_aabb()
			if reach.intersects(_box):
				shape.layers |= LAYER


## Сколько капель, брызг и кругов по уровню качества. На низком кругов и
## капели нет: там и капель вчетверо меньше, и круги на тонкой полосе настила
## читались бы мельканием.
func apply_graphics() -> void:
	var share := Graphics.rain_share()
	RainLook.scale_amount(_drops, share)
	RainLook.scale_amount(_splashes, share)
	RainLook.scale_amount(_ripples, share)
	var rich := Graphics.quality > Graphics.Quality.LOW
	_ripples.emitting = rich
	_ripples.visible = rich
	_drips.emitting = rich
	_drips.visible = rich


## Крышки над проёмами крыши, о которые гаснут капли, — для теста.
func lids() -> Array[GPUParticlesCollisionBox3D]:
	return _lids


## Капли, которые гаснут о крышу, — чтобы тест мог проверить коллизию.
func drops() -> GPUParticles3D:
	return _drops


## Карта высот дождя: с чего она снимается.
func catcher() -> GPUParticlesCollisionHeightField3D:
	return _catcher


func _catch(rules: BuildingRules) -> void:
	_catcher = GPUParticlesCollisionHeightField3D.new()
	_catcher.name = "RainCatcher"
	_catcher.size = _box.size
	_catcher.position = _box.get_center()
	_catcher.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_1024
	_catcher.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	_catcher.heightfield_mask = LAYER
	_catcher.set_meta(&"width", rules.floor_width(BuildingRules.ROOF))
	add_child(_catcher)


## Невидимые крышки над проёмами в плите крыши — над верхней шахтой.
##
## Машинное отделение накрывает шахту только у задней стены, а проём идёт
## сквозь плиту на всю глубину. Капли перед домиком падали бы в шахту и
## дальше вниз — перед порталом тридцатого этажа, то есть дождём в здании.
## Крышка — на уровне настила: там у шахты, стоящей на крыше, крыша кабины.
func _cover_the_gaps(rules: BuildingRules, plan: BuildingPlan, deck: float) -> void:
	for gap in plan.gaps_on(rules, BuildingRules.ROOF):
		var lid := GPUParticlesCollisionBox3D.new()
		lid.name = "Lid"
		lid.size = Vector3(gap.y - gap.x + 0.1, LID_DEPTH, _box.size.z)
		# Верх крышки чуть выше настила: капля гаснет, уйдя под верх на шаг
		# частиц, и так гаснет вровень с настилом, а не под ним.
		var top := deck + SPEED.y / float(TICKS)
		lid.position = Vector3((gap.x + gap.y) * 0.5, top - LID_DEPTH * 0.5, _box.get_center().z)
		add_child(lid)
		_lids.append(lid)


func _rain(rules: BuildingRules, deck: float, glow_at: Vector3, glow_colour: Color) -> void:
	var bounds := rules.floor_span(BuildingRules.ROOF)
	# Сыплются между краями отливов и со сдвигом против сноса: капля не
	# выносится за парапет и не падает мимо крыши вниз по фасаду.
	var fall := HEIGHT + 0.3
	var spread := fall * tan(deg_to_rad(RainLook.SPREAD))
	var from := bounds.x - BuildingShell.COPING_OVERHANG + spread
	var to := bounds.y + BuildingShell.COPING_OVERHANG - fall * SLANT - spread
	_drops = RainLook.streaks(
		DROPS,
		(HEIGHT + 1.0) / SPEED.x,
		Vector3((to - from) * 0.5, 0.3, (FRONT_Z - BACK_Z) * 0.5),
		SPEED,
		SLANT,
		DROP,
		ALPHA
	)
	_drops.name = "Drops"
	_drops.position = Vector3((from + to) * 0.5, deck + HEIGHT, (FRONT_Z + BACK_Z) * 0.5)
	_drops.fixed_fps = TICKS
	_drops.interpolate = true
	_drops.collision_base_size = 0.02
	_drops.visibility_aabb = AABB(
		Vector3(-(to - from), -HEIGHT - 1.0, -3.0), Vector3((to - from) * 2.0, HEIGHT + 2.0, 6.0)
	)
	var process := _drops.process_material as ParticleProcessMaterial
	process.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	process.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_COLLISION
	process.sub_emitter_amount_at_collision = SPLASH_PER_HIT
	var look := (_drops.draw_pass_1 as QuadMesh).material as ShaderMaterial
	look.set_shader_parameter("glow_at", glow_at)
	look.set_shader_parameter("glow_colour", Color(glow_colour * 0.5, 1.0))
	look.set_shader_parameter("glow_range", 3.5)
	add_child(_drops)


## Брызги в месте удара: несколько капелек вверх и в стороны, падают обратно.
func _splash() -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	# Капля гаснет, уже чуть уйдя под поверхность — на полшага частиц.
	process.emission_shape_offset = Vector3(0.0, SPEED.y / float(TICKS) * 0.5, 0.0)
	process.direction = Vector3.UP
	process.spread = 55.0
	process.initial_velocity_min = SPLASH_SPEED.x
	process.initial_velocity_max = SPLASH_SPEED.y
	process.gravity = Vector3(0.0, -9.8, 0.0)
	process.scale_min = 0.6
	process.scale_max = 1.3
	process.color_ramp = RainLook.ramp(Color.WHITE, Color(1.0, 1.0, 1.0, 0.0))

	var hits := float(DROPS) / ((HEIGHT + 1.0) / SPEED.x)
	var amount := int(hits * SPLASH_LIFE * float(SPLASH_PER_HIT) * 0.8)
	_splashes = GPUParticles3D.new()
	_splashes.name = "Splashes"
	_splashes.amount = amount
	_splashes.set_meta(RainLook.FULL, amount)
	_splashes.lifetime = SPLASH_LIFE
	_splashes.local_coords = false
	_splashes.fixed_fps = TICKS
	_splashes.interpolate = true
	_splashes.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	_splashes.process_material = process
	_splashes.draw_pass_1 = RainLook.streak_mesh(SPLASH, SPLASH_ALPHA, 0.5)
	_splashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_splashes.visibility_aabb = _local(_box)
	add_child(_splashes)
	_drops.sub_emitter = _drops.get_path_to(_splashes)


## Круги на мокром настиле: на всей его полосе между парапетами.
func _ripple(rules: BuildingRules, deck: float) -> void:
	var bounds := rules.floor_span(BuildingRules.ROOF)
	var inner := Vector2(bounds.x + BuildingShell.WALL_WIDTH, bounds.y - BuildingShell.WALL_WIDTH)
	var front := WorldSpace.CORRIDOR_DEPTH * 0.5
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3((inner.y - inner.x) * 0.5, 0.0, front - 0.05)
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.0
	process.scale_min = 0.6
	process.scale_max = 1.4
	var quad := QuadMesh.new()
	quad.size = Vector2(RIPPLE, RIPPLE)
	quad.orientation = PlaneMesh.FACE_Y
	var look := ShaderMaterial.new()
	look.shader = RainLook.RIPPLE_SHADER
	quad.material = look
	_ripples = GPUParticles3D.new()
	_ripples.name = "Ripples"
	_ripples.amount = RIPPLES
	_ripples.set_meta(RainLook.FULL, RIPPLES)
	_ripples.lifetime = RIPPLE_LIFE
	_ripples.preprocess = RIPPLE_LIFE
	_ripples.local_coords = false
	_ripples.process_material = process
	_ripples.draw_pass_1 = quad
	_ripples.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ripples.position = Vector3((inner.x + inner.y) * 0.5, deck + 0.006, 0.0)
	_ripples.visibility_aabb = AABB(
		Vector3(-(inner.y - inner.x), -0.5, -2.0), Vector3((inner.y - inner.x) * 2.0, 1.0, 4.0)
	)
	add_child(_ripples)


## Капель с кромок: отлив обоих парапетов и козырёк машинного отделения.
func _drip(rules: BuildingRules, plan: BuildingPlan, deck: float) -> void:
	var bounds := rules.floor_span(BuildingRules.ROOF)
	var coping := deck + BuildingShell.PARAPET_HEIGHT
	var edges: Array[PackedVector3Array] = []
	for x: float in [
		bounds.x + BuildingShell.WALL_WIDTH + BuildingShell.COPING_OVERHANG,
		bounds.y - BuildingShell.WALL_WIDTH - BuildingShell.COPING_OVERHANG,
	]:
		edges.append(PackedVector3Array([Vector3(x, coping, BACK_Z), Vector3(x, coping, FRONT_Z)]))
	var shaft := plan.roof_shaft()
	if shaft != null:
		var half := BuildingShafts.MACHINE_ROOM_SIZE.x * 0.5
		var top := deck + BuildingShafts.MACHINE_ROOM_SIZE.y
		var face := WorldSpace.BACK_WALL_Z + BuildingShafts.MACHINE_ROOM_DEPTH
		edges.append(
			PackedVector3Array(
				[Vector3(shaft.x - half, top, face), Vector3(shaft.x + half, top, face)]
			)
		)
	var points := Image.create(DRIP_POINTS, 1, false, Image.FORMAT_RGBF)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["drips", bounds])
	for index in DRIP_POINTS:
		var line := edges[index % edges.size()]
		var at := line[0].lerp(line[1], rng.randf())
		points.set_pixel(index, 0, Color(at.x, at.y, at.z))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	process.emission_point_texture = ImageTexture.create_from_image(points)
	process.emission_point_count = DRIP_POINTS
	process.gravity = Vector3(0.0, -9.8, 0.0)
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.2
	process.direction = Vector3.DOWN
	process.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_drips = GPUParticles3D.new()
	_drips.name = "Drips"
	_drips.amount = DRIPS
	_drips.lifetime = 0.8
	_drips.randomness = 0.6
	_drips.local_coords = false
	_drips.fixed_fps = TICKS
	_drips.interpolate = true
	_drips.collision_base_size = 0.02
	_drips.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	_drips.process_material = process
	_drips.draw_pass_1 = RainLook.streak_mesh(DRIP, 0.6, 0.4)
	_drips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drips.visibility_aabb = _local(_box)
	add_child(_drips)


## Мокрый настил: наклейка на слой [constant LAYER] — темнее и глаже, в лужах
## почти зеркало.
func _wet(rules: BuildingRules, deck: float) -> void:
	var bounds := rules.floor_span(BuildingRules.ROOF)
	var noise := FastNoiseLite.new()
	noise.seed = hash(["puddles", bounds])
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	var width := bounds.y - bounds.x
	var depth := WorldSpace.CORRIDOR_DEPTH
	var pixels := Vector2i(1024, maxi(int(1024.0 * depth / width), 32))
	var wet := Decal.new()
	wet.name = "WetDeck"
	wet.size = Vector3(width, 0.3, depth)
	wet.position = Vector3((bounds.x + bounds.y) * 0.5, deck, 0.0)
	wet.cull_mask = LAYER
	wet.texture_albedo = _puddles(noise, pixels, [WET, WET, PUDDLE, PUDDLE])
	wet.texture_orm = _puddles(
		noise,
		pixels,
		[
			Color(1.0, WET_ROUGHNESS, 0.0),
			Color(1.0, WET_ROUGHNESS, 0.0),
			Color(1.0, PUDDLE_ROUGHNESS, 0.0),
			Color(1.0, PUDDLE_ROUGHNESS, 0.0),
		]
	)
	wet.upper_fade = 0.05
	wet.lower_fade = 0.05
	add_child(wet)


## Лужи по шуму: сухое до середины шума, лужа — выше неё.
static func _puddles(noise: FastNoiseLite, pixels: Vector2i, colours: Array[Color]) -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.56, 0.64, 1.0])
	gradient.colors = PackedColorArray(colours)
	var texture := NoiseTexture2D.new()
	texture.width = pixels.x
	texture.height = pixels.y
	texture.noise = noise
	texture.color_ramp = gradient
	return texture


func _local(box: AABB) -> AABB:
	return AABB(box.position - global_position, box.size)
