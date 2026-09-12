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
const ALIVE_COLOR := Color(0.78, 0.32, 0.30)
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

var _brain := EnemyBrain.new()
var _target: Otto = null
var _corpse_left: float = 0.0

@onready var _body: ColorRect = $Body


func _physics_process(delta: float) -> void:
	if _brain.is_dead():
		_rot(delta)
		return

	var alive_target := _target != null and not _target.is_dead()
	var to_target := _target.global_position - global_position if alive_target else Vector2.ZERO
	var state := _brain.update(delta, to_target, alive_target)
	if _brain.fired():
		_fire()

	velocity.x = walk_speed * _brain.facing if state == EnemyBrain.State.WALK else 0.0
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)
	move_and_slide()


## Выпускает агента из двери: он выходит в сторону [param towards].
func setup(target: Otto, towards: float) -> void:
	_target = target
	_brain.start(towards)


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


## Досчитывает время, которое тело лежит на полу, и убирает его.
func _rot(delta: float) -> void:
	_corpse_left -= delta
	if _corpse_left <= 0.0:
		queue_free()


func _fire() -> void:
	var bullet := BULLET_SCENE.instantiate() as Bullet
	bullet.direction = _brain.facing
	bullet.speed = bullet_speed
	bullet.collision_mask = Bullet.HITS_PLAYER
	bullet.hit_target.connect(_on_bullet_hit)
	get_parent().add_child(bullet)
	bullet.global_position = global_position + Vector2(_brain.facing * muzzle_offset, shot_height)


## Попадание своей пули. Очков за Otto никто не получает — он просто гибнет.
func _on_bullet_hit(target: Node2D) -> void:
	var victim := target as Otto
	if victim == null:
		return
	victim.take_bullet()
