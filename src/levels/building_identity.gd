class_name BuildingIdentity
extends RefCounted

## What building this is: a hotel, an office tower or a residential building, and what it is called
## (ADR-0033, decisions 1 and 2; ADR-0055, decisions 1 and 2).
##
## Kind and name are a draw by the building's number and seed, like the car at the exit
## (ADR-0032, decision 7). The kind determines the sign on the facade corner, the wall finish,
## the dressing set and the agents' clothing; the mechanics are the same for all. No nodes: the draw
## is checked by a test.

enum Kind { HOTEL, OFFICE, RESIDENTIAL }

## Hotel names: eighties-style neon, short — the letters go in a column.
const HOTEL_NAMES: PackedStringArray = [
	"EMPIRE", "ROYAL", "METRO", "SAVOY", "REGENT", "PLAZA", "ASTOR", "COSMO"
]

## Corporation names: Otto steals documents from them.
const OFFICE_NAMES: PackedStringArray = [
	"KRONOS", "ATLAS", "VECTOR", "ORION", "HALCYON", "NOVA", "TITAN", "ZENITH"
]

## Residential building names: eighties New York towers are named after a street or
## a park (ADR-0055, decision 1).
const RESIDENTIAL_NAMES: PackedStringArray = [
	"LENOX", "BELMONT", "HUDSON", "CARLTON", "BEACON", "RIVIERA", "MAJESTIC", "PARKVIEW"
]

## The word written under the hotel name.
const HOTEL_WORD := "HOTEL"
## Under a residential building name — apartments, as on signs of those years.
const RESIDENTIAL_WORD := "APTS"

## Draw salt: its own, so that the kind does not move in step with the car and the layout.
const SALT: int = 0x1D_E7_17

var kind: Kind = Kind.HOTEL
var name: String = HOTEL_NAMES[0]


## Building [param building] of a game with seed [param building_seed]. The first is the hotel
## EMPIRE: the game starts with it, and the first frame is the same for everyone. The rest —
## an even draw over three kinds (ADR-0055, decision 2).
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


## Number of the first building of a game of kind [param which]: for milestone capture, shots and
## tests. [param building_seed] — the building seed; −1 — an unsalted game, where a building's seed
## is its number ([method GameState.building_seed]). Not found — the first building.
static func first_of(which: Kind, building_seed: int = -1) -> int:
	for building: int in range(1, 60):
		var draw_seed := building if building_seed < 0 else building_seed
		if BuildingIdentity.of(building, draw_seed).kind == which:
			return building
	return 1


## A building of kind [param which] with the first name of its list: for tests and shots.
static func typed(which: Kind) -> BuildingIdentity:
	var identity := BuildingIdentity.new()
	identity.kind = which
	identity.name = names_of(which)[0]
	return identity


## The name list of kind [param which].
static func names_of(which: Kind) -> PackedStringArray:
	match which:
		Kind.OFFICE:
			return OFFICE_NAMES
		Kind.RESIDENTIAL:
			return RESIDENTIAL_NAMES
	return HOTEL_NAMES


## Whether this is a hotel.
func is_hotel() -> bool:
	return kind == Kind.HOTEL


## Short kind name: kind textures in `assets/textures/` are labelled with it.
func key() -> String:
	match kind:
		Kind.OFFICE:
			return "office"
		Kind.RESIDENTIAL:
			return "residential"
	return "hotel"


## Which catalogue items fit in this building.
func fit() -> PropCatalog.Fit:
	match kind:
		Kind.OFFICE:
			return PropCatalog.Fit.OFFICE
		Kind.RESIDENTIAL:
			return PropCatalog.Fit.RESIDENTIAL
	return PropCatalog.Fit.HOTEL


## Sign lines top to bottom: the hotel has the name and HOTEL, the residential building — the name
## and APTS, the office — the name alone.
func sign_lines() -> PackedStringArray:
	match kind:
		Kind.HOTEL:
			return PackedStringArray([name, HOTEL_WORD])
		Kind.RESIDENTIAL:
			return PackedStringArray([name, RESIDENTIAL_WORD])
	return PackedStringArray([name])
