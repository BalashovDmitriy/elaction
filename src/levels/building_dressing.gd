class_name BuildingDressing
extends RefCounted

## Обстановка этажей: что стоит у задней стены коридора и что висит на ней
## (ADR-0029, решение 3; с M21b — модели паков, ADR-0033, решение 3).
##
## Только декор. В аркаде на этаже нет ничего, кроме дверей, ламп и шахт, и
## мебель у нас не служит ни укрытием, ни препятствием: у предметов нет тел,
## пули и люди проходят мимо. Поэтому правило раскладки одно — не мешать
## читаемости: предмет не встаёт на место двери, лампы, шахты, эскалатора и
## выхода и не жмётся к глухой стене. Раскладка без сцены, по плану и сиду, —
## тесты проверяют её на любом здании; строит предметы [BuildingProps].
##
## Что ставить, решает тип здания ([BuildingIdentity]): отель и офис берут из
## [PropCatalog] свои предметы и общие.


## Предмет этажа: имя в каталоге, этаж и середина по x.
class PropSpot:
	extends RefCounted
	var name: String = ""
	var floor_index: int = 0
	var x: float = 0.0
	## Ширина, которую предмет занимает у стены, м.
	var width: float = 0.0


## С каким шансом свободное место получает мебель на полу (решение
## пользователя: «богато, но читаемо» — каждое второе).
const FLOOR_CHANCE: float = 0.5

## С каким шансом место получает предмет на стене: почти всегда — пустая стена
## между дверями и читалась «квадратом».
const WALL_CHANCE: float = 0.9

## Доли шага мест, в которые влезает предмет: узкий — в своё место, широкий —
## в три места, если соседние свободны. Шире своего места предмет задевал бы
## дверь или табличку соседнего.
const NARROW: float = 0.8
const WIDE: float = 2.4

## Предмет на стене не шире этого, м: он висит между пилястрами, а те стоят в
## 0.6 м от середины места ([constant BuildingRibs.PILASTER_WIDTH] шириной).
const WALL_WIDTH: float = 0.7

## Мебель выше этого закрывает стену: над ней ничего не вешается.
const TALL: float = 1.25

## С каким шансом под потолком этажа офиса идёт труба. В отеле труб на виду нет.
const PIPE_CHANCE: float = 0.4

## Смешивается с сидом, чтобы обстановка не повторяла жребий раскладки.
const SALT: int = 0x0DEC_0A7E

var props: Array[PropSpot] = []
## Предметы на стене.
var decor: Array[PropSpot] = []
## Этажи, под потолком которых идёт труба.
var pipes: Array[int] = []


## Обстановка здания по его плану, сиду и типу.
static func lay(
	rules: BuildingRules,
	plan: BuildingPlan,
	building_seed: int,
	identity: BuildingIdentity = BuildingIdentity.new()
) -> BuildingDressing:
	var dressing := BuildingDressing.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, SALT])
	var step := rules.slot_x(1) - rules.slot_x(0)
	var floor_items := PropCatalog.pick(PropCatalog.Place.FLOOR, identity.fit())
	var wall_items := PropCatalog.pick(PropCatalog.Place.WALL, identity.fit())
	# Этаж выхода — гараж: пустой, с одной машиной (ADR-0031, решение 4).
	for index in rules.floors - 1:
		var spots := free_spots(rules, plan, index)
		var zones := blocked_zones(rules, plan, index)
		var taken := {}
		var on_floor: Array[PropSpot] = []
		for slot in spots.size():
			if taken.has(slot) or rng.randf() >= FLOOR_CHANCE:
				continue
			var roomy := _neighbour_free(spots, slot, -1, step, taken)
			roomy = roomy and _neighbour_free(spots, slot, 1, step, taken)
			var room := step * (WIDE if roomy else NARROW)
			room = minf(room, _room_between(zones, spots[slot]))
			var item := _draw(rng, floor_items, room)
			if item == null:
				continue
			var prop := _spot(item.name, index, spots[slot])
			on_floor.append(prop)
			dressing.props.append(prop)
			taken[slot] = true
			if prop.width > step * NARROW:
				taken[slot - 1] = true
				taken[slot + 1] = true
		var last := ""
		for x: float in wall_spots(rules, plan, index):
			if _under_tall(on_floor, x) or _beside_shaft(rules, plan, index, x):
				continue
			if rng.randf() >= WALL_CHANCE:
				continue
			var hung := _draw(rng, wall_items, WALL_WIDTH, last)
			if hung == null:
				continue
			last = hung.name
			dressing.decor.append(_spot(hung.name, index, x))
		if not identity.is_hotel() and rng.randf() < PIPE_CHANCE:
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


