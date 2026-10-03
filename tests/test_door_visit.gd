extends GutTest

## Tests of the door visit rules.
##
## The visit goes as in the ROM (ADR-0038, decision 2): the leaf opens, the guest goes inside, it
## closes behind him, exactly 70 ticks after the knock he is outside. There is no way to leave
## earlier: [method DoorVisit.tick] has no input at all, and the door node is checked for this
## separately, in [code]test_red_door.gd[/code].
##
## The "arming" of entry is not a whim: "up" held after exit would pull the guest back in endlessly.
## The M3 code review found this.
##
## The leaf is driven by [DoorCycle], and here it runs alongside — exactly as the door node brings
## them together: the visit only says when it is time for the leaf to move (ADR-0020, decision 1).

const STEP: float = 1.0 / 60.0
const LEAF_TIME: float = 0.25
const HELD_UP: float = -1.0
const RELEASED: float = 0.0


func _visit() -> DoorVisit:
	var visit := DoorVisit.new()
	visit.leaf_time = LEAF_TIME
	return visit


## The leaf, as the door node drives it for a guest.
func _cycle() -> DoorCycle:
	var cycle := DoorCycle.new()
	cycle.travel_time = LEAF_TIME
	return cycle


## One door frame with a guest: the leaf, then the visit, and the leaf carries out the hint.
func _frame(visit: DoorVisit, cycle: DoorCycle) -> DoorVisit.Cue:
	cycle.tick(STEP)
	var cue := visit.tick(STEP, cycle.is_open())
	match cue:
		DoorVisit.Cue.HIDE:
			cycle.close()
		DoorVisit.Cue.LET_OUT:
			cycle.open()
	return cue


## Lets the guest in, as the door node does: the knock opens the leaf.
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
	assert_false(_visit().knock(false, HELD_UP), "nobody enters a door mid-jump")


func test_held_up_does_not_pull_back_after_release() -> void:
	var visit := _visit()
	visit.admit()
	visit.release()
	assert_false(visit.knock(true, HELD_UP), "the button must be released and pressed again")
	visit.knock(true, RELEASED)
	assert_true(visit.knock(true, HELD_UP))


func test_the_time_inside_is_seventy_rom_ticks() -> void:
	assert_eq(Arcade.ROOM_TICKS, 70, "$82ED = $46 (@2A5B)")
	assert_almost_eq(DoorVisit.new().hide_time, 4.73, 0.01, "70 ticks — 4.73 s")


func test_the_guest_hides_only_once_the_leaf_is_open() -> void:
	var pair := _admitted()
	var visit: DoorVisit = pair[0]
	var cycle: DoorCycle = pair[1]
	var hid_at := -1.0
	for frame: int in 120:
		if _frame(visit, cycle) == DoorVisit.Cue.HIDE:
			hid_at = float(frame + 1) * STEP
			break
		assert_false(visit.is_hiding(), "while the leaf moves, the guest is still in view")
	assert_almost_eq(hid_at, LEAF_TIME, STEP * 1.5, "hides when the leaf has opened")
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
	# He hides after one leaf movement, after another one it closes — from then on it is closed.
	var expected := visit.hide_time - LEAF_TIME * 3.0
	assert_gt(float(shut_frames) * STEP, expected - STEP * 3.0, "the leaf is closed behind him")
	assert_gt(hiding_frames, shut_frames, "and at first it closes behind his back")


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
			assert_true(cycle.is_open(), "they come out into an open leaf")
			break
	assert_almost_eq(let_out_at, visit.hide_time - LEAF_TIME, STEP * 1.5, "opened in advance")
	assert_almost_eq(out_at, Arcade.seconds(Arcade.ROOM_TICKS), STEP * 1.5, "exactly 70 ticks")


func test_the_guest_waits_for_a_leaf_that_is_late() -> void:
	var visit := _visit()
	visit.admit()
	# The leaf stays closed: neither hiding nor leaving, however much time passes.
	for _frame_index: int in 600:
		assert_ne(
			visit.tick(STEP, false), DoorVisit.Cue.OUT, "nobody comes out through a closed one"
		)
	assert_false(visit.is_hiding(), "and do not hide")


func test_nothing_happens_without_a_guest() -> void:
	var visit := _visit()
	for _frame_index: int in 600:
		assert_eq(visit.tick(STEP, true), DoorVisit.Cue.NONE)
