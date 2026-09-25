extends GutTest

## Тесты решений агента по правилам ROM (ADR-0027).
##
## Мозги врага не знают ни про узлы, ни про физику: принимают вектор до Otto
## и возвращают решение. Числа — из [Arcade]: здесь проверяется, что мозг
## ими пользуется, а сами числа сверяет [code]test_arcade.gd[/code].

const STEP: float = 1.0 / 60.0
## Векторы до цели — в метрах, как и всё в правилах с M15.
const FAR_ABOVE := Vector2(0.4, -1.2)
const IN_FRONT := Vector2(2.0, 0.0)
const BEHIND := Vector2(-2.0, 0.0)


func _brain(anger: int = 0) -> EnemyBrain:
	var brain := EnemyBrain.new()
	brain.emerge_time = 0.3
	brain.anger = anger
	brain.rng.seed = 7
	brain.start(1.0)
	return brain


func _run(brain: EnemyBrain, seconds: float, to_target: Vector2, sees: bool = true) -> void:
	for _frame: int in int(roundf(seconds / STEP)):
		brain.update(STEP, to_target, sees)


## Сколько кадров до первого выстрела, -1 — не выстрелил за [param limit] с.
func _frames_to_shot(brain: EnemyBrain, to_target: Vector2, limit: float = 8.0) -> int:
	for frame: int in int(limit / STEP):
		brain.update(STEP, to_target, true)
		if brain.fired():
			return frame
	return -1


func test_agent_climbs_out_of_the_door_first() -> void:
	var brain := _brain()
	assert_eq(brain.update(STEP, IN_FRONT, true), EnemyBrain.State.EMERGING)
	assert_false(brain.fired(), "пока вылезает — не стреляет")


func test_agent_walks_once_it_is_out() -> void:
	var brain := _brain()
	_run(brain, 0.4, FAR_ABOVE)
	assert_eq(brain.state, EnemyBrain.State.WALK)


## Спокойный агент целится 10 тиков (@1BDF) — выстрел уходит не в тот же кадр.
func test_a_calm_agent_takes_aim() -> void:
	var brain := _brain(0)
	_run(brain, 0.4, FAR_ABOVE)
	var frames := _frames_to_shot(brain, IN_FRONT)
	assert_gt(frames, -1, "агент выстрелил")
	assert_gte(float(frames) * STEP, Arcade.wind_up(0) - STEP, "не раньше замаха")


## Замах виден: пока пуля не ушла, агент замахивается, и уровень зажигает луч
## прицела (ADR-0037, решение 5). Вылетела пуля — замаха больше нет.
func test_the_wind_up_is_visible_until_the_shot() -> void:
	var brain := _brain(0)
	_run(brain, 0.4, FAR_ABOVE)
	brain.update(STEP, IN_FRONT, true)
	assert_true(brain.is_winding_up(), "решил стрелять — замахивается")
	assert_almost_eq(brain.wind_up_left(), Arcade.wind_up(0), STEP * 1.5, "замах ROM")
	var frames := _frames_to_shot(brain, IN_FRONT)
	assert_gt(frames, -1, "выстрелил")
	assert_false(brain.is_winding_up(), "пуля ушла — луча нет")
	assert_eq(brain.wind_up_left(), 0.0)


## Злой — с самым коротким замахом: в ROM при злости 10 и выше пуля уходит
## сразу, у нас — через [constant EnemyBrain.MIN_TELL], чтобы луч успели увидеть.
func test_a_mean_agent_fires_after_the_shortest_tell() -> void:
	var brain := _brain(12)
	_run(brain, 0.4, FAR_ABOVE)
	var frames := _frames_to_shot(brain, IN_FRONT)
	var tell := int(ceil(EnemyBrain.MIN_TELL / STEP))
	assert_gte(frames, tell - 1, "не раньше минимального замаха")
	assert_lte(frames, tell + 1, "и не позже")


## Пауза после выстрела — max(0, 80 − 8·злость) тиков (@0055).
func test_agent_holds_fire_between_shots() -> void:
	var brain := _brain(0)
	_run(brain, 0.4, FAR_ABOVE)
	assert_gt(_frames_to_shot(brain, IN_FRONT), -1)
	var again := _frames_to_shot(brain, IN_FRONT)
	assert_gte(float(again) * STEP, Arcade.cooldown(0) - Arcade.action_time(0), "пауза по ROM")


## Пуля у агента одна: пока летит прошлая, новой нет (@1BAE).
func test_one_bullet_in_flight() -> void:
	var brain := _brain(12)
	_run(brain, 0.4, FAR_ABOVE)
	for _frame: int in 120:
		brain.update(STEP, IN_FRONT, true, -1.0, true, false)
		assert_false(brain.fired(), "прошлая пуля в полёте — не стреляет")


## Стреляет, глядя на Otto; спиной к нему — нет, если нет тревоги (@0568).
func test_agent_shoots_only_what_he_faces() -> void:
	var brain := _brain(12)
	_run(brain, 0.4, FAR_ABOVE)
	brain.face(1.0)
	for _frame: int in 30:
		brain.update(STEP, BEHIND, true)
		assert_false(brain.fired(), "Otto за спиной — не стреляет")
		brain.face(1.0)


