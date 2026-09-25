class_name Otto
extends CharacterBody3D

## Игрок — агент Otto.
##
## Отвечает за физику, форму коллизии и вид. Решение о том, в каком он
## состоянии, принимает [OttoStateMachine].
##
## Живёт в плоскости игры: Z заперт на [constant WorldSpace.PLAY_Z] и
## возвращается туда после каждого шага физики (ADR-0021, решение 1). Ходить
## вглубь Otto не будет — глубина это свойство картинки, а не движения.

## Otto погиб: пулей, падением больше чем на этаж или под кабиной.
signal died

const BULLET_SCENE := preload("res://src/systems/combat/bullet.tscn")

## Сколько держится поза выстрела, с. Выстрел мгновенный, а увидеть его надо.
const SHOOT_POSE_TIME: float = 0.18

## Сколько Otto падает, прежде чем лечь: смерть — две позы (ADR-0011, пункт 12).
const FALLING_TIME: float = 0.3

## Сколько Otto неуязвим, вернувшись в игру, с.
##
## Возвращается он на этаж, где погиб, а агент, который его убил, никуда не делся
## и стоит в своей зоне огня — без передышки вторая смерть приходит через четверть
## секунды после первой, и три жизни сгорают на одном месте (ADR-0014, пункт 6).
const RESPAWN_GRACE: float = 1.5

## Как часто мигает неуязвимый Otto, раз в секунду. Мигание — единственное, чем
## передышка себя показывает: без него игрок не знает, что она вообще была.
const GRACE_BLINKS: float = 8.0

## Насколько Otto может сместиться между двумя своими кадрами физики, м, и это
## ещё не перестановка. Сам он двигается только внутри своего кадра; между
## кадрами его переносят — уровень, тест, инструмент съёмки, — и такой перенос
## не падение: без этого поставленный этажом ниже разбивался бы на ровном месте.
const TELEPORT_GAP: float = 0.5

## Ходьба и пуля — по ROM: 2 и 8 px за тик логики (ADR-0027, решение 4); пуля
## втрое быстрее ROM ([constant Arcade.BULLET_PACE], ADR-0037, решение 5).
@export var walk_speed: float = Arcade.speed(Arcade.WALK_PX)
## Прыжок по ROM: ступни +25 px (1.88 м) за 14 тиков (0.95 с) — table_42E2.
## Высота прыжка = jump_speed в квадрате, делённая на 2 · gravity: 7.9 и 16.6
## дают те же 1.88 м за те же 0.95 с. До M18d прыжок был 2.4 м по физике.
@export var jump_speed: float = 7.9
@export var gravity: float = 16.6
@export var bullet_speed: float = Arcade.bullet_speed(Arcade.OTTO_BULLET_PX)
## Откуда вылетает пуля, от ног. Присев, Otto стреляет ниже — и его выстрел
## проходит там, где стоящий враг его не перепрыгнет.
##
## Числа — в [Proportions]: стоячая с кадра оригинала, до лампы под потолком
## не достаёт и из прыжка — Otto упирается головой в потолок раньше
## (ADR-0026, решение 5).
@export var shot_height_standing: float = Proportions.SHOT_HIGH
@export var shot_height_crouching: float = Proportions.SHOT_LOW
@export var muzzle_offset: float = Proportions.MUZZLE
@export var max_fall_speed: float = 12.6
## В оригинале Otto приседает на месте. Оставлено переключателем для настройки.
@export var can_move_while_crouching: bool = false

## Чем звучит шаг: пол ставит здание — ковёр отеля, камень конторы и крыши.
var step_sound: String = Sounds.STEP_CONCRETE
## Шаг этажа здания, м: упавший больше чем на этаж разбивается (ADR-0037,
## решение 7). Ставит уровень из своих правил; по умолчанию — стандартный этаж.
var floor_height: float = Proportions.FLOOR
## Идёт ли передышка после возвращения в игру: пуля в Otto попадает, но не
## ранит. По этому [Bullet] решает, брызгать ли кровью. Свойством, а не методом:
## пуля спрашивает его через [method Object.get], не зная класса Otto.
var invulnerable: bool:
	get:
		return _grace > 0.0

