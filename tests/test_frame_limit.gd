extends GutTest

## Tests of the frame limit and vertical sync (the user's request, M24b).
##
## Sync cannot be queried in headless — there is no window, so the decision is checked:
## what the limit and the flag mean for the engine and the window. The engine limit is set
## even without a window — the settings set it for real.

const TEMP := "user://test_frame_limit.cfg"


func after_each() -> void:
	if FileAccess.file_exists(TEMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))
	Engine.max_fps = 0


## The frame limit and sync survive a restart; an old file does not have them —
## it stays as it was before the setting: by the monitor and with sync.
func test_the_frame_limit_and_vsync_survive_a_restart() -> void:
	var settings := GameSettings.new()
	settings.frame_limit = 144
	settings.vsync = false
	settings.save_to(TEMP)
	var loaded := GameSettings.load_from(TEMP)
	assert_eq(loaded.frame_limit, 144)
	assert_false(loaded.vsync)

	var old := ConfigFile.new()
	old.set_value(GameSettings.SECTION, "blood", false)
	old.save(TEMP)
	var fresh := GameSettings.load_from(TEMP)
	assert_eq(fresh.frame_limit, DisplayModes.FRAME_MONITOR, "no key - follows the monitor")
	assert_true(fresh.vsync, "no key - vsync is on")

	old.set_value(GameSettings.SECTION, "frame_limit", 77)
	old.save(TEMP)
	assert_eq(
		GameSettings.load_from(TEMP).frame_limit,
		DisplayModes.FRAME_MONITOR,
		"a limit outside the list does not occur"
	)


## What the limit and the flag mean for the engine and the window.
func test_the_frame_limit_maps_to_the_engine() -> void:
	assert_eq(DisplayModes.max_fps(DisplayModes.FRAME_MONITOR, true, 144.0), 0, "vsync holds it")
	assert_eq(
		DisplayModes.max_fps(DisplayModes.FRAME_MONITOR, false, 143.9),
		144,
		"the screen refresh rate"
	)
	assert_eq(
		DisplayModes.max_fps(DisplayModes.FRAME_MONITOR, false, -1.0), 0, "refresh rate unknown"
	)
	assert_eq(DisplayModes.max_fps(120, true, 60.0), 120)
	assert_eq(DisplayModes.max_fps(DisplayModes.FRAME_UNLIMITED, false, 60.0), 0)
	assert_eq(DisplayModes.vsync_mode(true), DisplayServer.VSYNC_ENABLED)
	assert_eq(DisplayModes.vsync_mode(false), DisplayServer.VSYNC_DISABLED)
	assert_eq(
		DisplayModes.FRAME_LIMITS[0], DisplayModes.FRAME_MONITOR, "first - follows the monitor"
	)


## The settings set the engine limit; by default there is none, as before the setting.
func test_applying_settings_sets_the_frame_limit() -> void:
	var settings := GameSettings.new()
	settings.locale = TranslationServer.get_locale()
	settings.frame_limit = 60
	settings.apply()
	assert_eq(Engine.max_fps, 60)
	settings.frame_limit = DisplayModes.FRAME_MONITOR
	settings.apply()
	assert_eq(Engine.max_fps, 0)
