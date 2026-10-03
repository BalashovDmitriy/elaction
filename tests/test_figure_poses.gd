extends GutTest

## Figure pose table. Without a scene: [FigurePoses] is data and arithmetic.


func test_every_pose_of_otto_has_a_record() -> void:
	for pose_name: String in ActorPose.OTTO_POSES:
		assert_true(FigurePoses.knows(pose_name), "pose %s has no entry" % pose_name)


func test_every_pose_of_the_agent_has_a_record() -> void:
	for pose_name: String in ActorPose.AGENT_POSES:
		assert_true(FigurePoses.knows(pose_name), "pose %s has no entry" % pose_name)


func test_every_clip_a_pose_asks_for_is_one_the_model_carries() -> void:
	# Clip names are written by `build_actors.py`; a pose with a clip not in the list
	# would silently fall back to the idle stance.
	var poses: PackedStringArray = ActorPose.OTTO_POSES + ActorPose.AGENT_POSES
	for pose_name: String in poses:
		var clip := FigurePoses.clip_of(pose_name)
		if clip != null:
			assert_has(FigurePoses.CLIP_NAMES, clip.name, "%s: clip %s" % [pose_name, clip.name])


## ADR-0032, decision 1: where the ROM dictates the height, the pose is in code.
func test_the_rom_stances_are_poses_in_code() -> void:
	for pose_name: String in [ActorPose.CROUCH, ActorPose.PRONE, "crushed", "choke_hold"]:
		assert_null(FigurePoses.clip_of(pose_name), "%s is a pose by code, not a clip" % pose_name)


func test_the_jump_takes_off_and_lands_with_clips() -> void:
	# The jump in three phases (ADR-0039): takeoff and landing are UAL clips; in flight
	# since M24d — the flight clip, the kick is gone (ADR-0040).
	var jump := FigurePoses.clip_of("jump")
	assert_eq(jump.name, FigurePoses.CLIP_JUMP_START, "push-off is a clip")
	assert_gt(
		jump.start, 0.0, "from take-off, without a wind-up crouch: the jump in the game is instant"
	)
	var land := FigurePoses.clip_of("land")
	assert_eq(land.name, FigurePoses.CLIP_JUMP_LAND, "landing is a clip")
	assert_gt(land.rate, 1.0, "faster than recorded: the crouch flashes by instead of holding")


func test_every_transition_is_short_and_ends() -> void:
	# Time-based transition (ADR-0039, decision 5): each pose has its own duration, and
	# none lasts longer than a third of a second — otherwise movement is sluggish again.
	for pose_name: String in ActorPose.OTTO_POSES + ActorPose.AGENT_POSES:
		var time := FigurePoses.blend_time(pose_name)
		assert_gt(time, 0.0, "%s: has a transition" % pose_name)
		assert_lte(time, 0.3, "%s: and a short one" % pose_name)


func test_walking_idle_shooting_and_dying_are_clips() -> void:
	assert_eq(FigurePoses.clip_of("walk_1").name, FigurePoses.CLIP_WALK)
	assert_eq(FigurePoses.clip_of("walk_1").mode, FigurePoses.Clip.WALK)
	assert_eq(FigurePoses.clip_of("idle").mode, FigurePoses.Clip.LOOP)
	assert_eq(FigurePoses.clip_of("shoot").mode, FigurePoses.Clip.ONCE)


func test_death_is_the_fall_and_then_the_body() -> void:
	# Two death poses (ADR-0011, point 12) — one clip: the fall and its end.
	assert_eq(FigurePoses.clip_of("dead_0").name, FigurePoses.CLIP_DEATH)
	assert_eq(FigurePoses.clip_of("dead_1").name, FigurePoses.CLIP_DEATH)
	assert_eq(FigurePoses.clip_of("dead_0").mode, FigurePoses.Clip.ONCE)
	assert_eq(FigurePoses.clip_of("dead_1").mode, FigurePoses.Clip.END)


func test_an_unknown_pose_falls_back_to_the_stand() -> void:
	# An actor without a pose in the frame is worse than an actor in the wrong one.
	var fallback := FigurePoses.of("moonwalk")
	assert_eq(fallback.legs, Vector2.ZERO)
	assert_eq(fallback.knees, Vector2.ZERO)
	assert_almost_eq(fallback.tilt, 0.0, 0.001)


func test_a_copy_is_its_own() -> void:
	# The table is shared: editing a copy must not touch the record.
	var crouch := FigurePoses.of(ActorPose.CROUCH)
	crouch.legs = Vector2(1.0, 1.0)
	assert_ne(FigurePoses.of(ActorPose.CROUCH).legs, Vector2(1.0, 1.0))


func test_the_crouch_squats_on_bent_knees() -> void:
	# M18c debt: the crouch is squatting, not bending the torso.
	var crouch := FigurePoses.of(ActorPose.CROUCH)
	assert_gt(crouch.legs.x, 60.0, "hips forward")
	assert_gt(crouch.knees.x, 90.0, "knees bent")
	assert_lt(crouch.lean, 60.0, "torso above the knees, not on them")


func test_the_crushed_are_flat_and_the_prone_face_down() -> void:
	assert_lt(FigurePoses.of("crushed").squash, 0.5, "crushed one is flattened")
	assert_gt(FigurePoses.of(ActorPose.PRONE).tilt, 45.0, "prone — face forward, not on the back")


func test_lift_is_an_extra_above_the_ground_not_a_fix_for_sinking() -> void:
	# The gap for a lying figure comes from the rig's grounding, not the table.
	assert_almost_eq(FigurePoses.of(ActorPose.PRONE).lift, 0.0, 0.001)
	assert_almost_eq(FigurePoses.of(ActorPose.CROUCH).lift, 0.0, 0.001)
