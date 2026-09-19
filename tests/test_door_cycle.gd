extends GutTest

## Тесты хода створки.
##
## Створка — это то, что игрок видит вместо правил: по ней он и понимает, что
## сейчас из двери кто-то выйдет. Поэтому ход проверяется отдельно от того, кто
## дверь открыл (ADR-0020, решение 1).

const STEP: float = 0.1
const TRAVEL: float = 0.4


func _cycle() -> DoorCycle:
	var cycle := DoorCycle.new()
	cycle.travel_time = TRAVEL
	return cycle


## Гонит створку заданное время и отдаёт её же.
func _run(cycle: DoorCycle, seconds: float) -> DoorCycle:
	for _frame: int in int(roundf(seconds / STEP)):
		cycle.tick(STEP)
	return cycle


func test_a_fresh_door_is_shut() -> void:
	var cycle := _cycle()
	assert_true(cycle.is_shut())
	assert_false(cycle.is_open())
	assert_eq(cycle.openness(), 0.0)


func test_a_door_left_alone_does_not_move() -> void:
	assert_true(_run(_cycle(), 5.0).is_shut(), "никто не просил — никто и не открывал")


func test_the_door_needs_its_whole_travel_time() -> void:
	var cycle := _cycle()
	cycle.open()
	assert_false(_run(cycle, TRAVEL * 0.5).is_open(), "на полпути дверь ещё не открыта")
	assert_true(_run(cycle, TRAVEL * 0.5).is_open(), "к концу хода — открыта")


func test_openness_grows_with_the_travel() -> void:
	var cycle := _cycle()
	cycle.open()
	var half := _run(cycle, TRAVEL * 0.5).openness()
	assert_almost_eq(half, 0.5, 0.001, "ход считается долей времени")
	assert_almost_eq(_run(cycle, TRAVEL).openness(), 1.0, 0.001, "дальше настежь не бывает")


func test_a_closing_door_comes_back_to_shut() -> void:
	var cycle := _cycle()
	cycle.open()
	_run(cycle, TRAVEL)
	cycle.close()
	assert_false(_run(cycle, TRAVEL * 0.5).is_shut(), "на полпути обратно ещё не закрыта")
	assert_true(_run(cycle, TRAVEL * 0.5).is_shut())
	assert_eq(cycle.openness(), 0.0)


func test_closing_starts_from_where_the_door_stood() -> void:
	var cycle := _cycle()
	cycle.open()
	_run(cycle, TRAVEL * 0.5)
	cycle.close()
	# Половину хода прошла — столько же и возвращается, а не весь путь заново.
	assert_true(_run(cycle, TRAVEL * 0.5).is_shut(), "закрывается ровно с того места")


func test_opening_an_open_door_changes_nothing() -> void:
	var cycle := _cycle()
	cycle.open()
	_run(cycle, TRAVEL)
	cycle.open()
	assert_true(cycle.is_open(), "открытая дверь не начинает открываться заново")
	assert_eq(cycle.openness(), 1.0)


func test_closing_a_shut_door_changes_nothing() -> void:
	var cycle := _cycle()
	cycle.close()
	assert_true(cycle.is_shut())
	assert_eq(cycle.openness(), 0.0, "закрытой некуда закрываться")


func test_a_door_can_turn_back_before_it_opened() -> void:
	var cycle := _cycle()
	cycle.open()
	_run(cycle, TRAVEL * 0.5)
	cycle.close()
	_run(cycle, TRAVEL * 0.25)
	cycle.open()
	assert_true(_run(cycle, TRAVEL).is_open(), "передумала на полпути — всё равно дойдёт")


func test_a_door_without_travel_time_is_instant() -> void:
	var cycle := DoorCycle.new()
	cycle.travel_time = 0.0
	cycle.open()
	cycle.tick(STEP)
	assert_true(cycle.is_open(), "нулевое время хода — мгновенная дверь, а не деление на ноль")
