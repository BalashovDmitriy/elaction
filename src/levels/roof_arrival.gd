class_name RoofArrival
extends RefCounted

## Вступление здания: вертолёт привозит Otto на крышу (ADR-0038, решение 1;
## режиссура — ADR-0052, решение 6).
##
## Полное — в первом здании партии, 10–12 с: вертолёт подлетает с закрытой
## дверью, зависает и откатывает её, Otto выглядывает в проём, садится на
## порог, бухту троса сбрасывают, он берётся за трос, соскальзывает с порога и
## быстро съезжает на руках, тормозя у крыши, — и встаёт с приседом. С этого
## мига он слушается игрока, а вертолёт выбирает трос, задвигает дверь, пилот
## кивает, и вертолёт уходит сам. Короткое — в остальных зданиях, около 6 с:
## вертолёт с первого кадра висит над местом с открытой дверью.
##
## Прыжок, выстрел или пауза пропускают вступление: Otto сразу стоит на крыше,
## вертолёт уходит оттуда, где был.
##
## Пока идёт вступление, Otto «едет» ([method Otto.ride]): ввод не действует,
## физика молчит, неуязвим, координатой распоряжается вступление — тот же приём,
## что у эскалатора. В плоскости игры он стоит под проёмом и на тросе; в глубину
## кадра, в проём, уходит его фигура ([member Otto.ride_depth]). Пока вертолёт
## летит, Otto в нём, то есть не виден.
##
## Камера наезжает без смены ракурса, как у добиваний ([method SideCamera.close_up]):
## крупнее на двери, ведёт Otto по тросу и после приземления отъезжает к
## игровому кадру ([method linger]).
##
## Уровень только зовёт [method advance] каждый шаг физики, пока идёт
## [method is_playing], и держит на это время агентов и кабины.

enum Step { FLY_IN, DOOR, PEEK, SIT, DROP, GRAB, SWING, SLIDE, DONE }

## Высота полозьев над крышей в висении, м: выше прыжка Otto (2.4 м) и такая,
## чтобы спуск читался спуском, а вертолёт с винтом влезал в кадр.
const HOVER_HEIGHT: float = 4.2

## Насколько выше верха мира поднят кадр вступления, м.
##
## Кадр на крыше упирается в верх мира в 4.8 м над настилом — вертолёт с
## винтом над тросом туда не влезает. На вступление кадр встаёт выше и по
## вертикали не ходит вовсе: полоса границ ровно в кадр высотой. Границы здания
## возвращаются, когда вертолёт улетел или Otto ушёл с крыши, и камера съезжает
## к ним сглаживанием, без рывка.
const CAMERA_HEADROOM: float = 4.5

## Выше кадр вступления не поднимается, даже если вертолёт висит выше обычного
## над высокой техникой: крыша должна остаться в кадре с запасом на рост Otto.
const DECK_IN_FRAME: float = 1.6

## Сколько над верхом вертолёта остаётся неба в кадре, м.
const SKY_ABOVE: float = 0.4

## Руки Otto на тросе, ступни ниже на столько, м: рост с поднятыми руками.
const REACH: float = Proportions.BODY * 1.15

## Сколько длится каждый шаг, с: полное вступление и короткое. Сброс троса и
## спуск длятся столько, сколько падает бухта и едет Otto.
const DOOR_PAUSE: float = 0.35
const PEEK_TIME: float = 1.5
const PEEK_TIME_SHORT: float = 0.9
const SIT_TIME: float = 1.0
const SIT_TIME_SHORT: float = 0.7
## Сколько трос качается, прежде чем Otto за него возьмётся, с.
const SETTLE_TIME: float = 0.45
const GRAB_TIME: float = 0.5
const SWING_TIME: float = 0.45

## Otto в проёме: насколько глубже порога стоит, выглядывая, и насколько
## порог под ним, когда он сидит, — ступни свисают ниже, м.
const PEEK_INSET: float = 0.3
const SIT_DROP: float = 0.5
const SIT_OUT: float = 0.05
## Где Otto берётся за трос: руки на столько выше порога, м.
const GRAB_ABOVE_SILL: float = 0.95

## Спуск по тросу на руках (ADR-0052, решение 6): разгон, предел скорости, м/с,
## и торможение у крыши — с какой высоты над ней ступней, м, с каким
## замедлением, м/с², и до какой скорости, м/с.
const SLIDE_SPEED: float = 7.0
const SLIDE_ACCELERATION: float = 14.0
const BRAKE_FROM: float = 1.8
const BRAKING: float = 11.0
const TOUCH_SPEED: float = 1.3

