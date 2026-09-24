class_name BuildingIdentity
extends RefCounted

## Что за здание: отель или офисная башня и как оно зовётся (ADR-0033, решения
## 1 и 2).
##
## Тип и имя — жребий по номеру и сиду здания, как машина у выхода
## (ADR-0032, решение 7). От типа зависят вывеска на углу фасада, отделка стен и
## набор обстановки; механика у обоих одна. Без узлов: жребий проверяется тестом.

enum Kind { HOTEL, OFFICE }

## Имена отелей: неон в духе восьмидесятых, коротко — буквы идут столбиком.
const HOTEL_NAMES: PackedStringArray = [
	"EMPIRE", "ROYAL", "METRO", "SAVOY", "REGENT", "PLAZA", "ASTOR", "COSMO"
]

## Имена корпораций: у них Otto и выносит документы.
const OFFICE_NAMES: PackedStringArray = [
	"KRONOS", "ATLAS", "VECTOR", "ORION", "HALCYON", "NOVA", "TITAN", "ZENITH"
]

## Слово, которое пишется под именем отеля.
const HOTEL_WORD := "HOTEL"

## Доля отелей в жребии.
const HOTEL_CHANCE: float = 0.5

## Соль жребия: своя, чтобы тип не ходил в ногу с машиной и раскладкой.
const SALT: int = 0x1D_E7_17

var kind: Kind = Kind.HOTEL
var name: String = HOTEL_NAMES[0]


## Здание [param building] партии с сидом [param building_seed]. Первое — отель
## EMPIRE: с него начинается партия, и первый кадр одинаков у всех.
static func of(building: int, building_seed: int) -> BuildingIdentity:
	var identity := BuildingIdentity.new()
	if building <= 1:
		return identity
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, building, SALT])
	identity.kind = Kind.HOTEL if rng.randf() < HOTEL_CHANCE else Kind.OFFICE
	var names := HOTEL_NAMES if identity.kind == Kind.HOTEL else OFFICE_NAMES
	identity.name = names[rng.randi_range(0, names.size() - 1)]
	return identity


## Отель ли это.
func is_hotel() -> bool:
	return kind == Kind.HOTEL


## Какие предметы каталога уместны в этом здании.
func fit() -> PropCatalog.Fit:
	return PropCatalog.Fit.HOTEL if is_hotel() else PropCatalog.Fit.OFFICE


## Строки вывески сверху вниз: у отеля — имя и HOTEL, у офиса — одно имя.
func sign_lines() -> PackedStringArray:
	if is_hotel():
		return PackedStringArray([name, HOTEL_WORD])
	return PackedStringArray([name])
