class_name RoofArrival
extends RefCounted

## Вступление здания: вертолёт привозит Otto на крышу (ADR-0038, решение 1).
##
## Вертолёт влетает слева и зависает над местом приземления, спускает трос,
## Otto съезжает по нему и встаёт на крышу — с этого мига он слушается игрока, а
## вертолёт выбирает трос и уходит сам. Прыжок, выстрел или пауза пропускают
## вступление: Otto сразу стоит на крыше, вертолёт уходит оттуда, где был.
##
## Пока идёт вступление, Otto «едет» ([method Otto.ride]): ввод не действует,
## физика молчит, неуязвим, координатой распоряжается вступление — тот же приём,
## что у эскалатора. Пока вертолёт летит, Otto в нём, то есть не виден; стоит
## он при этом там, где потом повиснет на тросе, — на него смотрит камера, и
## вертолёт влетает в неподвижный кадр, а не тащит кадр за собой.
##
## Уровень только зовёт [method advance] каждый шаг физики, пока идёт
## [method is_playing], и держит на это время агентов и кабины.

enum Step { FLY_IN, GRAB, SLIDE, DONE }

## Высота полозьев над крышей в висении, м: выше прыжка Otto (2.4 м) и такая,
## чтобы спуск читался спуском, а вертолёт с винтом влезал в кадр.
const HOVER_HEIGHT: float = 4.2

## Насколько выше верха мира поднят кадр вступления, м.
##
## Кадр на крыше упирается в верх мира в 4.8 м над настилом — вертолёт с
## винтом над тросом туда не влезает. На вступление кадр встаёт выше и по
## вертикали не ходит вовсе: полоса границ ровно в кадр высотой. Вертолёт
## влетает, Otto съезжает и встаёт, вертолёт уходит — всё в одном неподвижном
## кадре. Границы здания возвращаются, когда вертолёт улетел или Otto ушёл
## с крыши, и камера съезжает к ним сглаживанием, без рывка.
const CAMERA_HEADROOM: float = 4.5

## Выше кадр вступления не поднимается, даже если вертолёт висит выше обычного
## над высокой техникой: крыша должна остаться в кадре с запасом на рост Otto.
const DECK_IN_FRAME: float = 1.6

## Сколько над верхом вертолёта остаётся неба в кадре, м.
const SKY_ABOVE: float = 0.4

## Руки Otto на крюке, ступни ниже на столько, м: рост с поднятыми руками.
const REACH: float = Proportions.BODY * 1.15

## Сколько Otto висит на тросе, прежде чем поехать, с.
const GRAB_PAUSE: float = 0.3

## Скорость спуска по тросу, м/с, и разгон до неё: с места он не срывается.
## Чуть медленнее, чем было на коротком тросе (4.2): трос длиннее, и спуск
## должно быть видно.
const SLIDE_SPEED: float = 3.6
const SLIDE_ACCELERATION: float = 9.0

## Сколько вертолёт висит после приземления, прежде чем уйти, с.
const LINGER: float = 0.35

## Действия, пропускающие вступление. Пауза — тоже, но её ловит [Main]: у него
## кнопка паузы, и открыть меню в ту же секунду он не должен.
const SKIP_ACTIONS: Array[StringName] = [&"jump", &"shoot"]

var _otto: Otto = null
var _helicopter: Helicopter = null
var _landing := Vector2.ZERO
var _bounds := Rect2()
var _step: Step = Step.DONE
var _wait: float = 0.0
var _speed: float = 0.0
## Где вступление поставило Otto в прошлый шаг. Стоит он не там — его переставил
## кто-то другой (тест, инструмент съёмки), и вступление кончается само, не
## трогая его: так было и с тросом до M24b.
var _placed := Vector3.ZERO
## Какие действия были нажаты в прошлый шаг: пропуск — по нажатию, а не по
## удержанию, иначе прыжок, зажатый с прошлого здания, съедал бы вступление.
var _held: Dictionary = {}
## Кадр ещё держится на вступлении: границы здания не вернули.
var _camera_held: bool = false


