class_name Enemy
extends CharacterBody2D

## Враг-агент.
##
## Выходит из обычной двери, идёт по своему этажу к Otto и стреляет, когда тот
## оказывается на одной с ним линии. Решает [EnemyBrain], узел исполняет.
##
## Телом агент не вредит: в оригинале жизнь снимает только выстрел (ADR-0006,
## пункт 4), поэтому зоны урона у него нет — только оружие.

## Агент убит. Передаёт себя, чтобы дверь знала, кого выпускать заново.
signal died(agent: Enemy)

const BULLET_SCENE := preload("res://src/systems/combat/bullet.tscn")
## Сколько агент падает, прежде чем лечь: смерть — две позы (ADR-0011, п. 12).
const FALLING_TIME: float = 0.25

## Сколько держится поза выстрела, с.
const SHOOT_POSE_TIME: float = 0.25

@export var walk_speed: float = 55.0
@export var gravity: float = 900.0
@export var max_fall_speed: float = 420.0
@export var bullet_speed: float = 180.0

## Высота выстрела от ног: попадает в стоящего Otto и проходит над присевшим.
@export var shot_height: float = -20.0
@export var muzzle_offset: float = 9.0

## Сколько тело лежит, прежде чем исчезнуть, с.
@export var corpse_time: float = 0.5

## Настройки решений. Узел держит их у себя и отдаёт [EnemyBrain] — так же, как
## дверь отдаёт свои [DoorVisit]: подкрутить агента можно в инспекторе.
@export var emerge_time: float = 0.6
@export var same_line: float = 10.0
@export var fire_range: float = 200.0
@export var fire_cooldown: float = 1.1

## Сколько агент целится, прежде чем выстрелить в появившуюся цель, с.
@export var aim_time: float = 0.35

## Дальность стрельбы на погашенном этаже: в темноте агент замечает Otto только
## вблизи. Это не слепота, а меньше огня — ADR-0007, пункт 4.
@export var dark_fire_range: float = 60.0

## С какой злости агент начинает уходить на колено и ложиться.
##
## В первых зданиях он только стоит: уклонение — это третья ось сложности
## оригинала, и включаться она должна не сразу (ADR-0016, пункт 2).
@export var kneels_from_menace: float = 1.4
@export var goes_prone_from_menace: float = 1.8

## Рост в каждой стойке, px. Стоячий равен форме коллизии из сцены; остальные
## ниже, и пуля выше их проходит мимо.
@export var kneel_height: float = 17.0
@export var prone_height: float = 8.0

## Насколько далеко агент замечает летящую в него пулю, px. Дальше он её
## игнорирует: уклоняться за секунду до попадания незачем, а стоять
## пригнувшимся весь бой — значит не дойти до Otto никогда.
@export var dodge_sight: float = 120.0

var _brain := EnemyBrain.new()
var _target: Otto = null
var _corpse_left: float = 0.0
var _in_the_dark: bool = false
## Фаза ходьбы, поза выстрела и падения, признак раздавленного — всё как у Otto.
var _walk_phase: float = 0.0
var _walking: bool = false
var _shooting: float = 0.0
var _falling_over: float = 0.0
var _crushed: bool = false
## Насколько агент злее обычного: 1 — как в первом здании, больше — злее.
var _menace: float = 1.0

@onready var _body: Sprite2D = $Body
@onready var _floor_probe: RayCast2D = $FloorProbe
@onready var _shape: CollisionShape2D = $Shape


func _ready() -> void:
	_brain.emerge_time = emerge_time
	_brain.same_line = same_line
	_brain.aim_time = aim_time
	# Стоячий рост берётся у самой формы, а не записывается вторым числом:
	# разъехавшись, они дали бы агента, который уклоняется не своим телом.
	_brain.stand_height = (_shape.shape as RectangleShape2D).size.y
	_brain.kneel_height = kneel_height
	_brain.prone_height = prone_height
	_refresh_brain()


