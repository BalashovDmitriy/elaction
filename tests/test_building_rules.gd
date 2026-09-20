extends GutTest

## Тесты правил здания.
##
## Отсюда берётся вся вертикальная арифметика: где поверхность этажа, какой этаж
## ближе к точке, где потолок. По ним же считается место возврата после смерти
## и геометрия затемняющей полосы. И злость агентов — она растёт из двух мест
## сразу, и потолок на ней держит игру проходимой.


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


func test_the_roof_lies_above_the_top_floor() -> void:
	var rules := _rules()
	assert_lt(rules.floor_surface(BuildingRules.ROOF), rules.floor_surface(0))
	assert_eq(
		rules.floor_surface(0) - rules.floor_surface(BuildingRules.ROOF),
		rules.floor_height,
		"крыша отстоит от верхнего этажа на целый пролёт"
	)


## Из-за этого нулевой этаж и был неиграбельным: просвет 20 px против 100 px
## у всех остальных, и макушка Otto уходила за верхний край кадра (ADR-0014).
func test_every_level_has_the_same_headroom() -> void:
	var rules := _rules()
	var expected := rules.floor_height - rules.slab_height
	for index: int in [0, 1, 7, rules.floors - 1]:
		var headroom := rules.floor_surface(index) - rules.story_top(index)
		assert_eq(headroom, expected, "этаж %d" % index)


func test_the_roof_has_sky_above_it() -> void:
	var rules := _rules()
	var roof := BuildingRules.ROOF
	assert_eq(rules.story_top(roof), 0.0, "над крышей край мира, а не перекрытие")
	assert_eq(rules.floor_surface(roof) - rules.story_top(roof), rules.sky_height)


## Прыжок Otto — 80 px. Если он не помещается над крышей, игрок улетает за кадр.
func test_a_jump_from_the_roof_stays_inside_the_world() -> void:
	var rules := _rules()
	var otto := preload("res://src/actors/otto/otto.tscn").instantiate() as Otto
	var apex := otto.jump_speed * otto.jump_speed / (2.0 * otto.gravity)
	otto.free()
	assert_gt(rules.sky_height, apex, "над крышей должно быть выше прыжка")


func test_floors_go_down_by_their_height() -> void:
	var rules := _rules()
	assert_eq(rules.floor_surface(1) - rules.floor_surface(0), rules.floor_height)


func test_nearest_floor_is_the_one_underfoot() -> void:
	var rules := _rules()
	assert_eq(rules.floor_index_near(rules.floor_surface(4)), 4)
	assert_eq(rules.floor_index_near(rules.floor_surface(4) + 10.0), 4, "чуть ниже — тот же")


func test_nearest_floor_never_leaves_the_building() -> void:
	var rules := _rules()
	assert_eq(rules.floor_index_near(-500.0), BuildingRules.ROOF, "выше крыши уровней нет")
	assert_eq(rules.floor_index_near(100000.0), rules.floors - 1)


func test_nearest_level_finds_the_roof() -> void:
	var rules := _rules()
	var roof := BuildingRules.ROOF
	assert_eq(rules.floor_index_near(rules.floor_surface(roof)), roof)
	assert_eq(rules.floor_index_near(rules.floor_surface(roof) + 10.0), roof, "чуть ниже — та же")


func test_ceiling_is_the_underside_of_the_slab_above() -> void:
	var rules := _rules()
	var expected := rules.floor_surface(0) + rules.slab_height
	assert_eq(rules.story_top(1), expected)


func test_slots_spread_between_the_margins() -> void:
	var rules := _rules()
	assert_eq(rules.slot_x(0), rules.margin, "первое место — у левого отступа")
	assert_eq(rules.slot_x(rules.slots - 1), rules.width - rules.margin)


func test_agents_get_meaner_building_by_building() -> void:
	var first := BuildingRules.for_building(1).agent_menace
	var second := BuildingRules.for_building(2).agent_menace
	assert_eq(first, 1.0, "первое здание — обычные агенты")
	assert_almost_eq(second - first, BuildingRules.MENACE_PER_BUILDING, 0.001)


