extends GutTest

## Tests of actor pose selection.
##
## The rule is checked, not a single pose: **every** state of the state
## machine must map to a drawn pose. Otherwise a new state will
## one day show the pink placeholder square — and show it to the player, not to a test.


func _every_state() -> Array[OttoStateMachine.State]:
	var states: Array[OttoStateMachine.State] = []
	for value: int in OttoStateMachine.State.values():
		states.append(value as OttoStateMachine.State)
	return states


func test_every_state_of_otto_has_a_pose() -> void:
	for state: OttoStateMachine.State in _every_state():
		var pose := ActorPose.of_otto(state, false, false, false, 0.0)
		assert_true(
			ActorPose.OTTO_POSES.has(pose),
			"состояние %s показывается позой %s" % [OttoStateMachine.state_name(state), pose]
		)


func test_every_pose_of_otto_is_reachable() -> void:
	# The reverse check: what is drawn must have someone to show it. Otherwise assets
	# pile up in the repository as dead weight, and the milestone counts them as work.
	var shown: Array[String] = []
	for state: OttoStateMachine.State in _every_state():
		for crushed: bool in [false, true]:
			for falling: bool in [false, true]:
				for shooting: bool in [false, true]:
					for phase: int in ActorPose.WALK_FRAMES:
						for landing: bool in [false, true]:
							var pose := ActorPose.of_otto(
								state, crushed, falling, shooting, float(phase), landing
							)
							if not shown.has(pose):
								shown.append(pose)

	# The rope is chosen not by the state but by who carries ([member Otto.ride_look]).
	shown.append(ActorPose.ROPE)
	# And the intro poses — the helicopter sets them ([member Otto.ride_pose]).
	shown.append_array(ActorPose.ARRIVAL_POSES)
	for pose: String in ActorPose.OTTO_POSES:
		assert_true(shown.has(pose), "поза %s кому-то нужна" % pose)
	# And the other way round — as for the agent: only what is drawn can be shown. Without this
	# a typo in [ActorPose] would reach the player as the pink placeholder square.
	for pose: String in shown:
		assert_true(ActorPose.OTTO_POSES.has(pose), "поза %s нарисована" % pose)


func test_every_pose_of_the_agent_is_reachable() -> void:
	var shown: Array[String] = []
	for dead: bool in [false, true]:
		for walking: bool in [false, true]:
			for crushed: bool in [false, true]:
				for falling: bool in [false, true]:
					for shooting: bool in [false, true]:
						for phase: int in ActorPose.WALK_FRAMES:
							# Stances are walked on par with the rest: since M11 the agent
							# dodges, and kneeling and lying down have their own poses.
							for stance: EnemyBrain.Stance in _stances():
								var pose := ActorPose.of_agent(
									dead, walking, crushed, falling, shooting, float(phase), stance
								)
								if not shown.has(pose):
									shown.append(pose)

	for pose: String in ActorPose.AGENT_POSES:
		assert_true(shown.has(pose), "поза %s кому-то нужна" % pose)
	for pose: String in shown:
		assert_true(ActorPose.AGENT_POSES.has(pose), "поза %s нарисована" % pose)


func test_death_tells_how_it_happened() -> void:
	# A crushed actor is shown with his own picture — this is the very finding of the
	# pre-milestone check against the original (ADR-0011, item 12).
	var dead := OttoStateMachine.State.DEAD
	assert_eq(ActorPose.of_otto(dead, false, true, false, 0.0), "dead_0", "падает")
	assert_eq(ActorPose.of_otto(dead, false, false, false, 0.0), "dead_1", "лежит")
	assert_eq(ActorPose.of_otto(dead, true, true, false, 0.0), "crushed", "раздавлен")


func test_the_dead_do_not_shoot() -> void:
	var pose := ActorPose.of_otto(OttoStateMachine.State.DEAD, false, false, true, 0.0)
	assert_eq(pose, "dead_1", "смерть важнее выстрела")


