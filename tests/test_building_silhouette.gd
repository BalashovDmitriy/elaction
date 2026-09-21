extends GutTest

## Тесты силуэта здания: сколько мест на уровне и где его стены.
##
## Здание расширяется книзу ступенями, и на этом держится всё остальное: шахта
## проходит сквозь этажи разной ширины и должна стоять на месте, которое есть на
## каждом из них. Считается всё по правилам, без сцены (ADR-0014, пункт 3).


func _rules() -> BuildingRules:
	var rules := BuildingRules.new()
	rules.floors = 30
	# Здание теста — свой маленький мир в целых числах, и задаётся он целиком:
	# все длины, от которых зависят проверки ниже. Пока часть бралась из
	# умолчаний, тест держался на том, что 480 и 3840 точны в любом float; с
	# M15 умолчания метрические — 4.8 и 38.4, — и точные равенства поплыли на
	# последнем бите дроби ([Vector2] к тому же хранит float32).
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


## Силуэт: наверху узко, внизу вся ширина. Ступени идут только вниз — на этом
## держится шахта, которая проходит сквозь этажи разной ширины (ADR-0014).
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


## Верхние этажи влезают в кадр целиком, нижние — шире экрана (ADR-0024,
## решение 2). Башню видно всю, а по стилобату надо ходить.
##
## Правила берутся умолчаниями, а не миром теста: ширина кадра метрическая, и
## сверять её надо с тем зданием, которое собирается в игре.
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


## Ширина кадра ортокамеры, м. Половину высоты задаёт камера, ширину — из неё
## и соотношения сторон вьюпорта проекта: считать по окну в headless нельзя,
## его там нет.
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


## Места симметричны относительно середины: несимметричный этаж уводил бы
## шахту, проходящую сквозь него, в сторону от собственного столбца.
func test_slots_stay_centred_on_every_level() -> void:
	var rules := _rules()
	var middle := rules.slots - 1
	for index: int in rules.levels():
		var span := rules.slot_range(index)
		assert_eq(span.x + span.y, middle, "этаж %d сдвинут вбок" % index)


## На самом узком этаже должно помещаться обязательное: шахта, его двери и его
## лампы. Двери и лампы считаются по ширине — узкий этаж заселён скупо.
##
## Самый узкий этаж — нулевой, и мерится именно его ширина. Крыша уже, но на
## ней нет ни дверей, ни ламп: мерить её шириной занятость этажа значило бы
## сравнивать два разных уровня и проходить по случайному совпадению их ступени.
func test_the_narrowest_level_fits_everything_it_must_hold() -> void:
	var rules := _rules()
	var needed := 1 + rules.doors_on(0) + rules.lamps_on(0)
	var span := rules.slot_range(0)
	assert_true(span.y - span.x + 1 >= needed, "мест меньше, чем надо поставить")
	assert_eq(rules.lamps_on(BuildingRules.ROOF), 0, "а крыше ставить нечего")


func test_slots_outside_the_silhouette_are_not_available() -> void:
	var rules := _rules()
	assert_false(rules.slot_available(0, BuildingRules.ROOF), "край здания наверху — улица")
	assert_true(rules.slot_available(0, rules.floors - 1), "внизу то же место — этаж")


## Перекрытие — и пол своего уровня, и потолок нижнего. На ступени силуэта
## нижний этаж шире, и без этого над его наружной полосой было бы открытое небо,
## а лампа на крайнем месте висела бы не на чем.
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


## Ниже собственных стен перекрытие не сужается: оно остаётся полом своего уровня.
func test_a_slab_is_never_narrower_than_its_own_level() -> void:
	var rules := _rules()
	for index: int in rules.levels():
		var slab := rules.slab_span(index)
		var own := rules.floor_span(index)
		assert_true(slab.x <= own.x and slab.y >= own.y, "этаж %d потерял свой пол" % index)


## Каждое место уровня имеет над собой потолок: лампа вешается на перекрытие,
## а его кладёт уровень выше.
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


## Границы выводятся из крайних мест: место должно отстоять от своей стены
## ровно на margin, как и на этаже во всю ширину.
func test_floor_span_keeps_the_margin_from_its_own_walls() -> void:
	var rules := _rules()
	for index: int in [BuildingRules.ROOF, 0, 15, rules.floors - 1]:
		var span := rules.floor_span(index)
		var slots := rules.slot_range(index)
		assert_eq(rules.slot_x(slots.x) - span.x, rules.margin, "слева, этаж %d" % index)
		assert_eq(span.y - rules.slot_x(slots.y), rules.margin, "справа, этаж %d" % index)


## Симметрия мест держится на нечётном их числе: у чётного набора середины нет,
## крайний столбец пропадает на всех уровнях разом, а нижний этаж перестаёт быть
## во всю ширину здания. Правило записано у самого поля, а стережётся здесь.
func test_slot_count_is_odd() -> void:
	var rules := _rules()
	assert_eq(rules.slots % 2, 1, "чётное число мест ломает симметрию силуэта")
	assert_eq(rules.top_slots % 2, 1, "и наверху тоже")


## То же правило, но с обратной стороны: на нечётном наборе нижний этаж обязан
## выходить на полную ширину здания, иначе силуэт не доходит до края.
func test_the_bottom_floor_reaches_both_walls() -> void:
	var rules := _rules()
	var span := rules.floor_span(rules.floors - 1)
	assert_eq(span.x, 0.0, "левая стена нижнего этажа — край здания")
	assert_eq(span.y, rules.width, "и правая тоже")
