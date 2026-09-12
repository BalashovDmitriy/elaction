extends GutTest

## Тесты состояния партии.
##
## Тест создаёт свой экземпляр и глобального автолоада не трогает: он становится
## общим только при входе в дерево, а тестовый туда не попадает.


func _state() -> GameState:
	return autofree(GameState.new()) as GameState


func test_building_starts_with_no_documents_collected() -> void:
	var game := _state()
	game.start_building(3)
	assert_eq(game.documents_collected, 0)
	assert_eq(game.documents_total, 3)
	assert_false(game.all_documents_collected())


func test_document_adds_count_and_score() -> void:
	var game := _state()
	game.start_building(2)
	game.collect_document()
	assert_eq(game.documents_collected, 1)
	assert_eq(game.score, GameState.DOCUMENT_SCORE)


func test_building_is_cleared_after_the_last_document() -> void:
	var game := _state()
	game.start_building(2)
	game.collect_document()
	assert_false(game.all_documents_collected(), "один из двух — ещё не всё")
	game.collect_document()
	assert_true(game.all_documents_collected())


func test_building_without_red_doors_is_already_cleared() -> void:
	var game := _state()
	game.start_building(0)
	assert_true(game.all_documents_collected())


func test_reset_clears_score_too() -> void:
	var game := _state()
	game.start_building(1)
	game.collect_document()
	game.reset()
	assert_eq(game.score, 0)
	assert_eq(game.documents_total, 0)


func test_collecting_reports_both_changes() -> void:
	var game := _state()
	game.start_building(1)
	watch_signals(game)
	game.collect_document()
	assert_signal_emitted(game, "documents_changed")
	assert_signal_emitted(game, "score_changed")


func test_partie_starts_with_three_lives() -> void:
	assert_eq(_state().lives, GameState.STARTING_LIVES)


func test_losing_a_life_leaves_otto_in_the_game() -> void:
	var game := _state()
	assert_true(game.lose_life(), "после первой смерти партия продолжается")
	assert_eq(game.lives, GameState.STARTING_LIVES - 1)


func test_last_life_ends_the_game() -> void:
	var game := _state()
	watch_signals(game)
	for _death: int in GameState.STARTING_LIVES - 1:
		game.lose_life()
	assert_false(game.lose_life(), "жизни кончились")
	assert_signal_emitted(game, "game_over")


func test_game_over_comes_once() -> void:
	var game := _state()
	for _death: int in GameState.STARTING_LIVES:
		game.lose_life()
	watch_signals(game)
	assert_false(game.lose_life(), "после конца партии жизнь снять нельзя")
	assert_eq(game.lives, 0)
	assert_signal_not_emitted(game, "game_over", "game_over сообщает о переходе, а не о состоянии")
	assert_signal_not_emitted(game, "lives_changed")


func test_kill_in_the_light_costs_its_face_value() -> void:
	assert_eq(GameState.kill_score(GameState.ENEMY_SHOT_SCORE, false), 100)


func test_kill_in_the_dark_is_worth_more() -> void:
	var dark := GameState.kill_score(GameState.ENEMY_SHOT_SCORE, true)
	assert_eq(dark, GameState.ENEMY_SHOT_SCORE * GameState.DARK_KILL_MULTIPLIER)


func test_game_starts_in_the_first_building() -> void:
	var game := _state()
	game.start_game()
	assert_eq(game.building, 1)
	assert_eq(game.lives, GameState.STARTING_LIVES)


func test_finished_building_pays_by_its_number() -> void:
	var game := _state()
	game.start_game()
	game.finish_building()
	assert_eq(game.score, GameState.BUILDING_BONUS, "первое здание — одна ставка")
	game.finish_building()
	assert_eq(game.score, GameState.BUILDING_BONUS * 3, "второе — двойная")


func test_new_building_takes_the_alarm_off() -> void:
	var game := _state()
	game.start_game()
	# Лимит меняется до того, как заводится отсчёт: иначе он останется прежним.
	game.alarm.time_limit = 0.0
	game.alarm.enter_building()
	game.alarm.tick(0.1)
	assert_true(game.alarm.raised)
	game.finish_building()
	assert_false(game.alarm.raised)
