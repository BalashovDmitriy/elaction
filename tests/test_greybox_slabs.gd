extends GutTest

## Тесты нарезки перекрытия проёмами.
##
## Порядок проёмов в списке не задан: шахта добавляется раньше эскалатора, но
## стоит правее. Пока список не сортировался, куски накладывались друг на друга
## и перекрытие выходило сплошным — проёма как не бывало.

const SURFACE: float = 220.0


func test_floor_without_gaps_is_one_slab() -> void:
	var gaps: Array[Vector2] = []
	var rects := GreyboxLevel.slab_segments(SURFACE, gaps)
	assert_eq(rects.size(), 1)
	assert_eq(rects[0].size.x, GreyboxLevel.LEVEL_WIDTH)


func test_single_gap_splits_the_slab_in_two() -> void:
	var gaps: Array[Vector2] = [Vector2(560.0, 600.0)]
	var rects := GreyboxLevel.slab_segments(SURFACE, gaps)
	assert_eq(rects.size(), 2)
	assert_eq(rects[0], Rect2(0.0, SURFACE, 560.0, GreyboxLevel.SLAB_HEIGHT))
	assert_eq(rects[1].position.x, 600.0)


func test_gaps_are_cut_in_any_order() -> void:
	# Именно в этом порядке их собирает уровень: шахта добавляется первой.
	var gaps: Array[Vector2] = [Vector2(560.0, 600.0), Vector2(380.0, 440.0)]
	var rects := GreyboxLevel.slab_segments(SURFACE, gaps)
	assert_eq(rects.size(), 3, "два проёма режут перекрытие на три куска")
	assert_eq(rects[0].end.x, 380.0)
	assert_eq(rects[1].position.x, 440.0)
	assert_eq(rects[1].end.x, 560.0)
	assert_eq(rects[2].position.x, 600.0)


func test_gap_at_the_left_edge_leaves_no_empty_slab() -> void:
	var gaps: Array[Vector2] = [Vector2(0.0, 40.0)]
	var rects := GreyboxLevel.slab_segments(SURFACE, gaps)
	assert_eq(rects.size(), 1)
	assert_eq(rects[0].position.x, 40.0)


func test_caller_list_is_left_alone() -> void:
	var gaps: Array[Vector2] = [Vector2(560.0, 600.0), Vector2(380.0, 440.0)]
	GreyboxLevel.slab_segments(SURFACE, gaps)
	assert_eq(gaps[0], Vector2(560.0, 600.0), "сортируем копию, а не список вызывающего")
