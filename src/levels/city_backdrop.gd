class_name CityBackdrop
extends Node

## Город за зданием — свой мир под перспективной камерой, подложенный фоном
## основного кадра (ADR-0029, решение 1).
##
## Основная камера ортографическая (ADR-0023, решение 1), и дома, поставленные
## в тот же мир, двигались бы с одной скоростью на любой глубине: параллакса не
## было бы. Поэтому город живёт в [SubViewport] со своим [World3D], его камера
## повторяет ход основной, но смотрит в перспективе — дальние ряды сдвигаются
## медленнее ближних. Картинка ложится на холст позади сцены, а основной
## воздух рисует этот холст фоном ([constant Environment.BG_CANVAS]): где нет
## здания — за башней и над крышей, — виден город.
##
## Окна — эмиссия без источников света: бюджет ламп кадра город не трогает.

## Слой холста, на котором лежит город. Отрицательный — позади сцены; основной
## воздух рисует фоном всё, что не выше него.
const CANVAS_LAYER: int = -1

## Насколько камера города отодвинута от плоскости игры, м. От этого зависит
## сила параллакса: чем ближе камера, тем быстрее ближний ряд уходит вбок
## относительно дальнего.
const CAMERA_DISTANCE: float = 30.0

## Расфокус города (ADR-0030, решение 2): резко до ближнего ряда, дальше —
## размыто, и тем сильнее, чем дальше. Плоскость игры не трогается — у основной
## камеры глубины резкости нет.
const BLUR_FROM: float = 90.0
const BLUR_OVER: float = 140.0
const BLUR_AMOUNT: float = 0.06

## Дом — тёмная коробка: его видно дымкой и окнами, а не гранями.
const FACADE := Color(0.012, 0.014, 0.022)

## Окна: тёплые и холодные вперемешку, как в ночном городе.
const WINDOW_WARM := Color(1.0, 0.78, 0.45)
const WINDOW_COLD := Color(0.62, 0.78, 1.0)
const WINDOW_SIZE := Vector2(1.2, 1.5)

## Яркость окон по ряду глубины. Окна не берут дымку — в ней они гасли вместе с
## фасадами, и ночной город выходил без огней, — поэтому даль задаётся здесь.
const WINDOW_FADE: Array[float] = [1.0, 0.75, 0.55, 0.4]

## Погасшее окно — тёмное стекло чуть светлее фасада: по нему фасад читается
## сеткой окон, а не россыпью огней (ADR-0031, решение 6).
const WINDOW_DARK := Color(0.05, 0.06, 0.09)

## Дождь: сколько капель в виду, их вид и скорость, м/с. Редкий и прозрачный:
## на первых кадрах густой дождь над крышей закрывал Otto — погода фон, а не
## занавес.
const RAIN_DROPS: int = 900
const RAIN_DROP := Vector2(0.025, 1.1)
const RAIN_COLOR := Color(0.65, 0.72, 0.9, 0.16)
const RAIN_SPEED: float = 28.0

var _view: SubViewport = null
var _camera: Camera3D = null
var _ground: float = 0.0
var _rules: BuildingRules = null
var _rain_node: GPUParticles3D = null


## Строит город вдоль здания по правилам и сиду, с погодой [param weather].
func build(rules: BuildingRules, building_seed: int, weather: Weather.Kind) -> void:
	_rules = rules
	_ground = WorldSpace.height_to_scene(rules.floor_surface(rules.floors - 1))
	_view = SubViewport.new()
	_view.name = "CityView"
	_view.own_world_3d = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)

	var air := WorldEnvironment.new()
	air.environment = _air(weather)
	_view.add_child(air)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.far = 700.0
	_camera.current = true
	var focus := CameraAttributesPractical.new()
	focus.dof_blur_far_enabled = true
	focus.dof_blur_far_distance = BLUR_FROM
	focus.dof_blur_far_transition = BLUR_OVER
	focus.dof_blur_amount = BLUR_AMOUNT
	_camera.attributes = focus
	_view.add_child(_camera)

	var blocks := CityPlan.generate(building_seed, 0.0, rules.width)
	_view.add_child(_facades(blocks))
	_view.add_child(_windows(blocks))
	_view.add_child(_dark_windows(blocks))
	if Weather.is_raining(weather):
		_rain_node = _rain()
		_camera.add_child(_rain_node)

	var layer := CanvasLayer.new()
	layer.name = "CityLayer"
	layer.layer = CANVAS_LAYER
	add_child(layer)
	var picture := TextureRect.new()
	picture.name = "City"
	picture.texture = _view.get_texture()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(picture)

	get_viewport().size_changed.connect(_fit_view)
	add_to_group(Graphics.GROUP)
	apply_graphics()


