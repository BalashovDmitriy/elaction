class_name SideCamera
extends Camera3D

## Ортографическая камера сбоку, наклонённая чуть сверху.
##
## Держит только то, что обязано быть в узле: читает размер окна, двигает
## трансформ, зовёт правило. Само правило — [CameraBounds], и оно без сцены.
##
## Наклон — свойство камеры, а не мира (ADR-0023, решение 1). Плоскость игры,
## попадания и полоса видимых этажей считаются как считались: камера лишь стоит
## выше цели, чтобы её ось прошла через точку плоскости игры, и видит по
## вертикали чуть больше. Строго сбоку верх перекрытия — полоска нулевой
## толщины, и отражений в полу не было бы никогда.

## Половина высоты кадра, м.
##
## Кадр показывает 3.67 этажа — столько, сколько поле здания у оригинала: 176 px
## при шаге этажа 48 (ADR-0026, решение 4). До M18c было 10.8 м и ровно три
## этажа. По ширине при 16:9 это 23.5 м — 7.8 просвета против 6.4 у оригинала:
## поле аркады уже экрана, и совпасть по обеим осям нельзя.
##
## Ортокамера наклонена, и на плоскости игры кадр выше её размера в 1/cos(наклона)
## раз ([method _read_frame]). Поэтому размер меньше поля на этот косинус: без
## поправки в кадр входило 3.72 этажа вместо 3.67 (авторевью M18c). Число —
## cos(10°): функции в константу GDScript не пускает.
const DEFAULT_HALF_HEIGHT: float = Proportions.FIELD * 0.5 * 0.98480775

## Насколько камера отодвинута от плоскости игры вдоль своей оси, м.
##
## Ортокамере расстояние безразлично для масштаба, но не для отсечения: всё,
## что ближе [member near], не рисуется, а коридор и актёры стоят на Z = 0.
const DISTANCE: float = 20.0

## Наклон сверху, градусы. Десять открывают пол коридора полосой в треть метра —
## в неё ложатся отражения и пятна ламп, — а этажи остаются параллельными
## полосами кадра. Перспектива отвергнута: у неё верх и низ кадра в разном
## масштабе, и правило «этаж — полоса кадра» пришлось бы пересчитывать.
const TILT_DEGREES: float = 10.0

## Во сколько раз уже кадр на крупном плане сценки добивания (ADR-0040).
const CLOSE_UP_SIZE: float = 0.38
## Свет камеры на фигуры: холодный, как лунный, и слабый — силуэт, а не
## освещённая фигура.
const ACTOR_FILL_COLOR := Color(0.62, 0.7, 0.95)
const ACTOR_FILL_ENERGY: float = 0.35

## Толчок камеры на ударе добивания (ADR-0050): сдвиг кадра, м, крен, рад, и
## добавочный наезд — доля размера кадра — при толчке в полную силу; за сколько
## секунд настоящего времени он гаснет и как часто дрожит, Гц. Время — не мира:
## мир на ударе почти стоит, а толчок должен пройти.
const KICK_SHIFT: float = 0.09
const KICK_ROLL: float = 0.04
const KICK_ZOOM: float = 0.12
const KICK_FADE: float = 0.45
const KICK_RATE: float = 19.0

## Скорость сглаживания. Число то же, что стояло у [Camera2D] в 2D-сцене.
@export var smoothing_speed: float = 8.0

