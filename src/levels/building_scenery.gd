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
const ROOF_RAIN_DROPS: int = 600
const ROOF_RAIN_HEIGHT: float = 7.0

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
func _roof_rain(rules: BuildingRules) -> GPUParticles3D:
	var span := rules.floor_span(BuildingRules.ROOF)
	var width := span.y - span.x
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(width * 0.5, 0.2, WorldSpace.CORRIDOR_DEPTH * 0.5)
	process.direction = Vector3(0.1, -1.0, 0.0)
	process.spread = 2.0
	process.initial_velocity_min = CityBackdrop.RAIN_SPEED
	process.initial_velocity_max = CityBackdrop.RAIN_SPEED
	process.gravity = Vector3.ZERO

	var drop := QuadMesh.new()
	drop.size = CityBackdrop.RAIN_DROP
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.albedo_color = CityBackdrop.RAIN_COLOR
	drop.material = look

	var rain := GPUParticles3D.new()
	rain.name = "RoofRain"
	rain.amount = ROOF_RAIN_DROPS
	rain.lifetime = ROOF_RAIN_HEIGHT / CityBackdrop.RAIN_SPEED
	rain.local_coords = false
	rain.process_material = process
	rain.draw_pass_1 = drop
	var surface := rules.floor_surface(BuildingRules.ROOF)
	rain.position = WorldSpace.to_scene(
		Vector2((span.x + span.y) * 0.5, surface - ROOF_RAIN_HEIGHT)
	)
	rain.visibility_aabb = AABB(
		Vector3(-width, -ROOF_RAIN_HEIGHT - 1.0, -2.0),
		Vector3(width * 2.0, ROOF_RAIN_HEIGHT + 2.0, 4.0)
	)
	return rain
