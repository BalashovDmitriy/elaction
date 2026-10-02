class_name BuildingIdentity
extends RefCounted

## Что за здание: отель, офисная башня или жилой дом и как оно зовётся
## (ADR-0033, решения 1 и 2; ADR-0055, решения 1 и 2).
##
## Тип и имя — жребий по номеру и сиду здания, как машина у выхода
## (ADR-0032, решение 7). От типа зависят вывеска на углу фасада, отделка стен,
## набор обстановки и одежда агентов; механика у всех одна. Без узлов: жребий
## проверяется тестом.

enum Kind { HOTEL, OFFICE, RESIDENTIAL }

## Имена отелей: неон в духе восьмидесятых, коротко — буквы идут столбиком.
const HOTEL_NAMES: PackedStringArray = [
	"EMPIRE", "ROYAL", "METRO", "SAVOY", "REGENT", "PLAZA", "ASTOR", "COSMO"
]

## Имена корпораций: у них Otto и выносит документы.
const OFFICE_NAMES: PackedStringArray = [
	"KRONOS", "ATLAS", "VECTOR", "ORION", "HALCYON", "NOVA", "TITAN", "ZENITH"
]

## Имена жилых домов: нью-йоркские башни восьмидесятых зовутся по улице или
## парку (ADR-0055, решение 1).
const RESIDENTIAL_NAMES: PackedStringArray = [
	"LENOX", "BELMONT", "HUDSON", "CARLTON", "BEACON", "RIVIERA", "MAJESTIC", "PARKVIEW"
]

## Слово, которое пишется под именем отеля.
const HOTEL_WORD := "HOTEL"
## Под именем жилого дома — квартиры, как на вывесках тех лет.
const RESIDENTIAL_WORD := "APTS"

## Соль жребия: своя, чтобы тип не ходил в ногу с машиной и раскладкой.
const SALT: int = 0x1D_E7_17

var kind: Kind = Kind.HOTEL
var name: String = HOTEL_NAMES[0]


## Здание [param building] партии с сидом [param building_seed]. Первое — отель
## EMPIRE: с него начинается партия, и первый кадр одинаков у всех. Остальные —
## жребий поровну на три типа (ADR-0055, решение 2).
static func of(building: int, building_seed: int) -> BuildingIdentity:
	var identity := BuildingIdentity.new()
	if building <= 1:
		return identity
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, building, SALT])
	identity.kind = rng.randi_range(0, Kind.size() - 1) as Kind
	var names := names_of(identity.kind)
	identity.name = names[rng.randi_range(0, names.size() - 1)]
	return identity


## Номер первого здания партии типа [param which]: съёмке вехи, кадрам и тестам.
## [param building_seed] — сид зданий; −1 — партия без соли, где сид здания —
## его номер ([method GameState.building_seed]). Не нашлось — первое здание.
static func first_of(which: Kind, building_seed: int = -1) -> int:
	for building: int in range(1, 60):
		var draw_seed := building if building_seed < 0 else building_seed
		if BuildingIdentity.of(building, draw_seed).kind == which:
			return building
	return 1


## Здание типа [param which] с первым именем своего списка: тестам и кадрам.
static func typed(which: Kind) -> BuildingIdentity:
	var identity := BuildingIdentity.new()
	identity.kind = which
	identity.name = names_of(which)[0]
	return identity


## Список имён типа [param which].
static func names_of(which: Kind) -> PackedStringArray:
	match which:
		Kind.OFFICE:
			return OFFICE_NAMES
		Kind.RESIDENTIAL:
			return RESIDENTIAL_NAMES
	return HOTEL_NAMES


## Отель ли это.
func is_hotel() -> bool:
	return kind == Kind.HOTEL


## Короткое имя типа: им подписаны фактуры типа в `assets/textures/`.
func key() -> String:
	match kind:
		Kind.OFFICE:
			return "office"
		Kind.RESIDENTIAL:
			return "residential"
	return "hotel"


## Какие предметы каталога уместны в этом здании.
func fit() -> PropCatalog.Fit:
	match kind:
		Kind.OFFICE:
			return PropCatalog.Fit.OFFICE
		Kind.RESIDENTIAL:
			return PropCatalog.Fit.RESIDENTIAL
	return PropCatalog.Fit.HOTEL


## Строки вывески сверху вниз: у отеля — имя и HOTEL, у жилого дома — имя и
## APTS, у офиса — одно имя.
func sign_lines() -> PackedStringArray:
	match kind:
		Kind.HOTEL:
			return PackedStringArray([name, HOTEL_WORD])
		Kind.RESIDENTIAL:
			return PackedStringArray([name, RESIDENTIAL_WORD])
	return PackedStringArray([name])
