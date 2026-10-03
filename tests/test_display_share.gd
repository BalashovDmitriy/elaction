extends GutTest

## Resolution in full screen is the 3D resolution (ADR-0042, decision 3).
##
## Godot does not change the monitor's video mode: full screen and borderless window are
## always at native resolution, and the "Resolution" option did nothing there. Now it
## sets the resolution the scene is drawn at — a share of native.

const UHD := Vector2i(3840, 2160)


func test_a_window_draws_the_scene_at_its_own_size() -> void:
	var share := DisplayModes.share(DisplayModes.Mode.WINDOWED, Vector2i(1280, 720), UHD)
	assert_eq(share, 1.0, "the window draws 3D at its full size")


func test_full_screen_draws_the_scene_at_the_chosen_resolution() -> void:
	for mode: DisplayModes.Mode in [DisplayModes.Mode.FULLSCREEN, DisplayModes.Mode.BORDERLESS]:
		assert_almost_eq(
			DisplayModes.share(mode, Vector2i(1920, 1080), UHD), 0.5, 0.001, "1080p on 4K is half"
		)
		assert_eq(DisplayModes.share(mode, UHD, UHD), 1.0, "native: no stretching")


func test_the_share_never_drops_below_the_floor() -> void:
	var share := DisplayModes.share(
		DisplayModes.Mode.FULLSCREEN, Vector2i(1280, 720), Vector2i(7680, 4320)
	)
	assert_almost_eq(share, DisplayModes.MIN_SHARE, 0.001, "720p on 8K is not below a third")


func test_an_odd_native_screen_is_on_the_list() -> void:
	var wide := Vector2i(3440, 1440)
	var full := DisplayModes.choices(DisplayModes.Mode.FULLSCREEN, wide)
	assert_true(full.has(wide), "a native non-standard resolution can be chosen")
	assert_eq(DisplayModes.share(DisplayModes.Mode.FULLSCREEN, wide, wide), 1.0, "and it is 100%")
	var windowed := DisplayModes.choices(DisplayModes.Mode.WINDOWED, wide)
	assert_false(windowed.has(wide), "a window the size of the screen is borderless, not a window")


## A file from before M24f stored the default window size in full screen: since M24f
## this is the 3D share, and a player on 4K would get half. Such a file switches to native.
func test_old_full_screen_settings_move_to_the_native_resolution() -> void:
	var uhd := Vector2i(3840, 2160)
	var hd := Vector2i(1920, 1080)
	var full := DisplayModes.Mode.FULLSCREEN
	assert_eq(
		GameSettings.migrated_resolution(true, full, hd, uhd), uhd, "an old one goes to native"
	)
	assert_eq(
		GameSettings.migrated_resolution(false, full, hd, uhd), hd, "a new one is not touched"
	)
	var windowed := DisplayModes.Mode.WINDOWED
	assert_eq(GameSettings.migrated_resolution(true, windowed, hd, uhd), hd, "a window too")
