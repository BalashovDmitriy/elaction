class_name PlaceSound
extends RefCounted

## Sound by Otto's place (ADR-0036, decision 5): where the street is heard and what a footstep
## sounds like.
##
## The rules are separate from [GreyboxLevel]: the level only asks them every frame, and they can be
## checked without a building.

## How far from the garage gate the street is heard, m: at the gate the ambience is at full
## strength, as on the roof. Since M24b the exit is a gate in the end wall of the bottom floor
## (ADR-0038, decision 3).
const STREET_REACH: float = 6.0


## Whether the street is heard from level [param index] at point [param x]: on the roof —
## everywhere, on the bottom floor — at the garage gate [param exit_x] ([method Garage.gate_x]).
static func hears_street(rules: BuildingRules, index: int, x: float, exit_x: float) -> bool:
	if index == BuildingRules.ROOF:
		return true
	return index == rules.floors - 1 and absf(x - exit_x) <= STREET_REACH


## What a footstep sounds like on a floor of building [param building]: hotel carpet, office stone,
## residential linoleum (ADR-0055, decision 8).
## [param on_concrete] — Otto on bare concrete: on the roof or in the garage of the bottom floor
## (ADR-0038, decision 3), there is no carpet there even in the hotel.
static func step_at(on_concrete: bool, building: BuildingIdentity) -> String:
	if on_concrete or building == null:
		return Sounds.STEP_CONCRETE
	match building.kind:
		BuildingIdentity.Kind.HOTEL:
			return Sounds.STEP_CARPET
		BuildingIdentity.Kind.RESIDENTIAL:
			return Sounds.STEP_LINO
	return Sounds.STEP_CONCRETE