## Начинает вступление: вертолёт появляется в [param host], Otto — в нём.
## [param landing] — место на крыше в плоскости правил, [param bounds] — границы
## камеры по зданию, которые вернутся после приземления.
func begin(host: Node3D, otto: Otto, landing: Vector2, bounds: Rect2) -> void:
	_otto = otto
	_landing = landing
	_bounds = bounds
	var deck := WorldSpace.to_scene(landing).y
	var obstacles := roof_obstacles(host, deck, [otto] as Array[Node])
	_helicopter = Helicopter.new()
	host.add_child(_helicopter)
	_helicopter.avoid(obstacles)
	# Над высокой техникой — башней, антенной — вертолёт висит выше обычного.
	var hover := _helicopter.safe_hover(WorldSpace.to_scene(landing - Vector2(0.0, HOVER_HEIGHT)))
	_helicopter.fly_in(hover)

	var hook := _helicopter.hook_at_hover(hover)
	_otto.ride(true)
	_otto.visible = false
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
	_step = Step.FLY_IN


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


## Вертолёт вступления; null, когда он уже улетел и убран.
func helicopter() -> Helicopter:
	return _helicopter if is_instance_valid(_helicopter) else null


## Пропускает вступление: Otto сразу на крыше. Возвращает, было ли что пропускать.
func skip() -> bool:
	if not is_playing():
		return false
	_land()
	return true


## Шаг после вступления: вернуть кадр, когда вертолёт улетел или Otto ушёл с
## крыши — съехал кабиной, спрыгнул. Зовётся каждый шаг физики и почти всегда
## ничего не делает.
func linger() -> void:
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
		_land()
		return

	match _step:
		Step.FLY_IN:
			if _helicopter.is_hovering():
				_helicopter.lower_rope(_hook_height() - _deck_height())
				_otto.visible = true
				_step = Step.GRAB
				_wait = GRAB_PAUSE
		Step.GRAB:
			_hold_on()
			_wait -= delta
			if _wait <= 0.0 and _helicopter.rope_is_down():
				_step = Step.SLIDE
				_helicopter.rope_slide(true)
		Step.SLIDE:
			_slide(delta)


## Висит на крюке: вертолёт чуть ходит в висении, и Otto ходит с ним.
func _hold_on() -> void:
	var hook := _helicopter.hook()
	_place(Vector3(_otto.global_position.x, hook.y - REACH, WorldSpace.PLAY_Z))


func _slide(delta: float) -> void:
	_speed = minf(_speed + SLIDE_ACCELERATION * delta, SLIDE_SPEED)
	var at := WorldSpace.to_plane(_otto.global_position)
	at.y = minf(at.y + _speed * delta, _landing.y)
	_place(WorldSpace.to_scene(at))
	if at.y >= _landing.y:
		_land()


## Конец вступления приездом или пропуском: Otto стоит на месте приземления и
## слушается, вертолёт уходит, а кадр вступления держится, пока он не улетел
## ([method linger]).
func _land() -> void:
	_otto.global_position = WorldSpace.to_scene(_landing)
	_release()


## Отпускает Otto там, где его поставили, — тест, съёмка, возвращение после
## гибели. Кадр догоняет его сразу, снимком: вступление им не распоряжается.
func _let_go() -> void:
	_release()
	_otto.apply_camera_bounds(_bounds)
	_camera_held = false


func _release() -> void:
	var sliding := _step == Step.SLIDE
	_step = Step.DONE
	_otto.visible = true
	_otto.ride(false)
	if is_instance_valid(_helicopter):
		# Приехал — звук троса доигрывает сам, он короче спуска; сорвали
		# посреди спуска — обрывается.
		if not sliding or _otto.global_position.distance_to(_placed) > 0.01:
			_helicopter.rope_slide(false)
		_helicopter.leave(LINGER)


## Возвращает камере границы здания — без снимка, сглаживанием.
func _restore_camera() -> void:
	_camera_held = false
	_otto.apply_camera_bounds(_bounds, false)


func _place(at: Vector3) -> void:
	_otto.global_position = at
	_placed = at


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