func _physics_process(delta: float) -> void:
	if _brain.is_dead():
		# Тело доезжает до пола: убитый в прыжке не должен зависать в воздухе.
		_apply_gravity(delta)
		move_and_slide()
		_walking = false
		_rot(delta)
		_update_look(delta)
		return

	var alive_target := _target != null and not _target.is_dead()
	var to_target := _target.global_position - global_position if alive_target else Vector2.ZERO
	var state := _brain.update(delta, to_target, alive_target, _incoming_height())
	_fit_shape()
	if _brain.fired():
		_fire()

	# Приседая и лёжа агент не ходит: уклонение — это замереть, а не идти
	# дальше пригнувшись.
	var walking := state == EnemyBrain.State.WALK and _brain.is_standing()
	if walking and is_on_floor() and not _floor_ahead():
		# Дальше пола нет: агент остаётся на своём этаже (ADR-0006, пункт 6).
		walking = false
	velocity.x = walk_speed * _brain.facing if walking else 0.0
	_apply_gravity(delta)
	move_and_slide()
	_walking = walking
	_update_look(delta)


## Выпускает агента из двери: он выходит в сторону [param towards].
func setup(target: Otto, towards: float) -> void:
	_target = target
	_brain.start(towards)


## Сообщает агенту, что его этаж погас или снова освещён.
func set_in_the_dark(value: bool) -> void:
	_in_the_dark = value
	_refresh_brain()


## Насколько агент злее обычного. Растёт от здания к зданию и по тревоге.
func set_menace(value: float) -> void:
	_menace = maxf(value, 0.1)
	_refresh_brain()


## Стоит ли агент в темноте. По этому признаку считается надбавка за убийство.
func is_in_the_dark() -> bool:
	return _in_the_dark


## Попадание пули. Кто стрелял, тот и получает очки — это решает он сам.
func take_bullet() -> void:
	kill()


## Убивает агента: пулей, ногой или упавшей лампой в M4b.
## [param crushed] — придавило упавшей лампой: у такой смерти своя поза.
func kill(crushed: bool = false) -> void:
	if _brain.is_dead():
		return
	_crushed = crushed
	_brain.kill()
	velocity = Vector2.ZERO
	_corpse_left = corpse_time
	_falling_over = FALLING_TIME
	Sounds.play(Sounds.AGENT_DEATH)
	died.emit(self)


func is_dead() -> bool:
	return _brain.is_dead()


## Высота ближайшей летящей в агента пули над его ногами, px, или -1, если
## лететь нечему.
##
## Ищется по группе пуль, а не по детям уровня: детей под три сотни, а пуль на
## экране от силы четыре. Своими пулями агент не интересуется — уклоняться от
## них ему незачем, и маска у них та же на всех агентов.
func _incoming_height() -> float:
	var best := -1.0
	var nearest := dodge_sight
	for node in get_tree().get_nodes_in_group(Bullet.GROUP):
		var bullet := node as Bullet
		if bullet == null or bullet.collision_mask != Bullet.FROM_OTTO:
			continue
		var to_bullet := bullet.global_position - global_position
		# Летит ли она в нас: направление пули должно смотреть в нашу сторону.
		if not is_equal_approx(signf(to_bullet.x), -bullet.direction):
			continue
		var reach := absf(to_bullet.x)
		if reach > nearest:
			continue
		nearest = reach
		# Ноги агента — ноль, вверх положительно: у пули y отрицательный.
		best = -to_bullet.y
	return best


## Подгоняет форму коллизии под стойку.
##
## Низ формы остаётся на полу, поэтому меняется и размер, и смещение: у
## [CollisionShape2D] начало в середине, и одна лишь смена размера утопила бы
## присевшего агента в перекрытие.
func _fit_shape() -> void:
	var box := _shape.shape as RectangleShape2D
	var height := _brain.height()
	if is_equal_approx(box.size.y, height):
		return
	# Форма приходит из сцены общей на всех агентов: правя её на месте, мы
	# пригибали бы разом всех, кто её делит.
	var own := box.duplicate() as RectangleShape2D
	own.size = Vector2(box.size.x, height)
	_shape.shape = own
	_shape.position.y = -height * 0.5


