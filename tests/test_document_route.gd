extends GutTest

## Тесты выбора двери, к которой возвращают за пропущенным документом.
##
## Правило — ADR-0005, пункт 5: самый верхний этаж с несобранной красной дверью.


func test_nothing_to_return_for_when_all_collected() -> void:
	assert_eq(DocumentRoute.door_to_return_to(PackedVector2Array()), -1)


func test_single_pending_door_is_the_target() -> void:
	var pending := PackedVector2Array([Vector2(200.0, 340.0)])
	assert_eq(DocumentRoute.door_to_return_to(pending), 0)


func test_highest_floor_wins() -> void:
	# Меньшая y — выше по экрану.
	var pending := PackedVector2Array(
		[Vector2(160.0, 340.0), Vector2(980.0, 100.0), Vector2(700.0, 220.0)]
	)
	assert_eq(DocumentRoute.door_to_return_to(pending), 1)


func test_leftmost_wins_on_the_same_floor() -> void:
	var pending := PackedVector2Array([Vector2(980.0, 100.0), Vector2(200.0, 100.0)])
	assert_eq(DocumentRoute.door_to_return_to(pending), 1, "на одном этаже берём левую")
