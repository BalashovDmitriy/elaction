class_name FloorRole
extends RefCounted

## Роль этажа: обычный коридор или особый зал (ADR-0057, решения 2 и 3).
##
## Особые этажи стоят по устройству ROM, а не жребием: нижняя полоса 1–7, где
## дверей почти нет (маски `81` и `00` в table_280E), — общественные залы;
## тёмная полоса 11–15, где ламп нет вовсе, — технические. Каждый этаж полосы
## свой, и в любом здании типа он тот же. Механику роль не трогает: двери, лампы
## и раскладка остаются по ROM, меняется только то, что за плоскостью игры.
##
## Без узлов: таблица проверяется тестом на любом здании.

enum Role {
	CORRIDOR,
	LOBBY,
	DINING,
	BALLROOM,
	POOL,
	BAR,
	CONFERENCE,
	MEETING,
	GYM,
	COMMUNITY,
	LOCKERS,
	LAUNDRY,
	BOILER,
	MECHANICAL,
	SERVER,
	ARCHIVE,
	KITCHEN,
	STORAGE,
	WORKSHOP,
}

## Чем зал отделён от коридора вместо задней стены: колоннами, стеклом или
## сеткой-рабицей на стойках (ADR-0057, решение 3).
enum Screen { COLUMNS, GLASS, MESH }

## Нижняя полоса ROM: общественные залы, по этажу ROM от 1 до 7.
const PUBLIC_BAND := Vector2i(1, 7)
## Тёмная полоса ROM — технические этажи ([constant Arcade.DARK_FLOORS]).
const TECHNICAL_BAND := Arcade.DARK_FLOORS

## Общественные залы этажей ROM 1–7 по типу здания. Этаж ROM 1 у здания в
## тридцать этажей — паркинг, и лобби стоит ещё и на втором.
const PUBLIC_HOTEL: Array[Role] = [
	Role.LOBBY, Role.LOBBY, Role.DINING, Role.BALLROOM, Role.POOL, Role.CONFERENCE, Role.BAR
]
const PUBLIC_OFFICE: Array[Role] = [
	Role.LOBBY, Role.LOBBY, Role.DINING, Role.GYM, Role.CONFERENCE, Role.MEETING, Role.LOBBY
]
const PUBLIC_RESIDENTIAL: Array[Role] = [
	Role.LOBBY,
	Role.LOBBY,
	Role.COMMUNITY,
	Role.LOCKERS,
	Role.GYM,
	Role.LOCKERS,
	Role.LAUNDRY,
]

## Технические этажи ROM 11–15 по типу здания.
const TECHNICAL_HOTEL: Array[Role] = [
	Role.BOILER, Role.MECHANICAL, Role.LAUNDRY, Role.KITCHEN, Role.STORAGE
]
const TECHNICAL_OFFICE: Array[Role] = [
	Role.MECHANICAL, Role.SERVER, Role.ARCHIVE, Role.SERVER, Role.STORAGE
]
const TECHNICAL_RESIDENTIAL: Array[Role] = [
	Role.BOILER, Role.WORKSHOP, Role.STORAGE, Role.MECHANICAL, Role.LAUNDRY
]


## Роль этажа ROM [param rom] в здании типа [param kind].
static func of_rom(kind: BuildingIdentity.Kind, rom: int) -> Role:
	if rom >= PUBLIC_BAND.x and rom <= PUBLIC_BAND.y:
		return _public(kind)[rom - PUBLIC_BAND.x]
	if rom >= TECHNICAL_BAND.x and rom <= TECHNICAL_BAND.y:
		return _technical(kind)[rom - TECHNICAL_BAND.x]
	return Role.CORRIDOR


## Роль нашего этажа [param index] в здании типа [member BuildingRules.kind]:
## крыша и паркинг — не залы.
static func at(rules: BuildingRules, index: int) -> Role:
	if index <= BuildingRules.ROOF or index >= rules.floors - 1:
		return Role.CORRIDOR
	return of_rom(rules.kind, Arcade.rom_floor(index, rules.floors))


## Особый ли этаж [param index]: за коридором зал, а не задняя стена.
static func hall_at(rules: BuildingRules, index: int) -> bool:
	return is_hall(at(rules, index))


## Особый ли этаж: за коридором зал, а не задняя стена.
static func is_hall(role: Role) -> bool:
	return role != Role.CORRIDOR


## Технический ли зал: тёмная полоса ROM.
static func is_technical(role: Role) -> bool:
	return (
		role
		in [
			Role.BOILER,
			Role.MECHANICAL,
			Role.SERVER,
			Role.ARCHIVE,
			Role.KITCHEN,
			Role.STORAGE,
			Role.WORKSHOP,
		]
	)


## Чем зал отделён от коридора. Офис — стеклом везде, кроме подсобок; серверная
## офиса — за стеклом, как в жизни; остальные технические — за сеткой.
static func screen_of(role: Role, kind: BuildingIdentity.Kind) -> Screen:
	if role == Role.SERVER or role == Role.MEETING:
		return Screen.GLASS
	if is_technical(role) or role == Role.LAUNDRY or role == Role.LOCKERS:
		return Screen.MESH
	if kind == BuildingIdentity.Kind.OFFICE:
		return Screen.GLASS
	return Screen.COLUMNS


## Имя роли для журнала и кадров.
static func name_of(role: Role) -> String:
	return String(Role.keys()[role]).to_lower()


static func _public(kind: BuildingIdentity.Kind) -> Array[Role]:
	match kind:
		BuildingIdentity.Kind.OFFICE:
			return PUBLIC_OFFICE
		BuildingIdentity.Kind.RESIDENTIAL:
			return PUBLIC_RESIDENTIAL
	return PUBLIC_HOTEL


static func _technical(kind: BuildingIdentity.Kind) -> Array[Role]:
	match kind:
		BuildingIdentity.Kind.OFFICE:
			return TECHNICAL_OFFICE
		BuildingIdentity.Kind.RESIDENTIAL:
			return TECHNICAL_RESIDENTIAL
	return TECHNICAL_HOTEL