var _states := OttoStateMachine.new()
## Один снимок ввода на всё время жизни: перечитывается, а не создаётся заново.
var _snapshot := OttoInput.new()
var _posed_state := OttoStateMachine.State.IDLE
## Скорость по горизонтали в полёте, м/с. Задаётся толчком и в воздухе не
## меняется: в ROM направление прыжка выбирается при старте (@43FA), а
## повернуться лицом в полёте можно (@42A7).
var _air_speed: float = 0.0
## Кабина, внутри которой сейчас Otto. На крыше кабины она не заполняется:
## оттуда лифтом не управляют (ADR-0004, пункт 3).
var _car: ElevatorCar = null
## Разница высот стоячей и сидячей формы: столько места нужно над головой.
var _headroom: float = 0.0
## Куда Otto смотрит: -1 влево, +1 вправо. Туда же летят его пули.
var _facing: float = 1.0
## Фаза ходьбы: целая часть — номер кадра из трёх.
var _walk_phase: float = 0.0
## Сколько ещё держать позу выстрела и позу падения, с.
var _shooting: float = 0.0
var _falling_over: float = 0.0
## Придавлен кабиной: у такой смерти своя поза.
var _crushed: bool = false
## На каком кадре ходьбы уже прозвучал шаг.
var _stepped_on: int = -1
var _gun := Gun.new()
## Высота последней опоры: от неё считается глубина падения, м сцены.
##
## От опоры, а не от верхней точки полёта: свой прыжок ничего к падению не
## прибавляет — спрыгнуть этажом ниже можно и с разбега, и с прыжка.
var _support_y: float = 0.0
## Стоял ли Otto на опоре в прошлом кадре: приземление — это переход.
var _was_grounded: bool = true
## Где Otto закончил прошлый кадр физики: по этому видно перестановку.
var _last_position := Vector3.ZERO
## Сколько ещё держится передышка после возвращения в игру, с.
var _grace: float = 0.0

@onready var _standing_shape: CollisionShape3D = $StandingShape
@onready var _crouching_shape: CollisionShape3D = $CrouchingShape
@onready var _body: FigureRig = $Body
@onready var _camera: SideCamera = $Camera
@onready var _kick_zone: Area3D = $KickZone


## Формы тела задаёт [Proportions], а не сцена: сразу после сборки сцены, ещё
## до дерева. Тесты читают формы у свежей копии, не добавляя её в дерево, и
## видеть они обязаны те же числа, что и игра.
func _notification(what: int) -> void:
	if what != NOTIFICATION_SCENE_INSTANTIATED:
		return
	var depth := WorldSpace.BODY_DEPTH
	var width := Proportions.BODY_WIDTH
	Proportions.fit_box($StandingShape as CollisionShape3D, Vector3(width, Proportions.BODY, depth))
	Proportions.fit_box(
		$CrouchingShape as CollisionShape3D, Vector3(width, Proportions.CROUCH, depth)
	)
	Proportions.fit_box(
		$KickZone/KickShape as CollisionShape3D,
		Vector3(Proportions.KICK_WIDTH, Proportions.BODY, depth)
	)


func _ready() -> void:
	var standing := _shape_size(_standing_shape)
	var crouching := _shape_size(_crouching_shape)
	_headroom = standing.y - crouching.y
	_rest_here()
	_camera.follow(self)
	_repose()


