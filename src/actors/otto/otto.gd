class_name Otto
extends CharacterBody2D

## Игрок — агент Otto.
##
## Отвечает за физику, форму коллизии и вид. Решение о том, в каком он
## состоянии, принимает [OttoStateMachine].

## Otto погиб: пулей, падением в шахту или под кабиной.
signal died

const BULLET_SCENE := preload("res://src/systems/combat/bullet.tscn")

## Цвет коробки по состоянию: временная замена спрайтам, настоящие придут в M7.
const IDLE_COLOR := Color(0.85, 0.78, 0.35)
const STATE_COLORS: Dictionary = {
	OttoStateMachine.State.WALK: Color(0.95, 0.85, 0.40),
	OttoStateMachine.State.CROUCH: Color(0.70, 0.60, 0.30),
	OttoStateMachine.State.JUMP: Color(0.60, 0.85, 0.95),
	OttoStateMachine.State.FALL: Color(0.45, 0.65, 0.85),
	OttoStateMachine.State.RIDE: Color(0.55, 0.80, 0.60),
	# Тёмно-жёлтый, а не красный: в грейбоксе труп Otto не должен путаться
	# с живым агентом, а тот красный.
	OttoStateMachine.State.DEAD: Color(0.46, 0.36, 0.18),
}

@export var walk_speed: float = 90.0
## Высота прыжка = jump_speed² / (2 · gravity). При 380 и 900 это ~80 px:
## хватает на площадки greybox-уровня (нижние в 70 px от пола, верхняя — с них).
@export var jump_speed: float = 380.0
@export var gravity: float = 900.0
@export var bullet_speed: float = 220.0
## Откуда вылетает пуля, от ног. Присев, Otto стреляет ниже — и его выстрел
## проходит там, где стоящий враг его не перепрыгнет.
@export var shot_height_standing: float = -20.0
@export var shot_height_crouching: float = -10.0
@export var muzzle_offset: float = 9.0
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
## Куда Otto смотрит: -1 влево, +1 вправо. Туда же летят его пули.
var _facing: float = 1.0
var _gun := Gun.new()
## Верхняя точка текущего полёта: от неё считается глубина падения.
var _apex_y: float = 0.0

@onready var _standing_shape: CollisionShape2D = $StandingShape
@onready var _crouching_shape: CollisionShape2D = $CrouchingShape
@onready var _body: ColorRect = $Body
@onready var _camera: Camera2D = $Camera2D
@onready var _kick_zone: Area2D = $KickZone


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

	if absf(_snapshot.move) > OttoStateMachine.MOVE_THRESHOLD:
		_facing = signf(_snapshot.move)
	if _snapshot.shoot_pressed and state != OttoStateMachine.State.DEAD and _gun.can_fire():
		_fire()

	# Импульс прыжка выдаётся в тот же кадр, пока тело ещё стоит на полу,
	# поэтому гравитация его в этом кадре не съедает.
	if _states.just_entered(OttoStateMachine.State.JUMP) and is_on_floor():
		velocity.y = -jump_speed

	velocity.x = _horizontal_speed(_snapshot, state)
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)

	move_and_slide()

	# Удар ногой засчитывается только в полёте — стоя врага не бьют.
	if state == OttoStateMachine.State.JUMP or state == OttoStateMachine.State.FALL:
		_kick_enemies()
	_track_fall()
	_apply_pose(_states.state)


## Убивает Otto: пуля, падение на дно шахты, сдавливание кабиной.
func kill() -> void:
	if _states.is_dead():
		return
	_states.kill()
	_repose()
	died.emit()


## Попадание вражеской пули.
func take_bullet() -> void:
	kill()


func is_dead() -> bool:
	return _states.is_dead()


## Возвращает Otto в игру после смерти. Ставить его на место — дело уровня,
## поэтому зовут это уже после переноса: верхняя точка полёта берётся отсюда.
##
## Без сброса [member _apex_y] упавший в шахту возвращался бы с чужой глубиной
## падения за спиной и разбивался бы на ровном месте.
func revive() -> void:
	_states.reset()
	velocity = Vector2.ZERO
	_apex_y = global_position.y
	_repose()


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


## Выпускает пулю. Высоту полёта задаёт поза: присев, Otto стреляет ниже.
func _fire() -> void:
	var crouching := _states.state == OttoStateMachine.State.CROUCH
	var height := shot_height_crouching if crouching else shot_height_standing

	var bullet := BULLET_SCENE.instantiate() as Bullet
	bullet.direction = _facing
	bullet.speed = bullet_speed
	bullet.collision_mask = Bullet.HITS_ENEMIES
	bullet.hit_target.connect(_on_bullet_hit)
	# Счётчик ведёт сам ствол: пуля кончается и попаданием, и на дальности.
	bullet.tree_exited.connect(_gun.bullet_spent)
	get_parent().add_child(bullet)
	bullet.global_position = global_position + Vector2(_facing * muzzle_offset, height)
	_gun.fired()


func _on_bullet_hit(target: Node2D) -> void:
	var agent := target as Enemy
	if agent == null or agent.is_dead():
		return
	agent.take_bullet()
	GameState.instance().add_score(GameState.ENEMY_SHOT_SCORE)


## Бьёт ногой всех, кого задел в полёте.
func _kick_enemies() -> void:
	for body: Node2D in _kick_zone.get_overlapping_bodies():
		var agent := body as Enemy
		if agent == null or agent.is_dead():
			continue
		agent.kill()
		GameState.instance().add_score(GameState.ENEMY_KICK_SCORE)


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