func test_an_alerted_agent_turns_and_shoots() -> void:
	var brain := _brain(12)
	_run(brain, 0.4, FAR_ABOVE)
	brain.face(1.0)
	brain.alert = true
	assert_gt(_frames_to_shot(brain, BEHIND, 1.0), -1, "под тревогой — развернулся и выстрелил")
	assert_eq(brain.facing, -1.0)


func test_agent_does_not_shoot_another_floor() -> void:
	var brain := _brain(12)
	_run(brain, 0.4, FAR_ABOVE)
	assert_eq(_frames_to_shot(brain, FAR_ABOVE, 1.0), -1)


## Дальности в ROM нет — есть «в кадре»: вне кадра агент не стреляет.
func test_agent_does_not_shoot_out_of_frame() -> void:
	var brain := _brain(12)
	_run(brain, 0.4, FAR_ABOVE)
	for _frame: int in 60:
		brain.update(STEP, IN_FRONT, true, -1.0, false)
		assert_false(brain.fired())


func test_agent_does_not_shoot_the_unseen() -> void:
	var brain := _brain(12)
	_run(brain, 0.4, FAR_ABOVE)
	for _frame: int in 60:
		brain.update(STEP, IN_FRONT, false)
		assert_false(brain.fired(), "невидимого не обстреливают")


func test_dead_agent_stays_dead() -> void:
	var brain := _brain()
	brain.kill()
	assert_eq(brain.update(STEP, IN_FRONT, true), EnemyBrain.State.DEAD)
	assert_false(brain.fired())


func test_turning_around_flips_the_facing() -> void:
	var brain := _brain()
	assert_eq(brain.facing, 1.0)
	brain.turn_around()
	assert_eq(brain.facing, -1.0)
	brain.turn_around()
	assert_eq(brain.facing, 1.0)


## Луч прицела виден при любой злости: у ROM на десяти и выше замаха нет, а
## втрое быстрая пуля без него неотвратима (ADR-0037, решение 5).
func test_the_tell_never_drops_below_the_minimum() -> void:
	for level: int in range(0, 20):
		assert_gte(EnemyBrain.tell_time(level), EnemyBrain.MIN_TELL, "злость %d" % level)
		assert_gte(EnemyBrain.tell_time(level), Arcade.wind_up(level), "не короче ROM")
		assert_gt(
			Arcade.action_time(level), EnemyBrain.tell_time(level), "пуля уходит внутри действия"
		)


## Неуязвимого не обстреливают: Otto выходит из двери, у которой его ждали,
## и пуля, пущенная в этот миг, прошла бы сквозь него. Агент целится — луч
## горит, — но пуля ждёт, сколько бы неуязвимость ни длилась.
func test_agent_holds_the_shot_while_otto_cannot_be_hit() -> void:
	var brain := _brain(0)
	_run(brain, 0.4, FAR_ABOVE)
	for _frame: int in 300:
		brain.update(STEP, IN_FRONT, true, -1.0, true, true, false, false)
		assert_false(brain.fired(), "в неуязвимого не стреляют")
	assert_true(brain.is_winding_up(), "но целятся: луч прицела горит")
	assert_eq(brain.state, EnemyBrain.State.SHOOT)
	assert_almost_eq(brain.wind_up_left(), EnemyBrain.MIN_TELL, STEP, "замах стоит на минимуме")


## Стал уязвим — пуля уходит через [constant EnemyBrain.MIN_TELL]: четверть
## секунды на реакцию, как у самого злого агента, и ни кадром позже.
func test_agent_fires_once_otto_can_be_hit_again() -> void:
	var brain := _brain(0)
	_run(brain, 0.4, FAR_ABOVE)
	for _frame: int in 120:
		brain.update(STEP, IN_FRONT, true, -1.0, true, true, false, false)
	var frames := -1
	for frame: int in 60:
		brain.update(STEP, IN_FRONT, true)
		if brain.fired():
			frames = frame
			break
	assert_gt(frames, -1, "стал уязвим — выстрел")
	assert_almost_eq(
		float(frames + 1) * STEP, EnemyBrain.MIN_TELL, STEP * 1.5, "через замах-минимум"
	)


## Короткая неуязвимость посреди длинного замаха его не удлиняет сверх нужного:
## пока замах больше минимума, он идёт как шёл.
func test_a_long_tell_runs_down_while_otto_cannot_be_hit() -> void:
	var brain := _brain(0)
	_run(brain, 0.4, FAR_ABOVE)
	brain.update(STEP, IN_FRONT, true, -1.0, true, true, false, false)
	var start := brain.wind_up_left()
	assert_gt(start, EnemyBrain.MIN_TELL + STEP * 3.0, "у спокойного замах длиннее минимума")
	brain.update(STEP, IN_FRONT, true, -1.0, true, true, false, false)
	assert_almost_eq(brain.wind_up_left(), start - STEP, 0.0001, "замах идёт")
