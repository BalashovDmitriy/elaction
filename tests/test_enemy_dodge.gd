extends GutTest

## An agent leaves the line of a flying bullet.
##
## [EnemyBrain] decides this without a scene, and its stances are checked separately. Here we check
## what it does not contain: how the node finds a flying bullet and what it does with the collision
## shape. Bugs live exactly between these two halves — for example, a bullet the agent considers
## flying at him, although it flies away from him.

const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const BULLET_SCENE := preload("res://src/systems/combat/bullet.tscn")

## Where the bullet flies from, m from the agent. Closer than 20 ROM px (1.5 m), otherwise he does
## not notice it yet (@05F5).
const BULLET_REACH: float = 1.2

## How many frames are given for the reaction: per frame the angriest one's chance is ~75%, over a
## dozen — certain.
const REACT_FRAMES: int = 12

## The rules the agent lives by — and the test measures the bullet height by the same ones. One
## object for both: with two, the test would measure with one set of numbers while the agent dodged
## by another, and they would diverge silently.
var _rules := BuildingRules.new()


## The angriest agent: his chance to dodge is 255 out of 256 per tick, and what is checked here is
## the dodge itself, not the draw.
func _agent() -> Enemy:
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.apply_rules(_rules)
	add_child_autofree(agent)
	agent.set_threat(Arcade.TOP, 0, false)
	# Decisions are seeded: the chance to dodge is per ROM tick, and a frame is a quarter of a tick,
	# and without a seed the test sometimes caught the reaction and sometimes not. Before coming out of
	# the door — coming out already draws the first transition from the generator.
	agent.seed_decisions(1)
	# No target: the dodge does not depend on it, and Otto would drag half the game along with him.
	agent.setup(null, 1.0)
	return agent


## Waits until the agent comes out of the doorway: per the ROM, one coming out does not dodge.
func _step_out(agent: Enemy) -> void:
	while agent.is_emerging():
		await wait_physics_frames(1)


## Otto's bullet flying at the agent left to right or right to left — no matter, as long as at him.
## [param height] — above the agent's feet, m. In the scene "above" means growing Y.
func _bullet_at(agent: Enemy, height: float) -> Bullet:
	var bullet := BULLET_SCENE.instantiate() as Bullet
	bullet.direction = -1.0
	bullet.speed = 0.0
	bullet.collision_mask = Bullet.FROM_OTTO
	add_child_autofree(bullet)
	bullet.global_position = agent.global_position + Vector3(BULLET_REACH, height, 0.0)
	return bullet


func test_agent_kneels_under_a_high_bullet() -> void:
	var agent := _agent()
	await _step_out(agent)
	_bullet_at(agent, _rules.agent_kneel_height + 0.05)
	await wait_physics_frames(REACT_FRAMES)
	assert_eq(agent.stance(), EnemyBrain.Stance.KNEEL, "from a high bullet — to a knee")


func test_agent_drops_prone_under_a_low_bullet() -> void:
	var agent := _agent()
	await _step_out(agent)
	_bullet_at(agent, _rules.agent_kneel_height - 0.03)
	await wait_physics_frames(REACT_FRAMES)
	assert_eq(agent.stance(), EnemyBrain.Stance.PRONE, "from a low one — prone")


## The agent's own bullet is no reason to lie down: its mask is different, and it flies away from
## him.
func test_agent_ignores_bullets_that_are_not_his_problem() -> void:
	var agent := _agent()
	await _step_out(agent)
	var bullet := _bullet_at(agent, 0.66)
	bullet.collision_mask = Bullet.FROM_ENEMY
	await wait_physics_frames(2)
	assert_eq(agent.stance(), EnemyBrain.Stance.STAND, "another's shot is no threat to the agent")


## A bullet flying away is no reason either: it has already gone past.
func test_agent_ignores_a_bullet_flying_away() -> void:
	var agent := _agent()
	await _step_out(agent)
	var bullet := _bullet_at(agent, 0.66)
	bullet.direction = 1.0
	await wait_physics_frames(2)
	assert_eq(
		agent.stance(), EnemyBrain.Stance.STAND, "they do not duck after a bullet that has passed"
	)


## A bullet that has passed the middle but not left the body is the most dangerous of all.
##
## While "is it flying at us" was decided by side, the agent straightened up exactly at that moment
## — and took the same bullet in the chest. This was found not by a test but by shooting poses: an
## agent who dodged a shot turned out dead time after time.
func test_agent_stays_down_until_the_bullet_clears_his_body() -> void:
	var agent := _agent()
	await _step_out(agent)
	var bullet := _bullet_at(agent, _rules.agent_kneel_height + 0.05)
	await wait_physics_frames(REACT_FRAMES)
	assert_eq(agent.stance(), EnemyBrain.Stance.KNEEL, "first he leaves the line")

	# Steps are measured from the body itself and the bullet itself, not with numbers: the agent and
	# the assets have already moved to a different scale twice, and the hand-written numbers then
	# silently stopped hitting the boundary this test was written for.
	var body_half := _body_half_width(agent)
	var tail := bullet.half_length()

	# The bullet is past the middle, but still in the body.
	bullet.global_position.x = agent.global_position.x - body_half * 0.5
	await wait_physics_frames(2)
	assert_eq(
		agent.stance(), EnemyBrain.Stance.KNEEL, "and does not stand while it is within his bounds"
	)

	# The middle of the bullet is outside the body's bounds, but the tail is still inside: half a body
	# width is not enough for it to clear the chest.
	bullet.global_position.x = agent.global_position.x - (body_half + tail * 0.5)
	await wait_physics_frames(2)
	assert_eq(agent.stance(), EnemyBrain.Stance.KNEEL, "and while the tail holds it — also")

	# One that has gone behind no longer holds him — but the agent stands up at the end of the action:
	# in the ROM a dodge lasts the whole action, not while the bullet is near (@1C7A).
	bullet.global_position.x = agent.global_position.x - (body_half + tail) * 2.0
	var action := int(
		ceilf((Arcade.action_time(Arcade.TOP) + 0.1) * Engine.physics_ticks_per_second)
	)
	await wait_physics_frames(action)
	assert_eq(
		agent.stance(), EnemyBrain.Stance.STAND, "one that went behind his back no longer holds him"
	)


## Half the width of the agent's body, m. Taken from the shape, as the agent takes it himself.
func _body_half_width(agent: Enemy) -> float:
	var shape := agent.get_node("Shape") as CollisionShape3D
	return (shape.shape as BoxShape3D).size.x * 0.5
