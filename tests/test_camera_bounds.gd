extends GutTest

## Кадрирование камеры. Без сцены: [CameraBounds] — арифметика, и проверять её
## запуском здания незачем.

var _bounds: CameraBounds = null


func before_each() -> void:
	_bounds = CameraBounds.new()
	_bounds.half_width = 10.0
	_bounds.half_height = 5.0
	_bounds.limits = Rect2(0.0, 0.0, 100.0, 50.0)


func test_a_centre_well_inside_is_left_alone() -> void:
	assert_eq(_bounds.clamp_centre(Vector2(50.0, 25.0)), Vector2(50.0, 25.0))


func test_the_frame_does_not_leave_the_left_edge() -> void:
	assert_eq(_bounds.clamp_centre(Vector2(0.0, 25.0)).x, 10.0)


func test_the_frame_does_not_leave_the_right_edge() -> void:
	assert_eq(_bounds.clamp_centre(Vector2(100.0, 25.0)).x, 90.0)


func test_the_frame_does_not_leave_the_top_and_bottom() -> void:
	assert_eq(_bounds.clamp_centre(Vector2(50.0, 0.0)).y, 5.0)
	assert_eq(_bounds.clamp_centre(Vector2(50.0, 50.0)).y, 45.0)


func test_a_band_narrower_than_the_frame_is_centred() -> void:
	# Упереться в оба края разом нельзя, и дёргаться между ними — худшее.
	_bounds.limits = Rect2(0.0, 0.0, 8.0, 50.0)
	assert_eq(_bounds.clamp_centre(Vector2(0.0, 25.0)).x, 4.0)
	assert_eq(_bounds.clamp_centre(Vector2(8.0, 25.0)).x, 4.0)


func test_without_limits_the_camera_goes_anywhere() -> void:
	_bounds.limits = Rect2(-INF, -INF, INF, INF)
	assert_eq(_bounds.clamp_centre(Vector2(-500.0, 900.0)), Vector2(-500.0, 900.0))


func test_the_view_is_the_frame_around_the_centre() -> void:
	var view := _bounds.view_at(Vector2(50.0, 25.0))
	assert_eq(view.position, Vector2(40.0, 20.0))
	assert_eq(view.size, Vector2(20.0, 10.0))


func test_smoothing_moves_towards_the_target_without_passing_it() -> void:
	var moved := CameraBounds.smoothed(Vector2.ZERO, Vector2(10.0, 0.0), 8.0, 1.0 / 60.0)
	assert_gt(moved.x, 0.0, "камера обязана двинуться")
	assert_lt(moved.x, 10.0, "и не обязана долетать за один кадр")


func test_smoothing_off_snaps_to_the_target() -> void:
	# Нужно съёмке и тестам: кадр должен показывать то, что уже случилось.
	assert_eq(CameraBounds.smoothed(Vector2.ZERO, Vector2(10.0, 3.0), 0.0, 1.0), Vector2(10.0, 3.0))


func test_smoothing_does_not_depend_on_the_frame_rate() -> void:
	# Один шаг в 1/30 обязан дать то же, что два шага в 1/60: иначе на просадке
	# камера обгоняет цель.
	var one := CameraBounds.smoothed(Vector2.ZERO, Vector2(10.0, 0.0), 8.0, 1.0 / 30.0)
	var first := CameraBounds.smoothed(Vector2.ZERO, Vector2(10.0, 0.0), 8.0, 1.0 / 60.0)
	var two := CameraBounds.smoothed(first, Vector2(10.0, 0.0), 8.0, 1.0 / 60.0)
	assert_almost_eq(one.x, two.x, 0.0001)


## Камера встаёт в стоящую цель ровно, а не ползёт к ней вечно на доли пикселя:
## ползущая камера давала мерцание кромок дверей и перекрытий (M22).
func test_the_camera_comes_to_rest() -> void:
	var at := Vector2.ZERO
	var target := Vector2(3.0, -2.0)
	for _frame in 240:
		at = CameraBounds.smoothed(at, target, 8.0, 1.0 / 60.0)
	assert_eq(at, target, "за четыре секунды камера встала в цель")
	assert_eq(CameraBounds.smoothed(at, target, 8.0, 1.0 / 60.0), target, "и больше не сдвигается")
