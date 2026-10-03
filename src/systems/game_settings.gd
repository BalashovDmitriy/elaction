class_name GameSettings
extends RefCounted

## Player settings: volumes, language, window, graphics, keys.
##
## The first thing the game writes to disk (ADR-0012). They live in `user://`, not next
## to the game: a built game has its own data folder, and writing there is the only
## portable way to lose nothing on update.
##
## A class without nodes: it reads, applies and saves, and who calls it —
## the menu or autostart — does not matter to it. So it is tested without a scene.

const PATH := "user://settings.cfg"
const SECTION := "settings"

## Interface languages. The first one is the fallback if the system language is unknown.
const LOCALES: PackedStringArray = ["en", "ru"]

## How many difficulty levels: as many positions as the arcade switch has.
const DIFFICULTIES: int = 4

var master: float = 1.0
var music: float = 0.7
var sfx: float = 1.0
var locale: String = ""
## Window mode — [enum DisplayModes.Mode]: windowed, borderless, fullscreen.
var window_mode: int = DisplayModes.Mode.WINDOWED
## Window size in windowed mode; in fullscreen and borderless — the 3D resolution, the window
## there is at screen resolution ([method DisplayModes.share]).
var resolution: Vector2i = DisplayModes.DEFAULT_RESOLUTION
## Frame limit — one of [constant DisplayModes.FRAME_LIMITS]. Default is
## "by monitor": as before the setting existed, sync holds the frames.
var frame_limit: int = DisplayModes.FRAME_MONITOR
## Vertical sync. On, as in the project by default.
var vsync: bool = true
## Difficulty level — the arcade DIP switch, 0–3: the game's starting skill,
## to which cleared buildings are added (ADR-0027, decision 8).
var difficulty: int = 0
## Graphics quality — [enum Graphics.Quality] (ADR-0030, decision 5).
var quality: int = Graphics.Quality.HIGH
## Whether the quality level was chosen — by the player or by the first-run measurement
## ([QualityProbe], ADR-0034, decision 3). Until then, the first building measures it.
var quality_measured: bool = false
## Whether to show blood on a bullet hit (ADR-0031).
var blood: bool = true
## Whether to show frames per second in the HUD corner (user request, M24a).
var show_fps: bool = false
## Control scheme: a key and a button per action (ADR-0039, decision 7). As its own
## section in the same file.
var bindings := KeyBindings.new()
## Where [method save_to] writes without an explicit path. Menu tests substitute it: the controls
## screen saves the scheme itself, and the player's settings must not suffer.
var file_path: String = PATH

## Mode and size already applied to the window: [method apply] is called for any
## setting, and the window is touched only when they have changed.
var _window_applied: Array = []
## Sync already applied to the window: changing it recreates the swap chain,
## and doing that on every [method apply] is pointless. Empty — not set yet.
var _vsync_applied: Array = []


## Resolution from a pre-M24f file. There in fullscreen and borderless the resolution
## meant nothing, and the file held the default window size, while since M24f it is the 3D
## fraction: a player on 4K would silently get half after an update (code review M24f).
## A pre-M24f file is recognized by the render scale key [param legacy]; in fullscreen
## and borderless it switches to the screen's native resolution [param screen].
static func migrated_resolution(
	legacy: bool, mode: int, resolution: Vector2i, screen: Vector2i
) -> Vector2i:
	if not legacy or mode == DisplayModes.Mode.WINDOWED or screen.x <= 0 or screen.y <= 0:
		return resolution
	return screen


## Settings from disk. No file — default values, language by system locale.
static func load_from(path: String = PATH) -> GameSettings:
	var settings := GameSettings.new()
	settings.locale = settings.system_locale()
	# What was read from its own file is written back there: the menu and the quality measurement call
	# [method save_to] without a path.
	settings.file_path = path

	var file := ConfigFile.new()
	if file.load(path) != OK:
		return settings

	settings.master = clampf(float(file.get_value(SECTION, "master", settings.master)), 0.0, 1.0)
	settings.music = clampf(float(file.get_value(SECTION, "music", settings.music)), 0.0, 1.0)
	settings.sfx = clampf(float(file.get_value(SECTION, "sfx", settings.sfx)), 0.0, 1.0)
	# Before M22 the window was a "fullscreen" flag: it becomes the mode.
	var legacy_full := bool(file.get_value(SECTION, "fullscreen", false))
	settings.window_mode = clampi(
		int(
			file.get_value(
				SECTION,
				"window_mode",
				DisplayModes.Mode.FULLSCREEN if legacy_full else settings.window_mode
			)
		),
		0,
		DisplayModes.Mode.size() - 1
	)
	var size: Variant = file.get_value(SECTION, "resolution", settings.resolution)
	if size is Vector2i:
		settings.resolution = size
	settings.resolution = migrated_resolution(
		file.has_section_key(SECTION, "render_scale"),
		settings.window_mode,
		settings.resolution,
		DisplayServer.screen_get_size()
	)
	var limit := int(file.get_value(SECTION, "frame_limit", settings.frame_limit))
	if DisplayModes.FRAME_LIMITS.has(limit):
		settings.frame_limit = limit
	settings.vsync = bool(file.get_value(SECTION, "vsync", settings.vsync))
	settings.blood = bool(file.get_value(SECTION, "blood", settings.blood))
	settings.show_fps = bool(file.get_value(SECTION, "show_fps", settings.show_fps))
	settings.difficulty = clampi(
		int(file.get_value(SECTION, "difficulty", settings.difficulty)), 0, DIFFICULTIES - 1
	)

	settings.quality = clampi(
		int(file.get_value(SECTION, "quality", settings.quality)), 0, Graphics.Quality.size() - 1
	)
	# A level saved before M22 was chosen by the player: no point measuring over it.
	settings.quality_measured = bool(
		file.get_value(SECTION, "quality_measured", file.has_section_key(SECTION, "quality"))
	)

	var saved := String(file.get_value(SECTION, "locale", settings.locale))
	settings.locale = saved if LOCALES.has(saved) else settings.locale
	settings.bindings = KeyBindings.read_from(file)
	return settings


