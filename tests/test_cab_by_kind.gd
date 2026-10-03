extends GutTest

## Cab, shaft and hall ambience by building kind (ADR-0057, decisions 4 and 6): only the
## residential freight cab has a gate and it shows the ROM's step-out window, the hotel
## dial's needle moves from the bottom floor to the top, the hall ambience is heard only
## inside.


func test_only_a_freight_cab_has_a_gate() -> void:
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		var detail := CarDetail.new()
		detail.dress_as(kind)
		add_child_autofree(detail)
		detail.build(1.8, 3.0)
		assert_eq(
			detail.has_gate(), kind == BuildingIdentity.Kind.RESIDENTIAL, "kind %d: gate" % kind
		)


## The gate closes when one cannot step out and folds when one can — over
## [constant CarDetail.GATE_TIME], not instantly.
func test_gate_follows_the_step_out_window() -> void:
	var detail := CarDetail.new()
	detail.dress_as(BuildingIdentity.Kind.RESIDENTIAL)
	add_child_autofree(detail)
	detail.build(1.8, 3.0)
	assert_eq(detail.gate_openness(), 1.0, "at the start the cab stands: the gate is folded")
	detail.tend_gate(false, CarDetail.GATE_TIME * 0.5)
	assert_almost_eq(detail.gate_openness(), 0.5, 0.01, "does not close at once")
	detail.tend_gate(false, CarDetail.GATE_TIME)
	assert_eq(detail.gate_openness(), 0.0, "closed")
	detail.tend_gate(true, CarDetail.GATE_TIME)
	assert_eq(detail.gate_openness(), 1.0, "folded")


func test_dial_needle_swings_from_bottom_to_top() -> void:
	var shaft := BuildingPlan.ShaftSpot.new()
	shaft.top = 3
	shaft.bottom = 13
	var bottom := BuildingShafts.needle_angle(shaft, 13)
	var top := BuildingShafts.needle_angle(shaft, 3)
	var middle := BuildingShafts.needle_angle(shaft, 8)
	assert_almost_eq(bottom, BuildingShafts.NEEDLE_SWING, 0.001, "at the bottom: left all the way")
	assert_almost_eq(top, -BuildingShafts.NEEDLE_SWING, 0.001, "at the top: right")
	assert_almost_eq(middle, 0.0, 0.001, "in the middle: up")
	assert_eq(BuildingShafts.needle_angle(shaft, 40), bottom, "beyond the shaft: at the stop")


## Each kind has its own indicator board digits.
func test_board_digits_differ_by_kind() -> void:
	var seen := {}
	for colour: Color in BuildingShafts.KIND_DIGITS:
		seen[colour] = true
	assert_eq(seen.size(), BuildingIdentity.Kind.size())


func test_hall_tone_sounds_only_indoors() -> void:
	for role: FloorRole.Role in Sounds.HALL_TONES:
		var tone := Sounds.hall_tone_of(role)
		assert_not_null(Sounds.stream(tone), "%s: sound exists" % tone)
		assert_true(Sounds.LOOPED.has(tone), "%s plays as a loop while Otto is on the floor" % tone)
		var inside := Sounds.weather_loops(
			Weather.Kind.CLEAR, false, TimeOfDay.Kind.NIGHT, BuildingIdentity.Kind.HOTEL, tone
		)
		assert_true(inside.has(tone), "%s plays inside" % tone)
		var outside := Sounds.weather_loops(
			Weather.Kind.CLEAR, true, TimeOfDay.Kind.NIGHT, BuildingIdentity.Kind.HOTEL, tone
		)
		assert_false(outside.has(tone), "%s does not play outside" % tone)
	assert_eq(
		Sounds.hall_tone_of(FloorRole.Role.CORRIDOR), "", "a corridor has no background of its own"
	)
	assert_not_null(Sounds.stream(Sounds.CAB_GATE), "the gate clang exists")
