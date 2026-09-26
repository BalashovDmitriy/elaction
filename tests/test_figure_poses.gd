extends GutTest

## Таблица поз фигуры. Без сцены: [FigurePoses] — данные и арифметика.


func test_every_pose_of_otto_has_a_record() -> void:
	for pose_name: String in ActorPose.OTTO_POSES:
		assert_true(FigurePoses.knows(pose_name), "у позы %s нет записи" % pose_name)


func test_every_pose_of_the_agent_has_a_record() -> void:
	for pose_name: String in ActorPose.AGENT_POSES:
		assert_true(FigurePoses.knows(pose_name), "у позы %s нет записи" % pose_name)


func test_every_clip_a_pose_asks_for_is_one_the_model_carries() -> void:
	# Имена клипов пишет `build_actors.py`; поза с клипом, которого нет в
	# списке, встала бы в стойку молча.
	var poses: PackedStringArray = ActorPose.OTTO_POSES + ActorPose.AGENT_POSES
	for pose_name: String in poses:
		var clip := FigurePoses.clip_of(pose_name)
		if clip != null:
			assert_has(FigurePoses.CLIP_NAMES, clip.name, "%s: клип %s" % [pose_name, clip.name])


## ADR-0032, решение 1: где ROM диктует высоту, там поза кодом.
func test_the_rom_stances_are_poses_in_code() -> void:
	for pose_name: String in [ActorPose.CROUCH, ActorPose.PRONE, "crushed", "choke_hold"]:
		assert_null(FigurePoses.clip_of(pose_name), "%s — поза кодом, не клип" % pose_name)


func test_the_jump_takes_off_and_lands_with_clips() -> void:
	# Прыжок тремя фазами (ADR-0039): толчок и приземление — клипы UAL; в полёте
	# с M24d — клип полёта, удара ногой больше нет (ADR-0040).
	var jump := FigurePoses.clip_of("jump")
	assert_eq(jump.name, FigurePoses.CLIP_JUMP_START, "толчок — клип")
	assert_gt(jump.start, 0.0, "с отрыва, без приседа-замаха: прыжок в игре мгновенный")
	var land := FigurePoses.clip_of("land")
	assert_eq(land.name, FigurePoses.CLIP_JUMP_LAND, "приземление — клип")
	assert_gt(land.rate, 1.0, "быстрее записанного: присед мелькает, а не держится")


func test_every_transition_is_short_and_ends() -> void:
	# Переход по времени (ADR-0039, решение 5): у каждой позы свой срок, и ни
	# один не тянется дольше трети секунды — иначе движение снова вязкое.
	for pose_name: String in ActorPose.OTTO_POSES + ActorPose.AGENT_POSES:
		var time := FigurePoses.blend_time(pose_name)
		assert_gt(time, 0.0, "%s: переход есть" % pose_name)
		assert_lte(time, 0.3, "%s: и короткий" % pose_name)


func test_walking_idle_shooting_and_dying_are_clips() -> void:
	assert_eq(FigurePoses.clip_of("walk_1").name, FigurePoses.CLIP_WALK)
	assert_eq(FigurePoses.clip_of("walk_1").mode, FigurePoses.Clip.WALK)
	assert_eq(FigurePoses.clip_of("idle").mode, FigurePoses.Clip.LOOP)
	assert_eq(FigurePoses.clip_of("shoot").mode, FigurePoses.Clip.ONCE)


func test_death_is_the_fall_and_then_the_body() -> void:
	# Две позы смерти (ADR-0011, пункт 12) — один клип: падение и его конец.
	assert_eq(FigurePoses.clip_of("dead_0").name, FigurePoses.CLIP_DEATH)
	assert_eq(FigurePoses.clip_of("dead_1").name, FigurePoses.CLIP_DEATH)
	assert_eq(FigurePoses.clip_of("dead_0").mode, FigurePoses.Clip.ONCE)
	assert_eq(FigurePoses.clip_of("dead_1").mode, FigurePoses.Clip.END)


func test_an_unknown_pose_falls_back_to_the_stand() -> void:
	# Актёр без позы в кадре хуже, чем актёр в неверной.
	var fallback := FigurePoses.of("moonwalk")
	assert_eq(fallback.legs, Vector2.ZERO)
	assert_eq(fallback.knees, Vector2.ZERO)
	assert_almost_eq(fallback.tilt, 0.0, 0.001)


func test_a_copy_is_its_own() -> void:
	# Таблица общая: правка копии не должна трогать запись.
	var crouch := FigurePoses.of(ActorPose.CROUCH)
	crouch.legs = Vector2(1.0, 1.0)
	assert_ne(FigurePoses.of(ActorPose.CROUCH).legs, Vector2(1.0, 1.0))


func test_the_crouch_squats_on_bent_knees() -> void:
	# Долг M18c: присед — на корточках, а не наклон корпуса.
	var crouch := FigurePoses.of(ActorPose.CROUCH)
	assert_gt(crouch.legs.x, 60.0, "бёдра вперёд")
	assert_gt(crouch.knees.x, 90.0, "колени сложены")
	assert_lt(crouch.lean, 60.0, "корпус над коленями, а не на них")


func test_the_crushed_are_flat_and_the_prone_face_down() -> void:
	assert_lt(FigurePoses.of("crushed").squash, 0.5, "раздавленный сплющен")
	assert_gt(FigurePoses.of(ActorPose.PRONE).tilt, 45.0, "залёгший — лицом вперёд, не на спине")


func test_lift_is_an_extra_above_the_ground_not_a_fix_for_sinking() -> void:
	# Зазор лежащему даёт риг заземлением, а не таблица.
	assert_almost_eq(FigurePoses.of(ActorPose.PRONE).lift, 0.0, 0.001)
	assert_almost_eq(FigurePoses.of(ActorPose.CROUCH).lift, 0.0, 0.001)
