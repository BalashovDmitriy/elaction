extends GutTest

## Тесты машины у выхода.
##
## В оригинале здание заканчивается тем, что Otto уезжает на красной машине
## (ADR-0011, пункт 14). Отсюда правило, которое легко потерять при правках:
## здание считается сданным **после** отъезда, а не в момент выхода. Иначе
## следующее здание соберётся поверх уезжающей машины, и кадра не будет.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

## Сколько кадров дать зданию собраться и сколько ждать отъезда.
const SETTLE_FRAMES: int = 5
const PATIENCE: int = 240

## Допуск на положение машины, м: полсантиметра. Машина стоит колёсами ровно на
## полу и ровно в зазоре от проёма; широкий допуск пропускал бы и машину,
## утонувшую в перекрытии по крышу.
const TOLERANCE: float = 0.005


func before_each() -> void:
	GameState.instance().start_game()


func after_each() -> void:
	GameState.instance().start_game()


func _building() -> GreyboxLevel:
	var rules := BuildingRules.new()
	rules.floors = 4
	# Без красных дверей здание сдано сразу, как только Otto дошёл до выхода:
	# документы здесь не проверяются, проверяется машина.
	rules.documents = 0

	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = rules
	level.building_seed = 1
	level.spawn_agents = false
	add_child_autofree(level)
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	return level


## Машина у выхода — модель под своим именем среди детей уровня.
func _car_of(level: GreyboxLevel) -> Node3D:
	return level.get_node_or_null("ExitCar") as Node3D


func test_the_exit_has_a_car() -> void:
	var level := await _building()
	var car := _car_of(level)
	assert_not_null(car, "у выхода стоит машина")
	if car == null:
		return

	# Числа берутся у здания, а не выписываются в тест. Машина стоит в сцене, а
	# выход задан в плоскости правил — сравниваем в плоскости правил.
	var exit_at := level.exit_position()
	var surface := exit_at.y + GreyboxLevel.EXIT_HEIGHT * 0.5
	var at := WorldSpace.to_plane(car.global_position)
	assert_almost_eq(at.y, surface, TOLERANCE, "колёсами на полу")

	var gap := GreyboxLevel.EXIT_WIDTH * 0.5 + GreyboxLevel.CAR_GAP + GreyboxLevel.CAR_LENGTH * 0.5
	assert_almost_eq(
		absf(at.x - exit_at.x), gap, TOLERANCE, "машина стоит в зазоре от проёма, а не в нём"
	)


func test_the_building_is_cleared_only_after_the_car_leaves() -> void:
	var level := await _building()
	var car := _car_of(level)
	assert_not_null(car)
	if car == null:
		return

	var cleared := [false]
	level.building_cleared.connect(func() -> void: cleared[0] = true)

	var parked_at := car.position.x
	level.otto.global_position = WorldSpace.to_scene(level.exit_position())
	# Ждём не выдержку, а состояние: зона выхода замечает тело на своём шаге
	# физики, и ждать «один кадр» здесь — та же ошибка, что водить съёмку
	# секундомером (docs/testing.md).
	var started := 0
	while is_equal_approx(car.position.x, parked_at) and started < SETTLE_FRAMES * 6:
		await get_tree().physics_frame
		started += 1

	assert_ne(car.position.x, parked_at, "машина поехала")
	assert_false(cleared[0], "выход ещё не конец: машина только тронулась")

	var waited := 0
	while not cleared[0] and waited < PATIENCE:
		await get_tree().process_frame
		waited += 1
	assert_true(cleared[0], "здание сдано, когда машина уехала")
