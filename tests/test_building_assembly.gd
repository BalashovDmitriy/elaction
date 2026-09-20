extends GutTest

## Дымовой тест сборки здания.
##
## Между «раскладка говорит: шахта на 12–17» и «кабина действительно стоит там»
## лежит код уровня, который не проверялся ничем. Здесь здание собирается
## по-настоящему, с физикой, и сверяется с собственной раскладкой.
##
## Здание маленькое: генератор тот же, а прогон короче.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const SEEDS: Array[int] = [1, 2, 3]

## Сколько кадров дать зданию устояться перед проверками.
const SETTLE_FRAMES: int = 10

## Сколько кадров ждать конца вступления: спуск по тросу занимает меньше секунды.
const LANDING_FRAMES: int = 180

## Сколько источников света разрешено держать зажжёнными разом.
##
## Число художественное, а не техническое: замер (ADR-0010, пункт 1) показал,
## что железо выдерживает вчетверо больше, но дюжина пятен света в кадре — это
## уже каша. Проверяется на здании в полный рост: на нём отбор и нужен.
const LIGHT_BUDGET: int = 12

## Сколько кадров ждать падения лампы. Ограничение есть намеренно: ожидание
## несбывшегося состояния иначе тянулось бы до конца прогона.
const FALL_FRAMES: int = 240


func _rules() -> BuildingRules:
	var rules := BuildingRules.new()
	rules.floors = 8
	rules.documents = 2
	return rules


func _build(building_seed: int) -> GreyboxLevel:
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = _rules()
	level.building_seed = building_seed
	add_child_autofree(level)
	return level


## Убирает здание из дерева сразу, не дожидаясь конца теста.
##
## [method GutTest.add_child_autofree] освобождает только после всего теста, а сиды
## перебираются внутри одного: без этого здания стоят друг в друге в одном
## физическом мире, со своими Otto и своими агентами. Освободит их всё равно GUT.
func _drop(level: GreyboxLevel) -> void:
	remove_child(level)


func _count(level: GreyboxLevel, type: Variant) -> int:
	var found := 0
	for child in level.get_children():
		if is_instance_of(child, type):
			found += 1
	return found


func test_every_seed_assembles_and_holds_otto() -> void:
	for building_seed: int in SEEDS:
		var level := _build(building_seed)
		await _wait_for_the_landing(level)
		assert_true(
			level.otto.is_grounded(),
			"сид %d: Otto не стоит на полу — провалился сквозь геометрию" % building_seed
		)
		assert_false(level.otto.is_dead(), "сид %d: Otto погиб на старте" % building_seed)
		_drop(level)


func test_scene_matches_the_plan() -> void:
	var rules := _rules()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		var level := _build(building_seed)
		await wait_physics_frames(SETTLE_FRAMES)

		assert_eq(
			_count(level, ElevatorCar),
			plan.shafts.size(),
			"сид %d: кабин не столько, сколько шахт" % building_seed
		)
		assert_eq(_count(level, Door), plan.doors.size(), "сид %d: дверей" % building_seed)
		assert_eq(_count(level, Escalator), plan.escalators.size(), "сид %d" % building_seed)
		_drop(level)


## Сколько источников горит прямо сейчас — по всему дереву уровня, не только
## среди прямых детей: свет лампы висит ребёнком самой лампы, и счёт по детям
## уровня его не видел бы вовсе — проверка проходила бы, даже если бы не гасла
## ни одна лампа в здании.
func _lit(level: GreyboxLevel) -> int:
	var count := 0
	for node: Node in level.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if light != null and light.is_visible_in_tree():
			count += 1
	return count


## Здание в полный рост: правила по умолчанию, тридцать этажей.
func _tall(building_seed: int) -> GreyboxLevel:
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.building_seed = building_seed
	level.spawn_agents = false
	add_child_autofree(level)
	return level


## Ближайшая лампа под Otto.
##
## Именно ближайшая, а не первая попавшаяся: этаж под ногами всегда в кадре,
## а значит, и свет на нём горит. Лампа с произвольного этажа могла бы оказаться
## за пределами отбора, где её этаж и так погашен, — и «источников стало меньше»
## не выполнилось бы, хотя гасить нечего.
func _nearest_lamp_below(level: GreyboxLevel) -> Lamp:
	# «Ниже» — в плоскости правил, где вниз это рост Y.
	var otto_y := WorldSpace.to_plane(level.otto.global_position).y
	var found: Lamp = null
	var found_y := INF
	for child in level.get_children():
		var lamp := child as Lamp
		if lamp == null:
			continue
		var lamp_y := WorldSpace.to_plane(lamp.global_position).y
		if lamp_y <= otto_y:
			continue
		if lamp_y < found_y:
			found = lamp
			found_y = lamp_y
	return found


## Источников в здании шестьдесят с лишним, а гореть должна горстка.
func test_a_tall_building_lights_only_what_is_in_frame() -> void:
	for building_seed: int in SEEDS:
		var level := _tall(building_seed)
		await wait_physics_frames(SETTLE_FRAMES)

		var burning := _lit(level)
		assert_gt(burning, 0, "сид %d: свет вообще не зажёгся" % building_seed)
		assert_lte(
			burning,
			LIGHT_BUDGET,
			"сид %d: горит %d источников при бюджете %d" % [building_seed, burning, LIGHT_BUDGET]
		)
		_drop(level)


## Тот же путь, что в игре: пуля сбивает лампу, лампа долетает — этаж гаснет.
## Проверяется не флаг, а погасший источник: флаг без света ничего не значит.
func test_a_fallen_lamp_puts_its_floor_out() -> void:
	var level := _tall(1)
	await wait_physics_frames(SETTLE_FRAMES)

	var lamp := _nearest_lamp_below(level)
	assert_not_null(lamp, "в здании должна быть лампа ниже Otto")
	if lamp == null:
		return

	var index := lamp.floor_index
	assert_false(level.is_dark(index), "до выстрела этаж горит")
	var before := _lit(level)

	lamp.shoot_down()
	var left := FALL_FRAMES
	while is_instance_valid(lamp) and left > 0:
		left -= 1
		await wait_physics_frames(1)
	assert_false(is_instance_valid(lamp), "лампа долетела до пола")

	await wait_physics_frames(2)
	assert_true(level.is_dark(index), "этаж %d погас" % index)
	# Источник у этажа один — лампа (ADR-0021, решение 4), и он уходит вместе с
	# ней: «этаж горит» и «лампа висит» — с M15 одно и то же.
	assert_eq(_lit(level), before - 1, "и источник этажа перестал гореть")
	_drop(level)


func test_otto_starts_on_the_roof() -> void:
	var rules := _rules()
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)
	assert_eq(
		rules.floor_index_near(WorldSpace.to_plane(level.otto.global_position).y),
		BuildingRules.ROOF,
		"Otto начинает с крыши, а не с верхнего этажа"
	)


## Ждёт, пока Otto съедет по тросу на крышу.
##
## Здание с M12 начинается вступлением: Otto приезжает сверху, и первые полсекунды
## он не на полу и не слушается ввода (ADR-0017, решение 4). Ждать его надо по
## состоянию, а не выдержкой: под [member Engine.time_scale] выдержка врёт.
func _wait_for_the_landing(level: GreyboxLevel) -> void:
	var left := LANDING_FRAMES
	while not level.otto.is_grounded() and left > 0:
		await wait_physics_frames(1)
		left -= 1
	assert_true(level.otto.is_grounded(), "Otto съехал по тросу и встал на крышу")
