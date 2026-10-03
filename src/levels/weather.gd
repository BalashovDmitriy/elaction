class_name Weather
extends RefCounted

## Building weather: clear, fog, rain or snow (ADR-0029, decision 2;
## ADR-0054, decision 1 — snow, each weather a quarter).
##
## One per building and chosen by its seed, so the rounds differ not only in
## colour, and the same building always meets you with the same weather. Inside the building
## there is none: the corridor is dry, the weather lives in the city and above the roof.
##
## The class only decides and returns numbers: city air density, rain or not.
## [BuildingScenery] builds the nodes.

enum Kind { CLEAR, FOG, RAIN, SNOW }

## City haze density by weather: on a clear night the far blocks are visible, in
## fog they melt from the second row already, in snowfall — from the third.
const CITY_FOG: Array[float] = [0.006, 0.02, 0.012, 0.016]

## Mixed with the seed so the weather draw does not coincide with the first draw of
## the layout of the same seed.
const SALT: int = 0x5EA7_4E12


## Building weather: set by hand in [member BuildingRules.forced_weather],
## and without it — a draw by seed.
static func of_building(rules: BuildingRules, building_seed: int) -> Kind:
	if rules.forced_weather >= 0:
		return rules.forced_weather as Kind
	return of_seed(building_seed)


## Building weather by its seed.
static func of_seed(building_seed: int) -> Kind:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, SALT])
	return rng.randi_range(0, Kind.size() - 1) as Kind


## City haze density in this weather.
static func city_fog(kind: Kind) -> float:
	return CITY_FOG[kind]


## Whether it is raining.
static func is_raining(kind: Kind) -> bool:
	return kind == Kind.RAIN


## Whether it is snowing (ADR-0054).
static func is_snowing(kind: Kind) -> bool:
	return kind == Kind.SNOW
