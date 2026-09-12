class_name Otto
extends CharacterBody2D

## Игрок — агент Otto.
##
## Отвечает за физику, форму коллизии и вид. Решение о том, в каком он
## состоянии, принимает [OttoStateMachine].

## Цвет коробки по состоянию: временная замена спрайтам, настоящие придут в M7.
const IDLE_COLOR := Color(0.85, 0.78, 0.35)
const STATE_COLORS: Dictionary = {
	OttoStateMachine.State.WALK: Color(0.95, 0.85, 0.40),
	OttoStateMachine.State.CROUCH: Color(0.70, 0.60, 0.30),
	OttoStateMachine.State.JUMP: Color(0.60, 0.85, 0.95),
	OttoStateMachine.State.FALL: Color(0.45, 0.65, 0.85),
	OttoStateMachine.State.RIDE: Color(0.55, 0.80, 0.60),
	OttoStateMachine.State.DEAD: Color(0.75, 0.25, 0.25),
}

@export var walk_speed: float = 90.0
## Высота прыжка = jump_speed² / (2 · gravity). При 380 и 900 это ~80 px:
## хватает на площадки greybox-уровня (нижние в 70 px от пола, верхняя — с них).
@export var jump_speed: float = 380.0
@export var gravity: float = 900.0
@export var max_fall_speed: float = 420.0
## В оригинале Otto приседает на месте. Оставлено переключателем для настройки.
@export var can_move_while_crouching: bool = false

var _states := OttoStateMachine.new()
## Один снимок ввода на всё время жизни: перечитывается, а не создаётся заново.
var _snapshot := OttoInput.new()
var _posed_state := OttoStateMachine.State.IDLE
## Кабина, внутри которой сейчас Otto. На крыше кабины она не заполняется:
## оттуда лифтом не управляют (ADR-0004, пункт 3).
var _car: ElevatorCar = null
## Разница высот стоячей и сидячей формы: столько места нужно над головой.
var _headroom: float = 0.0
## Верхняя точка текущего полёта: от неё считается глубина падения.
var _apex_y: float = 0.0

@onready var _standing_shape: CollisionShape2D = $StandingShape
@onready var _crouching_shape: CollisionShape2D = $CrouchingShape
@onready var _body: ColorRect = $Body
@onready var _camera: Camera2D = $Camera2D


func _ready() -> void:
	var standing := (_standing_shape.shape as RectangleShape2D).size.y
	var crouching := (_crouching_shape.shape as RectangleShape2D).size.y
	_headroom = standing - crouching
	_apex_y = global_position.y


func _physics_process(delta: float) -> void:
	_snapshot.read_actions()
	if _car != null:
		# В кабине «вверх/вниз» ведут её, а присесть внутри нельзя.
		_car.drive(vertical_intent())
		_snapshot.crouch = false

	var state := _states.update(_snapshot, is_on_floor(), velocity.y, _can_stand_up())

	# Пока Otto забрал кто-то другой — эскалатор везёт или дверь спрятала —
	# физика молчит: координатой распоряжается он, а не она.
	if state == OttoStateMachine.State.RIDE or state == OttoStateMachine.State.INDOORS:
		velocity = Vector2.ZERO
		# Его несут, а не роняют: падение с этой высоты не копится.
		_apex_y = global_position.y
		_apply_pose(state)
		return

	# Импульс прыжка выдаётся в тот же кадр, пока тело ещё стоит на полу,
	# поэтому гравитация его в этом кадре не съедает.
	if _states.just_entered(OttoStateMachine.State.JUMP) and is_on_floor():
		velocity.y = -jump_speed

	velocity.x = _horizontal_speed(_snapshot, state)
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)

	move_and_slide()
	_track_fall()
	_apply_pose(_states.state)


## Убивает Otto: падение на дно шахты, сдавливание кабиной, в M4 — пуля.
func kill() -> void:
	_states.kill()


## Намерение по вертикали за последний кадр. По нему кабина, эскалатор и дверь
## понимают, куда их просят, не читая [Input] сами.
##
## Пока Otto не свой — мёртв, едет на эскалаторе или сидит за дверью — он не
## просит ничего: иначе он продолжал бы вести кабину и просился бы в дверь
## оттуда, где его уже нет. Снять такое состояние может только тот, кто его
## поставил, а не игрок.
func vertical_intent() -> float:
	return 0.0 if _states.is_world_driven() else _snapshot.vertical


## Сколько Otto уже пролетел вниз от верхней точки полёта, px. На опоре — ноль.
func fall_height() -> float:
	return maxf(global_position.y - _apex_y, 0.0)


## На сколько поднимает прыжок: v² / (2 · g). Падение глубже — уже не свой прыжок.
func jump_height() -> float:
	return jump_speed * jump_speed / (2.0 * gravity)


