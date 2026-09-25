extends GutTest

## Тесты предела кадров и вертикальной синхронизации (просьба пользователя, M24b).
##
## Синхронизацию в headless не спросить — окна нет, поэтому проверяется решение:
## что предел и флажок значат для движка и окна. Предел у движка ставится и без
## окна — его настройки ставят по-настоящему.

const TEMP := "user://test_frame_limit.cfg"


func after_each() -> void:
	if FileAccess.file_exists(TEMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))
	Engine.max_fps = 0


## Предел кадров и синхронизация переживают перезапуск; в старом файле их нет —
## остаётся как было до настройки: по монитору и с синхронизацией.
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
	assert_eq(fresh.frame_limit, DisplayModes.FRAME_MONITOR, "без ключа — по монитору")
	assert_true(fresh.vsync, "без ключа — синхронизация включена")

	old.set_value(GameSettings.SECTION, "frame_limit", 77)
	old.save(TEMP)
	assert_eq(
		GameSettings.load_from(TEMP).frame_limit,
		DisplayModes.FRAME_MONITOR,
		"предела не из списка не бывает"
	)


## Что предел и флажок значат для движка и окна.
func test_the_frame_limit_maps_to_the_engine() -> void:
	assert_eq(
		DisplayModes.max_fps(DisplayModes.FRAME_MONITOR, true, 144.0), 0, "держит синхронизация"
	)
	assert_eq(DisplayModes.max_fps(DisplayModes.FRAME_MONITOR, false, 143.9), 144, "частота экрана")
	assert_eq(
		DisplayModes.max_fps(DisplayModes.FRAME_MONITOR, false, -1.0), 0, "частота неизвестна"
	)
	assert_eq(DisplayModes.max_fps(120, true, 60.0), 120)
	assert_eq(DisplayModes.max_fps(DisplayModes.FRAME_UNLIMITED, false, 60.0), 0)
	assert_eq(DisplayModes.vsync_mode(true), DisplayServer.VSYNC_ENABLED)
	assert_eq(DisplayModes.vsync_mode(false), DisplayServer.VSYNC_DISABLED)
	assert_eq(DisplayModes.FRAME_LIMITS[0], DisplayModes.FRAME_MONITOR, "первым — по монитору")


## Настройки ставят предел движку; по умолчанию его нет, как до настройки.
func test_applying_settings_sets_the_frame_limit() -> void:
	var settings := GameSettings.new()
	settings.locale = TranslationServer.get_locale()
	settings.frame_limit = 60
	settings.apply()
	assert_eq(Engine.max_fps, 60)
	settings.frame_limit = DisplayModes.FRAME_MONITOR
	settings.apply()
	assert_eq(Engine.max_fps, 0)
