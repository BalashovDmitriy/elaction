extends GutTest

## Тесты силуэта здания: сколько мест на уровне и где его стены.
##
## Здание расширяется книзу ступенями, и на этом держится всё остальное: шахта
## проходит сквозь этажи разной ширины и должна стоять на месте, которое есть на
## каждом из них. Считается всё по правилам, без сцены (ADR-0014, пункт 3).


func _rules() -> BuildingRules:
	var rules := BuildingRules.new()
	rules.floors = 30
	rules.floor_height = 120.0
	rules.slab_height = 20.0
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


## На самом узком уровне должно помещаться обязательное: шахта, двери и лампа.
func test_the_narrowest_level_fits_everything_it_must_hold() -> void:
	var rules := _rules()
	var needed := 1 + rules.doors_per_floor + rules.lamps_per_floor
	var span := rules.slot_range(BuildingRules.ROOF)
	assert_true(span.y - span.x + 1 >= needed, "мест меньше, чем надо поставить")


func test_slots_outside_the_silhouette_are_not_available() -> void:
	var rules := _rules()
	assert_false(rules.slot_available(0, BuildingRules.ROOF), "край здания наверху — улица")
	assert_true(rules.slot_available(0, rules.floors - 1), "внизу то же место — этаж")


## Границы выводятся из крайних мест: место должно отстоять от своей стены
## ровно на margin, как и на этаже во всю ширину.
func test_floor_span_keeps_the_margin_from_its_own_walls() -> void:
	var rules := _rules()
	for index: int in [BuildingRules.ROOF, 0, 15, rules.floors - 1]:
		var span := rules.floor_span(index)
		var slots := rules.slot_range(index)
		assert_eq(rules.slot_x(slots.x) - span.x, rules.margin, "слева, этаж %d" % index)
		assert_eq(span.y - rules.slot_x(slots.y), rules.margin, "справа, этаж %d" % index)
