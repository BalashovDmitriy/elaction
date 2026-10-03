extends GutTest

## Orthographic camera tilt (ADR-0023, decision 1): the camera axis passes through the
## target in the play plane, the frame covers slightly more vertically, the listener stays
## in the plane. The tilt is a camera property and the world does not know about it:
## [CameraBounds] is checked separately and without a scene.

const POINT := Vector2(3.0, 7.0)


func _camera() -> SideCamera:
	var camera := SideCamera.new()
	add_child_autofree(camera)
	return camera


func test_the_camera_looks_down_from_above() -> void:
	var camera := _camera()
	assert_lt(camera.rotation.x, 0.0, "the view is lowered")
	assert_almost_eq(rad_to_deg(-camera.rotation.x), SideCamera.TILT_DEGREES, 0.001)
	assert_eq(camera.projection, Camera3D.PROJECTION_ORTHOGONAL, "and still ortho")


## The camera stands above the target exactly enough for its axis to hit the target at
## Z = 0: otherwise the tilt would look at the feet, and the frame would drift down on
## every floor.
func test_the_axis_passes_through_the_target_in_the_play_plane() -> void:
	var camera := _camera()
	camera.snap_to(POINT)
	var forward := -camera.global_basis.z
	var steps := -camera.global_position.z / forward.z
	var hit := camera.global_position + forward * steps
	assert_almost_eq(hit.z, WorldSpace.PLAY_Z, 0.001)
	assert_almost_eq(hit.x, POINT.x, 0.001)
	assert_almost_eq(hit.y, POINT.y, 0.001)
	assert_gt(camera.global_position.y, POINT.y, "the camera is above the target")


## A tilted frame cuts the play plane at an angle and covers more than its size
## vertically, by 1/cos(tilt). Otherwise the band of visible floors would be computed
## from a frame that does not exist, and lamps at the edge would go out in the frame.
func test_the_frame_covers_a_little_more_height_for_the_tilt() -> void:
	var camera := _camera()
	camera.snap_to(Vector2.ZERO)
	var expected := camera.size / cos(deg_to_rad(SideCamera.TILT_DEGREES))
	assert_almost_eq(camera.view().size.y, expected, 0.001)
	assert_gt(camera.view().size.y, camera.size)


func test_the_listener_stays_in_the_play_plane() -> void:
	var camera := _camera()
	camera.snap_to(POINT)
	var found := camera.find_children("*", "AudioListener3D", false, false)
	assert_eq(found.size(), 1, "one listener")
	var listener := found[0] as AudioListener3D
	assert_almost_eq(listener.global_position.z, WorldSpace.PLAY_Z, 0.01)
	assert_almost_eq(listener.global_position.y, POINT.y, 0.01)
