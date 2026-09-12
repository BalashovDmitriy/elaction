extends GutTest

## Тесты правил посещения двери.
##
## Оба «взвода» здесь не прихоть: зажатая кнопка, которой Otto пришёл к двери,
## иначе выталкивала бы его сразу, а зажатый «вверх» после выхода втягивал бы
## обратно без конца. Второе нашло авторевью M3.

const STEP: float = 0.1
const HELD_UP: float = -1.0
const RELEASED: float = 0.0


func _visit() -> DoorVisit:
	var visit := DoorVisit.new()
	visit.open_time = 0.2
	visit.hide_time = 1.0
	return visit


## Прогоняет кадры с гостем внутри и возвращает, выпустили ли его.
func _run(visit: DoorVisit, seconds: float, horizontal: float) -> bool:
	for _frame: int in int(roundf(seconds / STEP)):
		if visit.tick(STEP, horizontal):
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


func test_door_opens_before_the_guest_can_leave() -> void:
	var visit := _visit()
	visit.admit()
	assert_eq(visit.phase, DoorVisit.Phase.OPENING)
	assert_false(_run(visit, 0.3, RELEASED), "за время открывания не выпускают")
	assert_eq(visit.phase, DoorVisit.Phase.OPEN)


func test_guest_is_put_out_when_the_time_is_up() -> void:
	var visit := _visit()
	visit.admit()
	assert_true(_run(visit, 2.0, RELEASED), "через отведённое время выставляют сами")


func test_the_key_that_brought_him_in_does_not_throw_him_out() -> void:
	var visit := _visit()
	visit.admit()
	# «Влево» держат с самого прихода к двери и не отпускали.
	assert_false(_run(visit, 0.9, -1.0), "зажатое направление выходом не считается")


func test_fresh_press_lets_the_guest_out_early() -> void:
	var visit := _visit()
	visit.admit()
	_run(visit, 0.4, RELEASED)
	assert_true(visit.tick(STEP, -1.0), "отпустил и нажал — вышел")


func test_press_during_opening_counts_as_released_later() -> void:
	var visit := _visit()
	visit.admit()
	# Отпустил, пока створка открывалась: выход должен взвестись и тут.
	visit.tick(STEP, RELEASED)
	assert_true(_run(visit, 0.5, -1.0), "взвод работает и во время открывания")
