class_name SideCamera
extends Camera3D

## Ортографическая камера сбоку — тот же кадр, что давал [Camera2D] в 2D.
##
## Держит только то, что обязано быть в узле: читает размер окна, двигает
## трансформ, зовёт правило. Само правило — [CameraBounds], и оно без сцены.
##
## Камера строго боковая. Наклонять её, чтобы стало видно пол и появились
## отражения, — открытый вопрос вехи света (ADR-0019, решение 6): в греев-боксе
## наклонять нечего, пол пустой.

## Половина высоты кадра, м. Прежний кадр — 1080 px при 100 px в метре.
const DEFAULT_HALF_HEIGHT: float = 5.4

## Насколько камера отодвинута от плоскости игры, м.
##
## Ортокамере расстояние безразлично для масштаба, но не для отсечения: всё,
## что ближе [member near], не рисуется, а коридор и актёры стоят на Z = 0.
const DISTANCE: float = 20.0

## Скорость сглаживания. Число то же, что стояло у [Camera2D] в 2D-сцене.
@export var smoothing_speed: float = 8.0

var _bounds := CameraBounds.new()
## За кем едет камера. Пустой — камера стоит там, где её поставили.
var _target: Node3D = null
var _centre := Vector2.ZERO
## Слушатель позиционного звука. Стоит в плоскости игры, а не у камеры: камера
## отодвинута на [constant DISTANCE], и без него каждый источник — гул кабины,
## «динь», створка двери — был бы дальше своего `max_distance` и молчал бы.
## В 2D слушателем был центр кадра, и дальности подобраны под него.
##
## Заводится в [method Node._ready], а не при объявлении: узел, созданный полем и
## не попавший в дерево, никто не освобождает — сцена Otto, поднятая тестом ради
## размера формы и тут же выброшенная, оставляла бы его сиротой.
var _listener: AudioListener3D = null


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	# Ортокамера смотрит вдоль -Z, стоя перед плоскостью игры.
	rotation = Vector3.ZERO
	size = DEFAULT_HALF_HEIGHT * 2.0
	near = 0.05
	far = DISTANCE * 2.0
	_read_frame()
	get_viewport().size_changed.connect(_read_frame)

	_listener = AudioListener3D.new()
	_listener.position = Vector3(0.0, 0.0, -DISTANCE)
	add_child(_listener)
	_listener.make_current()


func _process(delta: float) -> void:
	if _target == null:
		return
	var wanted := _bounds.clamp_centre(_target_point())
	_centre = CameraBounds.smoothed(_centre, wanted, smoothing_speed, delta)
	global_position = Vector3(_centre.x, _centre.y, DISTANCE)


## За кем ехать. Обычно это Otto.
func follow(target: Node3D) -> void:
	_target = target
	if target != null:
		snap_to(_target_point())


## Ставит камеру на место без сглаживания.
##
## Нужно на старте уровня и при возвращении в игру: иначе камера приезжает
## к воскресшему Otto через полсекунды, и эти полсекунды игрок смотрит туда,
## где его убили.
func snap_to(point: Vector2) -> void:
	_centre = _bounds.clamp_centre(point)
	global_position = Vector3(_centre.x, _centre.y, DISTANCE)


## Границы, за которые камере нельзя выходить. Приходят в координатах правил
## (Y вниз) и переводятся здесь: снаружи о развороте Y знать не должны.
##
## Границы приходят вместе с расстановкой уровня, когда цель уже стоит на
## месте. Поэтому камера встаёт на неё, а не на прежнюю середину: та осталась
## от [method follow], позванного из [method Node._ready] Otto, когда он ещё
## стоял в начале координат, — и от неё камера полсекунды ехала бы вбок через
## пустое здание. [Camera2D] такого не делал: он вставал на место первым кадром.
func apply_bounds(rect: Rect2) -> void:
	# Низ правил — это верх сцены, и наоборот.
	var lowest := WorldSpace.height_to_scene(rect.end.y)
	var highest := WorldSpace.height_to_scene(rect.position.y)
	_bounds.limits = Rect2(rect.position.x, lowest, rect.size.x, highest - lowest)
	snap_to(_target_point() if _target != null else _centre)


## Что сейчас в кадре, в координатах правил.
func view() -> Rect2:
	var scene_view := _bounds.view_at(_centre)
	var top := WorldSpace.height_to_plane(scene_view.end.y)
	return Rect2(scene_view.position.x, top, scene_view.size.x, scene_view.size.y)


## Где сейчас цель, в координатах сцены. Z отбрасывается: кадр плоский.
func _target_point() -> Vector2:
	return Vector2(_target.global_position.x, _target.global_position.y)


## Пересчитывает половины кадра по размеру окна: ширина кадра зависит от
## соотношения сторон, и на другом окне она другая.
func _read_frame() -> void:
	var window := get_viewport().get_visible_rect().size
	var aspect := window.x / maxf(window.y, 1.0)
	_bounds.half_height = size * 0.5
	_bounds.half_width = size * 0.5 * aspect
