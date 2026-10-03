extends GutTest

## Building silhouette tests: how many slots a level has and where its walls are.
##
## The building widens toward the bottom in steps, and everything else rests on this: a shaft
## passes through floors of different widths and must stand on a slot that exists on
## each of them. Everything is computed by the rules, without a scene (ADR-0014, point 3).


func _rules() -> BuildingRules:
	var rules := BuildingRules.new()
	rules.floors = 30
	# The test building is its own small world in integers, and it is set in full:
	# all lengths the checks below depend on. While part was taken from
	# defaults, the test relied on 480 and 3840 being exact in any float; since
	# M15 the defaults are metric — 4.8 and 38.4 — and exact equalities drifted on
	# the last bit of the fraction ([Vector2] also stores float32).
	rules.floor_height = 120.0
	rules.slab_height = 20.0
	rules.sky_height = 160.0
	rules.width = 3840.0
	rules.margin = 240.0
	return rules


func test_levels_start_at_the_roof_and_end_at_the_bottom() -> void:
	var rules := _rules()
	var all := rules.levels()
	assert_eq(all.size(), rules.floors + 1, "этажи плюс крыша")
	assert_eq(all[0], BuildingRules.ROOF)
	assert_eq(all[-1], rules.floors - 1)


## Silhouette: narrow at the top, full width at the bottom. Steps go only down — the shaft
## that passes through floors of different widths rests on this (ADR-0014).
func test_the_building_only_widens_going_down() -> void:
	var rules := _rules()
	var previous := -1.0
	for index: int in rules.levels():
		var width := rules.floor_width(index)
		assert_true(width >= previous, "этаж %d уже того, что над ним" % index)
		previous = width


func test_the_narrowest_level_is_the_roof_and_the_widest_is_the_bottom() -> void:
	var rules := _rules()
	assert_eq(rules.floor_width(rules.floors - 1), rules.width, "внизу здание во всю ширину")
	assert_lt(rules.floor_width(BuildingRules.ROOF), rules.width, "наверху уже")


## Upper floors fit in the frame entirely, lower ones are wider than the screen (ADR-0024,
## decision 2). The tower is seen whole, while the podium has to be walked.
##
## Rules are taken as defaults, not from the test world: the frame width is metric, and
## it must be checked against the building assembled in the game.
func test_narrow_levels_fit_the_frame_and_wide_ones_do_not() -> void:
	var rules := BuildingRules.new()
	var frame := _frame_width()
	var narrow := 0
	var wide := 0
	for index: int in rules.levels():
		var width := rules.floor_width(index)
		if rules.is_wide(index):
			assert_gt(width, frame, "этаж %d обязан быть шире кадра" % index)
			wide += 1
		else:
			assert_lt(width, frame, "этаж %d обязан влезать в кадр" % index)
			narrow += 1
	assert_gt(narrow, 0, "узкая часть не может быть пустой")
	assert_gt(wide, 0, "широкая тоже")


## Orthocamera frame width, m. Half the height is set by the camera, the width — from it
## and the project viewport aspect ratio: one cannot compute from the window in headless,
## there is none there.
func _frame_width() -> float:
	var wide := float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var high := float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	return SideCamera.DEFAULT_HALF_HEIGHT * 2.0 * wide / maxf(high, 1.0)


func test_narrow_levels_offer_fewer_slots() -> void:
	var rules := _rules()
	var top := rules.slot_range(BuildingRules.ROOF)
	var bottom := rules.slot_range(rules.floors - 1)
	assert_eq(top.y - top.x + 1, rules.top_slots, "наверху ровно столько мест, сколько обещано")
	assert_eq(bottom.y - bottom.x + 1, rules.slots)


## Slots are symmetric around the middle: an asymmetric floor would pull
## a shaft passing through it away from its own column.
func test_slots_stay_centred_on_every_level() -> void:
	var rules := _rules()
	var middle := rules.slots - 1
	for index: int in rules.levels():
		var span := rules.slot_range(index)
		assert_eq(span.x + span.y, middle, "этаж %d сдвинут вбок" % index)


