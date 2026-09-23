class_name AgentLifts
extends RefCounted

## Куда агенту идти, чтобы уехать к Otto.
##
## Правило одно — «иди к той кабине, что уже стоит вровень с твоим этажом», — но
## условий у него четыре, и каждое стоило вехе отдельной находки. Поэтому своим
## файлом, а не четырьмя методами в [GreyboxLevel]: тот и без того упёрся
## в потолок в тысячу строк.
##
## Устройство поездки — в [ADR-0025](../../docs/adr/0025-shafts-escalators-and-riders.md),
## решение 6. Что агент делает с ответом, знает [method Enemy.set_lift_at]:
## выбранную кабину он держит, пока ему вообще предлагают ехать.


## Ось кабины, в которую агенту стоит войти, чтобы стать ближе к Otto, или NAN.
##
## [param where] — этаж агента, [param x] — где он стоит, [param here] — этаж
## Otto.
##
## Предлагается только стоящая вровень с его этажом: вызова кабины в оригинале
## нет ни у кого, а ждать её у проёма агенту нечем — он бы топтался на кромке,
## разворачиваясь на каждом кадре.
##
## **Из подходящих берётся ближайшая.** На этаже стилобата шахт до пяти, и
## какая-нибудь кабина стоит вровень почти всегда; предложение прыгало с одной
## на другую, и агент метался между ними, не дойдя ни до одной за полминуты.
##
## На этаже Otto кабина не предлагается вовсе: приехали. Поэтому едущий агент
## выходит там, где Otto, а не на первом попавшемся этаже — пока кабина идёт,
## вровень она ни с чем не стоит, и предложение само пропадает.
##
## **Предлагается только та, до которой агент дойдёт.** Разворачиваться перед
## преградой он не станет — кабина за глухой стеной или за чужим проёмом
## означала бы агента, замершего у преграды до конца здания вместо патруля.
static func offer(
	plan: BuildingPlan,
	rules: BuildingRules,
	cars: Array[ElevatorCar],
	where: int,
	x: float,
	here: int
) -> float:
	if where == here:
		return NAN

	# Кабины, стоящие вровень с этажом агента: только они и возят, и они же
	# перекрывают собой свои проёмы.
	var standing := PackedFloat64Array()
	for car in cars:
		if car.is_aligned() and rules.floor_index_near(_height_of(car)) == where:
			standing.append(car.position.x)
	if standing.is_empty():
		return NAN

	var blocks := _walk_blocks(plan, rules, where, standing)
	var towards := signi(here - where)
	var best := NAN
	for axis: float in standing:
		var shaft := _shaft_in_column(plan, rules, axis, where)
		if shaft == null:
			continue
		# Шахта обязана вести в сторону Otto: иначе агент уезжает от него.
		var span := shaft.ride_span()
		if not ((towards > 0 and span.y > where) or (towards < 0 and span.x < where)):
			continue
		if not _reaches(blocks, x, axis):
			continue
		if is_nan(best) or absf(axis - x) < absf(best - x):
			best = axis
	return best


## Есть ли у агента на этаже [param where] шахта, которая везёт в сторону Otto и
## до которой он дойдёт, — стоит ли там сейчас кабина или нет.
##
## Такой агент ждёт кабину, а не уходит в дверь: иначе отставший на пару этажей
## агент уходил бы раньше, чем кабина успевала за ним прийти, и поездок
## агентов (ADR-0025, решение 6) не осталось бы вовсе.
static func can_ride(
	plan: BuildingPlan, rules: BuildingRules, where: int, x: float, here: int
) -> bool:
	if where == here:
		return false
	var towards := signi(here - where)
	for shaft in plan.shafts:
		if shaft.top > where or shaft.bottom < where:
			continue
		var span := shaft.ride_span()
		if not ((towards > 0 and span.y > where) or (towards < 0 and span.x < where)):
			continue
		var blocks := _walk_blocks(plan, rules, where, PackedFloat64Array([shaft.x]))
		if _reaches(blocks, x, shaft.x):
			return true
	return false


## Ближайшая дверь этажа [param where], до которой агент от [param x] дойдёт,
## или NAN. Туда уходит отставший агент (ADR-0027, решение 3а); как и кабина,
## предлагается только достижимая — за стеной или проёмом он замер бы у преграды.
static func nearest_door(
	plan: BuildingPlan, rules: BuildingRules, cars: Array[ElevatorCar], where: int, x: float
) -> float:
	var standing := PackedFloat64Array()
	for car in cars:
		if car.is_aligned() and rules.floor_index_near(_height_of(car)) == where:
			standing.append(car.position.x)
	var blocks := _walk_blocks(plan, rules, where, standing)
	var best := NAN
	for door in plan.doors:
		if door.floor_index != where or not _reaches(blocks, x, door.x):
			continue
		if is_nan(best) or absf(door.x - x) < absf(best - x):
			best = door.x
	return best


## Что режет агенту ходьбу по этажу: проёмы и глухие стены, кроме тех проёмов,
## где стоит кабина.
##
## Сквозь стоящую кабину проходят насквозь — этим живёт и граф здания
## ([BuildingRoute]), и половина этажа, разрезанного шахтой.
static func _walk_blocks(
	plan: BuildingPlan, rules: BuildingRules, where: int, standing: PackedFloat64Array
) -> Array[Vector2]:
	var blocks: Array[Vector2] = []
	for block: Vector2 in plan.blocks_on(rules, where):
		var bridged := false
		for axis: float in standing:
			if block.x <= axis and axis <= block.y:
				bridged = true
				break
		if not bridged:
			blocks.append(block)
	return blocks


## Дойдёт ли идущий по этажу от [param from_x] до [param to_x], не упёршись
## ни в одну из преград [param blocks].
static func _reaches(blocks: Array[Vector2], from_x: float, to_x: float) -> bool:
	var low := minf(from_x, to_x)
	var high := maxf(from_x, to_x)
	for block: Vector2 in blocks:
		if block.y > low and block.x < high:
			return false
	return true


## Шахта, стоящая в этом столбце и обслуживающая этот этаж.
##
## Столбец сам по себе шахту не опознаёт: полосы не перекрываются по этажам,
## но одно и то же место сетки занимают разные шахты на разной высоте.
static func _shaft_in_column(
	plan: BuildingPlan, rules: BuildingRules, x: float, index: int
) -> BuildingPlan.ShaftSpot:
	for shaft in plan.shafts:
		if index < shaft.top or index > shaft.bottom:
			continue
		if absf(shaft.x - x) <= rules.shaft_width * 0.5:
			return shaft
	return null


## Высота узла в координатах правил: там, где Y растёт вниз.
static func _height_of(node: Node3D) -> float:
	return WorldSpace.to_plane(node.global_position).y
