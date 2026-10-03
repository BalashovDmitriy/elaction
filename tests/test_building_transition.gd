extends GutTest

## Building change after the exit (ADR-0038, decision 4): the bonus counts up over the
## scene while the car drives off, finishes counting and hangs, then the frame fades to
## black, and only under the black does the bonus go into the score, the round advance
## and the next building get assembled; the frame comes out of black on it.

const HUD_SCENE := preload("res://src/ui/hud.tscn")
const MAIN_SCENE := preload("res://src/main.tscn")

## How many frames to wait for the fade and the bonus count-up: the whole change takes
## less than two seconds, the rest is a margin for building a thirty-floor building
## under the black.
const PATIENCE: int = 600


func before_each() -> void:
	GameState.instance().start_game()


func after_each() -> void:
	GameState.instance().start_game()


func test_the_curtain_swaps_under_black_once() -> void:
	var curtain := FadeCurtain.new()
	add_child_autofree(curtain)
	var swaps := [0]
	var seen_black := [false]
	curtain.cover(
		0.05,
		func() -> void:
			swaps[0] += 1
			seen_black[0] = is_equal_approx(curtain.opacity(), 1.0)
	)
	assert_true(curtain.is_running())
	var frames := 0
	while curtain.is_running() and frames < PATIENCE:
		await get_tree().process_frame
		frames += 1
	assert_eq(swaps[0], 1, "здание меняется один раз")
	assert_true(seen_black[0], "и под полным чёрным")
	assert_almost_eq(curtain.opacity(), 0.0, 0.001, "кадр вышел из чёрного")


func test_a_cancelled_curtain_never_swaps() -> void:
	var curtain := FadeCurtain.new()
	add_child_autofree(curtain)
	var swaps := [0]
	curtain.cover(0.0, func() -> void: swaps[0] += 1)
	await get_tree().process_frame
	curtain.cancel()
	for _frame: int in 90:
		await get_tree().process_frame
	assert_eq(swaps[0], 0, "брошенная смена здание не меняет")
	assert_eq(curtain.opacity(), 0.0, "и не оставляет кадр чёрным")


func test_the_bonus_counts_up_to_the_building_bonus() -> void:
	var hud := HUD_SCENE.instantiate() as Hud
	add_child_autofree(hud)
	assert_false(hud.bonus_shown(), "до выхода бонуса нет")
	hud.count_bonus(3000)
	assert_true(hud.bonus_shown())
	assert_eq(hud.bonus_text(), "0", "набегает от нуля")
	var frames := 0
	while hud.bonus_text() != Hud.format_score(3000) and frames < PATIENCE:
		await get_tree().process_frame
		frames += 1
	assert_eq(hud.bonus_text(), "3 000", "досчитал до бонуса")
	hud.hide_bonus()
	assert_false(hud.bonus_shown())


## The whole change for real, in main: the bonus on the drive-off, the fade, a new
## building.
func test_main_builds_the_next_building_under_the_curtain() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	main.call("_start_game")
	var first := main.get(&"_level") as GreyboxLevel
	var hud := main.get_node("Hud") as Hud
	var curtain := main.get(&"_curtain") as FadeCurtain
	assert_not_null(first)

	var game := GameState.instance()
	var bonus := Hud.format_score(Arcade.building_bonus(1))
	first.car_started.emit()
	assert_true(hud.bonus_shown(), "машина тронулась — бонус на кадре")
	var score := game.score
	first.building_cleared.emit()
	assert_same(main.get(&"_level"), first, "здание меняется не встык")

	# Until the frame is black, the game is the same: score without the bonus, round one,
	# the old building. The bonus on the plate finishes counting before the frame starts
	# to darken.
	var counted_before_fade := false
	var changed_before_black := false
	var darkest := 0.0
	var frames := 0
	while main.get(&"_level") == first and frames < PATIENCE:
		var opacity := curtain.opacity()
		darkest = maxf(darkest, opacity)
		if opacity <= 0.0 and hud.bonus_text() == bonus:
			counted_before_fade = true
		if opacity < 0.999 and (game.score != score or game.building != 1):
			changed_before_black = true
		await get_tree().process_frame
		frames += 1
	assert_true(counted_before_fade, "бонус досчитан до затемнения")
	assert_false(changed_before_black, "счёт и раунд не меняются, пока кадр не чёрный")
	assert_ne(main.get(&"_level"), first, "следующее здание собрано")
	assert_almost_eq(darkest, 1.0, 0.05, "под чёрным")
	assert_eq(game.score, score + Arcade.building_bonus(1), "под чёрным бонус здания — в счёт")
	assert_eq(game.building, 2, "и следующий раунд")
	assert_false(hud.bonus_shown(), "бонус ушёл вместе со старым зданием")
	frames = 0
	while curtain.is_running() and frames < PATIENCE:
		await get_tree().process_frame
		frames += 1
	assert_almost_eq(curtain.opacity(), 0.0, 0.001, "кадр вышел из чёрного")
	main.call("_open_menu")
