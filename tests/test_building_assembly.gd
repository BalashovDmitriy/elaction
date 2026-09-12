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
		await wait_physics_frames(SETTLE_FRAMES)
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


func test_otto_starts_on_the_roof() -> void:
	var rules := _rules()
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)
	assert_eq(rules.floor_index_near(level.otto.global_position.y), 0, "Otto начинает с крыши")
