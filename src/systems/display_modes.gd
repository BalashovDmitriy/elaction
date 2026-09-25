class_name DisplayModes
extends RefCounted

## Режим окна, разрешение и масштаб 3D-рендера (M22, вопрос пользователя —
## поддержка 4K и любых разрешений монитора).
##
## Сцена рисуется в настоящем разрешении окна: интерфейс растягивается от
## базовых 1920×1080 (`stretch = canvas_items`), а 3D — нет, поэтому на 4K
## кадр честный, не растянутый. Полный экран — в родном разрешении монитора;
## окно — одного из стандартных размеров, которые монитор держит. Масштаб
## рендера рисует сцену меньше и растягивает FSR: на слабой карте 4K
## выдерживается, а интерфейс остаётся чётким — он масштабом не задет.
##
## Без узлов: что предложить и как применить, проверяется тестом.

enum Mode { WINDOWED, BORDERLESS, FULLSCREEN }

## Стандартные размеры окна, 16:9, от малого к большому.
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3200, 1800),
	Vector2i(3840, 2160),
]

## Масштаб 3D-рендера, доли разрешения окна. Сто процентов — без FSR.
const RENDER_SCALES: Array[float] = [1.0, 0.77, 0.67, 0.5]

## Размер окна по умолчанию — базовый размер проекта.
const DEFAULT_RESOLUTION := Vector2i(1920, 1080)


## Размеры окна, которые влезают на экран [param screen]. Хоть один — всегда:
## на экране меньше 720p окно будет больше экрана, но игра запустится.
static func available(screen: Vector2i) -> Array[Vector2i]:
	var fitting: Array[Vector2i] = []
	for size in RESOLUTIONS:
		if size.x <= screen.x and size.y <= screen.y:
			fitting.append(size)
	if fitting.is_empty():
		fitting.append(RESOLUTIONS[0])
	return fitting


## Ближайший к [param wanted] размер из тех, что влезают на экран: монитор
## сменили — настройка с прошлого не выходит за новый экран.
static func nearest(wanted: Vector2i, screen: Vector2i) -> Vector2i:
	var fitting := available(screen)
	var best := fitting[0]
	for size in fitting:
		if size.x <= wanted.x and size.y <= wanted.y:
			best = size
	return best


## Где может стоять окно в режиме окна: экран без панели задач. Окно в размер
## всего экрана уходило бы заголовком за верхний край, а низом — под панель
## задач, и на FullHD размер по умолчанию так и выходил (авторевью M22).
static func window_area() -> Rect2i:
	return DisplayServer.screen_get_usable_rect()


## Экран целиком: по нему строится список размеров. По рабочей области его
## строить нельзя — на 4K-мониторе она ниже 2160 на панель задач, и 4K из
## списка пропадал (замечание пользователя, M24b).
static func screen_rect() -> Rect2i:
	return Rect2i(DisplayServer.screen_get_position(), DisplayServer.screen_get_size())


## Где встанет окно размера [param resolution]: по середине рабочей области
## [param usable], если влезает в неё с рамкой, иначе — по середине экрана
## [param screen] без рамки. Так 4K на 4K-мониторе — окно во весь экран поверх
## панели задач, а не окно с заголовком за краем.
static func windowed_rect(resolution: Vector2i, screen: Rect2i, usable: Rect2i) -> Rect2i:
	var size := nearest(resolution, screen.size)
	if size.x <= usable.size.x and size.y <= usable.size.y:
		return Rect2i(usable.position + (usable.size - size) / 2, size)
	return Rect2i(screen.position + (screen.size - size) / 2, size)


## Нужна ли окну рамка: не нужна, если оно не влезает в рабочую область.
static func framed(frame: Rect2i, usable: Rect2i) -> bool:
	return usable.encloses(frame)


## Применяет режим и размер к окну.
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


## Применяет масштаб 3D-рендера к корневому виду.
static func apply_scale(render_scale: float, root: Viewport) -> void:
	var share := clampf(render_scale, RENDER_SCALES[-1], 1.0)
	root.scaling_3d_mode = (
		Viewport.SCALING_3D_MODE_BILINEAR
		if is_equal_approx(share, 1.0)
		else Viewport.SCALING_3D_MODE_FSR
	)
	root.scaling_3d_scale = share
