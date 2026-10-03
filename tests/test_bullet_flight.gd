extends GutTest

## A bullet does not slip through what it must hit, and it passes through a corpse
## (ADR-0037, decisions 5 and 6).
##
## Since M24a a bullet is three times faster than in the ROM and covers almost a wall's
## thickness per physics frame; under the tests' [member Engine.time_scale], four times
## more. Here it is even faster than it ever is in the game: its path per frame is many
## times longer than both the wall and the body, so slipping past means the path is not
## checked in full.

const BULLET_SCENE := preload("res://src/systems/combat/bullet.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")

## Bullet speed in the test, m/s: 5 m per frame at 60 frames per second.
const TOO_FAST: float = 300.0

## Where the wall stands and how thick it is, m: ten times thinner than the bullet's
## path per frame.
const WALL_X: float = 6.0
const WALL_THICKNESS: float = 0.1

## Flight height above the floor, m: into the chest of a standing agent.
const SHOT_HEIGHT: float = 1.1


## A floor under the whole scene: the agent has something to stand and lie on.
func _ground() -> void:
	_box(Vector3(0.0, -0.2, 0.0), Vector3(40.0, 0.4, WorldSpace.CORRIDOR_DEPTH))


## A thin wall across the flight.
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


## Otto's bullet from point [param x], flying right. What it hit is written into
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


## An agent who has come out of a doorway: one coming out is invulnerable, and the
## bullet would pass through him even without any corpse.
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
	assert_eq(hits.size(), 1, "the bullet hit once")
	assert_true(hits.size() == 1 and hits[0] == wall, "into the wall, not past it")
	assert_false(is_instance_valid(bullet), "and died on it")


func test_a_fast_bullet_hits_the_agent_in_its_way() -> void:
	_ground()
	_wall()
	var agent: Enemy = await _agent_at(3.0)
	var hits: Array[Node3D] = []
	_fire(0.0, hits)
	await wait_physics_frames(6)
	assert_true(
		hits.size() == 1 and hits[0] == agent, "the bullet met the agent, not the wall behind him"
	)


## A corpse stays until the end of the building but is not a target: the bullet flies
## through it into whatever is behind it (ADR-0037, decision 6).
func test_bullets_pass_through_a_corpse() -> void:
	_ground()
	var wall := _wall()
	var agent: Enemy = await _agent_at(3.0)
	agent.kill()
	var hits: Array[Node3D] = []
	_fire(0.0, hits)
	await wait_physics_frames(6)
	assert_true(hits.size() == 1 and hits[0] == wall, "through the corpse — into the wall")


## A bullet in a wall leaves a mark, but there are no more marks in the building than
## the cap: the old ones go first.
func test_bullet_holes_are_left_and_capped() -> void:
	_wall()
	var hits: Array[Node3D] = []
	for _shot: int in ShotFx.HOLES_KEPT + 5:
		_fire(0.0, hits)
		await wait_physics_frames(2)
	assert_eq(hits.size(), ShotFx.HOLES_KEPT + 5, "every bullet reached the wall")
	assert_eq(ShotFx.holes(), ShotFx.HOLES_KEPT, "marks — no more than the ceiling")


## A bullet born inside a body hits it at once, by a direct query, and the engine's
## overlap events are off: Jolt reported such an overlap only on some runs, and the
## bot's run on one seed ended differently every time (fix/bot-determinism).
func test_a_point_blank_bullet_hits_at_once_and_by_query() -> void:
	_ground()
	var target := _box(Vector3(2.0, SHOT_HEIGHT, 0.0), Vector3(0.6, 0.6, 0.6))
	target.collision_layer = 4
	await wait_physics_frames(1)
	var hits: Array[Node3D] = []
	var bullet := _fire(2.0, hits)
	assert_false(bullet.monitoring, "no engine overlap events")
	bullet.strike_point_blank()
	assert_eq(hits.size(), 1, "hit in the same frame it is fired")
	if hits.size() == 1:
		assert_eq(hits[0], target)
	bullet.strike_point_blank()
	assert_eq(hits.size(), 1, "one bullet hits once")
