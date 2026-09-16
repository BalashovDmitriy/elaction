extends GutTest

## Тесты нарезки перекрытия проёмами.
##
## Порядок проёмов в списке не задан: шахта добавляется раньше эскалатора, но
## стоит правее. Пока список не сортировался, куски накладывались друг на друга
## и перекрытие выходило сплошным — проёма как не бывало.

const SURFACE: float = 220.0
const WIDTH: float = 1280.0
const THICKNESS: float = 20.0
## Границы этажа во всю ширину здания: перекрытие режется от стены до стены
## своего уровня, а не по ширине здания (ADR-0014, пункт 3).
const BOUNDS := Vector2(0.0, WIDTH)


func test_floor_without_gaps_is_one_slab() -> void:
	var gaps: Array[Vector2] = []
	var rects := GreyboxLevel.slab_segments(SURFACE, gaps, BOUNDS, THICKNESS)
	assert_eq(rects.size(), 1)
	assert_eq(rects[0].size.x, WIDTH)


func test_single_gap_splits_the_slab_in_two() -> void:
	var gaps: Array[Vector2] = [Vector2(560.0, 600.0)]
	var rects := GreyboxLevel.slab_segments(SURFACE, gaps, BOUNDS, THICKNESS)
	assert_eq(rects.size(), 2)
	assert_eq(rects[0], Rect2(0.0, SURFACE, 560.0, THICKNESS))
	assert_eq(rects[1].position.x, 600.0)


func test_gaps_are_cut_in_any_order() -> void:
	# Именно в этом порядке их собирает уровень: шахта добавляется первой.
	var gaps: Array[Vector2] = [Vector2(560.0, 600.0), Vector2(380.0, 440.0)]
	var rects := GreyboxLevel.slab_segments(SURFACE, gaps, BOUNDS, THICKNESS)
	assert_eq(rects.size(), 3, "два проёма режут перекрытие на три куска")
	assert_eq(rects[0].end.x, 380.0)
	assert_eq(rects[1].position.x, 440.0)
	assert_eq(rects[1].end.x, 560.0)
	assert_eq(rects[2].position.x, 600.0)


func test_gap_at_the_left_edge_leaves_no_empty_slab() -> void:
	var gaps: Array[Vector2] = [Vector2(0.0, 40.0)]
	var rects := GreyboxLevel.slab_segments(SURFACE, gaps, BOUNDS, THICKNESS)
	assert_eq(rects.size(), 1)
	assert_eq(rects[0].position.x, 40.0)


## Узкий этаж не начинается в нуле, и проём за его стеной ничего не режет:
## без обрезки кусок уходил бы в минус и переворачивался.
func test_narrow_floor_is_cut_within_its_own_walls() -> void:
	var bounds := Vector2(280.0, 1000.0)
	var gaps: Array[Vector2] = [Vector2(620.0, 660.0)]
	var rects := GreyboxLevel.slab_segments(SURFACE, gaps, bounds, THICKNESS)
	assert_eq(rects.size(), 2)
	assert_eq(rects[0].position.x, bounds.x, "перекрытие начинается у своей стены")
	assert_eq(rects[1].end.x, bounds.y, "и кончается у своей")


func test_gap_outside_the_floor_cuts_nothing() -> void:
	var bounds := Vector2(280.0, 1000.0)
	var gaps: Array[Vector2] = [Vector2(40.0, 100.0)]
	var rects := GreyboxLevel.slab_segments(SURFACE, gaps, bounds, THICKNESS)
	assert_eq(rects.size(), 1, "проём на улице перекрытие не режет")
	assert_eq(rects[0], Rect2(bounds.x, SURFACE, bounds.y - bounds.x, THICKNESS))


func test_caller_list_is_left_alone() -> void:
	var gaps: Array[Vector2] = [Vector2(560.0, 600.0), Vector2(380.0, 440.0)]
	GreyboxLevel.slab_segments(SURFACE, gaps, BOUNDS, THICKNESS)
	assert_eq(gaps[0], Vector2(560.0, 600.0), "сортируем копию, а не список вызывающего")