## Настраивает основной воздух так, чтобы он рисовал город фоном.
static func show_behind(environment: Environment) -> void:
	environment.background_mode = Environment.BG_CANVAS
	environment.background_canvas_max_layer = CANVAS_LAYER


## Капли дождя: частицы из коробки [param extents], падают в мире, а не за
## излучателем. Одни на город и крышу — у дождя один вид, и собирать его
## дважды значило бы развести капли при первой правке.
static func rain_particles(
	amount: int,
	lifetime: float,
	extents: Vector3,
	direction: Vector3,
	spread: float,
	speed: Vector2
) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extents
	process.direction = direction
	process.spread = spread
	process.initial_velocity_min = speed.x
	process.initial_velocity_max = speed.y
	process.gravity = Vector3.ZERO

	var drop := QuadMesh.new()
	drop.size = RAIN_DROP
	var look := _unshaded(RAIN_COLOR)
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.material = look

	var rain := GPUParticles3D.new()
	rain.amount = amount
	rain.lifetime = lifetime
	rain.local_coords = false
	rain.process_material = process
	rain.draw_pass_1 = drop
	return rain


## Повторяет ход основной камеры: те же x, y и наклон, своя глубина и угол
## обзора, при котором плоскость игры видна в том же масштабе.
func _process(_delta: float) -> void:
	var main := get_viewport().get_camera_3d()
	if main == null or _camera == null:
		return
	# Здание закрыло кадр целиком — город не виден, и второй кадр не рисуется
	# (ADR-0030, решение 7).
	var side := main as SideCamera
	var visible := side == null or is_visible_around(_rules, side.view())
	_view.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
	)
	if not visible:
		return
	var place := main.global_position
	# На оси основной камеры, только дальше от плоскости игры: основная стоит
	# выше цели на свой наклон, и камера города, поставленная прямо против
	# цели, сдвигала бы город на 3.5 м вниз (авторевью M19).
	var back := main.global_basis.z * (CAMERA_DISTANCE - SideCamera.DISTANCE)
	_camera.global_transform = Transform3D(main.global_basis, place + back)
	if main.projection == Camera3D.PROJECTION_ORTHOGONAL:
		_camera.fov = rad_to_deg(2.0 * atan(main.size * 0.5 / CAMERA_DISTANCE))


## Виден ли город в кадре [param view] (координаты правил): да, если в кадр
## попала крыша или небо над ней, или если хоть один этаж в кадре уже кадра.
static func is_visible_around(rules: BuildingRules, view: Rect2) -> bool:
	if view.position.y < rules.floor_surface(BuildingRules.ROOF):
		return true
	var span := VisibleFloors.around(rules, view)
	for index in range(span.x, span.y + 1):
		var bounds := rules.floor_span(clampi(index, 0, rules.floors - 1))
		if view.position.x < bounds.x or view.end.x > bounds.y:
			return true
	return false


## Разрешение и дождь по уровню качества (ADR-0030, решение 5).
func apply_graphics() -> void:
	_fit_view()
	if _rain_node != null:
		_rain_node.amount = maxi(int(float(RAIN_DROPS) * Graphics.rain_share()), 1)


func _fit_view() -> void:
	# Уровень снимают с дерева раньше, чем освобождают (main.gd, _drop_level), а
	# подписка на размер окна живёт до освобождения: вне дерева вьюпорта нет.
	if not is_inside_tree():
		return
	var window := get_viewport().get_visible_rect().size
	_view.size = Vector2i(
		maxi(int(window.x * Graphics.city_share()), 1),
		maxi(int(window.y * Graphics.city_share()), 1)
	)


func _air(weather: Weather.Kind) -> Environment:
	var air := Environment.new()
	air.background_mode = Environment.BG_COLOR
	air.background_color = Weather.sky(weather)
	air.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	air.fog_enabled = true
	air.fog_light_color = Weather.sky(weather)
	air.fog_density = Weather.city_fog(weather)
	air.tonemap_mode = Environment.TONE_MAPPER_ACES
	return air


