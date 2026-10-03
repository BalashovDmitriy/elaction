extends GutTest

## The agent's shot between the brain and the node: which way the bullet leaves and what it
## does when the shooter is gone (ADR-0060).
##
## [EnemyBrain] picks the shooting pose by a draw, so the shot is set on the brain
## directly: the test checks what the node does with a decided shot, not the draw.

const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")

## The agent's floor ends here: beyond it is a shaft, and Otto stands across it.
const EDGE_X: float = 0.0
const OTTO_X: float = 3.0

## Wind-up long enough for one shooting on the move to reach the floor edge first.
const LONG_WIND_UP: float = 0.8
const SHORT_WIND_UP: float = 0.05

## How many physics steps to wait for the shot and for the bullet to cross the shaft.
const SHOT_FRAMES: int = 120


func after_each() -> void:
	GameState.instance().reset()


## A floor slab: top at height 0, from [param from_x] to [param to_x].
func _slab(from_x: float, to_x: float) -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(to_x - from_x, 0.4, WorldSpace.CORRIDOR_DEPTH)
	shape.shape = box
	shape.position = Vector3((from_x + to_x) * 0.5, -0.2, 0.0)
	ground.add_child(shape)
	add_child_autofree(ground)


## Two floors with a shaft between them: the agent's on the left, Otto's on the right.
func _otto_across_a_shaft() -> Otto:
	_slab(-8.0, EDGE_X)
	_slab(OTTO_X - 1.0, OTTO_X + 5.0)
	var otto := OTTO_SCENE.instantiate() as Otto
	add_child_autofree(otto)
	otto.global_position = Vector3(OTTO_X, 0.05, WorldSpace.PLAY_Z)
	return otto


## An agent at [param x] who does not open fire by himself: the shot is set by
## [method _decide_a_shot].
func _agent_at(x: float, otto: Otto) -> Enemy:
	var rules := BuildingRules.new()
	rules.agents_hold_fire = true
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.apply_rules(rules)
	add_child_autofree(agent)
	agent.global_position = Vector3(x, 0.05, WorldSpace.PLAY_Z)
	agent.seed_decisions(1)
	agent.setup(otto, 1.0)
	return agent


## The brain has decided a shot to the right, toward Otto: the wind-up runs.
func _decide_a_shot(agent: Enemy, on_the_move: bool, wind_up: float) -> void:
	var brain := agent.get(&"_brain") as EnemyBrain
	brain.state = EnemyBrain.State.SHOOT
	brain.stance = EnemyBrain.Stance.STAND
	brain.facing = 1.0
	brain.set(&"_on_the_move", on_the_move)
	brain.set(&"_shot_pending", true)
	brain.set(&"_wind_up_left", wind_up)
	brain.set(&"_action_left", wind_up + 0.2)
	agent.set(&"_faced", 1.0)


## Waits for the agent's bullet and returns it; null if he never fired.
func _await_bullet(agent: Enemy) -> Bullet:
	for step: int in SHOT_FRAMES:
		await wait_physics_frames(1)
		var bullet := agent.get(&"_bullet") as Bullet
		if is_instance_valid(bullet):
			return bullet
	return null


## One shooting on the move walks on toward Otto during the wind-up and reaches the floor
## edge. The edge stops him, it does not turn him: turned, he fired away from Otto.
func test_a_shooter_on_the_move_fires_toward_otto_from_the_edge() -> void:
	var otto := _otto_across_a_shaft()
	var agent := _agent_at(EDGE_X - 0.4, otto)
	await wait_physics_frames(2)
	_decide_a_shot(agent, true, LONG_WIND_UP)
	var bullet := await _await_bullet(agent)
	assert_not_null(bullet, "the agent fired")
	if bullet == null:
		return
	assert_eq(bullet.direction, 1.0, "the bullet leaves toward Otto")
	assert_lt(agent.global_position.x, EDGE_X, "and the agent stayed on his floor")
	await wait_physics_frames(SHOT_FRAMES)
	assert_true(otto.is_dead(), "the shot across the shaft killed Otto")


## The shooter goes into a door while his bullet flies: the bullet still kills, it does
## not just spray blood on Otto.
func test_a_bullet_kills_after_its_shooter_is_gone() -> void:
	var otto := _otto_across_a_shaft()
	var agent := _agent_at(EDGE_X - 1.5, otto)
	await wait_physics_frames(2)
	_decide_a_shot(agent, false, SHORT_WIND_UP)
	var bullet := await _await_bullet(agent)
	assert_not_null(bullet, "the agent fired")
	agent.free()
	await wait_physics_frames(SHOT_FRAMES)
	assert_true(otto.is_dead(), "the bullet of a freed agent still kills")


## A bullet that reaches an Otto the world is carrying (a door or an escalator took him in this
## step) neither kills him nor marks him as shot: the mark would log his next fall as this
## bullet (ADR-0060).
func test_a_bullet_on_a_carried_otto_leaves_no_mark() -> void:
	var otto := OTTO_SCENE.instantiate() as Otto
	add_child_autofree(otto)
	await wait_physics_frames(2)
	otto.ride(true)
	Enemy._strike(otto, [0.0, 0.0], EnemyBrain.Stance.STAND)
	assert_false(otto.is_dead(), "carried, he is not killed")
	assert_false(otto.has_meta(&"shooter"), "nor marked as shot")
	otto.ride(false)
