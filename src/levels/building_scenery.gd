class_name BuildingScenery
extends Node3D

## Everything around the gameplay: air, light over the roof, roof slopes, floor dressing,
## the city and the weather (ADR-0029).
##
## As its own node, like [BuildingShell] and [BuildingShafts]: there is no gameplay here,
## and for a level assembled from builders one line is enough. The air and roof light
## used to live in the level itself; the city, weather and dressing would have added
## another hundred lines to a file that is already at its limit.

## Lamp over the roof — the roof has no lamps, and it must never go out: the city shines
## on it. The building's overall tone and air — [Atmosphere].
const ROOF_LIGHT_COLOR := Color(0.72, 0.78, 0.95)
const ROOF_LIGHT_ENERGY: float = 2.4
const ROOF_LIGHT_RANGE: float = 14.0
const ROOF_LIGHT_HEIGHT: float = 4.0

## How many times the building's ambient light brightens in a lightning flash.
const FLASH_AMBIENT: float = 2.5

## The sun in the morning, daytime and evening (ADR-0051): how many times its strength
## from [TimeOfDay], and how far it casts shadows, m. The lamp over the roof in the
## daytime is the sky's glow: its own share of strength and the sun's colour.
const SUN_GAIN: float = 1.5
const SUN_SHADOW_DISTANCE: float = 70.0
const ROOF_LIGHT_BY_DAY: float = 0.45

var weather: Weather.Kind = Weather.Kind.CLEAR
var dressing: BuildingDressing = null
## Hotel or office and the building's name (ADR-0033, decision 1).
var identity: BuildingIdentity = null

## The building's air and the rain over the roof: rebuilt by [method apply_graphics].
var _air: WorldEnvironment = null
var _rain_node: RoofRain = null
## Snow over the roof, if it is snowing (ADR-0054).
var _snow_node: RoofSnow = null
var _roof_light: OmniLight3D = null
var _sun: DirectionalLight3D = null
## The roof and its equipment: the rain heightmap is captured from them.
var _roof_parts: Array[Node] = []
## The corner sign: hangs outside, along the upper floors, and catches the sun.
var _sign: VerticalSign = null
var _city: CityBackdrop = null
## Ambient light of the air without a flash: the lightning flash is counted from it.
var _ambient: float = 0.0
## The flash level last written into the air: between flashes it is not rewritten.
var _flash_shown: float = 0.0


## Builds the building's surroundings by the rules, plan and seed.
func build(
	rules: BuildingRules,
	plan: BuildingPlan,
	building_seed: int,
	building_identity: BuildingIdentity = BuildingIdentity.new()
) -> void:
	weather = Weather.of_building(rules, building_seed)
	identity = building_identity

	_air = WorldEnvironment.new()
	_air.name = "Air"
	_air.environment = Atmosphere.environment(rules.palette.dark, rules.time_of_day, identity.kind)
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
	# Crown by building kind behind the play plane (ADR-0058, decision 2).
	var crown := BuildingCrown.new()
	add_child(crown)
	crown.build(rules)
	_roof_parts = [roof, kit, crown] as Array[Node]
	var sign_board := VerticalSign.new()
	_sign = sign_board
	add_child(sign_board)
	sign_board.hang(rules, identity)
	# Tower end walls and the podium setback by kind (ADR-0058, decision 3) — after the
	# sign: they are not placed in front of it on the right end wall.
	var flanks := BuildingFlanks.new()
	add_child(flanks)
	flanks.build(rules, building_seed, sign_board.span())

	var details := FloorDetail.new()
	details.name = "FloorDetail"
	add_child(details)
	details.build(rules, plan, BuildingStyle.of(identity))

	dressing = BuildingDressing.lay(rules, plan, building_seed, identity)
	var props := BuildingProps.new()
	props.name = "Props"
	add_child(props)
	props.build(rules, plan, dressing, identity)
	# The wall's structure before the stains: a stain goes around windows and doors
	# rather than lying under them.
	var laid := WallFeatures.lay(rules, plan, building_seed, identity, dressing)
	var wear := WallWear.new()
	add_child(wear)
	wear.build(rules, WallWear.lay(rules, plan, building_seed, identity, dressing, laid))
	var features := WallFeatures.new()
	add_child(features)
	features.build(rules, laid)
	Sounds.set_building(identity.kind)

	var city := CityBackdrop.new()
	_city = city
	city.name = "City"
	add_child(city)
	city.build(rules, building_seed, weather, rules.time_of_day)
	if Weather.is_raining(weather):
		# Drops die on the roof, not by a timer (ADR-0037, decision 3).
		_rain_node = RoofRain.new()
		_rain_node.name = "RoofRain"
		add_child(_rain_node)
		_rain_node.build(rules, plan, _roof_light)
		_rain_node.catch_on(_roof_parts)
		sign_board.glow_in_rain()
	elif Weather.is_snowing(weather):
		# Flakes die on the same heightmap, the snow cover is laid in advance (ADR-0054).
		_snow_node = RoofSnow.new()
		_snow_node.name = "RoofSnow"
		add_child(_snow_node)
		_snow_node.build(rules, plan, rules.time_of_day)
		_snow_node.catch_on(_roof_parts)
	# Lightning — only in a thunderstorm: on a clear night, in fog and in daytime rain the
	# air is not touched every frame (ADR-0051, decision 7).
	set_process(_city.has_lightning())
	add_to_group(Graphics.GROUP)
	apply_graphics()


