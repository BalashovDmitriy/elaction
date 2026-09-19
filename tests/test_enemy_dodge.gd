extends GutTest

## Агент уходит с линии летящей пули.
##
## [EnemyBrain] решает это без сцены, и его стойки проверены отдельно. Здесь
## проверяется то, чего в нём нет: как узел находит летящую пулю и что делает
## с формой коллизии. Между этими двумя половинами и живут ошибки — например,
## пуля, которую агент считает летящей в себя, хотя она летит от него.

const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const BULLET_SCENE := preload("res://src/systems/combat/bullet.tscn")

## Откуда летит пуля, px от агента. Меньше [member BuildingRules.agent_dodge_sight],
## иначе он её ещё не замечает.
const BULLET_REACH: float = 50.0

## Правила, по которым живёт агент, — и по ним же тест отмеряет высоту пули.
## Один объект на обоих: с двумя тест мерил бы одним набором чисел, а агент
## уклонялся бы по другому, и разошлись бы они молча.
var _rules := BuildingRules.new()


## Агент, которому позволено и приседать, и ложиться: в первых зданиях он этого
## не умеет, а тут проверяется само уклонение.
func _agent() -> Enemy:
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.apply_rules(_rules)
	add_child_autofree(agent)
	agent.set_menace(_rules.agent_goes_prone_from_menace)
	# Цели нет: уклонение от неё не зависит, а Otto притащил бы за собой
	# половину игры.
	agent.setup(null, 1.0)
	return agent


## Пуля Otto, летящая в агента слева направо или справа налево — всё равно,
## лишь бы в него. [param height] — над ногами агента, px.
func _bullet_at(agent: Enemy, height: float) -> Bullet:
	var bullet := BULLET_SCENE.instantiate() as Bullet
	bullet.direction = -1.0
	bullet.speed = 0.0
	bullet.collision_mask = Bullet.FROM_OTTO
	add_child_autofree(bullet)
	bullet.global_position = agent.global_position + Vector2(BULLET_REACH, -height)
	return bullet


func test_agent_kneels_under_a_high_bullet() -> void:
	var agent := _agent()
	_bullet_at(agent, _rules.agent_kneel_height + 5.0)
	await wait_physics_frames(2)
	assert_eq(agent.stance(), EnemyBrain.Stance.KNEEL, "от высокой пули — на колено")


func test_agent_drops_prone_under_a_low_bullet() -> void:
	var agent := _agent()
	_bullet_at(agent, _rules.agent_kneel_height - 3.0)
	await wait_physics_frames(2)
	assert_eq(agent.stance(), EnemyBrain.Stance.PRONE, "от низкой — лёжа")


## Своя пуля агента не повод ложиться: маска у неё другая, и летит она от него.
func test_agent_ignores_bullets_that_are_not_his_problem() -> void:
	var agent := _agent()
	var bullet := _bullet_at(agent, 22.0)
	bullet.collision_mask = Bullet.FROM_ENEMY
	await wait_physics_frames(2)
	assert_eq(agent.stance(), EnemyBrain.Stance.STAND, "чужой выстрел агенту не страшен")


## Пуля, летящая прочь, тоже не повод: она уже прошла мимо.
func test_agent_ignores_a_bullet_flying_away() -> void:
	var agent := _agent()
	var bullet := _bullet_at(agent, 22.0)
	bullet.direction = 1.0
	await wait_physics_frames(2)
	assert_eq(agent.stance(), EnemyBrain.Stance.STAND, "вслед ушедшей пуле не приседают")


## Пуля, миновавшая середину, но не вышедшая из тела, опаснее всех.
##
## Пока «летит ли она в нас» считалось по стороне, агент распрямлялся ровно
## в этот миг — и ловил ту же пулю грудью. Нашлось это не тестом, а съёмкой
## поз: агент, уклонившийся от выстрела, раз за разом оказывался мёртвым.
func test_agent_stays_down_until_the_bullet_clears_his_body() -> void:
	var agent := _agent()
	var bullet := _bullet_at(agent, _rules.agent_kneel_height + 5.0)
	await wait_physics_frames(2)
	assert_eq(agent.stance(), EnemyBrain.Stance.KNEEL, "сперва уходит с линии")

	# Тело агента — 12 px шириной, и четыре пикселя за серединой всё ещё в нём.
	bullet.global_position.x = agent.global_position.x - 4.0
	await wait_physics_frames(2)
	assert_eq(agent.stance(), EnemyBrain.Stance.KNEEL, "и не встаёт, пока она в габарите")

	# Середина пули за габаритом тела, а хвост — ещё внутри: пуля 6 px длиной,
	# и полширины тела ей не хватает, чтобы разминуться с грудью.
	bullet.global_position.x = agent.global_position.x - 8.0
	await wait_physics_frames(2)
	assert_eq(agent.stance(), EnemyBrain.Stance.KNEEL, "и пока её держит хвост — тоже")

	bullet.global_position.x = agent.global_position.x - 40.0
	await wait_physics_frames(2)
	assert_eq(agent.stance(), EnemyBrain.Stance.STAND, "ушедшая за спину больше не держит")
