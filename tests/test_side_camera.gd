extends GutTest

## Наклон ортокамеры (ADR-0023, решение 1): ось камеры проходит через цель в
## плоскости игры, кадр по вертикали накрывает чуть больше, слушатель остаётся
## в плоскости. Наклон — свойство камеры, и мир о нём не знает: [CameraBounds]
## проверяется отдельно и без сцены.

const POINT := Vector2(3.0, 7.0)


func _camera() -> SideCamera:
	var camera := SideCamera.new()
	add_child_autofree(camera)
	return camera


func test_the_camera_looks_down_from_above() -> void:
	var camera := _camera()
	assert_lt(camera.rotation.x, 0.0, "взгляд опущен")
	assert_almost_eq(rad_to_deg(-camera.rotation.x), SideCamera.TILT_DEGREES, 0.001)
	assert_eq(camera.projection, Camera3D.PROJECTION_ORTHOGONAL, "и всё ещё орто")


## Камера стоит выше цели ровно настолько, чтобы её ось пришла в цель на Z = 0:
## иначе наклон смотрел бы под ноги, и кадр уехал бы вниз на каждом этаже.
func test_the_axis_passes_through_the_target_in_the_play_plane() -> void:
	var camera := _camera()
	camera.snap_to(POINT)
	var forward := -camera.global_basis.z
	var steps := -camera.global_position.z / forward.z
	var hit := camera.global_position + forward * steps
	assert_almost_eq(hit.z, WorldSpace.PLAY_Z, 0.001)
	assert_almost_eq(hit.x, POINT.x, 0.001)
	assert_almost_eq(hit.y, POINT.y, 0.001)
	assert_gt(camera.global_position.y, POINT.y, "камера выше цели")


## Наклонённый кадр режет плоскость игры под углом и накрывает по вертикали
## больше своего размера — на 1/cos(наклон). Иначе полоса видимых этажей
## считалась бы по кадру, которого нет, и лампы у края гасли бы в кадре.
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
	assert_eq(found.size(), 1, "слушатель один")
	var listener := found[0] as AudioListener3D
	assert_almost_eq(listener.global_position.z, WorldSpace.PLAY_Z, 0.01)
	assert_almost_eq(listener.global_position.y, POINT.y, 0.01)
