class_name BuildingDecks
extends RefCounted

## Кто в здании ходит двухэтажной парой.
##
## Правило одно, но условий у него три, и каждое стоило вехе отдельной находки —
## поэтому своим файлом, а не строкой в [BuildingPlan]: тот и без того упёрся
## в потолок в тысячу строк.
##
## Устройство самой пары — в [ADR-0025](../../docs/adr/0025-shafts-escalators-and-riders.md),
## решение 1. Здесь только выбор шахты; всё, что пара меняет в ходе кабины,
## знает [method BuildingPlan.ShaftSpot.ride_span].

## Сколько пар ставится в здание самое большее.
##
## Две — столько их в оригинале: «two shafts featured a kind of double-decker
## elevator». Меньше выпадет там, где столько шахт с живой альтернативой
## не набралось; здание без пары — не поломка.
const MOST: int = 2


## Отмечает шахты, в которых ходит пара.
##
## Кандидаты пересчитываются после каждого выбора: поставленная пара сама
## становится путём похуже — на крайних своих этажах она не возит, — и второй
## паре опираться на неё нельзя.
static func lay(plan: BuildingPlan, rules: BuildingRules, rng: RandomNumberGenerator) -> void:
	# Считается один раз до всего: пара обязана оставить достижимым ровно то же,
	# что было достижимо без неё.
	var whole := BuildingRoute.reachable(plan, rules).size()

	for _left in MOST:
		# Копятся места в массиве шахт, а не сами шахты: выбор из набора идёт
		# одной строкой на весь проект ([method BuildingPlan.pick_any]), потому
		# что счёт сида зависит от порядка обращений к генератору.
		var fitting: Array[int] = []
		for index in plan.shafts.size():
			if not plan.shafts[index].double_deck and _takes_a_pair(plan, index):
				fitting.append(index)

		while not fitting.is_empty():
			var index := BuildingPlan.pick_any(rng, fitting)
			fitting.erase(index)
			plan.shafts[index].double_deck = true
			if BuildingRoute.reachable(plan, rules).size() == whole:
				break
			plan.shafts[index].double_deck = false


## Влезает ли в шахту пара и не запрёт ли она собой спуск.
##
## Условие структурное и грубое: оно смотрит на этаж целиком, а ходят по кускам
## этажа, и соседняя шахта может стоять за проёмом. Настоящий сторож — счёт
## достижимых узлов в [method lay]; это же условие отсеивает заведомо негодные
## шахты, не считая граф.
##
## **Порог достижимости здесь строже, чем у стены.** Стене довольно
## [method BuildingRoute.is_winnable] — та следит за документами и выходом.
## Паре этого мало: на сиде 3 она отняла у двух кусков девятнадцатого этажа
## единственный ход, шахта была там одна, и куски стали карманом. Документа
## в них нет, проходимость здания не пострадала — а бот, зайдя туда, встал
## до конца прогона.
static func _takes_a_pair(plan: BuildingPlan, index: int) -> bool:
	var shaft := plan.shafts[index]
	if shaft.height() < BuildingRules.MIN_SHAFT_FLOORS:
		return false
	# Шахта башни одна на верхнюю треть здания, и другого пути там нет вовсе,
	# но проверять это отдельно незачем — условие ниже её и не пропустит.
	for floor_index in range(shaft.top, shaft.bottom + 1):
		if not _another_way_off(plan, shaft, floor_index):
			return false
	return true


## Есть ли с этажа ход помимо этой шахты: соседняя шахта или эскалатор. Годится
## и эскалатор этажом выше: он ведёт вниз, но подняться по нему тоже можно,
## встав на нижнюю площадку (ADR-0005, пункт 8).
static func _another_way_off(
	plan: BuildingPlan, besides: BuildingPlan.ShaftSpot, floor_index: int
) -> bool:
	for other in plan.shafts:
		if other == besides:
			continue
		var span := other.ride_span()
		if floor_index >= span.x and floor_index <= span.y:
			return true
	for escalator in plan.escalators:
		if escalator.floor_index == floor_index or escalator.floor_index + 1 == floor_index:
			return true
	return false
