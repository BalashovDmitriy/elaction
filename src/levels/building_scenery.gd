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

var weather: Weather.Kind = Weather.Kind.CLEAR
var dressing: BuildingDressing = null


## Собирает окружение здания по правилам, плану и сиду.
func build(rules: BuildingRules, plan: BuildingPlan, building_seed: int) -> void:
	weather = Weather.of_seed(building_seed)

	var air := WorldEnvironment.new()
	air.name = "Air"
	air.environment = Atmosphere.environment(rules.palette.dark)
	CityBackdrop.show_behind(air.environment)
	add_child(air)
	_light_the_roof(rules)

	var roof := BuildingRoof.new()
	roof.name = "Roof"
	add_child(roof)
	roof.build(rules, plan)
	var kit := RoofKit.new()
	kit.name = "RoofKit"
	add_child(kit)
	kit.build(rules, plan)

	dressing = BuildingDressing.lay(rules, plan, building_seed)
	var props := BuildingProps.new()
	props.name = "Props"
	add_child(props)
	props.build(rules, plan, dressing)

	var city := CityBackdrop.new()
	city.name = "City"
	add_child(city)
	city.build(rules, building_seed, weather)
	if Weather.is_raining(weather):
		add_child(_roof_rain(rules))


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
