extends GutTest

## Тесты решений агента.
##
## Мозги врага не знают ни про узлы, ни про физику: принимают вектор до Otto
## и возвращают решение. В M4a агент выходит из двери, идёт и стреляет по
## линии — уклонения и лифты отложены (ADR-0006, пункт 6).

const STEP: float = 0.1
const FAR_ABOVE := Vector2(40.0, -120.0)
const IN_FRONT := Vector2(60.0, 0.0)


func _brain() -> EnemyBrain:
	var brain := EnemyBrain.new()
	brain.emerge_time = 0.3
	brain.fire_cooldown = 1.0
	brain.start(1.0)
	return brain


func _run(brain: EnemyBrain, seconds: float, to_target: Vector2) -> EnemyBrain.State:
	var state := brain.state
	for _frame: int in int(roundf(seconds / STEP)):
		state = brain.update(STEP, to_target, true)
	return state


func test_agent_climbs_out_of_the_door_first() -> void:
	var brain := _brain()
	assert_eq(brain.update(STEP, IN_FRONT, true), EnemyBrain.State.EMERGING)
	assert_false(brain.fired(), "пока вылезает — не стреляет")


func test_agent_walks_once_it_is_out() -> void:
	var brain := _brain()
	assert_eq(_run(brain, 0.4, FAR_ABOVE), EnemyBrain.State.WALK)


func test_agent_turns_towards_the_target() -> void:
	var brain := _brain()
	_run(brain, 0.4, Vector2(-200.0, -120.0))
	assert_eq(brain.facing, -1.0)


func test_agent_shoots_along_the_line() -> void:
	var brain := _brain()
	_run(brain, 0.4, FAR_ABOVE)
	assert_eq(brain.update(STEP, IN_FRONT, true), EnemyBrain.State.SHOOT)
	assert_true(brain.fired())


func test_agent_holds_fire_between_shots() -> void:
	var brain := _brain()
	_run(brain, 0.4, FAR_ABOVE)
	brain.update(STEP, IN_FRONT, true)
	brain.update(STEP, IN_FRONT, true)
	assert_false(brain.fired(), "между выстрелами есть пауза")


func test_agent_does_not_shoot_another_floor() -> void:
	var brain := _brain()
	assert_eq(_run(brain, 0.6, FAR_ABOVE), EnemyBrain.State.WALK)
	assert_false(brain.fired())


func test_agent_does_not_shoot_out_of_range() -> void:
	var brain := _brain()
	var far := Vector2(brain.fire_range + 50.0, 0.0)
	assert_eq(_run(brain, 0.6, far), EnemyBrain.State.WALK)


func test_agent_does_not_shoot_the_dead() -> void:
	var brain := _brain()
	_run(brain, 0.4, FAR_ABOVE)
	brain.update(STEP, IN_FRONT, false)
	assert_false(brain.fired(), "по мёртвому не стреляют")


func test_dead_agent_stays_dead() -> void:
	var brain := _brain()
	brain.kill()
	assert_eq(brain.update(STEP, IN_FRONT, true), EnemyBrain.State.DEAD)
	assert_false(brain.fired())
