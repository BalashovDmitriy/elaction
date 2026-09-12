extends GutTest

## Тесты отбора видимых этажей.
##
## В здании тридцать этажей и по источнику света на каждом, а в кадр влезает два
## с половиной. Отбор решает, чему гореть, и считается без сцены — значит,
## и проверяется без неё (ADR-0010, пункт 8).


func _rules() -> BuildingRules:
	var rules := BuildingRules.new()
	rules.floors = 30
	rules.floor_height = 120.0
	rules.slab_height = 20.0
	return rules


## Кадр вокруг этажа: камера показывает 360 px, этаж высотой 120.
func _view_at(rules: BuildingRules, index: int) -> Rect2:
	var middle := rules.floor_surface(index)
	return Rect2(0.0, middle - 180.0, 640.0, 360.0)


func test_span_covers_the_floors_in_frame() -> void:
	var rules := _rules()
	var span := VisibleFloors.around(rules, _view_at(rules, 10))
	assert_true(VisibleFloors.covers(span, 10), "этаж под ногами горит")
	assert_true(VisibleFloors.covers(span, 9), "и соседние сверху")
	assert_true(VisibleFloors.covers(span, 11), "и снизу")


func test_distant_floors_stay_dark() -> void:
	var rules := _rules()
	var span := VisibleFloors.around(rules, _view_at(rules, 10))
	assert_false(VisibleFloors.covers(span, 0), "крыша далеко")
	assert_false(VisibleFloors.covers(span, 20), "низ далеко")
	assert_false(VisibleFloors.covers(span, rules.floors - 1))


## Запас — чтобы этаж не въезжал в кадр погашенным и не вспыхивал на глазах.
func test_span_reaches_past_the_frame() -> void:
	var rules := _rules()
	var span := VisibleFloors.around(rules, _view_at(rules, 10))
	var in_frame := 3
	assert_gt(span.y - span.x + 1, in_frame, "видимых этажей три, гореть должно больше — с запасом")


func test_span_never_leaves_the_building() -> void:
	var rules := _rules()
	var roof := VisibleFloors.around(rules, _view_at(rules, 0))
	assert_eq(roof.x, 0, "выше крыши этажей нет")

	var bottom := VisibleFloors.around(rules, _view_at(rules, rules.floors - 1))
	assert_eq(bottom.y, rules.floors - 1, "ниже первого этажа тоже")


## Сколько бы этажей ни было, гореть должна горстка: на этом держится обещание
## про дюжину источников в кадре.
func test_a_tall_building_lights_no_more_than_a_short_one() -> void:
	var rules := _rules()
	var short_rules := _rules()
	short_rules.floors = 8

	var tall := VisibleFloors.around(rules, _view_at(rules, 15))
	var small := VisibleFloors.around(short_rules, _view_at(short_rules, 4))
	assert_eq(tall.y - tall.x, small.y - small.x, "высота здания на число горящих не влияет")