## Намерение по горизонтали за последний кадр. По нему дверь понимает, что
## Otto просится наружу раньше срока.
func horizontal_intent() -> float:
	return 0.0 if _states.is_dead() else _snapshot.move


## Otto скрылся за дверью: снаружи его нет, ввод игрока не действует.
func enter_door() -> void:
	_states.go_indoors()
	_repose()


## Дверь выпустила Otto наружу — сам вышел или выставили через пять секунд.
func leave_door() -> void:
	_states.come_out()
	_repose()


## Otto встал на эскалатор: до конца поездки ввод игрока не действует.
func board_escalator() -> void:
	_states.ride()


## Эскалатор довёз и вернул управление.
func leave_escalator() -> void:
	_states.stop_riding()


## Otto вошёл в кабину и теперь ею управляет.
func board(car: ElevatorCar) -> void:
	_car = car


## Otto вышел из кабины.
func leave(car: ElevatorCar) -> void:
	if _car == car:
		_car = null


## Едет ли Otto внутри кабины. Езда на крыше сюда не входит.
func is_riding() -> bool:
	return _car != null


## Текущее состояние. Нужно отладочному оверлею и будущим системам.
func current_state() -> OttoStateMachine.State:
	return _states.state


## Текущая скорость тела.
##
## Вместе с [method is_grounded] образует публичный интерфейс для наблюдателей
## вроде отладочного оверлея: они зависят от API Otto, а не от того, что внутри
## он именно [CharacterBody2D].
func motion() -> Vector2:
	return velocity


## Стоит ли Otto на поверхности.
func is_grounded() -> bool:
	return is_on_floor()


## Ограничивает камеру прямоугольником уровня.
func apply_camera_bounds(bounds: Rect2) -> void:
	_camera.limit_left = int(bounds.position.x)
	_camera.limit_top = int(bounds.position.y)
	_camera.limit_right = int(bounds.end.x)
	_camera.limit_bottom = int(bounds.end.y)


## Есть ли над головой место, чтобы выпрямиться из приседа.
##
## Проверяется сидячей формой: если ею удаётся подняться на разницу высот,
## то и стоячая поместится. Без этой проверки полная форма включалась бы
## безусловно и выталкивала Otto сквозь перекрытие (долг M1).
func _can_stand_up() -> bool:
	if _states.state != OttoStateMachine.State.CROUCH:
		return true
	return not test_move(global_transform, Vector2(0.0, -_headroom))


## Запоминает верхнюю точку полёта: на опоре она сбрасывается, в воздухе ползёт вверх.
func _track_fall() -> void:
	_apex_y = global_position.y if is_on_floor() else minf(_apex_y, global_position.y)


func _horizontal_speed(input: OttoInput, state: OttoStateMachine.State) -> float:
	if state == OttoStateMachine.State.DEAD:
		return 0.0
	# Пол кабины не совпал с полом этажа — выходить некуда (ADR-0004, пункт 6).
	if _car != null and not _car.is_aligned():
		return 0.0
	if state == OttoStateMachine.State.CROUCH and not can_move_while_crouching:
		return 0.0
	if absf(input.move) <= OttoStateMachine.MOVE_THRESHOLD:
		return 0.0
	# Движение аркадное, дискретное: наклон стика не меняет скорость.
	return signf(input.move) * walk_speed


## Пересобирает позу прямо сейчас, не дожидаясь следующего [method _physics_process].
##
## Нужно тем, кто меняет состояние Otto снаружи, посреди кадра: формы коллизии
## включаются отложенно, и без этого первый кадр после двери Otto провёл бы
## бестелесным — [method move_and_slide] не нашёл бы под ним пола.
func _repose() -> void:
	_apply_pose(_states.state)


func _apply_pose(state: OttoStateMachine.State) -> void:
	# Поза — функция от состояния: пересобираем её только на переходах, иначе
	# каждый физический кадр сыпал бы по два отложенных вызова в очередь.
	if state == _posed_state:
		return
	_posed_state = state

	var crouching := state == OttoStateMachine.State.CROUCH
	# За дверью Otto не только не виден, но и не задевается: он в комнате.
	var hidden := state == OttoStateMachine.State.INDOORS
	_standing_shape.set_deferred("disabled", hidden or crouching)
	_crouching_shape.set_deferred("disabled", hidden or not crouching)
	_body.visible = not hidden

	# Размер и посадку коробки берём из самой формы коллизии, чтобы вид и
	# хитбокс не разъезжались при правке сцены.
	var shape_node := _crouching_shape if crouching else _standing_shape
	var box := shape_node.shape as RectangleShape2D
	_body.size = box.size
	_body.position = shape_node.position - box.size * 0.5
	_body.color = _color_for(state)


func _color_for(state: OttoStateMachine.State) -> Color:
	return STATE_COLORS.get(state, IDLE_COLOR)
