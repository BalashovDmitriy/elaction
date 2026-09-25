class_name BuildingBasement
extends RefCounted

## Подвал на плане: одна шахта вниз и выход у ворот (ADR-0038, решение 3).
##
## Нижний этаж — подземный паркинг, как подвал ROM. Туда спускается одна шахта
## жребием из тех, что доходят до этажа над ним (шахта выхода ROM, $802D,
## @273F); остальные кончаются этажом выше, эскалаторы вниз не ведут. Машина
## Otto стоит у ворот в левом торце, и путь к ней зависит от того, какая
## шахта выпала.
##
## Отдельно от [BuildingPlan], как [BuildingDecks] и [BuildingDocuments]:
## раскладка упёрлась в предел строк, а правила подвала — своя тема. Счёт
## тот же: без узлов, по правилам и жребию плана.


## Нижний этаж, до которого доходят шахты, кроме одной: этаж над подвалом.
static func lowest_landing(rules: BuildingRules) -> int:
	return rules.floors - 2


## Годится ли место [param x] шахте с дном [param bottom].
##
## Дошедшая до дна может выпасть шахтой в подвал, а там у левого торца стоит
## машина: такой шахте места у торца нет ([method ExitCar.clears_shaft]).
## Проверяется при открытии шахты, а не при жребии: тогда выбирать есть из
## чего всегда.
static func fits_shaft(rules: BuildingRules, bottom: int, x: float) -> bool:
	return bottom != lowest_landing(rules) or ExitCar.clears_shaft(rules, x)


## Шахта, которая уйдёт в подвал: одна жребием из доходящих до этажа над ним.
## [code]null[/code] — шахт нет вовсе.
##
## Кандидатка есть в любом здании с шахтами: верхняя доходит до дна всегда,
## если короче её не сделает само здание, а машину ни одна не задевает —
## это стережёт [method fits_shaft].
static func pick_shaft(
	plan: BuildingPlan, rules: BuildingRules, rng: RandomNumberGenerator
) -> BuildingPlan.ShaftSpot:
	var candidates: Array[int] = []
	for number in plan.shafts.size():
		var shaft := plan.shafts[number]
		if shaft.bottom == lowest_landing(rules) and ExitCar.clears_shaft(rules, shaft.x):
			candidates.append(number)
	if candidates.is_empty():
		if not plan.shafts.is_empty():
			push_error("в подвал не спускается ни одна шахта")
		return null
	return plan.shafts[BuildingPlan.pick_any(rng, candidates)]


## Шахта в подвал: единственная, что доходит до нижнего этажа. Пустое здание
## шахт не имеет, поэтому ответ бывает и пустым.
static func shaft_of(plan: BuildingPlan) -> BuildingPlan.ShaftSpot:
	for shaft in plan.shafts:
		if shaft.bottom == plan.floors - 1:
			return shaft
	return null


## Место выхода: крайнее левое место подвала.
##
## Не жребием, а у торца: там ворота паркинга и машина Otto капотом к ним — в
## ROM машина всегда слева. Место приходится на машину у водительской двери
## ([method ExitCar.parked_span]); шахта в подвал машину не задевает, поэтому
## оно свободно всегда.
static func exit_slot(rules: BuildingRules) -> int:
	return rules.slot_range(rules.floors - 1).x