var _bounds := CameraBounds.new()
## Кадр по правилам боя: 16:9 и без сглаживания, см. [method rule_view].
var _rule_bounds := CameraBounds.new()
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
## Крупный план: насколько наехали, 0–1, и на что. Ведёт его режиссёр сценки.
var _close: float = 0.0
var _close_point := Vector2.ZERO
## Сила толчка, 0–1, и сколько он уже идёт, с настоящего времени.
var _kick: float = 0.0
var _kick_age: float = 0.0
var _kick_ticks: int = 0


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	# Камера смотрит вдоль -Z, стоя перед плоскостью игры; отрицательный поворот
	# вокруг X опускает взгляд.
	rotation = Vector3(-_tilt(), 0.0, 0.0)
	size = DEFAULT_HALF_HEIGHT * 2.0
	near = 0.05
	far = DISTANCE * 2.0
	_read_frame()
	get_viewport().size_changed.connect(_read_frame)

	add_child(actor_fill())

	_listener = AudioListener3D.new()
	# По оси камеры до плоскости игры: с наклоном это дальше, чем [constant DISTANCE].
	_listener.position = Vector3(0.0, 0.0, -DISTANCE / cos(_tilt()))
	add_child(_listener)
	_listener.make_current()


func _process(delta: float) -> void:
	if _target == null:
		return
	var wanted := _bounds.clamp_centre(_target_point().lerp(_close_point, _close))
	# На крупном плане ход задаёт режиссёр плавной кривой, а мир вокруг замедлен:
	# сглаживание по замедленным часам волокло бы кадр позади пары.
	if _close > 0.0:
		_centre = wanted
	else:
		_centre = CameraBounds.smoothed(_centre, wanted, smoothing_speed, delta)
	global_position = _perch(_centre)
	_shake()


## Толкает кадр: сдвиг, крен и добавочный наезд, гаснущие за [constant
## KICK_FADE] с настоящего времени. [param strength] — 0–1.
func kick(strength: float) -> void:
	_kick = clampf(strength, 0.0, 1.0)
	_kick_age = 0.0
	_kick_ticks = Time.get_ticks_msec()


## Идёт ли толчок. Тестам.
func is_kicked() -> bool:
	return _kick > 0.0


func _shake() -> void:
	if _kick <= 0.0:
		return
	_kick_age = (Time.get_ticks_msec() - _kick_ticks) / 1000.0
	var left := 1.0 - _kick_age / KICK_FADE
	if left <= 0.0:
		_kick = 0.0
		rotation = Vector3(-_tilt(), 0.0, 0.0)
		close_up(_close, _close_point)
		return
	var force := _kick * left * left
	var wave := _kick_age * KICK_RATE * TAU
	global_position += (
		Vector3(sin(wave) * KICK_SHIFT, cos(wave * 1.3) * KICK_SHIFT * 0.6, 0.0) * force
	)
	rotation = Vector3(-_tilt(), 0.0, sin(wave * 0.7) * KICK_ROLL * force)
	size = DEFAULT_HALF_HEIGHT * 2.0 * lerpf(1.0, CLOSE_UP_SIZE, _close) * (1.0 - KICK_ZOOM * force)


## Свет камеры на фигуры: слабый, по оси взгляда, только на слой фигур
## ([constant FigureRig.RENDER_LAYER]). Им, а не обводкой, Otto и агенты
## читаются на погашенном этаже (ADR-0042, решение 7): окружение ему не
## подчиняется, и темнота этажа остаётся темнотой. Без тени и мимо тумана.
static func actor_fill() -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = "ActorFill"
	light.light_color = ACTOR_FILL_COLOR
	light.light_energy = ACTOR_FILL_ENERGY
	light.light_cull_mask = FigureRig.RENDER_LAYER
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = 0.0
	light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	return light


## За кем ехать. Обычно это Otto.
func follow(target: Node3D) -> void:
	_target = target
	if target != null:
		snap_to(_target_point())


## Крупный план сценки добивания (ADR-0040): [param amount] 0 — обычный кадр,
## 1 — уже в [constant CLOSE_UP_SIZE] раза и с серединой в [param point]
## (координаты сцены). Кадр боя ([method rule_view]) крупный план не трогает:
## кто кого видит, решает он, и наезд камеры бой менять не должен.
func close_up(amount: float, point: Vector2) -> void:
	_close = clampf(amount, 0.0, 1.0)
	_close_point = point
	size = DEFAULT_HALF_HEIGHT * 2.0 * lerpf(1.0, CLOSE_UP_SIZE, _close)
	_read_frame()


