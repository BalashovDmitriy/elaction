class_name BuildingDressing
extends RefCounted

## Обстановка этажей: что стоит у задней стены коридора (ADR-0029, решение 3).
##
## Только декор. В аркаде на этаже нет ничего, кроме дверей, ламп и шахт, и
## мебель у нас не служит ни укрытием, ни препятствием: у предметов нет тел,
## пули и люди проходят мимо. Поэтому правило раскладки одно — не мешать
## читаемости: предмет не встаёт на место двери, лампы, шахты, эскалатора и
## выхода и не жмётся к глухой стене. Раскладка без узлов, по плану и сиду, —
## тесты проверяют её на любом здании; строит предметы [BuildingProps].

## Что за предмет.
enum Kind { PLANT, VENDING, COOLER, BENCH, CABINET, SIGN }


## Предмет у задней стены этажа.
class PropSpot:
	extends RefCounted
	var kind: Kind = Kind.PLANT
	var floor_index: int = 0
	var x: float = 0.0


## С каким шансом свободное место этажа получает предмет. Не каждое: этаж,
## заставленный от стены до стены, читается складом, а не конторой.
const FILL_CHANCE: float = 0.45

## С каким шансом под потолком этажа идёт труба.
const PIPE_CHANCE: float = 0.4

## Смешивается с сидом, чтобы обстановка не повторяла жребий раскладки.
const SALT: int = 0x0DEC_0A7E

var props: Array[PropSpot] = []
## Этажи, под потолком которых идёт труба.
var pipes: Array[int] = []


## Обстановка здания по его плану и сиду.
static func lay(rules: BuildingRules, plan: BuildingPlan, building_seed: int) -> BuildingDressing:
	var dressing := BuildingDressing.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, SALT])
	# Этаж выхода — гараж: пустой, с одной машиной (ADR-0031, решение 4).
	for index in rules.floors - 1:
		for x: float in free_spots(rules, plan, index):
			if rng.randf() >= FILL_CHANCE:
				continue
			var prop := PropSpot.new()
			prop.floor_index = index
			prop.x = x
			prop.kind = rng.randi_range(0, Kind.size() - 1) as Kind
			dressing.props.append(prop)
		if rng.randf() < PIPE_CHANCE:
			dressing.pipes.append(index)
	return dressing


## Места этажа, где предмету стоять можно: там, где встают люди
## ([method BuildingPlan.safe_spots] — не шахта, не эскалатор и не выход), и не
## на месте двери или лампы, не у нижней площадки эскалатора и не вплотную к
## глухой стене.
static func free_spots(
	rules: BuildingRules, plan: BuildingPlan, floor_index: int
) -> PackedFloat64Array:
	var step := rules.slot_x(1) - rules.slot_x(0)
	var near_wall := step * 0.5 + rules.inner_wall_width * 0.5
	var busy := PackedFloat64Array()
	for door in plan.doors:
		if door.floor_index == floor_index:
			busy.append(door.x)
	for lamp in plan.lamps:
		if lamp.floor_index == floor_index:
			busy.append(lamp.x)
	for escalator in plan.escalators:
		if escalator.floor_index + 1 == floor_index:
			busy.append(escalator.x + escalator.towards * rules.escalator_run)

	var free := PackedFloat64Array()
	for x: float in plan.safe_spots(rules, floor_index):
		var taken := false
		for other: float in busy:
			if absf(other - x) < step * 0.5:
				taken = true
				break
		for wall in plan.walls:
			if wall.floor_index == floor_index and absf(wall.x - x) < near_wall:
				taken = true
		if not taken:
			free.append(x)
	return free