func _physics_process(delta: float) -> void:
	_grace = maxf(_grace - delta, 0.0)
	if global_position.distance_to(_last_position) > TELEPORT_GAP:
		# Переставили — уровень, тест или съёмка: с новой точки и считаем.
		_rest_here()
	_snapshot.read_actions()
	if _car != null:
		# В кабине «вверх/вниз» ведут её, а присесть внутри нельзя.
		_car.drive(vertical_intent())
		_snapshot.crouch = false

	# Машине состояний нужна скорость в координатах правил, где Y вниз:
	# падение для неё положительно, как было в 2D.
	var state := _states.update(_snapshot, is_on_floor(), -velocity.y, _can_stand_up())

	# Пока Otto забрал кто-то другой — эскалатор везёт или дверь спрятала —
	# физика молчит: координатой распоряжается он, а не она.
	if state == OttoStateMachine.State.RIDE or state == OttoStateMachine.State.INDOORS:
		velocity = Vector3.ZERO
		# Его несут, а не роняют: падение с этой высоты не копится.
		_rest_here()
		_apply_pose(state)
		_update_look(delta)
		return

	# Мёртвый не поворачивается: труп лежит той стороной, которой упал. На цветной
	# коробке этого было не видно, а модель разворачивается на глазах — и тыканье
	# в стрелки крутило бы тело, пока идёт отсчёт до возвращения в игру.
	var turning := absf(_snapshot.move) > OttoStateMachine.MOVE_THRESHOLD
	if turning and state != OttoStateMachine.State.DEAD:
		_facing = signf(_snapshot.move)
	if _snapshot.shoot_pressed and state != OttoStateMachine.State.DEAD and _gun.can_fire():
		_fire()

	# Импульс прыжка выдаётся в тот же кадр, пока тело ещё стоит на полу,
	# поэтому гравитация его в этом кадре не съедает.
	if _states.just_entered(OttoStateMachine.State.JUMP) and is_on_floor():
		velocity.y = jump_speed

	if is_on_floor() or state == OttoStateMachine.State.DEAD:
		_air_speed = _horizontal_speed(_snapshot, state)
	velocity.x = _air_speed
	if not is_on_floor():
		velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)

	move_and_slide()
	_hold_the_plane()

	# Удар ногой засчитывается только в полёте — стоя врага не бьют.
	if state == OttoStateMachine.State.JUMP or state == OttoStateMachine.State.FALL:
		_kick_enemies()
	_track_fall()
	_last_position = global_position
	_apply_pose(_states.state)
	_update_look(delta)


## Убивает Otto: пуля, падение больше чем на этаж, сдавливание кабиной.
##
## Во время передышки после возвращения в игру не делает ничего: неуязвимость
## общая на все причины, а не только на пули — воскреснуть под кабиной так же
## обидно, как под выстрелом.
##
## [param crushed] — придавило кабиной: у такой смерти своя поза, в оригинале
## раздавленный показан отдельной картинкой (ADR-0011, пункт 12).
func kill(crushed: bool = false) -> void:
	if _grace > 0.0:
		return

	if _states.is_dead():
		return
	_crushed = crushed
	_states.kill()
	_falling_over = FALLING_TIME
	Sounds.play(Sounds.OTTO_DEATH)
	Sounds.play(Sounds.DEATH_JINGLE)
	_repose()
	died.emit()


func is_dead() -> bool:
	return _states.is_dead()


## Стоит ли Otto на своих ногах — не в кабине, не на эскалаторе, не за дверью.
## Пока нет, агентов на этаж выходит не больше одного (@59F4).
func is_on_foot() -> bool:
	return _car == null and not _states.is_world_driven()


## Сидит ли Otto: агент тогда стреляет из приседа (@1CD8).
func is_crouching() -> bool:
	return _states.state == OttoStateMachine.State.CROUCH


## Скрылся ли Otto за дверью. Снаружи его нет, и агентам он не виден:
## в оригинале войти в дверь значит сбить их со следа (ADR-0023, решение 8).
func is_hidden() -> bool:
	return _states.state == OttoStateMachine.State.INDOORS


## Возвращает Otto в игру после смерти. Ставить его на место — дело уровня,
## поэтому зовут это уже после переноса: опора, от которой считается падение,
## берётся отсюда.
##
## Без сброса [member _support_y] упавший в шахту возвращался бы с чужой
## глубиной падения за спиной и разбивался бы на ровном месте.
func revive() -> void:
	_crushed = false
	_states.reset()
	velocity = Vector3.ZERO
	_rest_here()
	_grace = RESPAWN_GRACE
	# Камера приезжает к воскресшему сразу: иначе полсекунды сглаживания игрок
	# смотрит туда, где его убили.
	_camera.snap_to(Vector2(global_position.x, global_position.y))
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


## На сколько Otto ниже своей последней опоры, м. На опоре — ноль.
func fall_height() -> float:
	return maxf(_support_y - global_position.y, 0.0)


## На сколько поднимает прыжок, м.
func jump_height() -> float:
	return jump_speed * jump_speed / (2.0 * gravity)


