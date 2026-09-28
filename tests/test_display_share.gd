extends GutTest

## Разрешение в полном экране — это разрешение 3D (ADR-0042, решение 3).
##
## Godot не меняет видеорежим монитора: полный экран и окно без рамки всегда в
## родном разрешении, и пункт «Разрешение» там ничего не делал. Теперь он задаёт,
## в каком разрешении рисуется сцена, — долю родного.

const UHD := Vector2i(3840, 2160)


func test_a_window_draws_the_scene_at_its_own_size() -> void:
	var share := DisplayModes.share(DisplayModes.Mode.WINDOWED, Vector2i(1280, 720), UHD)
	assert_eq(share, 1.0, "окно рисует 3D во весь свой размер")


func test_full_screen_draws_the_scene_at_the_chosen_resolution() -> void:
	for mode: DisplayModes.Mode in [DisplayModes.Mode.FULLSCREEN, DisplayModes.Mode.BORDERLESS]:
		assert_almost_eq(
			DisplayModes.share(mode, Vector2i(1920, 1080), UHD),
			0.5,
			0.001,
			"1080p на 4K — половина"
		)
		assert_eq(DisplayModes.share(mode, UHD, UHD), 1.0, "родное — без растяжения")


func test_the_share_never_drops_below_the_floor() -> void:
	var share := DisplayModes.share(
		DisplayModes.Mode.FULLSCREEN, Vector2i(1280, 720), Vector2i(7680, 4320)
	)
	assert_almost_eq(share, DisplayModes.MIN_SHARE, 0.001, "720p на 8K — не меньше трети")


func test_an_odd_native_screen_is_on_the_list() -> void:
	var wide := Vector2i(3440, 1440)
	var full := DisplayModes.choices(DisplayModes.Mode.FULLSCREEN, wide)
	assert_true(full.has(wide), "родное нестандартное разрешение можно выбрать")
	assert_eq(DisplayModes.share(DisplayModes.Mode.FULLSCREEN, wide, wide), 1.0, "и оно — 100%")
	var windowed := DisplayModes.choices(DisplayModes.Mode.WINDOWED, wide)
	assert_false(windowed.has(wide), "окно размером с экран — это без рамки, не окно")