func test_growth_by_building_leaves_room_for_the_alarm() -> void:
	var far := BuildingRules.for_building(100).agent_menace
	assert_eq(far, BuildingRules.MENACE_BY_BUILDING_CAP)
	assert_lt(
		far,
		BuildingRules.MENACE_CAP,
		"рост от зданий упирается ниже общего потолка, иначе сирене нечего добавить"
	)


## Потолок общий: пока он стоял только на росте от зданий, тревога множила уже
## обрезанное число и уводила дальность выстрела на 900 px при этаже в 1120 px.
func test_the_alarm_cannot_push_menace_past_the_cap() -> void:
	var rules := BuildingRules.for_building(100)
	assert_eq(rules.menace_with(1.5), BuildingRules.MENACE_CAP)
	assert_eq(rules.menace_with(100.0), BuildingRules.MENACE_CAP, "и никакая другая")


func test_the_alarm_still_bites_on_early_buildings() -> void:
	var rules := BuildingRules.for_building(1)
	assert_gt(rules.menace_with(1.5), rules.menace_with(1.0))


## Ноль из инспектора делил бы на себя задержку смены агента и запер бы дверь.
func test_menace_never_reaches_zero() -> void:
	var rules := BuildingRules.new()
	rules.agent_menace = 0.0
	assert_gt(rules.menace_with(1.0), 0.0)


## Числа боя лежат в правилах здания, а не в сцене агента: только так их можно
## растить от здания к зданию (ADR-0016, пункт 5).
func test_combat_numbers_hold_together() -> void:
	var rules := BuildingRules.new()
	assert_lt(rules.agent_dark_fire_range, rules.agent_fire_range, "в темноте агент замечает ближе")
	assert_lt(rules.agent_prone_height, rules.agent_kneel_height, "лёжа ниже, чем на колене")
	assert_lt(
		rules.agent_kneels_from_menace,
		rules.agent_goes_prone_from_menace,
		"сперва агент учится приседать и только потом ложиться"
	)
	assert_gt(rules.agent_dodge_sight, 0.0, "не видя пули, уклоняться не от чего")
	assert_gt(rules.agents_at_once, 0, "здание без агентов — не здание")


## Дальность агента не должна простреливать этаж насквозь: иначе подойти к нему
## нечем, и это ровно то, из-за чего в ADR-0006 пришлось заводить потолок злости.
##
## Считается по самому узкому этажу с дверями — верхнему: на широких нижних
## запас только больше.
func test_an_agent_cannot_cover_a_whole_floor() -> void:
	var rules := BuildingRules.new()
	assert_lt(
		rules.agent_fire_range,
		rules.floor_width(0) * 0.5,
		"даже на самом узком этаже есть куда встать вне огня"
	)


## Ради чего стоит потолок злости: даже у самого злого агента пуля летит
## дольше, чем игрок успевает нажать.
##
## Держит он теперь скорострельность и скорость пули, а не дальность (ADR-0016,
## пункт 1), и проверять его надо по ним. Время на ход считается по пуле:
## сколько она летит с дальнего края зоны огня. Пятая доля секунды — это уже
## не реакция, а лотерея.
func test_even_the_meanest_agent_leaves_time_to_react() -> void:
	var rules := BuildingRules.for_building(99)
	var menace := rules.menace_with(GreyboxLevel.ALARM_MENACE)
	assert_eq(menace, BuildingRules.MENACE_CAP, "к девяносто девятому зданию злее уже некуда")

	var flight := rules.agent_fire_range / (rules.agent_bullet_speed * menace)
	assert_gt(flight, 0.2, "пуля с дальнего края летит дольше человеческой реакции")
	assert_gt(rules.agent_aim_time, 0.0, "а первый выстрел не уходит в тот же кадр")