## Ставит камеру на место без сглаживания.
##
## Нужно на старте уровня и при возвращении в игру: иначе камера приезжает
## к воскресшему Otto через полсекунды, и эти полсекунды игрок смотрит туда,
## где его убили.
func snap_to(point: Vector2) -> void:
	_centre = _bounds.clamp_centre(point)
	global_position = _perch(_centre)


## Границы, за которые камере нельзя выходить. Приходят в координатах правил
## (Y вниз) и переводятся здесь: снаружи о развороте Y знать не должны.
##
## Границы приходят вместе с расстановкой уровня, когда цель уже стоит на
## месте. Поэтому камера встаёт на неё, а не на прежнюю середину: та осталась
## от [method follow], позванного из [method Node._ready] Otto, когда он ещё
## стоял в начале координат, — и от неё камера полсекунды ехала бы вбок через
## пустое здание. [Camera2D] такого не делал: он вставал на место первым кадром.
##
## [param snap] = false оставляет камеру ехать к новым границам сглаживанием: так
## кадр вступления, пущенный выше верха мира, опускается к зданию (ADR-0038).
func apply_bounds(rect: Rect2, snap: bool = true) -> void:
	# Низ правил — это верх сцены, и наоборот.
	var lowest := WorldSpace.height_to_scene(rect.end.y)
	var highest := WorldSpace.height_to_scene(rect.position.y)
	_bounds.limits = Rect2(rect.position.x, lowest, rect.size.x, highest - lowest)
	_rule_bounds.limits = _bounds.limits
	if snap:
		snap_to(_target_point() if _target != null else _centre)


## Что сейчас в кадре, в координатах правил.
func view() -> Rect2:
	return _to_plane(_bounds.view_at(_centre))


## Кадр, по которому решает бой, в координатах правил: тот же, что у игрока,
## но при 16:9 и без сглаживания — встаёт на цель сразу.
##
## Кадр игрока едет в [method Node._process] по настенным часам и шире на
## широком окне. Исход партии обязан идти от физики (`docs/testing.md`, правило
## из M18b): по кадру игрока агент стрелял бы или нет в зависимости от машины
## и размера окна, и прогон бота переставал бы повторяться (ADR-0027, решение 3а).
func rule_view() -> Rect2:
	var centre := _centre if _target == null else _rule_bounds.clamp_centre(_target_point())
	return _to_plane(_rule_bounds.view_at(centre))


## Кадр сцены — в координаты правил: Y там растёт вниз.
static func _to_plane(scene_view: Rect2) -> Rect2:
	var top := WorldSpace.height_to_plane(scene_view.end.y)
	return Rect2(scene_view.position.x, top, scene_view.size.x, scene_view.size.y)


## Где сейчас цель, в координатах сцены. Z отбрасывается: кадр плоский.
func _target_point() -> Vector2:
	return Vector2(_target.global_position.x, _target.global_position.y)


## Где стоит камера, чтобы её ось прошла через [param centre] в плоскости игры:
## выше на «расстояние × tg(наклон)», иначе наклон смотрел бы под ноги цели.
func _perch(centre: Vector2) -> Vector3:
	return Vector3(centre.x, centre.y + DISTANCE * tan(_tilt()), DISTANCE)


func _tilt() -> float:
	return deg_to_rad(TILT_DEGREES)


## Пересчитывает половины кадра по размеру окна: ширина кадра зависит от
## соотношения сторон, и на другом окне она другая.
##
## По вертикали наклонённая камера накрывает в плоскости игры чуть больше своего
## размера — на 1/cos(наклон): кадр режет плоскость под углом.
func _read_frame() -> void:
	var window := get_viewport().get_visible_rect().size
	var aspect := window.x / maxf(window.y, 1.0)
	_bounds.half_height = size * 0.5 / cos(_tilt())
	_bounds.half_width = size * 0.5 * aspect