## A lightning flash reaches the building: the corridor air brightens for a moment (M22).
## Not a light source — ambient light brightness, and it does not touch the lamp budget.
func _process(_delta: float) -> void:
	if _city == null or _air == null:
		return
	# Between flashes the air is not rewritten every frame, as the city sky is not
	# ([CityBackdrop], ADR-0060).
	var flash := _city.flash_level()
	if flash == _flash_shown:
		return
	_flash_shown = flash
	_air.environment.ambient_light_energy = _ambient * (1.0 + flash * FLASH_AMBIENT)


## Gives the sun what is outside: everything the surroundings built on the roof, the
## corner sign, and what other level builders built above the roof slab ([Outdoors]).
## At night there is no sun, and the layer is set anyway — the building is the same.
func light_outdoors(roots: Array[Node], rules: BuildingRules) -> void:
	for part in _roof_parts:
		Outdoors.mark(part)
	if _sign != null:
		Outdoors.mark(_sign)
	var under_roof := WorldSpace.height_to_scene(
		rules.floor_surface(BuildingRules.ROOF) + rules.slab_height
	)
	for root in roots:
		Outdoors.mark_above(root, under_roof - 0.02)


## The sun over the building: shines only on layer [constant Outdoors.LAYER].
func _raise_sun(rules: BuildingRules) -> void:
	var time := rules.time_of_day
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.light_color = TimeOfDay.sun_colour(time)
	_sun.light_energy = TimeOfDay.sun_energy(time, weather) * SUN_GAIN
	_sun.light_cull_mask = Outdoors.LAYER
	# Volumetric fog does not know layers: with its own share the sun would shine in the
	# haze in front of the corridors, inside the building's cutaway.
	_sun.light_volumetric_fog_energy = 0.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = SUN_SHADOW_DISTANCE
	var toward := TimeOfDay.sun_direction(time)
	_sun.basis = Basis.looking_at(-toward, Vector3.UP)
	add_child(_sun)
	_roof_light.light_color = TimeOfDay.sun_colour(time).lerp(ROOF_LIGHT_COLOR, 0.5)
	_roof_light.light_energy = ROOF_LIGHT_ENERGY * ROOF_LIGHT_BY_DAY


## The sun, if there is one: in the morning, daytime and evening.
func sun() -> DirectionalLight3D:
	return _sun


## Rain and snow over the roof also die on what other level builders built on it: the
## slab and parapets, the machine room, slab end faces ([RoofCatch]); the snow cover
## lies on the same.
func catch_rain(roots: Array[Node]) -> void:
	if _rain_node != null:
		_rain_node.catch_on(roots)
	if _snow_node != null:
		_snow_node.catch_on(roots)


## Rain over the roof — so a test can check where the drops die.
func roof_rain() -> RoofRain:
	return _rain_node


## Snow over the roof — for the test.
func roof_snow() -> RoofSnow:
	return _snow_node


## Reflections, contact shadows and volumetric fog by quality level (ADR-0030,
## decision 5). The level is changed mid-game, and it applies to this building, not from
## the next one: the air is assembled for the whole building once. The rain over the
## roof recomputes its drop share itself ([RoofRain]).
func apply_graphics() -> void:
	if _air != null:
		Graphics.apply_to(_air.environment)
	if _sun != null:
		_sun.shadow_enabled = Graphics.sun_shadows()


## Lamp over the roof. A zone is made light by its own light source, not by an absence
## of darkness: the darkness rule rests on this (ADR-0010, point 3).
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