## Сколько вертолёт висит после приземления, прежде чем выбирать трос, с.
const LINGER: float = 0.35

## Наезд камеры: доля крупного плана у двери и на тросе, как быстро кадр идёт
## к нужному наезду, 1/с, и за сколько секунд отъезжает после приземления.
const CLOSE_AT_DOOR: float = 0.5
const CLOSE_ON_ROPE: float = 0.32
const CLOSE_EASE: float = 2.6
const CLOSE_RELEASE: float = 0.9
## Сколько неба над винтом и крыши под тросом остаётся в кадре у двери, м, на
## оба края вместе.
const DOOR_FRAME_MARGIN: float = 1.6
## Меньше этой доли наезд в расчёте точки не берётся: на нуле точка ушла бы в
## бесконечность, а кадр всё равно почти обычный.
const MIN_CLOSE: float = 0.05
## Середина кадра на тросе выше ступней Otto на столько, м.
const ROPE_FRAME_RISE: float = 1.0

## Действия, пропускающие вступление. Пауза — тоже, но её ловит [Main]: у него
## кнопка паузы, и открыть меню в ту же секунду он не должен.
const SKIP_ACTIONS: Array[StringName] = [&"jump", &"shoot"]

var _otto: Otto = null
var _helicopter: Helicopter = null
var _host: Node3D = null
var _landing := Vector2.ZERO
var _bounds := Rect2()
var _step: Step = Step.DONE
var _wait: float = 0.0
var _speed: float = 0.0
## Полное вступление или короткое.
var _full: bool = true
## Сколько троса между крюком и руками Otto, м.
var _along: float = 0.0
## Где вступление поставило Otto в прошлый шаг. Стоит он не там — его переставил
## кто-то другой (тест, инструмент съёмки), и вступление кончается само, не
## трогая его: так было и с тросом до M24b.
var _placed := Vector3.ZERO
## Какие действия были нажаты в прошлый шаг: пропуск — по нажатию, а не по
## удержанию, иначе прыжок, зажатый с прошлого здания, съедал бы вступление.
var _held: Dictionary = {}
## Кадр ещё держится на вступлении: границы здания не вернули.
var _camera_held: bool = false
## Наезд камеры сейчас и его середина в координатах сцены.
var _close: float = 0.0
var _close_point := Vector2.ZERO
## Сколько ещё отъезжает камера после приземления, с.
var _release_left: float = 0.0


## Начинает вступление: вертолёт появляется в [param host], Otto — в нём.
## [param landing] — место на крыше в плоскости правил, [param bounds] — границы
## камеры по зданию, которые вернутся после приземления. [param full] — полное
## вступление первого здания партии, иначе короткое; [param daytime] — утро
## или день: прожектор не горит.
func begin(
	host: Node3D,
	otto: Otto,
	landing: Vector2,
	bounds: Rect2,
	full: bool = false,
	daytime: bool = false
) -> void:
	_host = host
	_otto = otto
	_landing = landing
	_bounds = bounds
	_full = full
	var deck := WorldSpace.to_scene(landing).y
	var obstacles := roof_obstacles(host, deck, [otto] as Array[Node])
	_helicopter = Helicopter.new()
	host.add_child(_helicopter)
	# Вертолёт снаружи: днём на нём солнце (ADR-0051).
	Outdoors.mark(_helicopter)
	_helicopter.daytime = daytime
	_helicopter.avoid(obstacles)
	# Над высокой техникой — башней, антенной — вертолёт висит выше обычного.
	var hover := _helicopter.safe_hover(WorldSpace.to_scene(landing - Vector2(0.0, HOVER_HEIGHT)))
	_helicopter.fly_in(hover, not full)

	var hook := _helicopter.hook_at_hover(hover)
	_otto.ride_look = Otto.LOOK_HELI
	_otto.ride(true)
	_otto.visible = not full
	_place(Vector3(hook.x, hook.y - REACH, WorldSpace.PLAY_Z))
	# Кадр встаёт сразу, снимком: первый кадр здания — уже кадр вступления.
	# Висит вертолёт выше обычного — и кадр выше, пока крыша в нём остаётся.
	var top := WorldSpace.to_plane(hover).y - _helicopter.top_above_skids() - SKY_ABOVE
	var headroom := clampf(
		bounds.position.y - top,
		CAMERA_HEADROOM,
		bounds.position.y + Proportions.FIELD - landing.y - DECK_IN_FRAME
	)
	var framed := Rect2(
		bounds.position.x, bounds.position.y - headroom, bounds.size.x, Proportions.FIELD
	)
	_otto.apply_camera_bounds(framed)
	_camera_held = true
	for action: StringName in SKIP_ACTIONS:
		_held[action] = Input.is_action_pressed(action)
	_close = 0.0
	_close_point = Vector2(hover.x, hover.y)
	if full:
		_step = Step.FLY_IN
	else:
		_enter(Step.PEEK)


