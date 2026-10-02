class_name RespawnSpot
extends RefCounted

## Куда Otto возвращается после гибели — по правилу ROM (@7633, @2FAA;
## ADR-0053, решение 2): не ниже пятого этажа ROM, у красной двери этажа, если
## документ за ней ещё не взят, а без неё — в постоянной точке этажа. Где Otto
## погиб и где стоят агенты, не важно: агенты с этажей уходят, а выпускают их
## снова с задержкой. Вынесено из [GreyboxLevel] — правило без узлов.

## Кусок этажа уже этого, м, — тупик: между стеной и шахтой бывает карман в
## полтора метра, и вернувшийся туда Otto уходил бы из него только кабиной
## (M24g, сид 3). Точка возвращения ищется вне таких карманов.
const POCKET: float = 3.0


## Этаж возвращения для погибшего на [param index]: тот же, но не ниже пятого
## этажа ROM. Ниже здание у аркады — первые этажи с дверью по краям, и
## вернувшийся там у самого выхода прошёл бы их даром.
static func floor_for(rules: BuildingRules, index: int) -> int:
	var at := index
	while (
		at > BuildingRules.ROOF and Arcade.rom_floor(at, rules.floors) < Arcade.RESPAWN_FROM_FLOOR
	):
		at -= 1
	return at


## Место на этаже [param index]: у красной двери [param red_x], если она есть
## (NAN — нет), а без неё — точка ROM на доле этажа
## [constant Arcade.RESPAWN_SHARE]. Встаёт Otto на ближайшее к ней место, где
## можно стоять. Карманы обходит только точка ROM, пока на этаже есть что-то
## кроме них: красная дверь в кармане — всё равно цель, и Otto встаёт у неё.
static func choose(plan: BuildingPlan, rules: BuildingRules, index: int, red_x: float) -> float:
	var spots := plan.safe_spots(rules, index)
	if spots.is_empty():
		return plan.safe_x(rules, index)
	var target := red_x
	if is_nan(target):
		var span := rules.floor_span(index)
		target = lerpf(span.x, span.y, Arcade.RESPAWN_SHARE)
		var open := _off_pockets(plan, rules, index, spots)
		if not open.is_empty():
			spots = open

	var best := spots[0]
	for x: float in spots:
		if absf(x - target) < absf(best - target):
			best = x
	return best


## Где на этаже [param index] красная дверь с документом из [param doors], или
## NAN: документ за ней взят или красной двери на этаже нет.
static func red_door_x(doors: Array[Door], rules: BuildingRules, index: int) -> float:
	for door in doors:
		if door.is_pending() and rules.floor_index_near(door.mat_position().y) == index:
			return door.mat_position().x
	return NAN


## Места из [param spots], что стоят на кусках этажа шире [constant POCKET].
static func _off_pockets(
	plan: BuildingPlan, rules: BuildingRules, index: int, spots: PackedFloat64Array
) -> PackedFloat64Array:
	var open := PackedFloat64Array()
	var pieces := BuildingPlan.spans_between(plan.blocks_on(rules, index), rules.floor_span(index))
	for piece: Vector2 in pieces:
		var same := PackedFloat64Array()
		for x: float in spots:
			if x >= piece.x and x <= piece.y:
				same.append(x)
		if same.size() > 0 and same[same.size() - 1] - same[0] >= POCKET:
			open.append_array(same)
	return open
