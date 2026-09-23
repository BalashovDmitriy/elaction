extends GutTest

## Агент уходит с линии летящей пули.
##
## [EnemyBrain] решает это без сцены, и его стойки проверены отдельно. Здесь
## проверяется то, чего в нём нет: как узел находит летящую пулю и что делает
## с формой коллизии. Между этими двумя половинами и живут ошибки — например,
## пуля, которую агент считает летящей в себя, хотя она летит от него.

const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const BULLET_SCENE := preload("res://src/systems/combat/bullet.tscn")

## Откуда летит пуля, м от агента. Ближе 20 px ROM (1.5 м), иначе он её ещё
## не замечает (@05F5).
const BULLET_REACH: float = 1.2

## Сколько кадров даётся на реакцию: за кадр шанс самого злого ~75%, за
## дюжину — наверняка.
const REACT_FRAMES: int = 12

## Правила, по которым живёт агент, — и по ним же тест отмеряет высоту пули.
## Один объект на обоих: с двумя тест мерил бы одним набором чисел, а агент
## уклонялся бы по другому, и разошлись бы они молча.
var _rules := BuildingRules.new()


## Самый злой агент: шанс увернуться у него — 255 из 256 за тик, а тут
## проверяется само уклонение, а не жребий.
func _agent() -> Enemy:
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.apply_rules(_rules)
	add_child_autofree(agent)
	agent.set_threat(Arcade.TOP, 0, false)
	# Цели нет: уклонение от неё не зависит, а Otto притащил бы за собой
	# половину игры.
	agent.setup(null, 1.0)
	# Решения посеяны: шанс увернуться — за тик ROM, а кадр — четверть тика,
	# и без сида тест то ловил реакцию, то нет.
	agent.seed_decisions(1)
	return agent


## Ждёт, пока агент выйдет из проёма: выходящий по ROM не уворачивается.
func _step_out(agent: Enemy) -> void:
	while agent.is_emerging():
		await wait_physics_frames(1)


## Пуля Otto, летящая в агента слева направо или справа налево — всё равно,
## лишь бы в него. [param height] — над ногами агента, м. В сцене «над» — это
## рост Y.
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
	assert_eq(agent.stance(), EnemyBrain.Stance.KNEEL, "от высокой пули — на колено")


func test_agent_drops_prone_under_a_low_bullet() -> void:
	var agent := _agent()
	await _step_out(agent)
	_bullet_at(agent, _rules.agent_kneel_height - 0.03)
	await wait_physics_frames(REACT_FRAMES)
	assert_eq(agent.stance(), EnemyBrain.Stance.PRONE, "от низкой — лёжа")


## Своя пуля агента не повод ложиться: маска у неё другая, и летит она от него.
func test_agent_ignores_bullets_that_are_not_his_problem() -> void:
	var agent := _agent()
	await _step_out(agent)
	var bullet := _bullet_at(agent, 0.66)
	bullet.collision_mask = Bullet.FROM_ENEMY
	await wait_physics_frames(2)
	assert_eq(agent.stance(), EnemyBrain.Stance.STAND, "чужой выстрел агенту не страшен")


## Пуля, летящая прочь, тоже не повод: она уже прошла мимо.
func test_agent_ignores_a_bullet_flying_away() -> void:
	var agent := _agent()
	await _step_out(agent)
	var bullet := _bullet_at(agent, 0.66)
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
	await _step_out(agent)
	var bullet := _bullet_at(agent, _rules.agent_kneel_height + 0.05)
	await wait_physics_frames(REACT_FRAMES)
	assert_eq(agent.stance(), EnemyBrain.Stance.KNEEL, "сперва уходит с линии")

	# Шаги отмеряются от самого тела и самой пули, а не числами: агент и ассеты
	# уже дважды переезжали в другой масштаб, и записанные руками числа тогда
	# молча перестали попадать в границу, ради которой этот тест и написан.
	var body_half := _body_half_width(agent)
	var tail := bullet.half_length()

	# Пуля за серединой, но ещё в теле.
	bullet.global_position.x = agent.global_position.x - body_half * 0.5
	await wait_physics_frames(2)
	assert_eq(agent.stance(), EnemyBrain.Stance.KNEEL, "и не встаёт, пока она в габарите")

	# Середина пули за габаритом тела, а хвост — ещё внутри: полширины тела
	# ей не хватает, чтобы разминуться с грудью.
	bullet.global_position.x = agent.global_position.x - (body_half + tail * 0.5)
	await wait_physics_frames(2)
	assert_eq(agent.stance(), EnemyBrain.Stance.KNEEL, "и пока её держит хвост — тоже")

	# Ушедшая за спину больше не держит — но встаёт агент по концу действия:
	# увёртка в ROM длится действие целиком, а не пока пуля рядом (@1C7A).
	bullet.global_position.x = agent.global_position.x - (body_half + tail) * 2.0
	var action := int(
		ceilf((Arcade.action_time(Arcade.TOP) + 0.1) * Engine.physics_ticks_per_second)
	)
	await wait_physics_frames(action)
	assert_eq(agent.stance(), EnemyBrain.Stance.STAND, "ушедшая за спину больше не держит")


## Полширины тела агента, м. Берётся у формы, как её берёт сам агент.
func _body_half_width(agent: Enemy) -> float:
	var shape := agent.get_node("Shape") as CollisionShape3D
	return (shape.shape as BoxShape3D).size.x * 0.5
