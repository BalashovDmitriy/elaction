class_name BuildingScenery
extends Node3D

## Всё, что вокруг игры: воздух, свет над крышей, скаты крыши, обстановка
## этажей, город и погода (ADR-0029).
##
## Своим узлом, как [BuildingShell] и [BuildingShafts]: геймплея здесь нет, и
## уровню, собранному из строителей, довольно одной строки. Раньше воздух и
## свет крыши жили в самом уровне; город, погода и обстановка к ним добавились
## бы ещё сотней строк в файл, который и так на пределе.

## Лампа над крышей — у крыши ламп нет, а гаснуть она не должна никогда: ей
## светит город. Общий тон и воздух здания — [Atmosphere].
const ROOF_LIGHT_COLOR := Color(0.72, 0.78, 0.95)
const ROOF_LIGHT_ENERGY: float = 2.4
const ROOF_LIGHT_RANGE: float = 14.0
const ROOF_LIGHT_HEIGHT: float = 4.0

## Во сколько раз светлеет окружающий свет здания во вспышке молнии.
const FLASH_AMBIENT: float = 2.5

## Солнце утром, днём и вечером (ADR-0051): во сколько раз его сила из
## [TimeOfDay] и докуда кладёт тень, м. Лампа над крышей днём — отсвет неба:
## своя доля силы и цвет солнца.
const SUN_GAIN: float = 1.0
const SUN_SHADOW_DISTANCE: float = 70.0
const ROOF_LIGHT_BY_DAY: float = 0.45

var weather: Weather.Kind = Weather.Kind.CLEAR
var dressing: BuildingDressing = null
## Отель или офис и имя здания (ADR-0033, решение 1).
var identity: BuildingIdentity = null

## Воздух здания и дождь над крышей: их перестраивает [method apply_graphics].
var _air: WorldEnvironment = null
var _rain_node: RoofRain = null
var _roof_light: OmniLight3D = null
var _sun: DirectionalLight3D = null
## Крыша и её техника: с них снимается карта высот дождя.
var _roof_parts: Array[Node] = []
var _city: CityBackdrop = null
## Окружающий свет воздуха без вспышки: от него считается вспышка молнии.
var _ambient: float = 0.0


## Собирает окружение здания по правилам, плану и сиду.
func build(
	rules: BuildingRules,
	plan: BuildingPlan,
	building_seed: int,
	building_identity: BuildingIdentity = BuildingIdentity.new()
) -> void:
	weather = Weather.of_seed(building_seed)
	identity = building_identity

	_air = WorldEnvironment.new()
	_air.name = "Air"
	_air.environment = Atmosphere.environment(rules.palette.dark, rules.time_of_day)
	_ambient = _air.environment.ambient_light_energy
	CityBackdrop.show_behind(_air.environment)
	add_child(_air)
	_light_the_roof(rules)
	if not rules.is_night():
		_raise_sun(rules)

	var roof := BuildingRoof.new()
	roof.name = "Roof"
	add_child(roof)
	roof.build(rules, plan)
	var kit := RoofKit.new()
	kit.name = "RoofKit"
	add_child(kit)
	kit.build(rules, plan, building_seed)
	_roof_parts = [roof, kit] as Array[Node]
	var sign_board := VerticalSign.new()
	add_child(sign_board)
	sign_board.hang(rules, identity)

	var details := FloorDetail.new()
	details.name = "FloorDetail"
	add_child(details)
	details.build(rules, plan, BuildingStyle.of(identity))

	dressing = BuildingDressing.lay(rules, plan, building_seed, identity)
	var props := BuildingProps.new()
	props.name = "Props"
	add_child(props)
	props.build(rules, plan, dressing, identity)

	var city := CityBackdrop.new()
	_city = city
	city.name = "City"
	add_child(city)
	city.build(rules, building_seed, weather, rules.time_of_day)
	if Weather.is_raining(weather):
		# Капли гаснут о крышу, а не по таймеру (ADR-0037, решение 3).
		_rain_node = RoofRain.new()
		_rain_node.name = "RoofRain"
		add_child(_rain_node)
		_rain_node.build(rules, plan, _roof_light)
		_rain_node.catch_on(_roof_parts)
		sign_board.glow_in_rain()
	# Молнии — только в грозу: в ясную ночь, в туман и в дождь днём воздух
	# покадрово не трогается (ADR-0051, решение 7).
	set_process(_city.has_lightning())
	add_to_group(Graphics.GROUP)
	apply_graphics()