static func _unshaded(color: Color, vertex_colors: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.vertex_color_use_as_albedo = vertex_colors
	return material


## Коробки домов одним мультимешем: их сотни, и по узлу на дом не нужно.
func _facades(blocks: Array[CityPlan.Block]) -> MultiMeshInstance3D:
	var box := BoxMesh.new()
	box.material = _unshaded(FACADE)
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.mesh = box
	many.instance_count = blocks.size()
	for index in blocks.size():
		var block := blocks[index]
		var basis := Basis.from_scale(Vector3(block.width, block.height, block.depth))
		var centre := Vector3(block.x, _ground + block.height * 0.5, block.z)
		many.set_instance_transform(index, Transform3D(basis, centre))
	var node := MultiMeshInstance3D.new()
	node.name = "Facades"
	node.multimesh = many
	return node


## Горящие окна на фасадах, обращённых к камере, одним мультимешем.
func _windows(blocks: Array[CityPlan.Block]) -> MultiMeshInstance3D:
	var places: Array[Transform3D] = []
	var colors: Array[Color] = []
	for block in blocks:
		for window: Vector2i in block.lit:
			places.append(_window_place(block, window))
			# Холодное окно — по хешу окна и дома, а не по диагонали сетки: иначе
			# по всему городу шёл один и тот же узор (авторевью M19).
			var cold := hash([block.x, window]) % 3 == 0
			var tone := WINDOW_COLD if cold else WINDOW_WARM
			var fade := WINDOW_FADE[mini(block.row, WINDOW_FADE.size() - 1)]
			colors.append(Color(tone.r * fade, tone.g * fade, tone.b * fade))
	return _window_quads("Windows", places, colors, false)


## Погасшие окна — вся остальная сетка фасада — своим мультимешем.
##
## В дымке, в отличие от горящих: тёмное стекло обязано быть чуть светлее своего
## фасада, а фасад дымка высветляет. Без неё в тумане и под дождём погасшее окно
## выходило темнее фасада дальнего ряда, и сетка читалась дырами (авторевью M20).
func _dark_windows(blocks: Array[CityPlan.Block]) -> MultiMeshInstance3D:
	var places: Array[Transform3D] = []
	var colors: Array[Color] = []
	for block in blocks:
		var grid := CityPlan.window_grid(block)
		var burning: Dictionary = {}
		for window: Vector2i in block.lit:
			burning[window] = true
		for column in grid.x:
			for level in grid.y:
				var cell := Vector2i(column, level)
				if burning.has(cell):
					continue
				places.append(_window_place(block, cell))
				colors.append(WINDOW_DARK)
	return _window_quads("DarkWindows", places, colors, true)


## Где на фасаде дома [param block] окно [param cell] сетки: колонка и этаж.
func _window_place(block: CityPlan.Block, cell: Vector2i) -> Transform3D:
	var grid := CityPlan.window_grid(block)
	var left := block.x - float(grid.x - 1) * CityPlan.WINDOW_STEP.x * 0.5
	var x := left + float(cell.x) * CityPlan.WINDOW_STEP.x
	var y := _ground + CityPlan.WINDOW_STEP.y * (float(cell.y) + 1.0)
	var front := block.z + block.depth * 0.5 + 0.05
	return Transform3D(Basis.IDENTITY, Vector3(x, y, front))


## Окна одним мультимешем: квад на окно, цвет — вершинный. [param fogged] —
## берут ли они дымку города.
static func _window_quads(
	title: String, places: Array[Transform3D], colors: Array[Color], fogged: bool
) -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = WINDOW_SIZE
	var look := _unshaded(Color.WHITE, true)
	look.disable_fog = not fogged
	quad.material = look
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_colors = true
	many.mesh = quad
	many.instance_count = places.size()
	for index in places.size():
		many.set_instance_transform(index, places[index])
		many.set_instance_color(index, colors[index])
	var node := MultiMeshInstance3D.new()
	node.name = title
	node.multimesh = many
	return node


## Дождь перед камерой города: частицы едут вместе с ней, но падают в мире.
func _rain() -> GPUParticles3D:
	var rain := rain_particles(
		RAIN_DROPS,
		1.6,
		Vector3(40.0, 2.0, 30.0),
		Vector3(0.15, -1.0, 0.0),
		3.0,
		Vector2(RAIN_SPEED, RAIN_SPEED * 1.2)
	)
	rain.name = "Rain"
	# Облако капель — над кадром и перед камерой: падают они сквозь весь вид.
	rain.position = Vector3(0.0, 20.0, -35.0)
	rain.visibility_aabb = AABB(Vector3(-60.0, -80.0, -60.0), Vector3(120.0, 120.0, 120.0))
	return rain
