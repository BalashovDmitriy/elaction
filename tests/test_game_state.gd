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
