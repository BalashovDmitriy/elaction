extends GutTest

## Тесты правил посещения двери.
##
## Ход визита — как в ROM (ADR-0038, решение 2): створка открывается, гость уходит
## внутрь, она закрывается за ним, ровно через 70 тиков от стука он снаружи.
## Раньше не выйти ничем: ввода у [method DoorVisit.tick] нет вовсе, и узел
## двери проверяется на это отдельно, в [code]test_red_door.gd[/code].
##
## «Взвод» входа не прихоть: зажатый «вверх» после выхода втягивал бы гостя
## обратно без конца. Это нашло авторевью M3.
##
## Створку ведёт [DoorCycle], и здесь она идёт рядом — ровно так, как их сводит
## узел двери: визит только говорит, когда ей пора пойти (ADR-0020, решение 1).

const STEP: float = 1.0 / 60.0
const LEAF_TIME: float = 0.25
const HELD_UP: float = -1.0
const RELEASED: float = 0.0


func _visit() -> DoorVisit:
	var visit := DoorVisit.new()
	visit.leaf_time = LEAF_TIME
	return visit


## Створка, как её ведёт узел двери у гостя.
func _cycle() -> DoorCycle:
	var cycle := DoorCycle.new()
	cycle.travel_time = LEAF_TIME
	return cycle


## Один кадр двери с гостем: створка, затем визит, и створка исполняет подсказку.
func _frame(visit: DoorVisit, cycle: DoorCycle) -> DoorVisit.Cue:
	cycle.tick(STEP)
	var cue := visit.tick(STEP, cycle.is_open())
	match cue:
		DoorVisit.Cue.HIDE:
			cycle.close()
		DoorVisit.Cue.LET_OUT:
			cycle.open()
	return cue


## Впускает гостя, как это делает узел двери: стук открывает створку.
func _admitted() -> Array:
	var visit := _visit()
	var cycle := _cycle()
	visit.admit()
	cycle.open()
	return [visit, cycle]


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


func test_the_time_inside_is_seventy_rom_ticks() -> void:
	assert_eq(Arcade.ROOM_TICKS, 70, "$82ED = $46 (@2A5B)")
	assert_almost_eq(DoorVisit.new().hide_time, 4.73, 0.01, "70 тиков — 4,73 с")


func test_the_guest_hides_only_once_the_leaf_is_open() -> void:
	var pair := _admitted()
	var visit: DoorVisit = pair[0]
	var cycle: DoorCycle = pair[1]
	var hid_at := -1.0
	for frame: int in 120:
		if _frame(visit, cycle) == DoorVisit.Cue.HIDE:
			hid_at = float(frame + 1) * STEP
			break
		assert_false(visit.is_hiding(), "пока створка идёт, гость ещё на виду")
	assert_almost_eq(hid_at, LEAF_TIME, STEP * 1.5, "прячется, когда створка открылась")
	assert_true(visit.is_hiding())


func test_the_leaf_is_shut_while_the_guest_is_inside() -> void:
	var pair := _admitted()
	var visit: DoorVisit = pair[0]
	var cycle: DoorCycle = pair[1]
	var shut_frames := 0
	var hiding_frames := 0
	while visit.elapsed() < visit.hide_time - LEAF_TIME - STEP:
		_frame(visit, cycle)
		if not visit.is_hiding():
			continue
		hiding_frames += 1
		if cycle.is_shut():
			shut_frames += 1
	# Прячется он через ход створки, ещё ход она закрывается — дальше закрыта.
	var expected := visit.hide_time - LEAF_TIME * 3.0
	assert_gt(float(shut_frames) * STEP, expected - STEP * 3.0, "за ним створка закрыта")
	assert_gt(hiding_frames, shut_frames, "а сперва закрывается у него за спиной")


func test_the_leaf_opens_to_let_him_out_and_he_is_out_exactly_on_time() -> void:
	var pair := _admitted()
	var visit: DoorVisit = pair[0]
	var cycle: DoorCycle = pair[1]
	var let_out_at := -1.0
	var out_at := -1.0
	for _frame_index: int in 600:
		var cue := _frame(visit, cycle)
		if cue == DoorVisit.Cue.LET_OUT:
			let_out_at = visit.elapsed()
		if cue == DoorVisit.Cue.OUT:
			out_at = visit.elapsed()
			assert_true(cycle.is_open(), "выходят в открытую створку")
			break
	assert_almost_eq(let_out_at, visit.hide_time - LEAF_TIME, STEP * 1.5, "открывают заранее")
	assert_almost_eq(out_at, Arcade.seconds(Arcade.ROOM_TICKS), STEP * 1.5, "ровно 70 тиков")


func test_the_guest_waits_for_a_leaf_that_is_late() -> void:
	var visit := _visit()
	visit.admit()
	# Створка стоит закрытой: ни спрятаться, ни выйти, сколько бы ни прошло.
	for _frame_index: int in 600:
		assert_ne(visit.tick(STEP, false), DoorVisit.Cue.OUT, "сквозь закрытую не выходят")
	assert_false(visit.is_hiding(), "и не прячутся")


func test_nothing_happens_without_a_guest() -> void:
	var visit := _visit()
	for _frame_index: int in 600:
		assert_eq(visit.tick(STEP, true), DoorVisit.Cue.NONE)
