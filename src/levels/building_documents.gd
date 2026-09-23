class_name BuildingDocuments
extends RefCounted

## Красные двери здания: сколько их и на каких этажах.
##
## Своим классом, а не в [BuildingPlan]: правило пришло из ROM целой таблицей
## полос и квот (ADR-0028, решение 3), и в раскладке ему стало тесно. План
## зовёт [method lay] и получает этажи, на которых встали документы; сами двери
## ставит [method BuildingPlan.place_door] — тем же жребием, что и синие.


## Сколько красных дверей в здании: вручную
## ([member BuildingRules.documents_cap]) или по ROM на навыке здания —
## [method Arcade.red_doors], от 5 до 10.
static func count(rules: BuildingRules) -> int:
	return rules.documents_cap if rules.documents_cap >= 0 else Arcade.red_doors(rules.skill)


## Раскладывает красные двери: здание делится на полосы, и в каждой их столько,
## сколько велит правило. На этаже — не больше одной.
##
## По ROM полосы и квоты — оригинала, по навыку здания ([method _rom_bands]):
## в первом здании верх пуст, с навыком заполняются низ и верх (ADR-0028,
## решение 3). Ручное число ([member BuildingRules.documents_cap]) делится
## поровну по высоте, как до M18e.
##
## Внутри полосы этажи перебираются, пока дверь не встанет: на достижимой части
## этажа может не остаться места. Документ, которому в своей полосе места не
## нашлось, кладётся на любой этаж здания без документа, а не пропадает: собрать
## четыре из пяти нельзя.
static func lay(
	plan: BuildingPlan, rules: BuildingRules, rng: RandomNumberGenerator, taken: Dictionary
) -> Dictionary:
	var chosen: Dictionary = {}
	var wanted := mini(count(rules), rules.floors)
	if wanted <= 0:
		# Раньше проверки: маршрут — перебор всей раскладки, а в здании без
		# документов он никому не нужен. Да и на здании в ноль этажей он падает.
		return chosen

	# Куски этажей считаем один раз: сами по себе они — перебор всей раскладки,
	# и маршруту нужны ровно те же самые.
	var spans := BuildingRoute.segments(plan, rules)
	var routed := BuildingRoute.reachable_in(plan, rules, spans)

	var bands := _rom_bands(rules) if rules.documents_cap < 0 else _even_bands(rules.floors, wanted)
	var left := 0
	for band: Vector3i in bands:
		var placed := _lay_in(
			plan, rules, rng, taken, band.x, band.y, band.z, chosen, routed, spans
		)
		left += band.z - placed
	# Больше одной на этаж не положить: в здании ниже числа ROM остаток
	# урезается по этажам, как и ручное число, а не падает ошибкой.
	left = mini(left, wanted - chosen.size())
	if left > 0:
		left -= _lay_in(plan, rules, rng, taken, 0, rules.floors - 1, left, chosen, routed, spans)
	if left > 0:
		push_error("в здании некуда положить %d документ(а)" % left)
	return chosen


## Кладёт до [param wanted] красных дверей на этажи [param from]..[param to],
## по одной на этаж, в случайном порядке. Возвращает, сколько встало.
static func _lay_in(
	plan: BuildingPlan,
	rules: BuildingRules,
	rng: RandomNumberGenerator,
	taken: Dictionary,
	from: int,
	to: int,
	wanted: int,
	chosen: Dictionary,
	routed: Dictionary,
	spans: Dictionary
) -> int:
	var placed := 0
	if wanted <= 0 or to < from:
		return placed
	for index: int in _shuffled_range(rng, from, to):
		if placed >= wanted:
			break
		if chosen.has(index) or rules.doors_on(index) <= 0:
			continue
		if not plan.place_door(rules, rng, taken, index, true, routed, spans):
			continue
		chosen[index] = true
		placed += 1
	return placed


## Полосы красных дверей оригинала в наших этажах: «первый, последний, сколько».
##
## Полоса ROM переводится этажами, чей номер ROM в неё попадает
## ([method Arcade.rom_floor]). В здании ниже тридцати этажей полоса может
## не получить ни одного — её документы уходят в общий остаток.
static func _rom_bands(rules: BuildingRules) -> Array[Vector3i]:
	var bands: Array[Vector3i] = []
	for band in Arcade.RED_DOOR_BANDS.size():
		var quota := Arcade.red_doors_in_band(band, rules.skill)
		if quota <= 0:
			continue
		var rom := Arcade.RED_DOOR_BANDS[band]
		var from := rules.floors
		var to := -1
		for index in rules.floors:
			var number := Arcade.rom_floor(index, rules.floors)
			if number >= rom.x and number <= rom.y:
				from = mini(from, index)
				to = maxi(to, index)
		bands.append(Vector3i(from, to, quota))
	return bands


## Здание поровну на [param wanted] полос, по документу в каждой.
static func _even_bands(floors: int, wanted: int) -> Array[Vector3i]:
	var bands: Array[Vector3i] = []
	var band := float(floors) / float(wanted)
	for number in wanted:
		var from := int(floor(band * float(number)))
		var to := maxi(int(floor(band * float(number + 1))) - 1, from)
		bands.append(Vector3i(from, to, 1))
	return bands


## Этажи полосы в случайном порядке. Своя тасовка, а не [method Array.shuffle]:
## та берёт глобальный генератор, и здание перестало бы повторяться по сиду.
static func _shuffled_range(rng: RandomNumberGenerator, from: int, to: int) -> Array[int]:
	var order: Array[int] = []
	for index in range(from, to + 1):
		order.append(index)
	for index in range(order.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var kept := order[index]
		order[index] = order[other]
		order[other] = kept
	return order