## The system language, if we know it. Otherwise English: an unknown language is better
## shown in readable Latin script than in Cyrillic at random.
func system_locale() -> String:
	var system := OS.get_locale_language()
	return system if LOCALES.has(system) else LOCALES[0]


func save_to(path: String = "") -> void:
	if path.is_empty():
		path = file_path
	var file := ConfigFile.new()
	file.set_value(SECTION, "master", master)
	file.set_value(SECTION, "music", music)
	file.set_value(SECTION, "sfx", sfx)
	file.set_value(SECTION, "locale", locale)
	file.set_value(SECTION, "window_mode", window_mode)
	file.set_value(SECTION, "resolution", resolution)
	file.set_value(SECTION, "frame_limit", frame_limit)
	file.set_value(SECTION, "vsync", vsync)
	file.set_value(SECTION, "difficulty", difficulty)
	file.set_value(SECTION, "quality", quality)
	file.set_value(SECTION, "quality_measured", quality_measured)
	file.set_value(SECTION, "blood", blood)
	file.set_value(SECTION, "show_fps", show_fps)
	bindings.write_to(file)
	file.save(path)


## Applies settings to the game: buses, language, window, frames, graphics and keys.
##
## One method for everything, because they must be applied together and in one order:
## otherwise the menu changes the volume while the language stays from the previous launch.
func apply() -> void:
	Sounds.set_level(Sounds.MASTER_BUS, master)
	Sounds.set_level(Sounds.MUSIC_BUS, music)
	Sounds.set_level(Sounds.SFX_BUS, sfx)
	TranslationServer.set_locale(locale)
	# The window is not touched in headless runs: there is none there, and settings tests
	# would resize a nonexistent window.
	if DisplayServer.get_name() != "headless":
		# The window is set anew only if mode or size changed: otherwise
		# toggling blood or language would re-centre a window the player had
		# moved, and enter fullscreen again (code review M22).
		# In fullscreen and borderless the resolution is a 3D fraction, not the window: changing
		# it does not re-enter fullscreen.
		var windowed := window_mode == DisplayModes.Mode.WINDOWED
		var window := [window_mode, resolution if windowed else Vector2i.ZERO]
		if window != _window_applied:
			DisplayModes.apply_window(window_mode as DisplayModes.Mode, resolution)
			_window_applied = window
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			var screen := DisplayServer.screen_get_size()
			var share := DisplayModes.share(window_mode as DisplayModes.Mode, resolution, screen)
			DisplayModes.apply_scale(share, tree.root)
		if _vsync_applied != [vsync]:
			DisplayModes.apply_vsync(vsync)
			_vsync_applied = [vsync]
	# The frame limit belongs to the engine, not the window: it is set even without one.
	DisplayModes.apply_frame_limit(frame_limit, vsync)
	Graphics.broadcast(quality as Graphics.Quality)
	Blood.enabled = blood
	Hud.show_fps = show_fps
	bindings.apply()


## Bus volume by its name. The menu needs it: there are three sliders and three fields,
## and binding them one by one would mean writing the same code three times.
func level_of(bus: String) -> float:
	match bus:
		Sounds.MUSIC_BUS:
			return music
		Sounds.SFX_BUS:
			return sfx
		_:
			return master


func set_level(bus: String, value: float) -> void:
	var level := clampf(value, 0.0, 1.0)
	match bus:
		Sounds.MUSIC_BUS:
			music = level
		Sounds.SFX_BUS:
			sfx = level
		_:
			master = level
	Sounds.set_level(bus, level)
