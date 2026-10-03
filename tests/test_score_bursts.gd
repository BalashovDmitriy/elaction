extends GutTest

## Points in view: the score counts up to the new number, the increment pops up at the score and
## above the place of the event, the building bonus does not pop up above a place, a new game resets
## the score at once.


func after_each() -> void:
	GameState.instance().start_game()


func _bursts() -> Array:
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.position = Vector3(0.0, 0.0, 10.0)
	camera.make_current()
	var score := Label.new()
	add_child_autofree(score)
	var bursts := ScoreBursts.new()
	add_child_autofree(bursts)
	bursts.watch(score)
	return [bursts, score]


func _pluses(bursts: ScoreBursts) -> int:
	var count := 0
	for child: Node in bursts.get_children():
		var label := child as Label
		if label != null and label.text.begins_with("+"):
			count += 1
	return count


func test_the_score_rolls_up_to_the_new_value() -> void:
	var made := _bursts()
	var bursts: ScoreBursts = made[0]
	var score: Label = made[1]
	bursts.show_score(0)
	assert_eq(score.text, "0")
	bursts.show_score(1300)
	assert_ne(score.text, "1 300", "does not jump at once")
	await wait_seconds(ScoreBursts.ROLL_TIME + 0.2)
	assert_eq(score.text, Hud.format_score(1300), "ran up to the new number")
	bursts.show_score(0)
	assert_eq(score.text, "0", "a new game - at once")


func test_a_kill_bursts_over_its_place_and_by_the_score() -> void:
	var bursts: ScoreBursts = _bursts()[0]
	GameState.instance().add_score(300, Vector3.ZERO)
	assert_eq(_pluses(bursts), 2, "a bonus at the score and above the spot")
	await wait_seconds(ScoreBursts.BURST_TIME + 0.3)
	assert_eq(_pluses(bursts), 0, "the bonuses fade and go")


func test_the_building_bonus_shows_only_by_the_score() -> void:
	var bursts: ScoreBursts = _bursts()[0]
	GameState.instance().add_score(3000, GameState.AT_OTTO, false)
	assert_eq(_pluses(bursts), 1, "a bonus - at the score only")
