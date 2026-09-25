extends GutTest

## Пуля не проскакивает сквозь то, во что должна попасть, — и проходит сквозь
## труп (ADR-0037, решения 5 и 6).
##
## С M24a пуля втрое быстрее ROM и за кадр физики проходит почти толщину стены;
## под [member Engine.time_scale] тестов — вчетверо больше. Здесь она ещё
## быстрее, чем бывает в игре: путь за кадр в разы длиннее и стены, и тела, —
## проскочить мимо значит, что путь не проверяется целиком.

const BULLET_SCENE := preload("res://src/systems/combat/bullet.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")

## Скорость пули в тесте, м/с: 5 м за кадр при 60 кадрах в секунду.
const TOO_FAST: float = 300.0

## Где стоит стена и какой она толщины, м: тоньше пути пули за кадр вдесятеро.
const WALL_X: float = 6.0
const WALL_THICKNESS: float = 0.1

## Высота полёта над полом, м: в грудь стоящему агенту.
const SHOT_HEIGHT: float = 1.1


## Пол под всей сценой: агенту есть на чём стоять и на что лечь.
func _ground() -> void:
	_box(Vector3(0.0, -0.2, 0.0), Vector3(40.0, 0.4, WorldSpace.CORRIDOR_DEPTH))


## Тонкая стена поперёк полёта.
func _wall() -> StaticBody3D:
	return _box(Vector3(WALL_X, 1.5, 0.0), Vector3(WALL_THICKNESS, 3.0, WorldSpace.CORRIDOR_DEPTH))


func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child_autofree(body)
	body.global_position = at
	return body


## Пуля Otto из точки [param x], летящая вправо. Что она задела, пишется в
## [param hits].
func _fire(x: float, hits: Array[Node3D]) -> Bullet:
	var bullet := BULLET_SCENE.instantiate() as Bullet
	bullet.direction = 1.0
	bullet.speed = TOO_FAST
	bullet.collision_mask = Bullet.FROM_OTTO
	bullet.hit_target.connect(func(target: Node3D) -> void: hits.append(target))
	add_child_autofree(bullet)
	bullet.global_position = Vector3(x, SHOT_HEIGHT, 0.0)
	return bullet


## Агент, вышедший из проёма: выходящий неуязвим, и пуля прошла бы сквозь него
## и без всякого трупа.
func _agent_at(x: float) -> Enemy:
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.walk_speed = 0.0
	add_child_autofree(agent)
	agent.global_position = Vector3(x, 0.0, 0.0)
	agent.setup(null, 1.0)
	while agent.is_emerging():
		await wait_physics_frames(1)
	return agent


func test_a_fast_bullet_stops_at_a_thin_wall() -> void:
	var wall := _wall()
	var hits: Array[Node3D] = []
	var bullet := _fire(0.0, hits)
	await wait_physics_frames(6)
	assert_eq(hits.size(), 1, "пуля попала один раз")
	assert_true(hits.size() == 1 and hits[0] == wall, "в стену, а не мимо неё")
	assert_false(is_instance_valid(bullet), "и погасла о неё")


func test_a_fast_bullet_hits_the_agent_in_its_way() -> void:
	_ground()
	_wall()
	var agent: Enemy = await _agent_at(3.0)
	var hits: Array[Node3D] = []
	_fire(0.0, hits)
	await wait_physics_frames(6)
	assert_true(hits.size() == 1 and hits[0] == agent, "пуля встретила агента, а не стену за ним")


## Труп лежит до конца здания, но мишенью не служит: пуля летит сквозь него в
## то, что за ним (ADR-0037, решение 6).
func test_bullets_pass_through_a_corpse() -> void:
	_ground()
	var wall := _wall()
	var agent: Enemy = await _agent_at(3.0)
	agent.kill()
	var hits: Array[Node3D] = []
	_fire(0.0, hits)
	await wait_physics_frames(6)
	assert_true(hits.size() == 1 and hits[0] == wall, "сквозь труп — в стену")


## Пуля в стене оставляет след, но следов в здании не больше потолка: старые
## уходят первыми.
func test_bullet_holes_are_left_and_capped() -> void:
	_wall()
	var hits: Array[Node3D] = []
	for _shot: int in ShotFx.HOLES_KEPT + 5:
		_fire(0.0, hits)
		await wait_physics_frames(2)
	assert_eq(hits.size(), ShotFx.HOLES_KEPT + 5, "каждая пуля дошла до стены")
	assert_eq(ShotFx.holes(), ShotFx.HOLES_KEPT, "следов — не больше потолка")
