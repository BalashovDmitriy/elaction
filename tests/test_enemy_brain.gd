extends GutTest

## Tests of agent decisions by the ROM rules (ADR-0027).
##
## The enemy brain knows nothing about nodes or physics: it takes a vector to Otto
## and returns a decision. The numbers come from [Arcade]: here we check that the brain
## uses them, and the numbers themselves are checked by [code]test_arcade.gd[/code].

const STEP: float = 1.0 / 60.0
## Vectors to the target are in meters, like everything in the rules since M15.
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


## How many frames until the first shot, -1 means no shot within [param limit] s.
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


## A calm agent aims for 10 ticks (@1BDF): the shot does not go out in the same frame.
func test_a_calm_agent_takes_aim() -> void:
	var brain := _brain(0)
	_run(brain, 0.4, FAR_ABOVE)
	var frames := _frames_to_shot(brain, IN_FRONT)
	assert_gt(frames, -1, "агент выстрелил")
	assert_gte(float(frames) * STEP, Arcade.wind_up(0) - STEP, "не раньше замаха")


## The windup is visible: until the bullet has gone out, the agent winds up, and the
## level lights the aiming beam (ADR-0037, decision 5). Once the bullet is out, there is
## no windup.
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


## An angry agent has the shortest windup: in the ROM at anger 10 and above the bullet
## goes out at once, for us after [constant EnemyBrain.MIN_TELL], so the beam can be seen.
func test_a_mean_agent_fires_after_the_shortest_tell() -> void:
	var brain := _brain(12)
	_run(brain, 0.4, FAR_ABOVE)
	var frames := _frames_to_shot(brain, IN_FRONT)
	var tell := int(ceil(EnemyBrain.MIN_TELL / STEP))
	assert_gte(frames, tell - 1, "не раньше минимального замаха")
	assert_lte(frames, tell + 1, "и не позже")


## The pause after a shot is max(0, 80 − 8·anger) ticks (@0055).
func test_agent_holds_fire_between_shots() -> void:
	var brain := _brain(0)
	_run(brain, 0.4, FAR_ABOVE)
	assert_gt(_frames_to_shot(brain, IN_FRONT), -1)
	var again := _frames_to_shot(brain, IN_FRONT)
	assert_gte(float(again) * STEP, Arcade.cooldown(0) - Arcade.action_time(0), "пауза по ROM")


## An agent has one bullet: while the previous one flies, there is no new one (@1BAE).
func test_one_bullet_in_flight() -> void:
	var brain := _brain(12)
	_run(brain, 0.4, FAR_ABOVE)
	for _frame: int in 120:
		brain.update(STEP, IN_FRONT, true, -1.0, true, false)
		assert_false(brain.fired(), "прошлая пуля в полёте — не стреляет")


## Shoots when facing Otto; with his back to him, no, unless there is an alarm (@0568).
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


## The ROM has no range, only "in frame": outside the frame an agent does not shoot.
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


## The aiming beam is visible at any anger: the ROM has no windup at ten and above, and
## a bullet three times faster is unavoidable without it (ADR-0037, decision 5).
func test_the_tell_never_drops_below_the_minimum() -> void:
	for level: int in range(0, 20):
		assert_gte(EnemyBrain.tell_time(level), EnemyBrain.MIN_TELL, "злость %d" % level)
		assert_gte(EnemyBrain.tell_time(level), Arcade.wind_up(level), "не короче ROM")
		assert_gt(
			Arcade.action_time(level), EnemyBrain.tell_time(level), "пуля уходит внутри действия"
		)


## The invulnerable are not fired upon: Otto comes out of a door where he was waited
## for, and a bullet fired at that moment would pass through him. The agent aims, the
## beam is lit, but the bullet waits however long the invulnerability lasts.
func test_agent_holds_the_shot_while_otto_cannot_be_hit() -> void:
	var brain := _brain(0)
	_run(brain, 0.4, FAR_ABOVE)
	for _frame: int in 300:
		brain.update(STEP, IN_FRONT, true, -1.0, true, true, false, false)
		assert_false(brain.fired(), "в неуязвимого не стреляют")
	assert_true(brain.is_winding_up(), "но целятся: луч прицела горит")
	assert_eq(brain.state, EnemyBrain.State.SHOOT)
	assert_almost_eq(brain.wind_up_left(), EnemyBrain.MIN_TELL, STEP, "замах стоит на минимуме")


## Once he becomes vulnerable, the bullet goes out after [constant EnemyBrain.MIN_TELL]:
## a quarter second to react, as with the angriest agent, and not a frame later.
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


## A short invulnerability in the middle of a long windup does not extend it beyond what
## is needed: while the windup is above the minimum, it goes on as it was.
func test_a_long_tell_runs_down_while_otto_cannot_be_hit() -> void:
	var brain := _brain(0)
	_run(brain, 0.4, FAR_ABOVE)
	brain.update(STEP, IN_FRONT, true, -1.0, true, true, false, false)
	var start := brain.wind_up_left()
	assert_gt(start, EnemyBrain.MIN_TELL + STEP * 3.0, "у спокойного замах длиннее минимума")
	brain.update(STEP, IN_FRONT, true, -1.0, true, true, false, false)
	assert_almost_eq(brain.wind_up_left(), start - STEP, 0.0001, "замах идёт")