## Что стоит на крыше выше настила [param deck] (высота в координатах сцены):
## видимые меши уровня — техника, машинное отделение с антенной, кровля,
## вывеска. Без кабин (их прикрывает машинное отделение), без города (он в
## своём [SubViewport] и своём мире), без дождя (его струи и ореолы — не
## предметы) и без [param skip] — Otto и тому подобного.
static func roof_obstacles(host: Node, deck: float, skip: Array[Node]) -> Array[AABB]:
	var found: Array[AABB] = []
	for node: Node in host.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree() or _skipped(mesh, host, skip):
			continue
		var box := mesh.global_transform * mesh.mesh.get_aabb()
		if box.end.y > deck + 0.05 and box.position.y < deck + 20.0:
			found.append(box)
	return found


static func _skipped(node: Node, host: Node, skip: Array[Node]) -> bool:
	var at := node.get_parent()
	while at != null and at != host:
		if at is SubViewport or at is RoofRain or at is Helicopter or skip.has(at):
			return true
		# Кабина — внутри шахты, а её тросы тянутся до потолка машинного
		# отделения и режутся шейдером: габарит у них выше того, что видно.
		if at is ElevatorCar:
			return true
		at = at.get_parent()
	return false


## Идёт ли вступление: Otto ещё не на крыше.
func is_playing() -> bool:
	return _step != Step.DONE


## Полное ли вступление.
func is_full() -> bool:
	return _full


## Какой шаг идёт — для тестов и кадров.
func step() -> Step:
	return _step


## Вертолёт вступления; null, когда он уже улетел и убран.
func helicopter() -> Helicopter:
	return _helicopter if is_instance_valid(_helicopter) else null


## Пропускает вступление: Otto сразу на крыше. Возвращает, было ли что пропускать.
func skip() -> bool:
	if not is_playing():
		return false
	_land()
	_release_camera(true)
	return true


## Шаг после вступления: отъезд камеры к игровому кадру и возврат границ, когда
## вертолёт улетел или Otto ушёл с крыши — съехал кабиной, спрыгнул. Зовётся
## каждый шаг физики и почти всегда ничего не делает.
func linger(delta: float = 1.0 / 60.0) -> void:
	if _release_left > 0.0:
		_release_left = maxf(_release_left - delta, 0.0)
		var share := _release_left / CLOSE_RELEASE
		_frame(_close * smoothstep(0.0, 1.0, share), _close_point)
		if _release_left <= 0.0:
			_close = 0.0
	if not _camera_held or is_playing():
		return
	var off_the_roof := WorldSpace.to_plane(_otto.global_position).y > _landing.y + 0.5
	if helicopter() == null or off_the_roof:
		_restore_camera()


## Шаг вступления. [param delta] — шаг физики, с.
func advance(delta: float) -> void:
	if not is_playing():
		return
	if _otto.global_position.distance_to(_placed) > 0.01:
		# Переставили — вступление им больше не распоряжается.
		_let_go()
		return
	if _skip_pressed():
		# Нажатие потрачено на пропуск: Otto, отпущенный в этом же шаге, его
		# уже не получит — ни выстрела, ни прыжка с места приземления.
		_land(true)
		_release_camera(true)
		return

	_wait -= delta
	match _step:
		Step.FLY_IN:
			_hold_in_the_cabin()
			if _helicopter.is_hovering():
				_helicopter.set_door_open(true)
				_enter(Step.DOOR)
		Step.DOOR:
			_hold_in_the_cabin()
			if _helicopter.door_share() >= 1.0 and _wait <= 0.0:
				_enter(Step.PEEK)
		Step.PEEK:
			_peek()
			if _wait <= 0.0:
				_enter(Step.SIT)
		Step.SIT:
			_sit_down()
			if _wait <= 0.0:
				_helicopter.drop_rope(_hook_height() - _deck_height())
				_enter(Step.DROP)
		Step.DROP:
			_sit_down()
			if _helicopter.rope_is_down() and _wait <= 0.0:
				_enter(Step.GRAB)
			elif not _helicopter.rope_is_down():
				_wait = SETTLE_TIME
		Step.GRAB:
			_sit_down()
			if _wait <= 0.0:
				_enter(Step.SWING)
		Step.SWING:
			_swing_out()
			if _wait <= 0.0:
				_enter(Step.SLIDE)
		Step.SLIDE:
			_slide(delta)
	_follow(delta)


