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

## Дождь над крышей: сколько капель и с какой высоты над настилом они падают.
## Внутри здания погоды нет, а крыша — снаружи.
const ROOF_RAIN_DROPS: int = 140
const ROOF_RAIN_HEIGHT: float = 7.0
## Наклон капель над крышей (снос вбок на метр падения) и разброс, градусы.
const ROOF_RAIN_SLANT: float = 0.1
const ROOF_RAIN_SPREAD: float = 2.0

## Во сколько раз светлеет окружающий свет здания во вспышке молнии.
const FLASH_AMBIENT: float = 2.5

var weather: Weather.Kind = Weather.Kind.CLEAR
var dressing: BuildingDressing = null
## Отель или офис и имя здания (ADR-0033, решение 1).
var identity: BuildingIdentity = null

## Воздух здания и дождь над крышей: их перестраивает [method apply_graphics].
var _air: WorldEnvironment = null
var _rain_node: GPUParticles3D = null
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
	_air.environment = Atmosphere.environment(rules.palette.dark)
	_ambient = _air.environment.ambient_light_energy
	CityBackdrop.show_behind(_air.environment)
	add_child(_air)
	_light_the_roof(rules)

	var roof := BuildingRoof.new()
	roof.name = "Roof"
	add_child(roof)
	roof.build(rules, plan)
	var kit := RoofKit.new()
	kit.name = "RoofKit"
	add_child(kit)
	kit.build(rules, plan, building_seed)
	var sign_board := VerticalSign.new()
	add_child(sign_board)
	sign_board.hang(rules, identity)

	var details := FloorDetail.new()
	details.name = "FloorDetail"
	add_child(details)
	details.build(rules, plan)

	dressing = BuildingDressing.lay(rules, plan, building_seed, identity)
	var props := BuildingProps.new()
	props.name = "Props"
	add_child(props)
	props.build(rules, plan, dressing, identity)

	var city := CityBackdrop.new()
	_city = city
	city.name = "City"
	add_child(city)
	city.build(rules, building_seed, weather)
	if Weather.is_raining(weather):
		_rain_node = _roof_rain(rules)
		add_child(_rain_node)
	# Молнии — только в дождь: в ясную ночь и в туман воздух покадрово не трогается.
	set_process(Weather.is_raining(weather))
	add_to_group(Graphics.GROUP)
	apply_graphics()


## Вспышка молнии доходит до здания: воздух коридоров на миг светлеет (M22).
## Не источник — яркость окружающего света, и бюджет ламп она не трогает.
func _process(_delta: float) -> void:
	if _city == null or _air == null:
		return
	_air.environment.ambient_light_energy = _ambient * (1.0 + _city.flash_level() * FLASH_AMBIENT)


## Отражения, контактные тени, объёмный туман и доля капель над крышей по уровню
## качества (ADR-0030, решение 5). Уровень меняют посреди партии, и применяется
## он к этому зданию, а не со следующего: воздух собран на всё здание один раз.
func apply_graphics() -> void:
	if _air != null:
		Graphics.apply_to(_air.environment)
	if _rain_node != null:
		_rain_node.amount = maxi(int(float(ROOF_RAIN_DROPS) * Graphics.rain_share()), 1)


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


## Капли над крышей: падают с неба до настила и там кончаются — время жизни
## ровно на эту высоту, столкновения частицам не нужны.
##
## Сыплются между парапетами и со сдвигом против сноса: из коробки во всю
## ширину крыши капли у правого парапета выносило за стену, и они гасли в
## воздухе снаружи башни, на высоте настила (авторевью M19).
func _roof_rain(rules: BuildingRules) -> GPUParticles3D:
	var span := rules.floor_span(BuildingRules.ROOF)
	var width := span.y - span.x
	var inner := Vector2(span.x + BuildingShell.WALL_WIDTH, span.y - BuildingShell.WALL_WIDTH)
	var drift := ROOF_RAIN_HEIGHT * (ROOF_RAIN_SLANT + tan(deg_to_rad(ROOF_RAIN_SPREAD)))
	var emitting := Vector2(inner.x, maxf(inner.y - drift, inner.x))
	var rain := CityBackdrop.rain_particles(
		ROOF_RAIN_DROPS,
		ROOF_RAIN_HEIGHT / CityBackdrop.RAIN_SPEED,
		Vector3((emitting.y - emitting.x) * 0.5, 0.2, WorldSpace.CORRIDOR_DEPTH * 0.5),
		Vector3(ROOF_RAIN_SLANT, -1.0, 0.0),
		ROOF_RAIN_SPREAD,
		Vector2(CityBackdrop.RAIN_SPEED, CityBackdrop.RAIN_SPEED)
	)
	rain.name = "RoofRain"
	var surface := rules.floor_surface(BuildingRules.ROOF)
	rain.position = WorldSpace.to_scene(
		Vector2((emitting.x + emitting.y) * 0.5, surface - ROOF_RAIN_HEIGHT)
	)
	rain.visibility_aabb = AABB(
		Vector3(-width, -ROOF_RAIN_HEIGHT - 1.0, -2.0),
		Vector3(width * 2.0, ROOF_RAIN_HEIGHT + 2.0, 4.0)
	)
	return rain
