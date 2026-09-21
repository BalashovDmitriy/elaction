extends GutTest

## Тесты внутренних стен, делящих этаж надвое (ADR-0024, решение 5).
##
## Стена — единственное, что режет этаж, не делая дыры в полу, и потому она
## опаснее проёма: проём видно, а запертую половину — нет. Проверяется здесь и
## то, где стена стоит, и то, что она никого не заперла.
##
## Своим файлом, а не в [code]test_building_plan.gd[/code]: тот уже уперся
## в потолок публичных методов, а стены — отдельная история со своим счётом
## кусков этажа.

## Сиды, на которых проверяются правила. Здание случайно, и одна проверка на
## одном сиде подтверждает только его — а дыры вылезают на редких.
const SEEDS: Array[int] = [1, 2, 3, 5, 8, 13, 21, 34]


func _rules() -> BuildingRules:
	return BuildingRules.new()


## Стена стоит на плите и между местами, а не над проёмом: ADR-0024, решение 5.
## Стена над шахтой висела бы в воздухе, а у самого края отрезала бы не половину
## этажа, а полоску, на которой нечему стоять.
func test_walls_stand_on_the_slab_between_the_openings() -> void:
	var rules := _rules()
	var floors_with_walls := 0
	for building_seed in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		floors_with_walls += plan.walls.size()
		for wall in plan.walls:
			var index := wall.floor_index
			var band := wall.band(rules)
			var where := "сид %d, этаж %d" % [building_seed, index]

			for gap: Vector2 in plan.gaps_on(rules, index):
				var over := band.y > gap.x and band.x < gap.y
				assert_false(over, "стена висит над проёмом: " + where)

			var span := rules.floor_span(index)
			var edge := rules.slot_x(1) - rules.slot_x(0)
			assert_gt(band.x, span.x + edge, "стена у самой стены: " + where)
			assert_lt(band.y, span.y - edge, "стена у самой стены: " + where)

	assert_gt(floors_with_walls, 0, "стены должны хоть где-то появляться")


## Стена — не на каждом этаже: это крюк через другой этаж, и подряд они
## превратили бы спуск в лабиринт.
func test_walls_are_not_on_every_floor() -> void:
	var rules := _rules()
	for building_seed in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		var walled: Dictionary = {}
		for wall in plan.walls:
			assert_false(walled.has(wall.floor_index), "на этаже не больше одной стены")
			walled[wall.floor_index] = true
		var share := float(walled.size()) / float(rules.floors)
		assert_lt(share, 0.6, "сид %d: стены почти на каждом этаже" % building_seed)


## Стена, из-за которой документ или выход стали недостижимы, снимается при
## раскладке. Проверяется на многих сидах: запирает не всякая стена и не всегда.
func test_no_wall_locks_a_document_or_the_exit_away() -> void:
	var rules := _rules()
	for building_seed in range(1, 60):
		var plan := BuildingPlan.generate(rules, building_seed)
		var missing := BuildingRoute.unreachable_spots(plan, rules)
		assert_true(missing.is_empty(), "сид %d: заперто — %s" % [building_seed, str(missing)])


## Раскладка со стенами обязана быть тяжелее раскладки без них, иначе проверка
## выше подтверждает не работу отбраковки, а её отсутствие: здание, в котором
## стен не появляется вовсе, проходимо само по себе.
func test_walls_really_cut_the_floors_they_stand_on() -> void:
	var rules := _rules()
	var cut := 0
	for building_seed in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for wall in plan.walls:
			var span := rules.floor_span(wall.floor_index)
			var slab := BuildingPlan.spans_between(plan.gaps_on(rules, wall.floor_index), span)
			var walk := BuildingPlan.spans_between(plan.blocks_on(rules, wall.floor_index), span)
			assert_gt(walk.size(), slab.size(), "стена обязана добавлять кусок этажу")
			cut += 1
	assert_gt(cut, 0, "стены должны хоть где-то появляться")


## Агент по другую сторону глухой стены Otto не видит: стрелять в стену незачем.
## Разбирается это тем же путём, что и темнота, — не видит, значит не цель.
func test_a_wall_hides_otto_from_an_agent_on_the_same_floor() -> void:
	var rules := _rules()
	var plan := BuildingPlan.generate(rules, 1)
	var wall := BuildingPlan.WallSpot.new()
	wall.floor_index = 5
	wall.x = 18.0
	plan.walls.append(wall)

	assert_true(plan.wall_between(5, 14.0, 22.0), "стена между ними")
	assert_true(plan.wall_between(5, 22.0, 14.0), "порядок точек не важен")
	assert_false(plan.wall_between(5, 19.0, 22.0), "по одну сторону стены нет")
	assert_false(plan.wall_between(6, 14.0, 22.0), "стена делит только свой этаж")