## Переход к шагу [param next]: его длина, поза и звук.
func _enter(next: Step) -> void:
	_step = next
	match next:
		Step.DOOR:
			_wait = DOOR_PAUSE
		Step.PEEK:
			_wait = PEEK_TIME if _full else PEEK_TIME_SHORT
			_otto.visible = true
			_otto.ride_pose = ActorPose.PEEK
			_otto.ride_turn = 1.0
		Step.SIT:
			_wait = SIT_TIME if _full else SIT_TIME_SHORT
			_otto.ride_pose = ActorPose.SIT_EDGE
		Step.DROP:
			_wait = SETTLE_TIME
		Step.GRAB:
			_wait = GRAB_TIME
			_otto.ride_pose = ActorPose.SIT_GRAB
		Step.SWING:
			_wait = SWING_TIME
			_along = maxf(_hook_height() - _sill().y - GRAB_ABOVE_SILL, 0.2)
			_otto.ride_pose = ActorPose.ROPE
		Step.SLIDE:
			_otto.ride_look = Otto.LOOK_ROPE
			_otto.ride_depth = 0.0
			_otto.ride_turn = 0.0
			_speed = 0.0
			_helicopter.rope_slide(true)


## Пока вертолёт летит и открывает дверь, Otto в салоне: не виден и стоит под
## крюком, куда смотрит кадр.
func _hold_in_the_cabin() -> void:
	var hook := _helicopter.hook()
	_place(Vector3(hook.x, hook.y - REACH, WorldSpace.PLAY_Z))


## Выглядывает: стоит на полу салона в глубине проёма, лицом к камере.
func _peek() -> void:
	var sill := _sill()
	_place(Vector3(sill.x, sill.y, WorldSpace.PLAY_Z))
	_otto.ride_depth = sill.z - WorldSpace.PLAY_Z - PEEK_INSET


## Садится на порог: опускается и выдвигается к краю за время шага, потом
## сидит, свесив ноги, — и пока падает бухта, и пока берётся за трос.
func _sit_down() -> void:
	var sill := _sill()
	var share := 1.0
	if _step == Step.SIT:
		var total := SIT_TIME if _full else SIT_TIME_SHORT
		share = smoothstep(0.0, 1.0, 1.0 - _wait / total)
	var drop := SIT_DROP * share
	_place(Vector3(sill.x, sill.y - drop, WorldSpace.PLAY_Z))
	_otto.ride_depth = (sill.z - WorldSpace.PLAY_Z + lerpf(-PEEK_INSET, SIT_OUT, share))


## Соскальзывает с порога на трос: из сидячей в висящую, в плоскость игры, и
## поворачивается вдоль этажа.
func _swing_out() -> void:
	var share := smoothstep(0.0, 1.0, 1.0 - _wait / SWING_TIME)
	var sill := _sill()
	var seated := Vector3(sill.x, sill.y - SIT_DROP, WorldSpace.PLAY_Z)
	var hanging := _on_rope()
	_place(seated.lerp(hanging, share))
	_otto.ride_depth = lerpf(sill.z - WorldSpace.PLAY_Z + SIT_OUT, 0.0, share)
	_otto.ride_turn = 1.0 - share


## Съезжает на руках: разгон до предела и торможение у крыши.
func _slide(delta: float) -> void:
	var feet := _on_rope().y
	var left := feet - _deck_height()
	if left < BRAKE_FROM:
		var allowed := maxf(sqrt(2.0 * BRAKING * maxf(left, 0.0)), TOUCH_SPEED)
		_speed = minf(_speed, allowed)
	else:
		_speed = minf(_speed + SLIDE_ACCELERATION * delta, SLIDE_SPEED)
	_along += _speed * delta
	var at := _on_rope()
	if at.y <= _deck_height() + 0.001:
		_land()
		_release_camera(false)
		return
	_place(at)


## Где стоит Otto, держась за трос в [member _along] метрах от крюка: ступни
## ниже рук на рост с поднятыми руками, в плоскости игры.
func _on_rope() -> Vector3:
	var hands := _helicopter.rope_point(_along)
	return Vector3(hands.x, hands.y - REACH, WorldSpace.PLAY_Z)


