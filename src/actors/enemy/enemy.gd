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
## Живым агент покрашен в сцене; здесь — только цвет трупа.
const DEAD_COLOR := Color(0.38, 0.20, 0.20)

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

## Дальность стрельбы на погашенном этаже: в темноте агент замечает Otto только
## вблизи. Это не слепота, а меньше огня — ADR-0007, пункт 4.
@export var dark_fire_range: float = 60.0

var _brain := EnemyBrain.new()
var _target: Otto = null
var _corpse_left: float = 0.0
var _in_the_dark: bool = false

@onready var _body: ColorRect = $Body
@onready var _floor_probe: RayCast2D = $FloorProbe


func _ready() -> void:
	_brain.emerge_time = emerge_time
	_brain.same_line = same_line
	_brain.fire_cooldown = fire_cooldown
	_refresh_fire_range()


func _physics_process(delta: float) -> void:
	if _brain.is_dead():
		# Тело доезжает до пола: убитый в прыжке не должен зависать в воздухе.
		_apply_gravity(delta)
		move_and_slide()
		_rot(delta)
		return

	var alive_target := _target != null and not _target.is_dead()
	var to_target := _target.global_position - global_position if alive_target else Vector2.ZERO
	var state := _brain.update(delta, to_target, alive_target)
	if _brain.fired():
		_fire()

	var walking := state == EnemyBrain.State.WALK
	if walking and is_on_floor() and not _floor_ahead():
		# Дальше пола нет: агент остаётся на своём этаже (ADR-0006, пункт 6).
		walking = false
	velocity.x = walk_speed * _brain.facing if walking else 0.0
	_apply_gravity(delta)
	move_and_slide()


## Выпускает агента из двери: он выходит в сторону [param towards].
func setup(target: Otto, towards: float) -> void:
	_target = target
	_brain.start(towards)


## Сообщает агенту, что его этаж погас или снова освещён.
func set_in_the_dark(value: bool) -> void:
	_in_the_dark = value
	_refresh_fire_range()


## Стоит ли агент в темноте. По этому признаку считается надбавка за убийство.
func is_in_the_dark() -> bool:
	return _in_the_dark


## Попадание пули. Кто стрелял, тот и получает очки — это решает он сам.
func take_bullet() -> void:
	kill()


## Убивает агента: пулей, ногой или упавшей лампой в M4b.
func kill() -> void:
	if _brain.is_dead():
		return
	_brain.kill()
	velocity = Vector2.ZERO
	_corpse_left = corpse_time
	_body.color = DEAD_COLOR
	died.emit(self)


func is_dead() -> bool:
	return _brain.is_dead()


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


## Дальность стрельбы: на погашенном этаже она короче. Считается в одном месте,
## чтобы порядок вызовов [method _ready] и [method set_in_the_dark] ничего не
## решал — иначе настроенный до [method Node.add_child] агент прозревал бы обратно.
func _refresh_fire_range() -> void:
	_brain.fire_range = dark_fire_range if _in_the_dark else fire_range


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)


## Досчитывает время, которое тело лежит на полу, и убирает его.
func _rot(delta: float) -> void:
	_corpse_left -= delta
	if _corpse_left <= 0.0:
		queue_free()


func _fire() -> void:
	var bullet := BULLET_SCENE.instantiate() as Bullet
	bullet.direction = _brain.facing
	bullet.speed = bullet_speed
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
