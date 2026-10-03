extends GutTest

## Tests of visible floor selection.
##
## The building has thirty floors and a light source on each, and two and a half fit in the frame.
## The selection decides what is lit, and it is computed without a scene — so it is also checked
## without one (ADR-0010, item 8).


func _rules() -> BuildingRules:
	var rules := BuildingRules.new()
	rules.floors = 30
	rules.floor_height = 120.0
	rules.slab_height = 20.0
	return rules


## A frame around a floor: the camera shows 360 px, the floor is 120 high.
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
	assert_false(VisibleFloors.covers(span, BuildingRules.ROOF), "крыша далеко")
	assert_false(VisibleFloors.covers(span, 0), "верхний этаж тоже")
	assert_false(VisibleFloors.covers(span, 20), "низ далеко")
	assert_false(VisibleFloors.covers(span, rules.floors - 1))


## Margin — so that a floor does not enter the frame dark and light up before your eyes.
func test_span_reaches_past_the_frame() -> void:
	var rules := _rules()
	var span := VisibleFloors.around(rules, _view_at(rules, 10))
	var in_frame := 3
	assert_gt(span.y - span.x + 1, in_frame, "видимых этажей три, гореть должно больше — с запасом")


func test_span_never_leaves_the_building() -> void:
	var rules := _rules()
	var roof := VisibleFloors.around(rules, _view_at(rules, BuildingRules.ROOF))
	assert_eq(roof.x, BuildingRules.ROOF, "выше крыши уровней нет")

	var bottom := VisibleFloors.around(rules, _view_at(rules, rules.floors - 1))
	assert_eq(bottom.y, rules.floors - 1, "ниже первого этажа тоже")


## However many floors there are, only a handful should be lit: the promise of a dozen sources in
## the frame rests on this.
func test_a_tall_building_lights_no_more_than_a_short_one() -> void:
	var rules := _rules()
	var short_rules := _rules()
	short_rules.floors = 8

	var tall := VisibleFloors.around(rules, _view_at(rules, 15))
	var small := VisibleFloors.around(short_rules, _view_at(short_rules, 4))
	assert_eq(tall.y - tall.x, small.y - small.x, "высота здания на число горящих не влияет")


## In the frame — floors visible at least at the edge, without margin: their lamps cast shadows, the
## margin ones are lit without shadows (ADR-0042, decision 2).
func test_seen_floors_are_the_frame_without_the_margin() -> void:
	var rules := _rules()
	var view := _view_at(rules, 10)
	var seen := VisibleFloors.seen(rules, view)
	var lit := VisibleFloors.around(rules, view)
	assert_true(VisibleFloors.covers(seen, 10), "этаж под ногами в кадре")
	assert_true(seen.x >= lit.x and seen.y <= lit.y, "в кадре — не шире горящих")
	assert_lt(seen.y - seen.x, lit.y - lit.x, "запас в кадр не входит")
	# The frame edge is 10 px below the floor of floor 11 — a piece of floor 12 is already in the
	# frame.
	var edge := Rect2(0.0, rules.floor_surface(11) - 350.0, 640.0, 360.0)
	assert_true(VisibleFloors.covers(VisibleFloors.seen(rules, edge), 12), "видный краем — в кадре")
