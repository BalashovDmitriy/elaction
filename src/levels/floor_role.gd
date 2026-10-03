class_name FloorRole
extends RefCounted

## Floor role: an ordinary corridor or a special hall (ADR-0057, decisions 2 and 3).
##
## Special floors are placed by the ROM layout, not by a draw: the bottom band 1–7, where there are
## almost no doors (masks `81` and `00` in table_280E), — public halls; the dark band 11–15, where
## there are no lamps at all, — technical ones. Each floor of a band is its own, and in any building
## of a kind it is the same. The role does not touch mechanics: doors, lamps and layout stay per the
## ROM, only what is behind the play plane changes.
##
## No nodes: the table is checked by a test on any building.

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

## What separates the hall from the corridor instead of a back wall: columns, glass or chain-link
## mesh on posts (ADR-0057, decision 3).
enum Screen { COLUMNS, GLASS, MESH }

## Bottom ROM band: public halls, by ROM floor from 1 to 7.
const PUBLIC_BAND := Vector2i(1, 7)
## Dark ROM band — technical floors ([constant Arcade.DARK_FLOORS]).
const TECHNICAL_BAND := Arcade.DARK_FLOORS

## Public halls of ROM floors 1–7 by building kind. ROM floor 1 in a thirty-floor building is the
## garage, so the lobby also stands on the second.
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

## Technical floors ROM 11–15 by building kind.
const TECHNICAL_HOTEL: Array[Role] = [
	Role.BOILER, Role.MECHANICAL, Role.LAUNDRY, Role.KITCHEN, Role.STORAGE
]
const TECHNICAL_OFFICE: Array[Role] = [
	Role.MECHANICAL, Role.SERVER, Role.ARCHIVE, Role.SERVER, Role.STORAGE
]
const TECHNICAL_RESIDENTIAL: Array[Role] = [
	Role.BOILER, Role.WORKSHOP, Role.STORAGE, Role.MECHANICAL, Role.LAUNDRY
]


## Role of ROM floor [param rom] in a building of kind [param kind].
static func of_rom(kind: BuildingIdentity.Kind, rom: int) -> Role:
	if rom >= PUBLIC_BAND.x and rom <= PUBLIC_BAND.y:
		return _public(kind)[rom - PUBLIC_BAND.x]
	if rom >= TECHNICAL_BAND.x and rom <= TECHNICAL_BAND.y:
		return _technical(kind)[rom - TECHNICAL_BAND.x]
	return Role.CORRIDOR


## Role of our floor [param index] in a building of kind [member BuildingRules.kind]: the roof and
## the garage are not halls.
static func at(rules: BuildingRules, index: int) -> Role:
	if index <= BuildingRules.ROOF or index >= rules.floors - 1:
		return Role.CORRIDOR
	return of_rom(rules.kind, Arcade.rom_floor(index, rules.floors))


## Whether floor [param index] is special: beyond the corridor is a hall, not a back wall.
static func hall_at(rules: BuildingRules, index: int) -> bool:
	return is_hall(at(rules, index))


## Whether the floor is special: beyond the corridor is a hall, not a back wall.
static func is_hall(role: Role) -> bool:
	return role != Role.CORRIDOR


## Whether the hall is technical: the dark ROM band.
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


## What separates the hall from the corridor. The office — glass everywhere except utility rooms;
## the office server room — behind glass, as in real life; other technical ones — behind mesh.
static func screen_of(role: Role, kind: BuildingIdentity.Kind) -> Screen:
	if role == Role.SERVER or role == Role.MEETING:
		return Screen.GLASS
	if is_technical(role) or role == Role.LAUNDRY or role == Role.LOCKERS:
		return Screen.MESH
	if kind == BuildingIdentity.Kind.OFFICE:
		return Screen.GLASS
	return Screen.COLUMNS


## Role name for the log and shots.
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
