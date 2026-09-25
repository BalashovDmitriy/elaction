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

## Ближняя и дальняя плоскости камеры города, м. Ближе шестидесяти метров в
## городе ничего нет, а точность глубины растёт с ближней плоскостью.
const LENS_NEAR: float = 1.0
const CITY_FAR: float = 700.0

## Расфокус города (ADR-0030, решение 2): резко до ближнего ряда, дальше —
## размыто, и тем сильнее, чем дальше. Плоскость игры не трогается — у основной
## камеры глубины резкости нет.
##
## Отсчёт — от камеры города, а она в тридцати метрах перед плоскостью игры:
## ближний ряд ([constant CityPlan.ROWS]) стоит от 90 до 102 м от неё. При
## начале расфокуса на 90 м граница резала ближний ряд по фасаду, и половина
## его окон была резкой, половина — нет (ADR-0037, решение 4).
const BLUR_FROM: float = 106.0
const BLUR_OVER: float = 120.0
const BLUR_AMOUNT: float = 0.035

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

## Во сколько раз небо ярче во вспышке молнии, и как сильно загораются стёкла.
const FLASH_SKY: float = 4.0
const FLASH_GLASS := Color(0.55, 0.6, 0.75)

var _view: SubViewport = null
var _camera: Camera3D = null
var _ground: float = 0.0
var _rules: BuildingRules = null
## Струи дождя у камеры города: их долю пересчитывает уровень качества.
var _rain_layers: Array[GPUParticles3D] = []
var _city_air: Environment = null
var _dark_glass: ShaderMaterial = null
var _fog_banks: Node3D = null
var _lightning: Lightning = null
## Вспышка, которая сейчас стоит на небе и в стёклах.
var _flash_shown: float = 0.0


## Строит город вдоль здания по правилам и сиду, с погодой [param weather].
func build(rules: BuildingRules, building_seed: int, weather: Weather.Kind) -> void:
	_rules = rules
	_ground = WorldSpace.height_to_scene(rules.floor_surface(rules.floors - 1))
	# Город звучит тем же, что показывает: улица, дождь или ветер (ADR-0036).
	Sounds.set_weather(weather)
	_view = SubViewport.new()
	_view.name = "CityView"
	_view.own_world_3d = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)

	var air := WorldEnvironment.new()
	_city_air = _air(weather)
	air.environment = _city_air
	_view.add_child(air)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_FRUSTUM
	_camera.near = LENS_NEAR
	_camera.far = CITY_FAR
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
	var dark := _dark_windows(blocks)
	_dark_glass = (dark.multimesh.mesh as QuadMesh).material as ShaderMaterial
	_view.add_child(dark)
	# Детали города (M22): верхи, огни, неон, зарево улиц.
	_view.add_child(CityDetails.crowns(blocks, _ground, _unshaded(FACADE)))
	_view.add_child(CityDetails.beacons(blocks, _ground))
	_view.add_child(CityDetails.signs(blocks, _ground))
	_view.add_child(CityDetails.street_glow(_ground, 0.0, rules.width))
	match weather:
		Weather.Kind.CLEAR:
			_view.add_child(CityDetails.night_sky(building_seed, 0.0, rules.width, _ground))
		Weather.Kind.FOG:
			_fog_banks = CityDetails.fog_banks(building_seed, 0.0, rules.width, _ground)
			_view.add_child(_fog_banks)
		Weather.Kind.RAIN:
			# Слои струй у камеры и завесы между рядами (ADR-0037, решение 3).
			_view.add_child(RainLook.city(_camera, _ground, 0.0, rules.width))
			_rain_layers = RainLook.city_layers(_camera)
			_lightning = Lightning.new()
			_lightning.setup(building_seed, Vector2(0.0, rules.width), _ground)
			_view.add_child(_lightning)

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


## Повторяет ход основной камеры: те же x, y и наклон, своя глубина и угол
## обзора, при котором плоскость игры видна в том же масштабе.
func _process(delta: float) -> void:
	if _fog_banks != null:
		CityDetails.drift(_fog_banks, delta, 0.0, _rules.width)
	if _lightning != null:
		var flash := _lightning.level()
		# Между вспышками небо и стёкла покадрово не переписываются.
		if flash != _flash_shown:
			_flash_shown = flash
			_city_air.background_energy_multiplier = 1.0 + flash * (FLASH_SKY - 1.0)
			# Отсвет молнии в стёклах: погасшие окна загораются отражённым небом.
			_dark_glass.set_shader_parameter("flash", flash)
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
	follow(main)


## Ставит камеру города по основной [param main]: на её оси, дальше от
## плоскости игры, и смотрит ровно вглубь (ADR-0037, решение 4).
##
## На оси основной, потому что основная стоит выше цели на свой наклон, и
## камера города, поставленная прямо против цели, сдвигала бы город на 3.5 м
## вниз (авторевью M19). Ровно, а не с наклоном основной: у перспективы с
## наклоном вертикали сходятся, края окон идут ступенькой, и на ходу ступеньки
## ползут по рядам окон. Вид сверху даёт сдвиг объектива — кадр смещается вниз
## в той же плоскости, и вертикали остаются вертикалями.
func follow(main: Camera3D) -> void:
	var back := main.global_basis.z * (CAMERA_DISTANCE - SideCamera.DISTANCE)
	var place := main.global_position + back
	_camera.global_transform = Transform3D(Basis.IDENTITY, place)
	# Куда смотрела ось основной камеры — там середина кадра: на плоскости игры
	# она ниже камеры на глубину, помноженную на наклон.
	var ahead := -main.global_basis.z
	var depth := maxf(place.z, 1.0)
	var drop := ahead.y / maxf(-ahead.z, 0.01)
	var height := main.size
	if main.projection != Camera3D.PROJECTION_ORTHOGONAL:
		# Кадр перспективы на плоскости игры — с расстояния основной камеры, а
		# не города: иначе город в кадре мельче в CAMERA_DISTANCE / DISTANCE раз.
		height = 2.0 * SideCamera.DISTANCE * tan(deg_to_rad(main.fov) * 0.5)
	_camera.set_frustum(
		height * LENS_NEAR / depth, Vector2(0.0, drop * LENS_NEAR), LENS_NEAR, CITY_FAR
	)


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


