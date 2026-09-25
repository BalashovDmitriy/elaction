class_name BuildingLamps
extends RefCounted

## Лампы на плане здания: где на каждом этаже висит светильник.
##
## Отдельно от [BuildingPlan], как [BuildingDecks] и [BuildingBasement]:
## раскладка упёрлась в предел строк. Счёт прежний, перенесён без изменений
## (M24b).


## Раскладывает лампы: по ширине этажа и по серединам равных зон.
##
## Крыша ламп не получает — над ней небо, подвес держать не на чем. В диапазон
## она и не входит: этажи начинаются с нулевого, крыша лежит выше (ADR-0014).
##
## Не случайно, как остальное: зона лампы — единица темноты (ADR-0023), и лампы,
## сбившиеся в один край, оставили бы другой край этажа тёмным при всех горящих.
## Этаж делится на столько зон, сколько ламп, и каждая встаёт в ближайшее к
## середине своей зоны свободное место.
##
## Лампы уступают шахтам, эскалаторам и обязательной двери — двери сверх неё
## встают уже после ламп ([method BuildingPlan.generate]), — поэтому свободного
## места может не хватить, и тогда ламп меньше. Тёмный этаж карты ламп не просит
## вовсе ([method BuildingRules.is_unlit]). **Прочий — не ноль:** этаж
## без единой лампы не светел и погасить его нечем — для правила темноты он
## навсегда освещённый, хотя в кадре он чёрный. Когда свободных мест не
## осталось, лампа делит место с дверью: дверь стоит у задней стены, лампа
## висит под потолком, и мешают друг другу они только на плане. С правилами по
## умолчанию до этого не доходит — 12000 этажей на 400 сидах получили хотя бы
## одну, — но запас нужен тем правилам, которых ещё нет.
static func lay(plan: BuildingPlan, rules: BuildingRules, taken: Dictionary) -> void:
	for index in plan.floors:
		var span := rules.slot_range(index)
		var free: Array[int] = []
		for slot in range(span.x, span.y + 1):
			if not BuildingPlan.is_taken(taken, index, slot):
				free.append(slot)
		if free.is_empty():
			free = _slots_beside_the_openings(plan, rules, index)

		var wanted := rules.lamps_on(index)
		for number in wanted:
			if free.is_empty():
				break
			var ideal := (
				float(span.x)
				+ float(span.y - span.x) * (2.0 * float(number) + 1.0) / (2.0 * float(wanted))
			)
			var slot := _nearest_slot(free, ideal)
			free.erase(slot)

			var lamp := BuildingPlan.LampSpot.new()
			lamp.floor_index = index
			lamp.x = rules.slot_x(slot)
			BuildingPlan.occupy(taken, index, slot)
			plan.lamps.append(lamp)


## Места этажа, куда лампу повесить всё-таки можно, когда свободных не осталось:
## всё, кроме проёмов — шахт, эскалаторов и выхода. Над проёмом лампы не будет
## никогда: там ездит кабина и падать лампе некуда.
##
## Это места, где можно стоять ([method BuildingPlan.safe_spots]), — тот же
## отбор, только местами сетки, а не координатами.
static func _slots_beside_the_openings(
	plan: BuildingPlan, rules: BuildingRules, floor_index: int
) -> Array[int]:
	var clear := plan.safe_spots(rules, floor_index)
	var free: Array[int] = []
	var span := rules.slot_range(floor_index)
	for slot in range(span.x, span.y + 1):
		if clear.has(rules.slot_x(slot)):
			free.append(slot)
	return free


## Свободное место, ближайшее к желаемому. При равном расстоянии — левое.
static func _nearest_slot(free: Array[int], ideal: float) -> int:
	var best := free[0]
	for slot in free:
		if absf(float(slot) - ideal) < absf(float(best) - ideal):
			best = slot
	return best
