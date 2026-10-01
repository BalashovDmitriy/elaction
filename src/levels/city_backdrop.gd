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

## Окна улицы выезда (`ExitStreet`) — квадами, как было у города до M24j.
const WINDOW_SIZE := Vector2(1.2, 1.5)

## Яркость окон по ряду глубины. Окна не берут дымку — в ней они гасли вместе с
## фасадами, и ночной город выходил без огней, — поэтому даль задаётся здесь.
const WINDOW_FADE: Array[float] = [1.0, 0.75, 0.55, 0.4]

## Погасшее окно — тёмное стекло чуть светлее фасада: по нему фасад читается
## сеткой окон, а не россыпью огней (ADR-0031, решение 6).
const WINDOW_DARK := Color(0.05, 0.06, 0.09)

## Как сильно стёкла загораются во вспышке молнии.
const FLASH_GLASS := Color(0.55, 0.6, 0.75)

## Дымка города — доля плотности погоды: дальние ряды уходят в цвет неба.
const HAZE: float = 0.25
## Экспозиция города: панорамы Poly Haven ярче нашего кадра.
const EXPOSURE: float = 0.8
## Сила света окон по времени суток: днём комната за стеклом темнее неба.
const WINDOW_GLOW: Array[float] = [0.45, 0.2, 0.6, 0.65]
## Сила дождя города днём — доля ночной: на светлом небе капли видны и так.
const DAY_RAIN: float = 0.25
## Тон верхов домов.
const CROWN := Color(0.32, 0.31, 0.3)

var _view: SubViewport = null
var _camera: Camera3D = null
var _ground: float = 0.0
var _rules: BuildingRules = null
## Струи дождя у камеры города: их долю пересчитывает уровень качества.
var _rain_layers: Array[GPUParticles3D] = []
var _city_air: Environment = null
## Материал домов: в него — доля горящих окон и вспышка молнии.
var _house_look: ShaderMaterial = null
var _fog_banks: Node3D = null
var _lightning: Lightning = null
## Вспышка, которая сейчас стоит на небе и в стёклах.
var _flash_shown: float = 0.0


## Строит город вдоль здания по правилам и сиду, с погодой [param weather] во
## время суток [param time] (ADR-0051).
func build(
	rules: BuildingRules,
	building_seed: int,
	weather: Weather.Kind,
	time: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT
) -> void:
	_rules = rules
	_ground = WorldSpace.height_to_scene(rules.floor_surface(rules.floors - 1))
	# Город звучит тем же, что показывает: улица, дождь или ветер (ADR-0036).
	Sounds.set_weather(weather, time)
	_view = SubViewport.new()
	_view.name = "CityView"
	_view.own_world_3d = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)

	var air := WorldEnvironment.new()
	_city_air = _air(weather, time)
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
	var houses := _buildings(blocks)
	_view.add_child(houses)
	_house_look = (houses.multimesh.mesh as BoxMesh).material as ShaderMaterial
	_house_look.set_shader_parameter("lit_share", CityPlan.LIT_SHARE * TimeOfDay.lit_windows(time))
	_house_look.set_shader_parameter("window_glow", WINDOW_GLOW[time])
	_view.add_child(CitySky.light(time, weather))
	# Детали города (M22): верхи, огни, неон, зарево улиц.
	_view.add_child(CityDetails.crowns(blocks, _ground, _crown_look()))
	var lights := TimeOfDay.street_lights(time, weather)
	var signs := CityDetails.signs(blocks, _ground)
	var neon := (signs.multimesh.mesh as QuadMesh).material as ShaderMaterial
	neon.set_shader_parameter("power", lights)
	neon.set_shader_parameter("daylight", TimeOfDay.daylight(time))
	_view.add_child(signs)
	if lights > 0.0:
		_view.add_child(CityDetails.beacons(blocks, _ground))
		var glow := CityDetails.street_glow(_ground, 0.0, rules.width)
		((glow.mesh as QuadMesh).material as StandardMaterial3D).albedo_color.a = lights
		_view.add_child(glow)
	match weather:
		Weather.Kind.FOG:
			_fog_banks = CityDetails.fog_banks(building_seed, 0.0, rules.width, _ground)
			_view.add_child(_fog_banks)
		Weather.Kind.RAIN:
			# Слои струй у камеры и завесы между рядами (ADR-0037, решение 3).
			var share := lerpf(1.0, DAY_RAIN, TimeOfDay.daylight(time))
			_view.add_child(RainLook.city(_camera, _ground, 0.0, rules.width, share))
			_rain_layers = RainLook.city_layers(_camera)
			# Гроза — только вечером и ночью (ADR-0051, решение 7).
			if TimeOfDay.has_thunder(time):
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
			(_city_air.sky.sky_material as ShaderMaterial).set_shader_parameter("flash", flash)
			# Отсвет молнии в стёклах: окна загораются отражённым небом.
			_house_look.set_shader_parameter("flash", flash)
	var main := get_viewport().get_camera_3d()
	if main == null or _camera == null:
		return
	# Здание закрыло кадр целиком — город не виден, и второй кадр не рисуется
	# (ADR-0030, решение 7).
	var side := main as SideCamera
	# Открытая комната показывает город в окне (ADR-0052, решение 5).
	var visible := side == null or is_visible_around(_rules, side.view()) or DoorRoom.open_count > 0
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


## Бьют ли над городом молнии: в дождь вечером и ночью.
func has_lightning() -> bool:
	return _lightning != null


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


func _air(weather: Weather.Kind, time: TimeOfDay.Kind) -> Environment:
	var air := Environment.new()
	air.background_mode = Environment.BG_SKY
	air.sky = Sky.new()
	air.sky.sky_material = CitySky.material(time, weather)
	air.sky.radiance_size = Sky.RADIANCE_SIZE_128
	# Свет и отражения — от неба: тени лиловые на закате и серые в дождь сами.
	air.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	air.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	air.fog_enabled = true
	# Дымка берёт цвет неба по направлению: даль уходит в небо, а не в серое.
	air.fog_aerial_perspective = 1.0
	air.fog_sky_affect = 0.0
	air.fog_density = Weather.city_fog(weather) * HAZE
	air.tonemap_mode = Environment.TONE_MAPPER_ACES
	air.tonemap_exposure = EXPOSURE
	# Свечение — чтобы огни антенн и неон на дальних домах цвели в размытии.
	air.glow_enabled = true
	air.glow_intensity = 0.45
	air.glow_hdr_threshold = 1.5
	return air


## Материал верхов: уступов, шпилей, баков — бетон под тем же светом.
static func _crown_look() -> StandardMaterial3D:
	var look := StandardMaterial3D.new()
	look.albedo_color = CROWN
	look.roughness = 0.85
	return look


## Дома одним мультимешем: их сотни, и по узлу на дом не нужно. Фасад —
## запечённый фасад пака по стилю дома, окна — в нём же ([CityLook]).
func _buildings(blocks: Array[CityPlan.Block]) -> MultiMeshInstance3D:
	var box := BoxMesh.new()
	box.material = CityLook.building()
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
		many.set_instance_color(index, CityLook.wall_tint(block))
		many.set_instance_custom_data(index, CityLook.building_custom(block))
	var node := MultiMeshInstance3D.new()
	node.name = "Buildings"
	node.multimesh = many
	return node


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