func test_walking_cycles_three_frames() -> void:
	# The phase grows fractionally, the frame changes on integers: the cycle must close.
	assert_eq(ActorPose.walk_frame(0.0), "walk_0")
	assert_eq(ActorPose.walk_frame(0.9), "walk_0", "дробная часть кадр не меняет")
	assert_eq(ActorPose.walk_frame(1.0), "walk_1")
	assert_eq(ActorPose.walk_frame(2.9), "walk_2")
	assert_eq(ActorPose.walk_frame(3.0), "walk_0", "цикл замыкается")


func test_the_phase_never_skips_a_frame_of_the_cycle() -> void:
	# Only WALK_FRAMES knows the cycle length, and phase advancement must count it
	# the same way as frame selection. If they diverge, the last walk frame will never
	# show, and it cannot be noticed by eye: the step simply becomes shorter.
	var phase := 0.0
	var seen: Array[String] = []
	for _step: int in 120:
		phase = ActorPose.advance(phase, 1.0 / 60.0)
		assert_between(phase, 0.0, float(ActorPose.WALK_FRAMES), "фаза не уходит из цикла")
		var frame := ActorPose.walk_frame(phase)
		if not seen.has(frame):
			seen.append(frame)
	assert_eq(seen.size(), ActorPose.WALK_FRAMES, "за две секунды показаны все кадры")


func test_a_broken_phase_does_not_break_the_frame() -> void:
	# The phase comes from a time accumulator, and it has no reason to be negative —
	# but the frame must still remain a frame, not "walk_-1".
	assert_eq(ActorPose.walk_frame(-1.0), "walk_0")


## All agent stances. Listed by hand: an enum in GDScript cannot be iterated by
## values, and a list of three lines is more honest than walking Stance.keys().
func _stances() -> Array[EnemyBrain.Stance]:
	return [EnemyBrain.Stance.STAND, EnemyBrain.Stance.KNEEL, EnemyBrain.Stance.PRONE]


func test_every_way_of_dying_counts_as_down() -> void:
	# A miss here will leave a corpse standing — for whoever asks some day.
	for crushed: bool in [true, false]:
		for falling: bool in [true, false]:
			var pose := ActorPose.of_otto(OttoStateMachine.State.DEAD, crushed, falling, false, 0.0)
			assert_true(ActorPose.is_down(pose), "%s — это лежащий" % pose)


func test_an_agent_dodging_prone_counts_as_down() -> void:
	var pose := ActorPose.of_agent(false, false, false, false, false, 0.0, EnemyBrain.Stance.PRONE)
	assert_true(ActorPose.is_down(pose))


func test_the_living_and_upright_are_not_down() -> void:
	for pose: String in [
		"idle", "walk_0", "walk_1", "walk_2", "jump", "fall", "shoot", ActorPose.CROUCH
	]:
		assert_false(ActorPose.is_down(pose), "%s — это не лежащий" % pose)


func test_the_knee_and_the_crouch_are_one_pose() -> void:
	# A kneeling agent and a crouching Otto are shown the same way — as it was in 2D.
	var kneeling := ActorPose.of_agent(
		false, false, false, false, false, 0.0, EnemyBrain.Stance.KNEEL
	)
	var crouching := ActorPose.of_otto(OttoStateMachine.State.CROUCH, false, false, false, 0.0)
	assert_eq(kneeling, crouching)
	assert_eq(kneeling, ActorPose.CROUCH)


## Landing is shown only while Otto stands (ADR-0039): stepped — he walks,
## crouched — he sits, fired — he shoots.
func test_landing_shows_only_while_standing() -> void:
	var idle := OttoStateMachine.State.IDLE
	assert_eq(
		ActorPose.of_otto(idle, false, false, false, 0.0, true), "land", "стоит — приземляется"
	)
	assert_eq(
		ActorPose.of_otto(idle, false, false, false, 0.0, false), "idle", "без приземления — стоит"
	)
	var walk := OttoStateMachine.State.WALK
	assert_eq(ActorPose.of_otto(walk, false, false, false, 0.0, true), "walk_0", "шагнул — идёт")
	assert_eq(ActorPose.of_otto(idle, false, false, true, 0.0, true), "shoot", "выстрел важнее")
