class_name PlaceSound
extends RefCounted

## Звук по месту Otto (ADR-0036, решение 5): где слышна улица и чем звучит шаг.
##
## Правила — отдельно от [GreyboxLevel]: уровень только спрашивает их каждый
## кадр, а проверить их можно без здания.

## Докуда от проёма выхода слышна улица, м: у выхода фон в полную силу, как на
## крыше.
const STREET_REACH: float = 6.0


## Слышна ли улица с уровня [param index] в точке [param x]: на крыше — везде,
## на нижнем этаже — у проёма выхода [param exit_x].
static func hears_street(rules: BuildingRules, index: int, x: float, exit_x: float) -> bool:
	if index == BuildingRules.ROOF:
		return true
	return index == rules.floors - 1 and absf(x - exit_x) <= STREET_REACH


## Чем звучит шаг на крыше или на этаже здания [param building]: ковёр отеля,
## камень конторы и крыши.
static func step_at(on_roof: bool, building: BuildingIdentity) -> String:
	if on_roof or building == null or not building.is_hotel():
		return Sounds.STEP_CONCRETE
	return Sounds.STEP_CARPET