## Есть ли пол там, куда агент собирается шагнуть.
##
## Без этой проверки он уходил бы с собственного этажа в проём шахты или
## эскалатора: маска у него только на геометрию, а дыра в перекрытии для
## него ничем не отличается от продолжения пола.
func _floor_ahead() -> bool:
	_floor_probe.position.x = absf(_floor_probe.position.x) * signf(_brain.facing)
	# Луч обновляется в начале кадра, а мы только что его подвинули.
	_floor_probe.force_raycast_update()
	return _floor_probe.is_colliding()


## Переносит в [EnemyBrain] числа, которые зависят от темноты и злости: дальность
## стрельбы и паузу между выстрелами. Считается в одном месте, чтобы порядок вызовов
## [method _ready], [method set_in_the_dark] и [method set_menace] ничего не решал —
## иначе настроенный до [method Node.add_child] агент прозревал бы обратно.
func _refresh_brain() -> void:
	# Дальность не растёт со злостью: в оригинале сложность добавляют
	# скорострельность, скорость пули и уклонение, а дальности среди них нет
	# (ADR-0016, пункт 1). Пока она росла, к поздним зданиям агент простреливал
	# этаж насквозь, и подойти к нему было нечем.
	_brain.fire_range = dark_fire_range if _in_the_dark else fire_range
	_brain.fire_cooldown = fire_cooldown / _menace
	# Уклоняться агент учится не сразу: это третья ось сложности оригинала,
	# и в первых зданиях его берут стоящим.
	_brain.can_kneel = _menace >= kneels_from_menace
	_brain.can_go_prone = _menace >= goes_prone_from_menace


## Скорость пули этого агента: растёт со злостью, как в оригинале. Отбирает
## время на реакцию, но не саму возможность подойти.
func _bullet_speed() -> float:
	return bullet_speed * _menace


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)


## Картинка на этот кадр: поза, сторона и ход ходьбы. Устроено так же, как
## у Otto, — разница только в наборе поз: агент не приседает и не прыгает.
func _update_look(delta: float) -> void:
	_shooting = maxf(_shooting - delta, 0.0)
	_falling_over = maxf(_falling_over - delta, 0.0)
	if _walking:
		_walk_phase = ActorPose.advance(_walk_phase, delta)
	else:
		_walk_phase = 0.0

	_body.texture = SpriteTextures.actor("agent", _pose())
	_body.flip_h = _brain.facing < 0.0


func _pose() -> String:
	return ActorPose.of_agent(
		_brain.is_dead(),
		_walking,
		_crushed,
		_falling_over > 0.0,
		_shooting > 0.0,
		_walk_phase,
		_brain.stance
	)


## Досчитывает время, которое тело лежит на полу, и убирает его.
func _rot(delta: float) -> void:
	_corpse_left -= delta
	if _corpse_left <= 0.0:
		queue_free()


func _fire() -> void:
	_shooting = SHOOT_POSE_TIME
	Sounds.play(Sounds.SHOT)
	var bullet := BULLET_SCENE.instantiate() as Bullet
	bullet.direction = _brain.facing
	bullet.speed = _bullet_speed()
	bullet.collision_mask = Bullet.FROM_ENEMY
	bullet.hit_target.connect(_on_bullet_hit)
	get_parent().add_child(bullet)
	bullet.global_position = global_position + Vector2(_brain.facing * muzzle_offset, shot_height)


## Попадание своей пули. Очков за Otto никто не получает — он просто гибнет.
func _on_bullet_hit(target: Node2D) -> void:
	var victim := target as Otto
	if victim == null:
		return
	victim.take_bullet()
