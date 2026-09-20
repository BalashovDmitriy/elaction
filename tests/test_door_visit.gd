extends GutTest

## Тесты правил посещения двери.
##
## Оба «взвода» здесь не прихоть: зажатая кнопка, которой Otto пришёл к двери,
## иначе выталкивала бы его сразу, а зажатый «вверх» после выхода втягивал бы
## обратно без конца. Второе нашло авторевью M3.
##
## Створку ведёт [DoorCycle], и здесь она идёт рядом — ровно так, как их сводит
## узел двери. Иначе «пока открывается, наружу не просятся» проверять не на чем:
## сам [DoorVisit] про створку больше ничего не знает (ADR-0020, решение 1).

const STEP: float = 0.1
const OPEN_TIME: float = 0.2
const HELD_UP: float = -1.0
const RELEASED: float = 0.0


func _visit() -> DoorVisit:
	var visit := DoorVisit.new()
	visit.hide_time = 1.0
	return visit


## Створка, которую только что попросили открыться.
func _cycle() -> DoorCycle:
	var cycle := DoorCycle.new()
	cycle.travel_time = OPEN_TIME
	cycle.open()
	return cycle


## Прогоняет кадры с гостем внутри и возвращает, выпустили ли его.
func _run(visit: DoorVisit, cycle: DoorCycle, seconds: float, horizontal: float) -> bool:
	for _frame: int in int(roundf(seconds / STEP)):
		cycle.tick(STEP)
		if visit.tick(STEP, horizontal, cycle.is_open()):
			return true
	return false


func test_up_on_the_mat_opens_the_door() -> void:
	assert_true(_visit().knock(true, HELD_UP))


func test_without_up_nobody_enters() -> void:
	assert_false(_visit().knock(true, RELEASED))


func test_jumping_past_the_door_does_not_enter_it() -> void:
	assert_false(_visit().knock(false, HELD_UP), "в прыжке в дверь не заходят")


func test_held_up_does_not_pull_back_after_release() -> void:
	var visit := _visit()
	visit.admit()
	visit.release()
	assert_false(visit.knock(true, HELD_UP), "кнопку надо отпустить и нажать заново")
	visit.knock(true, RELEASED)
	assert_true(visit.knock(true, HELD_UP))


func test_the_guest_is_not_let_out_while_the_door_is_still_opening() -> void:
	var visit := _visit()
	visit.admit()
	# Времени хватило бы и на открывание, и на всю отсидку, но створка стоит.
	for _frame: int in 40:
		assert_false(visit.tick(STEP, RELEASED, false), "закрытая дверь никого не выпускает")


func test_the_hiding_time_starts_only_once_the_door_is_open() -> void:
	var visit := _visit()
	var cycle := _cycle()
	visit.admit()
	# 0.3 с: 0.2 уходит на створку, и на отсидку остаётся всего 0.1 из 1.0.
	assert_false(_run(visit, cycle, 0.3, RELEASED), "за время открывания не выпускают")
	assert_true(cycle.is_open(), "к этому моменту створка уже открыта")
	assert_false(_run(visit, cycle, 0.8, RELEASED), "отсидка отсчитывается от открытия")
	assert_true(_run(visit, cycle, 0.3, RELEASED), "и дальше время выходит")


func test_guest_is_put_out_when_the_time_is_up() -> void:
	var visit := _visit()
	visit.admit()
	assert_true(_run(visit, _cycle(), 2.0, RELEASED), "через отведённое время выставляют сами")


func test_the_key_that_brought_him_in_does_not_throw_him_out() -> void:
	var visit := _visit()
	visit.admit()
	# «Влево» держат с самого прихода к двери и не отпускали.
	assert_false(_run(visit, _cycle(), 0.9, -1.0), "зажатое направление выходом не считается")


func test_fresh_press_lets_the_guest_out_early() -> void:
	var visit := _visit()
	var cycle := _cycle()
	visit.admit()
	_run(visit, cycle, 0.4, RELEASED)
	assert_true(visit.tick(STEP, -1.0, cycle.is_open()), "отпустил и нажал — вышел")


func test_press_during_opening_counts_as_released_later() -> void:
	var visit := _visit()
	var cycle := _cycle()
	visit.admit()
	# Отпустил, пока створка открывалась: выход должен взвестись и тут.
	visit.tick(STEP, RELEASED, false)
	assert_true(_run(visit, cycle, 0.5, -1.0), "взвод работает и во время открывания")