## Вспышка молнии доходит до здания: воздух коридоров на миг светлеет (M22).
## Не источник — яркость окружающего света, и бюджет ламп она не трогает.
func _process(_delta: float) -> void:
	if _city == null or _air == null:
		return
	_air.environment.ambient_light_energy = _ambient * (1.0 + _city.flash_level() * FLASH_AMBIENT)


## Отдаёт солнцу то, что снаружи: всё, что окружение построило на крыше, и
## то, что над перекрытием крыши построили другие строители уровня
## ([Outdoors]). Ночью солнца нет, и слой ставится всё равно — здание одно.
func light_outdoors(roots: Array[Node], rules: BuildingRules) -> void:
	for part in _roof_parts:
		Outdoors.mark(part)
	var under_roof := WorldSpace.height_to_scene(
		rules.floor_surface(BuildingRules.ROOF) + rules.slab_height
	)
	for root in roots:
		Outdoors.mark_above(root, under_roof - 0.02)


## Солнце над зданием: светит только на слой [constant Outdoors.LAYER].
func _raise_sun(rules: BuildingRules) -> void:
	var time := rules.time_of_day
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.light_color = TimeOfDay.sun_colour(time)
	_sun.light_energy = TimeOfDay.sun_energy(time, weather) * SUN_GAIN
	_sun.light_cull_mask = Outdoors.LAYER
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = SUN_SHADOW_DISTANCE
	var toward := TimeOfDay.sun_direction(time)
	_sun.basis = Basis.looking_at(-toward, Vector3.UP)
	add_child(_sun)
	_roof_light.light_color = TimeOfDay.sun_colour(time).lerp(ROOF_LIGHT_COLOR, 0.5)
	_roof_light.light_energy = ROOF_LIGHT_ENERGY * ROOF_LIGHT_BY_DAY


## Солнце, если оно есть: утром, днём и вечером.
func sun() -> DirectionalLight3D:
	return _sun


## Дождь над крышей гаснет и о то, что на ней построили другие строители
## уровня: плиту и парапеты, машинное отделение, торцы плит ([RoofRain]).
func catch_rain(roots: Array[Node]) -> void:
	if _rain_node != null:
		_rain_node.catch_on(roots)


## Дождь над крышей — чтобы тест мог проверить, где гаснут капли.
func roof_rain() -> RoofRain:
	return _rain_node


## Отражения, контактные тени и объёмный туман по уровню качества (ADR-0030,
## решение 5). Уровень меняют посреди партии, и применяется он к этому
## зданию, а не со следующего: воздух собран на всё здание один раз. Долю
## капель дождь над крышей пересчитывает сам ([RoofRain]).
func apply_graphics() -> void:
	if _air != null:
		Graphics.apply_to(_air.environment)
	if _sun != null:
		_sun.shadow_enabled = Graphics.sun_shadows()


## Лампа над крышей. Светлой зону делает собственный источник, а не отсутствие
## темноты: на этом держится правило темноты (ADR-0010, пункт 3).
func _light_the_roof(rules: BuildingRules) -> void:
	var roof_span := rules.floor_span(BuildingRules.ROOF)
	var over_roof := Vector2(
		(roof_span.x + roof_span.y) * 0.5,
		rules.floor_surface(BuildingRules.ROOF) - ROOF_LIGHT_HEIGHT
	)
	var sky_light := OmniLight3D.new()
	sky_light.name = "RoofLight"
	sky_light.light_color = ROOF_LIGHT_COLOR
	sky_light.light_energy = ROOF_LIGHT_ENERGY
	sky_light.omni_range = ROOF_LIGHT_RANGE
	sky_light.position = WorldSpace.to_scene(over_roof)
	add_child(sky_light)
	_roof_light = sky_light