## Места этажа для предмета на стене: там же, где встают люди, кроме дверей и
## мест вплотную к глухой стене. Лампа стене не мешает — она висит под
## потолком, — и место под ней тоже годится: иначе на узком этаже башни стены
## оставались голыми.
static func wall_spots(
	rules: BuildingRules, plan: BuildingPlan, floor_index: int
) -> PackedFloat64Array:
	var step := rules.slot_x(1) - rules.slot_x(0)
	var near_wall := step * 0.5 + rules.inner_wall_width * 0.5
	var free := PackedFloat64Array()
	for x: float in plan.safe_spots(rules, floor_index):
		var taken := false
		for door in plan.doors:
			if door.floor_index == floor_index and absf(door.x - x) < step * 0.5:
				taken = true
		for wall in plan.walls:
			if wall.floor_index == floor_index and absf(wall.x - x) < near_wall:
				taken = true
		if not taken:
			free.append(x)
	return free


## Что на этаже мебели задевать нельзя, отрезками «левый край, правый край»:
## проёмы дверей, шахты с наличниками, глухие стены и пролёт эскалатора с
## этажа выше — он спускается сюда наклонной полосой почти в два метра.
static func blocked_zones(
	rules: BuildingRules, plan: BuildingPlan, floor_index: int
) -> Array[Vector2]:
	var zones: Array[Vector2] = []
	var door_half := Door.LEAF_SIZE.x * 0.5
	for door in plan.doors:
		if door.floor_index == floor_index:
			zones.append(Vector2(door.x - door_half, door.x + door_half))
	var shaft_half := rules.shaft_width * 0.5 + BuildingShafts.PORTAL_JAMB
	for shaft in plan.shafts:
		if shaft.top <= floor_index and floor_index <= shaft.bottom:
			zones.append(Vector2(shaft.x - shaft_half, shaft.x + shaft_half))
	for wall in plan.walls:
		if wall.floor_index == floor_index:
			zones.append(wall.band(rules))
	for escalator in plan.escalators:
		if escalator.floor_index + 1 == floor_index:
			zones.append(escalator.gap(rules))
	return zones


## Сколько ширины у места [param x] до ближайшей занятой зоны — вдвое, потому
## что предмет встаёт серединой на место.
static func _room_between(zones: Array[Vector2], x: float) -> float:
	var half := INF
	for zone in zones:
		if x >= zone.x and x <= zone.y:
			return 0.0
		half = minf(half, minf(absf(zone.x - x), absf(x - zone.y)))
	return half * 2.0 - 0.02


## Свободно ли соседнее место: оно есть среди свободных ровно в шаге от этого и
## его ещё никто не занял.
static func _neighbour_free(
	spots: PackedFloat64Array, slot: int, side: int, step: float, taken: Dictionary
) -> bool:
	var other := slot + side
	if other < 0 or other >= spots.size() or taken.has(other):
		return false
	return absf(absf(spots[other] - spots[slot]) - step) < 0.01


## Предмет жребием из тех, что влезают в [param room] по ширине; не тот же, что
## [param avoid], если есть из чего выбрать.
static func _draw(
	rng: RandomNumberGenerator, items: Array[PropCatalog.Entry], room: float, avoid: String = ""
) -> PropCatalog.Entry:
	var fitting: Array[PropCatalog.Entry] = []
	for item in items:
		if PropCatalog.footprint(item.name).x <= room and item.name != avoid:
			fitting.append(item)
	if fitting.is_empty():
		return null
	return fitting[rng.randi_range(0, fitting.size() - 1)]


static func _spot(prop_name: String, floor_index: int, x: float) -> PropSpot:
	var spot := PropSpot.new()
	spot.name = prop_name
	spot.floor_index = floor_index
	spot.x = x
	spot.width = PropCatalog.footprint(prop_name).x
	return spot


## Соседнее ли место с шахтой: на стене у портала — панель кнопок вызова
## ([BuildingShafts], ADR-0033, решение 7), и картина налезла бы на неё.
static func _beside_shaft(
	rules: BuildingRules, plan: BuildingPlan, floor_index: int, x: float
) -> bool:
	var step := rules.slot_x(1) - rules.slot_x(0)
	for shaft in plan.shafts:
		if shaft.top <= floor_index and floor_index <= shaft.bottom:
			if absf(shaft.x - x) < step * 1.5:
				return true
	return false


## Стоит ли на [param x] высокая мебель, закрывающая стену.
static func _under_tall(on_floor: Array[PropSpot], x: float) -> bool:
	for prop in on_floor:
		var item := PropCatalog.entry(prop.name)
		if item.height > TALL and absf(prop.x - x) < prop.width * 0.5 + WALL_WIDTH * 0.5:
			return true
	return false