## Конец вступления приездом или пропуском: Otto стоит на месте приземления и
## слушается, вертолёт уходит, а кадр вступления держится, пока он не улетел
## ([method linger]).
##
## [param presses_spent] — вступление пропущено нажатием, и Otto его не слышит
## ([method Otto.ride]).
func _land(presses_spent: bool = false) -> void:
	_otto.global_position = WorldSpace.to_scene(_landing)
	# Приземление с приседом — клипом троса, а не стойкой из проёма.
	_otto.ride_look = Otto.LOOK_ROPE
	_release(presses_spent)


## Отпускает Otto там, где его поставили, — тест, съёмка, возвращение после
## гибели. Кадр догоняет его сразу, снимком: вступление им не распоряжается.
func _let_go() -> void:
	_otto.ride_look = ""
	_release()
	_release_camera(true)
	_otto.apply_camera_bounds(_bounds)
	_camera_held = false


func _release(presses_spent: bool = false) -> void:
	var sliding := _step == Step.SLIDE
	_step = Step.DONE
	_otto.visible = true
	_otto.ride(false, presses_spent)
	if is_instance_valid(_helicopter):
		# Приехал — звук троса доигрывает сам, он короче спуска; сорвали
		# посреди спуска — обрывается.
		if not sliding or _otto.global_position.distance_to(_placed) > 0.01:
			_helicopter.rope_slide(false)
		_helicopter.leave(LINGER)


## Кадр едет к наезду шага: у двери — на проём, на тросе — за Otto.
func _follow(delta: float) -> void:
	if not is_playing():
		return
	var wanted := 0.0
	var point := _close_point
	match _step:
		Step.DOOR, Step.PEEK, Step.SIT, Step.DROP, Step.GRAB:
			# Крупно, но так, чтобы в кадр влезли и винт, и крыша под тросом.
			var top := _helicopter.global_position.y + _helicopter.top_above_skids()
			var deck := _deck_height()
			var needed := (top - deck + DOOR_FRAME_MARGIN) / Proportions.FIELD
			var room := (1.0 - needed) / (1.0 - SideCamera.CLOSE_UP_SIZE)
			wanted = clampf(room, 0.0, CLOSE_AT_DOOR)
			point = Vector2(_sill().x, (top + deck) * 0.5)
		Step.SWING, Step.SLIDE:
			wanted = CLOSE_ON_ROPE
			point = Vector2(_otto.global_position.x, _otto.global_position.y + ROPE_FRAME_RISE)
	var ease := 1.0 - exp(-CLOSE_EASE * delta)
	_close = lerpf(_close, wanted, ease)
	_close_point = _close_point.lerp(point, ease)
	_frame(_close, _close_point)


## Отъезд к игровому кадру: после приземления — плавно, на пропуске — сразу.
func _release_camera(at_once: bool) -> void:
	if at_once:
		_close = 0.0
		_release_left = 0.0
		_frame(0.0, _close_point)
	else:
		_release_left = CLOSE_RELEASE


## Наезд на [param amount] с серединой кадра в [param centre]. Камера ставит
## середину между целью — Otto — и точкой наезда в доле наезда
## ([method SideCamera.close_up]); точка считается обратно, чтобы середина
## встала туда, куда нужно вступлению.
func _frame(amount: float, centre: Vector2) -> void:
	var camera := _camera()
	if camera == null:
		return
	var otto := Vector2(_otto.global_position.x, _otto.global_position.y)
	var point := otto + (centre - otto) / maxf(amount, MIN_CLOSE)
	camera.close_up(amount, point)


func _camera() -> SideCamera:
	if _host == null or not is_instance_valid(_host) or not _host.is_inside_tree():
		return null
	var viewport := _host.get_viewport()
	return viewport.get_camera_3d() as SideCamera if viewport != null else null


## Возвращает камере границы здания — без снимка, сглаживанием.
func _restore_camera() -> void:
	_camera_held = false
	_otto.apply_camera_bounds(_bounds, false)


func _place(at: Vector3) -> void:
	_otto.global_position = at
	_placed = at


## Порог проёма в координатах сцены.
func _sill() -> Vector3:
	return _helicopter.doorway()


func _hook_height() -> float:
	return _helicopter.hook().y


func _deck_height() -> float:
	return WorldSpace.to_scene(_landing).y


func _skip_pressed() -> bool:
	var pressed := false
	for action: StringName in SKIP_ACTIONS:
		var down := Input.is_action_pressed(action)
		if down and not bool(_held.get(action, false)):
			pressed = true
		_held[action] = down
	return pressed
