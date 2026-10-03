extends GutTest

## Agent stances by the ROM rules: shooting pose, dodge, wandering (ADR-0027).
##
## Separate from [code]test_enemy_brain.gd[/code]: there — when the agent shoots, here — in which
## stance he does it and how he leaves the bullet's line.

const STEP: float = 1.0 / 60.0
const FAR_ABOVE := Vector2(0.4, -1.2)
const IN_FRONT := Vector2(2.0, 0.0)


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


## Shooting poses by anger: a calm one shoots standing, an angry one more often lying.
func test_a_mean_agent_mostly_fires_lying() -> void:
	var prone := 0
	for attempt: int in 40:
		var brain := _brain(14)
		brain.rng.seed = attempt
		_run(brain, 0.4, FAR_ABOVE)
		brain.update(STEP, IN_FRONT, true)
		if brain.stance == EnemyBrain.Stance.PRONE:
			prone += 1
	assert_gt(prone, 20, "anger 14 — prone in three cases out of four")


func test_a_calm_agent_never_fires_lying() -> void:
	for attempt: int in 40:
		var brain := _brain(0)
		brain.rng.seed = attempt
		_run(brain, 0.4, FAR_ABOVE)
		brain.update(STEP, IN_FRONT, true)
		assert_ne(brain.stance, EnemyBrain.Stance.PRONE)


## The agent takes a crouching Otto from a crouch (@1CD8).
func test_a_crouching_target_is_shot_from_a_crouch() -> void:
	var brain := _brain(4)
	brain.rng.seed = 1
	_run(brain, 0.4, FAR_ABOVE)
	brain.update(STEP, IN_FRONT, true, -1.0, true, true, true)
	assert_ne(brain.stance, EnemyBrain.Stance.STAND, "after a crouched one — not standing")


## Dodge by the ROM: from a high bullet onto a knee, from a low one — lying (@05F5).
func test_dodge_picks_the_stance_by_bullet_height() -> void:
	var brain := _brain()
	assert_eq(brain.stance_against(brain.kneel_height + 0.04), EnemyBrain.Stance.KNEEL)
	assert_eq(brain.stance_against(brain.kneel_height - 0.1), EnemyBrain.Stance.PRONE)
	assert_eq(brain.stance_against(-1.0), EnemyBrain.Stance.STAND)


## A calm one does not dodge at all, the angriest — almost at once.
func test_dodge_depends_on_anger() -> void:
	var calm := _brain(0)
	_run(calm, 0.4, FAR_ABOVE)
	for _frame: int in 60:
		calm.update(STEP, FAR_ABOVE, true, 1.1)
	assert_true(calm.is_standing(), "anger 0 — no chance")

	var mean := _brain(15)
	_run(mean, 0.4, FAR_ABOVE)
	mean.update(STEP, FAR_ABOVE, true, 1.1)
	assert_eq(mean.stance, EnemyBrain.Stance.KNEEL, "anger 15 — to a knee from the first tick")


## A dodge is an action: the agent stands up when it has finished.
func test_agent_stands_up_after_the_dodge() -> void:
	var brain := _brain(15)
	_run(brain, 0.4, FAR_ABOVE)
	brain.update(STEP, FAR_ABOVE, true, 1.1)
	assert_false(brain.is_standing())
	_run(brain, Arcade.action_time(15) + 0.1, FAR_ABOVE)
	assert_true(brain.is_standing())


## Height follows the stance: the level fits the collision shape by it.
func test_height_follows_the_stance() -> void:
	var brain := _brain()
	brain.stance = EnemyBrain.Stance.STAND
	assert_eq(brain.height(), brain.stand_height)
	brain.stance = EnemyBrain.Stance.KNEEL
	assert_eq(brain.height(), brain.kneel_height)
	brain.stance = EnemyBrain.Stance.PRONE
	assert_eq(brain.height(), brain.prone_height)
	assert_false(brain.is_standing(), "a prone agent does not walk")


func test_the_dead_do_not_dodge() -> void:
	var brain := _brain()
	brain.stance = EnemyBrain.Stance.KNEEL
	brain.kill()
	assert_eq(brain.stance, EnemyBrain.Stance.STAND)


## The agent does not chase Otto: he wanders — walks and stands for a pause (@5D13).
func test_agent_strolls_and_pauses() -> void:
	var brain := _brain()
	var walked := false
	var stood := false
	for _frame: int in int(6.0 / STEP):
		brain.update(STEP, FAR_ABOVE, false)
		if brain.wants_to_walk():
			walked = true
		else:
			stood = true
	assert_true(walked, "walks")
	assert_true(stood, "and stands between the moves")