## Otto скрылся за дверью или дверь выпустила его наружу — через 70 тиков ROM,
## раньше не выйти (ADR-0038, решение 2). Пока внутри, снаружи его нет и ввод
## игрока не действует; так же он прячется, пока его увозит машина у выхода.
func stay_indoors(inside: bool) -> void:
	if inside:
		_states.go_indoors()
	else:
		_states.come_out()
	_repose()


## Otto встал на эскалатор или сошёл с него: пока едет, ввод игрока не
## действует, а позицией распоряжается эскалатор. Трос вступления пользуется
## тем же — Otto на нём тоже везут.
func ride(on: bool) -> void:
	if on:
		_states.ride()
	else:
		_states.stop_riding()
	_repose()


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


## Текущая скорость тела, в координатах правил.
##
## Вместе с [method is_grounded] образует публичный интерфейс для наблюдателей:
## они зависят от API Otto, а не от того, что внутри он [CharacterBody3D] и что
## у сцены Y смотрит вверх.
func motion() -> Vector2:
	return WorldSpace.direction_to_plane(velocity)


## Стоит ли Otto на поверхности.
func is_grounded() -> bool:
	return is_on_floor()


## Что сейчас попадает в кадр, в координатах правил.
##
## Камера едет за Otto, но упирается в края здания. Поэтому видимое место
## считает тот, у кого камера, а не тот, кому оно нужно: снаружи пришлось бы
## спрашивать и середину, и размер кадра, и размер окна.
##
## [param for_combat] — кадр, по которому решает бой: агент в нём достаёт Otto
## (ADR-0027, решение 3а). Тот же, что видит игрок, но не зависит ни от окна,
## ни от сглаживания камеры — см. [method SideCamera.rule_view].
func camera_view(for_combat: bool = false) -> Rect2:
	return _camera.rule_view() if for_combat else _camera.view()


## Куда Otto смотрит: -1 влево, +1 вправо. Туда же уйдёт его следующая пуля.
func facing() -> float:
	return _facing


## Границы камеры в координатах правил. [param snap] — встать на место сразу;
## без него камера доедет к новым границам сглаживанием (конец вступления).
func apply_camera_bounds(bounds: Rect2, snap: bool = true) -> void:
	_camera.apply_bounds(bounds, snap)


## Возвращает тело в плоскость игры.
##
## [method move_and_slide] умеет вытолкнуть тело по Z, если оно хоть краем
## задело грань под углом, и такой сдвиг не виден в боковом кадре вовсе:
## Otto просто перестаёт доставать до того, до чего доставал.
func _hold_the_plane() -> void:
	velocity.z = 0.0
	global_position.z = WorldSpace.PLAY_Z


## Выпускает пулю. Высоту полёта задаёт поза: присев, Otto стреляет ниже.
func _fire() -> void:
	_shooting = SHOOT_POSE_TIME
	Sounds.play(Sounds.SHOT)
	var crouching := _states.state == OttoStateMachine.State.CROUCH
	var height := shot_height_crouching if crouching else shot_height_standing

	var bullet := BULLET_SCENE.instantiate() as Bullet
	bullet.direction = _facing
	bullet.speed = bullet_speed
	bullet.collision_mask = Bullet.FROM_OTTO
	bullet.hit_target.connect(_on_bullet_hit)
	# Счётчик ведёт сам ствол: пуля кончается и попаданием, и на дальности.
	bullet.tree_exited.connect(_gun.bullet_spent)
	get_parent().add_child(bullet)
	bullet.global_position = global_position + Vector3(_facing * muzzle_offset, height, 0.0)
	_gun.fired()


func _on_bullet_hit(target: Node3D) -> void:
	# Пуля не разбирает, во что попала, — разбирает стрелявший.
	var lamp := target as Lamp
	if lamp != null:
		lamp.shoot_down()
		return

	var agent := target as Enemy
	if agent == null or agent.is_dead():
		return
	agent.take_bullet()
	_award_for(agent, GameState.ENEMY_SHOT_SCORE)


## Начисляет очки за убитого агента: в темноте они дороже.
func _award_for(agent: Enemy, base: int) -> void:
	GameState.instance().add_score(GameState.kill_score(base, agent.is_in_the_dark()))


