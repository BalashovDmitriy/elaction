class_name Otto
extends CharacterBody2D

## Игрок — агент Otto.
##
## Отвечает за физику, форму коллизии и вид. Решение о том, в каком он
## состоянии, принимает [OttoStateMachine].

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

@onready var _standing_shape: CollisionShape2D = $StandingShape
@onready var _crouching_shape: CollisionShape2D = $CrouchingShape
@onready var _body: ColorRect = $Body
@onready var _camera: Camera2D = $Camera2D


func _physics_process(delta: float) -> void:
	_snapshot.read_actions()
	if _car != null:
		# В кабине «вверх/вниз» ведут её, а присесть внутри нельзя.
		_car.drive(_snapshot.vertical)
		_snapshot.crouch = false

	var state := _states.update(_snapshot, is_on_floor(), velocity.y)

	# Импульс прыжка выдаётся в тот же кадр, пока тело ещё стоит на полу,
	# поэтому гравитация его в этом кадре не съедает.
	if _states.just_entered(OttoStateMachine.State.JUMP) and is_on_floor():
		velocity.y = -jump_speed

	velocity.x = _horizontal_speed(_snapshot, state)
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)

	move_and_slide()
	_apply_pose(state)


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


func _horizontal_speed(input: OttoInput, state: OttoStateMachine.State) -> float:
	if state == OttoStateMachine.State.DEAD:
		return 0.0
	if state == OttoStateMachine.State.CROUCH and not can_move_while_crouching:
		return 0.0
	if absf(input.move) <= OttoStateMachine.MOVE_THRESHOLD:
		return 0.0
	# Движение аркадное, дискретное: наклон стика не меняет скорость.
	return signf(input.move) * walk_speed


func _apply_pose(state: OttoStateMachine.State) -> void:
	# Поза — функция от состояния: пересобираем её только на переходах, иначе
	# каждый физический кадр сыпал бы по два отложенных вызова в очередь.
	if state == _posed_state:
		return
	_posed_state = state

	var crouching := state == OttoStateMachine.State.CROUCH
	_standing_shape.set_deferred("disabled", crouching)
	_crouching_shape.set_deferred("disabled", not crouching)

	# Размер и посадку коробки берём из самой формы коллизии, чтобы вид и
	# хитбокс не разъезжались при правке сцены.
	var shape_node := _crouching_shape if crouching else _standing_shape
	var box := shape_node.shape as RectangleShape2D
	_body.size = box.size
	_body.position = shape_node.position - box.size * 0.5
	_body.color = _color_for(state)


func _color_for(state: OttoStateMachine.State) -> Color:
	match state:
		OttoStateMachine.State.WALK:
			return Color(0.95, 0.85, 0.40)
		OttoStateMachine.State.CROUCH:
			return Color(0.70, 0.60, 0.30)
		OttoStateMachine.State.JUMP:
			return Color(0.60, 0.85, 0.95)
		OttoStateMachine.State.FALL:
			return Color(0.45, 0.65, 0.85)
		OttoStateMachine.State.DEAD:
			return Color(0.75, 0.25, 0.25)
		_:
			return Color(0.85, 0.78, 0.35)
