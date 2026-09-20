extends GutTest

## Тесты решений агента.
##
## Мозги врага не знают ни про узлы, ни про физику: принимают вектор до Otto
## и возвращают решение. В M4a агент выходит из двери, идёт и стреляет по
## линии — уклонения и лифты отложены (ADR-0006, пункт 6).

const STEP: float = 0.1
## Векторы до цели — в метрах, как и всё в правилах с M15.
const FAR_ABOVE := Vector2(0.4, -1.2)
const IN_FRONT := Vector2(0.6, 0.0)


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
	_run(brain, 0.4, Vector2(-2.0, -1.2))
	assert_eq(brain.facing, -1.0)


## Замах: первый выстрел по появившейся цели уходит не в тот же кадр.
##
## Без него у игрока не было хода вовсе — особенно в кабине лифта, где присед
## выключен и уклоняться нечем (ADR-0016, пункт 1).
func test_agent_takes_aim_before_the_first_shot() -> void:
	var brain := _brain()
	_run(brain, 0.4, FAR_ABOVE)
	assert_eq(brain.update(STEP, IN_FRONT, true), EnemyBrain.State.SHOOT, "цель на линии")
	assert_false(brain.fired(), "но выстрела в тот же кадр нет")


func test_agent_shoots_along_the_line() -> void:
	var brain := _brain()
	_run(brain, 0.4, FAR_ABOVE)

	# Ждём выстрела кадр за кадром, а не выдержкой: [method EnemyBrain.fired]
	# говорит только про последний кадр, и пройти мимо него выдержкой легко.
	var fired := false
	var frames := 0
	while not fired and frames < 120:
		brain.update(STEP, IN_FRONT, true)
		fired = brain.fired()
		frames += 1

	assert_true(fired, "агент выстрелил, отцелившись")
	assert_eq(brain.state, EnemyBrain.State.SHOOT)
	assert_gt(float(frames) * STEP, brain.aim_time, "и не раньше замаха")


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
	var far := Vector2(brain.fire_range + 0.5, 0.0)
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


## Уклонение: от высокой пули агент уходит на колено, от низкой ложится.
## Считается ростом стойки против высоты пули, поэтому проверяется без сцены.
func test_agent_kneels_under_a_high_bullet() -> void:
	var brain := _brain()
	brain.can_kneel = true
	var high := brain.kneel_height + 0.04
	assert_eq(brain.stance_against(high), EnemyBrain.Stance.KNEEL)


func test_agent_goes_prone_under_a_bullet_a_knee_cannot_clear() -> void:
	var brain := _brain()
	brain.can_kneel = true
	brain.can_go_prone = true
	var low := brain.prone_height + 0.02
	assert_lt(low, brain.kneel_height, "колено такую пулю не пропускает")
	assert_eq(brain.stance_against(low), EnemyBrain.Stance.PRONE)


## Самая высокая из годных, а не самая низкая: лёжа агент неподвижен, и ложиться
## он должен только тогда, когда колено уже не спасает.
func test_agent_prefers_the_knee_while_it_still_helps() -> void:
	var brain := _brain()
	brain.can_kneel = true
	brain.can_go_prone = true
	assert_eq(brain.stance_against(brain.kneel_height + 0.04), EnemyBrain.Stance.KNEEL)


func test_agent_stands_when_nothing_flies() -> void:
	var brain := _brain()
	brain.can_kneel = true
	brain.can_go_prone = true
	assert_eq(brain.stance_against(-1.0), EnemyBrain.Stance.STAND)
	assert_true(brain.is_standing())


## Пуля ниже всех стоек: уклоняться нечем, и притворяться, что получилось,
## нельзя — иначе агент считался бы неуязвимым, стоя во весь рост.
func test_agent_stands_when_no_stance_clears_the_bullet() -> void:
	var brain := _brain()
	brain.can_kneel = true
	brain.can_go_prone = true
	assert_eq(brain.stance_against(0.01), EnemyBrain.Stance.STAND)


## В первых зданиях агенты только стоят: уклонение включается злостью.
func test_an_agent_that_may_not_kneel_stays_standing() -> void:
	var brain := _brain()
	assert_false(brain.can_kneel)
	assert_eq(brain.stance_against(brain.kneel_height + 0.04), EnemyBrain.Stance.STAND)


## Рост идёт за стойкой: по нему уровень подгоняет форму коллизии, и разъехаться
## им нельзя — иначе лежачий агент ловил бы пули стоячим телом.
func test_height_follows_the_stance() -> void:
	var brain := _brain()
	brain.can_kneel = true
	brain.can_go_prone = true

	brain.stance = EnemyBrain.Stance.STAND
	assert_eq(brain.height(), brain.stand_height)
	brain.stance = EnemyBrain.Stance.KNEEL
	assert_eq(brain.height(), brain.kneel_height)
	brain.stance = EnemyBrain.Stance.PRONE
	assert_eq(brain.height(), brain.prone_height)
	assert_false(brain.is_standing(), "лёжа агент не ходит")


## Мёртвый не уклоняется: труп лежит как упал.
func test_the_dead_do_not_dodge() -> void:
	var brain := _brain()
	brain.can_kneel = true
	brain.stance = EnemyBrain.Stance.KNEEL
	brain.kill()
	assert_eq(brain.stance, EnemyBrain.Stance.STAND)
