extends GutTest

## Кабина, шахта и фон залов по типу здания (ADR-0057, решения 4 и 6): решётка
## только у грузовой кабины жилого дома и показывает окно выхода ROM, стрелка
## циферблата отеля ходит от нижнего этажа к верхнему, фон зала звучит только
## внутри.


func test_only_a_freight_cab_has_a_gate() -> void:
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		var detail := CarDetail.new()
		detail.dress_as(kind)
		add_child_autofree(detail)
		detail.build(1.8, 3.0)
		assert_eq(
			detail.has_gate(), kind == BuildingIdentity.Kind.RESIDENTIAL, "тип %d: решётка" % kind
		)


## Решётка закрывается, когда сойти нельзя, и складывается, когда можно, — за
## время [constant CarDetail.GATE_TIME], а не мгновенно.
func test_gate_follows_the_step_out_window() -> void:
	var detail := CarDetail.new()
	detail.dress_as(BuildingIdentity.Kind.RESIDENTIAL)
	add_child_autofree(detail)
	detail.build(1.8, 3.0)
	assert_eq(detail.gate_openness(), 1.0, "в начале кабина стоит — решётка сложена")
	detail.tend_gate(false, CarDetail.GATE_TIME * 0.5)
	assert_almost_eq(detail.gate_openness(), 0.5, 0.01, "закрывается не сразу")
	detail.tend_gate(false, CarDetail.GATE_TIME)
	assert_eq(detail.gate_openness(), 0.0, "закрыта")
	detail.tend_gate(true, CarDetail.GATE_TIME)
	assert_eq(detail.gate_openness(), 1.0, "сложена")


func test_dial_needle_swings_from_bottom_to_top() -> void:
	var shaft := BuildingPlan.ShaftSpot.new()
	shaft.top = 3
	shaft.bottom = 13
	var bottom := BuildingShafts.needle_angle(shaft, 13)
	var top := BuildingShafts.needle_angle(shaft, 3)
	var middle := BuildingShafts.needle_angle(shaft, 8)
	assert_almost_eq(bottom, BuildingShafts.NEEDLE_SWING, 0.001, "внизу — влево до упора")
	assert_almost_eq(top, -BuildingShafts.NEEDLE_SWING, 0.001, "наверху — вправо")
	assert_almost_eq(middle, 0.0, 0.001, "посередине — вверх")
	assert_eq(BuildingShafts.needle_angle(shaft, 40), bottom, "за шахтой — у упора")


## Цифры табло у каждого типа свои.
func test_board_digits_differ_by_kind() -> void:
	var seen := {}
	for colour: Color in BuildingShafts.KIND_DIGITS:
		seen[colour] = true
	assert_eq(seen.size(), BuildingIdentity.Kind.size())


func test_hall_tone_sounds_only_indoors() -> void:
	for role: FloorRole.Role in Sounds.HALL_TONES:
		var tone := Sounds.hall_tone_of(role)
		assert_not_null(Sounds.stream(tone), "%s: звук есть" % tone)
		assert_true(Sounds.LOOPED.has(tone), "%s звучит петлёй, пока Otto на этаже" % tone)
		var inside := Sounds.weather_loops(
			Weather.Kind.CLEAR, false, TimeOfDay.Kind.NIGHT, BuildingIdentity.Kind.HOTEL, tone
		)
		assert_true(inside.has(tone), "%s внутри звучит" % tone)
		var outside := Sounds.weather_loops(
			Weather.Kind.CLEAR, true, TimeOfDay.Kind.NIGHT, BuildingIdentity.Kind.HOTEL, tone
		)
		assert_false(outside.has(tone), "%s снаружи не звучит" % tone)
	assert_eq(Sounds.hall_tone_of(FloorRole.Role.CORRIDOR), "", "у коридора своего фона нет")
	assert_not_null(Sounds.stream(Sounds.CAB_GATE), "лязг решётки есть")