## Яркость вспышки молнии прямо сейчас, 0–1: воздух здания светлеет с ней.
func flash_level() -> float:
	return _lightning.level() if _lightning != null else 0.0


## Разрешение и дождь по уровню качества (ADR-0030, решение 5).
func apply_graphics() -> void:
	_fit_view()
	Graphics.smooth(_view)
	for layer in _rain_layers:
		RainLook.scale_amount(layer, Graphics.rain_share())


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
	# Свечение — чтобы огни антенн и неон на дальних домах цвели в размытии.
	air.glow_enabled = true
	air.glow_intensity = 0.7
	air.glow_hdr_threshold = 0.9
	return air


static func _unshaded(color: Color, vertex_colors: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.vertex_color_use_as_albedo = vertex_colors
	return material


## Коробки домов одним мультимешем: их сотни, и по узлу на дом не нужно.
## Пояса, простенки и карниз рисует шейдер ([CityLook]), тон — тип дома.
func _facades(blocks: Array[CityPlan.Block]) -> MultiMeshInstance3D:
	var box := BoxMesh.new()
	box.material = CityLook.facade()
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_colors = true
	many.use_custom_data = true
	many.mesh = box
	many.instance_count = blocks.size()
	for index in blocks.size():
		var block := blocks[index]
		var basis := Basis.from_scale(Vector3(block.width, block.height, block.depth))
		var centre := Vector3(block.x, _ground + block.height * 0.5, block.z)
		many.set_instance_transform(index, Transform3D(basis, centre))
		many.set_instance_color(index, CityLook.facade_tone(block))
		many.set_instance_custom_data(index, CityLook.facade_custom(block))
	var node := MultiMeshInstance3D.new()
	node.name = "Facades"
	node.multimesh = many
	return node


## Горящие окна на фасадах, обращённых к камере, одним мультимешем.
func _windows(blocks: Array[CityPlan.Block]) -> MultiMeshInstance3D:
	var places: Array[Transform3D] = []
	var colors: Array[Color] = []
	var customs: Array[Color] = []
	for block in blocks:
		for window: Vector2i in block.lit:
			places.append(_window_place(block, window))
			customs.append(CityLook.window_custom(block, window, true))
			# Холодное окно — по хешу окна и дома, а не по диагонали сетки: иначе
			# по всему городу шёл один и тот же узор (авторевью M19).
			var cold := hash([block.x, window]) % 3 == 0
			var tone := WINDOW_COLD if cold else WINDOW_WARM
			var fade := WINDOW_FADE[mini(block.row, WINDOW_FADE.size() - 1)]
			colors.append(Color(tone.r * fade, tone.g * fade, tone.b * fade))
	return window_quads("Windows", places, colors, customs, true)


## Погасшие окна — вся остальная сетка фасада — своим мультимешем.
##
## В дымке, в отличие от горящих: тёмное стекло обязано быть чуть светлее своего
## фасада, а фасад дымка высветляет. Без неё в тумане и под дождём погасшее окно
## выходило темнее фасада дальнего ряда, и сетка читалась дырами (авторевью M20).
func _dark_windows(blocks: Array[CityPlan.Block]) -> MultiMeshInstance3D:
	var places: Array[Transform3D] = []
	var colors: Array[Color] = []
	var customs: Array[Color] = []
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
				customs.append(CityLook.window_custom(block, cell, false))
	return window_quads("DarkWindows", places, colors, customs, false)


## Где на фасаде дома [param block] окно [param cell] сетки: колонка и этаж.
func _window_place(block: CityPlan.Block, cell: Vector2i) -> Transform3D:
	var grid := CityPlan.window_grid(block)
	var left := block.x - float(grid.x - 1) * CityPlan.WINDOW_STEP.x * 0.5
	var x := left + float(cell.x) * CityPlan.WINDOW_STEP.x
	var y := _ground + CityPlan.WINDOW_STEP.y * (float(cell.y) + 1.0)
	var front := block.z + block.depth * 0.5 + 0.05
	return Transform3D(Basis.from_scale(CityLook.window_scale(block)), Vector3(x, y, front))


## Окна одним мультимешем: квад на окно, цвет — вершинный, что за стеклом —
## в данных окна ([CityLook]). [param lit] — горящие: мимо дымки города.
static func window_quads(
	title: String,
	places: Array[Transform3D],
	colors: Array[Color],
	customs: Array[Color],
	lit: bool
) -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = WINDOW_SIZE
	quad.material = CityLook.windows(lit)
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_colors = true
	many.use_custom_data = true
	many.mesh = quad
	many.instance_count = places.size()
	for index in places.size():
		many.set_instance_transform(index, places[index])
		many.set_instance_color(index, colors[index])
		many.set_instance_custom_data(index, customs[index])
	var node := MultiMeshInstance3D.new()
	node.name = title
	node.multimesh = many
	return node
