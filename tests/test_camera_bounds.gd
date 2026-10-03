extends GutTest

## Camera framing. No scene: [CameraBounds] is arithmetic, and there is no point in
## launching a building to check it.

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
	# You cannot rest against both edges at once, and jerking between them is the worst.
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
	# Needed by shots and tests: the frame must show what has already happened.
	assert_eq(CameraBounds.smoothed(Vector2.ZERO, Vector2(10.0, 3.0), 0.0, 1.0), Vector2(10.0, 3.0))


func test_smoothing_does_not_depend_on_the_frame_rate() -> void:
	# One step of 1/30 must give the same as two steps of 1/60: otherwise on a frame drop
	# the camera overtakes the target.
	var one := CameraBounds.smoothed(Vector2.ZERO, Vector2(10.0, 0.0), 8.0, 1.0 / 30.0)
	var first := CameraBounds.smoothed(Vector2.ZERO, Vector2(10.0, 0.0), 8.0, 1.0 / 60.0)
	var two := CameraBounds.smoothed(first, Vector2(10.0, 0.0), 8.0, 1.0 / 60.0)
	assert_almost_eq(one.x, two.x, 0.0001)


## The camera settles on a standing target exactly instead of creeping toward it forever
## by fractions of a pixel: a creeping camera made the edges of doors and slabs flicker
## (M22).
func test_the_camera_comes_to_rest() -> void:
	var at := Vector2.ZERO
	var target := Vector2(3.0, -2.0)
	for _frame in 240:
		at = CameraBounds.smoothed(at, target, 8.0, 1.0 / 60.0)
	assert_eq(at, target, "за четыре секунды камера встала в цель")
	assert_eq(CameraBounds.smoothed(at, target, 8.0, 1.0 / 60.0), target, "и больше не сдвигается")