## The narrowest floor must fit the mandatory: a shaft, one door and its
## lamps. Doors beyond one are not mandatory — they take what is left
## (ADR-0028, decision 2).
##
## The narrowest floor is floor zero, and its width is what gets measured. The roof is narrower, but
## it has neither doors nor lamps: measuring floor occupancy by its width would mean
## comparing two different levels and passing by a chance match of their step.
func test_the_narrowest_level_fits_everything_it_must_hold() -> void:
	var rules := _rules()
	var needed := 1 + mini(rules.doors_on(0), 1) + rules.lamps_on(0)
	var span := rules.slot_range(0)
	assert_true(span.y - span.x + 1 >= needed, "мест меньше, чем надо поставить")
	assert_eq(rules.lamps_on(BuildingRules.ROOF), 0, "а крыше ставить нечего")


func test_slots_outside_the_silhouette_are_not_available() -> void:
	var rules := _rules()
	assert_false(rules.slot_available(0, BuildingRules.ROOF), "край здания наверху — улица")
	assert_true(rules.slot_available(0, rules.floors - 1), "внизу то же место — этаж")


## The slab is both the floor of its level and the ceiling of the one below. At a silhouette step
## the lower floor is wider, and without this there would be open sky above its outer strip,
## and a lamp in the outermost slot would hang on nothing.
func test_a_slab_covers_the_floor_below_it_whole() -> void:
	var rules := _rules()
	for index: int in rules.levels():
		if index >= rules.floors - 1:
			continue
		var slab := rules.slab_span(index)
		var below := rules.floor_span(index + 1)
		assert_true(
			slab.x <= below.x and slab.y >= below.y,
			"этаж %d остался без потолка по краям" % (index + 1)
		)


## The slab does not get narrower than its own walls: it stays the floor of its level.
func test_a_slab_is_never_narrower_than_its_own_level() -> void:
	var rules := _rules()
	for index: int in rules.levels():
		var slab := rules.slab_span(index)
		var own := rules.floor_span(index)
		assert_true(slab.x <= own.x and slab.y >= own.y, "этаж %d потерял свой пол" % index)


## Every slot of a level has a ceiling above it: a lamp is hung on the slab,
## and the level above lays it.
func test_every_slot_of_a_floor_has_a_ceiling_over_it() -> void:
	var rules := _rules()
	for index: int in rules.floors:
		var ceiling := rules.slab_span(index - 1)
		var span := rules.slot_range(index)
		for slot: int in range(span.x, span.y + 1):
			var x := rules.slot_x(slot)
			assert_true(
				x >= ceiling.x and x <= ceiling.y,
				"место %d этажа %d висит под открытым небом" % [slot, index]
			)


## Bounds are derived from the outermost slots: a slot must be exactly margin away from its
## wall, as on a full-width floor.
func test_floor_span_keeps_the_margin_from_its_own_walls() -> void:
	var rules := _rules()
	for index: int in [BuildingRules.ROOF, 0, 15, rules.floors - 1]:
		var span := rules.floor_span(index)
		var slots := rules.slot_range(index)
		assert_eq(rules.slot_x(slots.x) - span.x, rules.margin, "слева, этаж %d" % index)
		assert_eq(span.y - rules.slot_x(slots.y), rules.margin, "справа, этаж %d" % index)


## Slot symmetry rests on their odd count: an even set has no middle,
## the outermost column disappears on all levels at once, and the bottom floor stops being
## the full width of the building. The rule is written next to the field itself, and guarded here.
func test_slot_count_is_odd() -> void:
	var rules := _rules()
	assert_eq(rules.slots % 2, 1, "чётное число мест ломает симметрию силуэта")
	assert_eq(rules.top_slots % 2, 1, "и наверху тоже")


## The same rule, from the other side: with an odd set the bottom floor must
## reach the full width of the building, otherwise the silhouette does not reach the edge.
func test_the_bottom_floor_reaches_both_walls() -> void:
	var rules := _rules()
	var span := rules.floor_span(rules.floors - 1)
	assert_eq(span.x, 0.0, "левая стена нижнего этажа — край здания")
	assert_eq(span.y, rules.width, "и правая тоже")
