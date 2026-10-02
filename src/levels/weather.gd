class_name Weather
extends RefCounted

## Погода здания: ясно, туман, дождь или снег (ADR-0029, решение 2;
## ADR-0054, решение 1 — снег, каждая погода по четверти).
##
## Одна на здание и выбирается его сидом, поэтому раунды отличаются не только
## цветом, а одно и то же здание всегда встречает одной погодой. Внутри здания
## её нет: коридор сухой, погода живёт в городе и над крышей.
##
## Класс только решает и отдаёт числа: плотность воздуха города, дождь или нет.
## Узлы строит [BuildingScenery].

enum Kind { CLEAR, FOG, RAIN, SNOW }

## Плотность дымки города по погоде: на ясной ночи дальние кварталы видны, в
## тумане тают уже со второго ряда, в снегопад — с третьего.
const CITY_FOG: Array[float] = [0.006, 0.02, 0.012, 0.016]

## Смешивается с сидом, чтобы жребий погоды не совпадал с первым жребием
## раскладки того же сида.
const SALT: int = 0x5EA7_4E12


## Погода здания: поставленная руками в [member BuildingRules.forced_weather],
## а без неё — жребий по сиду.
static func of_building(rules: BuildingRules, building_seed: int) -> Kind:
	if rules.forced_weather >= 0:
		return rules.forced_weather as Kind
	return of_seed(building_seed)


## Погода здания по его сиду.
static func of_seed(building_seed: int) -> Kind:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, SALT])
	return rng.randi_range(0, Kind.size() - 1) as Kind


## Плотность дымки города при этой погоде.
static func city_fog(kind: Kind) -> float:
	return CITY_FOG[kind]


## Идёт ли дождь.
static func is_raining(kind: Kind) -> bool:
	return kind == Kind.RAIN


## Идёт ли снег (ADR-0054).
static func is_snowing(kind: Kind) -> bool:
	return kind == Kind.SNOW