## Бьёт ногой всех, кого задел в полёте.
func _kick_enemies() -> void:
	# Удар один, сколько бы агентов он ни задел: звук на каждого съедал бы
	# голоса пула и звучал бы вдвое громче самого себя.
	var landed := false
	for body: Node3D in _kick_zone.get_overlapping_bodies():
		var agent := body as Enemy
		if agent == null or agent.is_dead():
			continue
		agent.kill()
		landed = true
		_award_for(agent, GameState.ENEMY_KICK_SCORE)

	if landed:
		Sounds.play(Sounds.KICK)


## Есть ли над головой место, чтобы выпрямиться из приседа.
##
## Проверяется сидячей формой: если ею удаётся подняться на разницу высот,
## то и стоячая поместится. Без этой проверки полная форма включалась бы
## безусловно и выталкивала Otto сквозь перекрытие (долг M1).
func _can_stand_up() -> bool:
	if _states.state != OttoStateMachine.State.CROUCH:
		return true
	return not test_move(global_transform, Vector3(0.0, _headroom, 0.0))


## Следит за падением: на опоре запоминает её высоту, а приземлившись, решает,
## не разбился ли (ADR-0037, решение 7).
##
## Правило одно на пол, крышу кабины и дно шахты — всё это опора под ногами.
## В кабине опора едет вместе с Otto: пол кабины под ним каждый кадр, и спуск
## в ней падением не копится, даже если движок на кадр потеряет пол под ногами.
func _track_fall() -> void:
	var grounded := is_on_floor()
	if grounded and not _was_grounded:
		if ShaftHazards.is_deadly_fall(fall_height(), floor_height):
			kill()
	_was_grounded = grounded
	if grounded or _car != null:
		_support_y = global_position.y


## Считает опорой то место, где Otto сейчас: сюда его поставили или донесли.
func _rest_here() -> void:
	_support_y = global_position.y
	_last_position = global_position
	_was_grounded = true


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
	# За дверью Otto нет вовсе, на эскалаторе он на виду — но достать нельзя
	# ни там, ни там: «neither kill nor be killed» (ADR-0007, пункт 7).
	var hidden := state == OttoStateMachine.State.INDOORS
	var untouchable := hidden or state == OttoStateMachine.State.RIDE
	_standing_shape.set_deferred("disabled", untouchable or crouching)
	_crouching_shape.set_deferred("disabled", untouchable or not crouching)
	_body.visible = not hidden


## Поза, которую Otto отыгрывает прямо сейчас.
##
## Выбирает её [ActorPose] — тот же, что выбирал спрайт, — а исполняет [FigureRig]
## на скелете: между позами он интерполирует сам (ADR-0022, решение 2).
func _pose() -> String:
	return ActorPose.of_otto(
		_states.state, _crushed, _falling_over > 0.0, _shooting > 0.0, _walk_phase
	)


## Прозрачность тела: неуязвимый Otto мигает, остальные кадры он сплошной.
func _grace_alpha() -> float:
	if _grace <= 0.0:
		return 1.0
	var phase := fmod(_grace * GRACE_BLINKS, 1.0)
	return 1.0 if phase < 0.5 else 0.25


## Что меняется каждый кадр, а не на переходах: ход ходьбы, таймеры поз и
## мигание передышки.
func _update_look(delta: float) -> void:
	_shooting = maxf(_shooting - delta, 0.0)
	_falling_over = maxf(_falling_over - delta, 0.0)
	if _states.state == OttoStateMachine.State.WALK:
		_walk_phase = ActorPose.advance(_walk_phase, delta)
		_step_sound()
	else:
		_walk_phase = 0.0
		_stepped_on = -1

	_body.show_pose(_pose())
	_body.set_walk_phase(_walk_phase)
	_body.face(_facing)
	_body.set_transparency(1.0 - _grace_alpha())


## Шаг звучит на крайних кадрах ходьбы — тех, где нога ставится. На каждом
## кадре цикла шагов выходило бы вдвое больше, чем делает Otto.
func _step_sound() -> void:
	var frame := int(_walk_phase)
	# Кадр помечается пройденным только вместе со звуком: помеченный в воздухе
	# терял бы шаг насовсем — нога встала, а слышно ничего.
	if frame == _stepped_on or frame == 1 or not is_on_floor():
		return
	_stepped_on = frame
	Sounds.play(step_sound)


static func _shape_size(shape: CollisionShape3D) -> Vector3:
	return (shape.shape as BoxShape3D).size
