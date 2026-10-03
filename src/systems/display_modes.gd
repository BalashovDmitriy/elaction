class_name DisplayModes
extends RefCounted

## Window mode, resolution and 3D render scale (M22, the user's question —
## support for 4K and any monitor resolutions).
##
## The scene is drawn at the real window resolution: the interface stretches from
## the base 1920×1080 (`stretch = canvas_items`), while 3D does not, so on 4K
## the frame is honest, not stretched. The window is one of the standard sizes the
## monitor supports.
##
## Fullscreen and the borderless window are always at the monitor's native resolution: Godot
## does not switch its video mode. There the chosen resolution is the 3D resolution:
## the scene is drawn smaller and upscaled by FSR, while the interface stays sharp
## (ADR-0042, decision 3). Since M24f there is no separate render scale: the fraction is
## the chosen resolution relative to the native one.
##
## No nodes: what to offer and how to apply it is checked by a test.

enum Mode { WINDOWED, BORDERLESS, FULLSCREEN }

## Standard window sizes, 16:9, from small to large.
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3200, 1800),
	Vector2i(3840, 2160),
]

## 3D is not drawn below this fraction of the native resolution: 720p on 4K is a third.
const MIN_SHARE: float = 0.33

## Default window size — the project's base size.
const DEFAULT_RESOLUTION := Vector2i(1920, 1080)

## Frame limit "by monitor": with vertical sync it holds the frames,
## without it — a limit at the screen refresh rate.
const FRAME_MONITOR: int = 0
## No limit: as many as the card gives (with sync — the screen refresh rate anyway).
const FRAME_UNLIMITED: int = -1
## Frame limits in the menu. A list of monitor refresh rates is not offered: Godot 4.7
## has no way to either enumerate screen modes or change the refresh rate — exclusive
## fullscreen takes the desktop mode. So the game does not choose the screen refresh rate,
## it only limits frames (user request, M24b).
const FRAME_LIMITS: Array[int] = [FRAME_MONITOR, 60, 120, 144, 165, 240, FRAME_UNLIMITED]


## Window sizes that fit on screen [param screen]. Always at least one:
## on a screen smaller than 720p the window will be larger than the screen, but the game will start.
static func available(screen: Vector2i) -> Array[Vector2i]:
	var fitting: Array[Vector2i] = []
	for size in RESOLUTIONS:
		if size.x <= screen.x and size.y <= screen.y:
			fitting.append(size)
	if fitting.is_empty():
		fitting.append(RESOLUTIONS[0])
	return fitting


## Resolutions to choose from in mode [param mode]: windowed — the sizes that fit on
## the screen; in fullscreen and borderless — the same plus the screen itself if its size is not
## a standard one (3440×1440): otherwise the native resolution could not be chosen.
static func choices(mode: Mode, screen: Vector2i) -> Array[Vector2i]:
	var sizes := available(screen)
	if mode != Mode.WINDOWED and not sizes.has(screen):
		sizes.append(screen)
	return sizes


## The size closest to [param wanted] among those that fit on the screen: if the monitor
## was changed, the setting from before does not exceed the new screen.
static func nearest(wanted: Vector2i, screen: Vector2i) -> Vector2i:
	var fitting := available(screen)
	var best := fitting[0]
	for size in fitting:
		if size.x <= wanted.x and size.y <= wanted.y:
			best = size
	return best


## Where the window can be in windowed mode: the screen without the taskbar. A window the size
## of the whole screen would have its title bar past the top edge and its bottom under the
## taskbar, and on FullHD the default size came out exactly like that (code review M22).
static func window_area() -> Rect2i:
	return DisplayServer.screen_get_usable_rect()


## The whole screen: the size list is built from it. It cannot be built from the work
## area — on a 4K monitor that is shorter than 2160 by the taskbar, and 4K disappeared from
## the list (user's remark, M24b).
static func screen_rect() -> Rect2i:
	return Rect2i(DisplayServer.screen_get_position(), DisplayServer.screen_get_size())


## Where a window of size [param resolution] goes: centred in the work area
## [param usable] if it fits there with a frame, otherwise centred on screen
## [param screen] without a frame. So 4K on a 4K monitor is a full-screen window over
## the taskbar, not a window with its title past the edge.
static func windowed_rect(resolution: Vector2i, screen: Rect2i, usable: Rect2i) -> Rect2i:
	var size := nearest(resolution, screen.size)
	if size.x <= usable.size.x and size.y <= usable.size.y:
		return Rect2i(usable.position + (usable.size - size) / 2, size)
	return Rect2i(screen.position + (screen.size - size) / 2, size)


## Whether the window needs a frame: it does not if it does not fit in the work area.
static func framed(frame: Rect2i, usable: Rect2i) -> bool:
	return usable.encloses(frame)


## Applies mode and size to the window.
static func apply_window(mode: Mode, resolution: Vector2i) -> void:
	match mode:
		Mode.FULLSCREEN:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		Mode.BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_size(DisplayServer.screen_get_size())
			DisplayServer.window_set_position(DisplayServer.screen_get_position())
		_:
			var usable := window_area()
			var frame := windowed_rect(resolution, screen_rect(), usable)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(
				DisplayServer.WINDOW_FLAG_BORDERLESS, not framed(frame, usable)
			)
			DisplayServer.window_set_size(frame.size)
			DisplayServer.window_set_position(frame.position)


## [member Engine.max_fps] for limit [param limit] from [constant FRAME_LIMITS]:
## zero — no engine limit. "By monitor" without sync — the screen refresh rate
## [param refresh], if known; with sync it holds the frames itself.
static func max_fps(limit: int, vsync: bool, refresh: float) -> int:
	match limit:
		FRAME_UNLIMITED:
			return 0
		FRAME_MONITOR:
			return 0 if vsync or refresh <= 0.0 else roundi(refresh)
		_:
			return maxi(limit, 0)


## Window vertical sync mode for the settings flag.
static func vsync_mode(vsync: bool) -> DisplayServer.VSyncMode:
	return DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED


## Applies vertical sync to the window.
static func apply_vsync(vsync: bool) -> void:
	DisplayServer.window_set_vsync_mode(vsync_mode(vsync))


## Applies the frame limit: the refresh rate is asked of the screen the window is on.
static func apply_frame_limit(limit: int, vsync: bool) -> void:
	Engine.max_fps = max_fps(limit, vsync, DisplayServer.screen_get_refresh_rate())


## Fraction of the native resolution at which 3D is drawn: windowed — the whole window, in
## fullscreen and borderless — the chosen resolution [param resolution] relative to the screen
## [param screen].
static func share(mode: Mode, resolution: Vector2i, screen: Vector2i) -> float:
	if mode == Mode.WINDOWED or screen.y <= 0 or resolution == screen:
		return 1.0
	var size := nearest(resolution, screen)
	return clampf(float(size.y) / float(screen.y), MIN_SHARE, 1.0)


## Applies the 3D render fraction [param render_share] to the root viewport.
static func apply_scale(render_share: float, root: Viewport) -> void:
	var share := clampf(render_share, MIN_SHARE, 1.0)
	root.scaling_3d_mode = (
		Viewport.SCALING_3D_MODE_BILINEAR
		if is_equal_approx(share, 1.0)
		else Viewport.SCALING_3D_MODE_FSR
	)
	root.scaling_3d_scale = share
