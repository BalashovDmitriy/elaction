extends GutTest

## Таблица поз фигуры. Без сцены: [FigurePoses] — данные и арифметика.


func test_every_pose_of_otto_has_a_record() -> void:
	for pose_name: String in ActorPose.OTTO_POSES:
		assert_true(FigurePoses.knows(pose_name), "у позы %s нет записи" % pose_name)


func test_every_pose_of_the_agent_has_a_record() -> void:
	for pose_name: String in ActorPose.AGENT_POSES:
		assert_true(FigurePoses.knows(pose_name), "у позы %s нет записи" % pose_name)


func test_an_unknown_pose_falls_back_to_idle() -> void:
	# Актёр без позы в кадре хуже, чем актёр в неверной.
	assert_true(FigurePoses.of("moonwalk").is_close_to(FigurePoses.of("idle")))


func test_walking_swings_the_legs_in_antiphase() -> void:
	var stride := FigurePoses.walking(0.75)
	assert_gt(stride.legs.x, 0.0, "левая нога впереди")
	assert_lt(stride.legs.y, 0.0, "правая позади")
	assert_almost_eq(stride.legs.x, -stride.legs.y, 0.001, "и ровно в противофазе")
	assert_lt(stride.arms.x, 0.0, "левая рука навстречу левой ноге")
	assert_gt(stride.arms.y, 0.0, "правая — навстречу правой")


func test_walking_is_a_cycle() -> void:
	var start := FigurePoses.walking(0.0)
	var round_trip := FigurePoses.walking(float(ActorPose.WALK_FRAMES))
	assert_true(start.is_close_to(round_trip), "фаза в полный цикл возвращает ту же позу")


func test_the_body_rises_when_the_legs_meet() -> void:
	var together := FigurePoses.walking(0.0)
	var apart := FigurePoses.walking(0.75)
	assert_gt(together.lift, apart.lift, "выше всего тело, когда ноги сошлись")


func test_walk_frames_are_points_of_the_cycle() -> void:
	# Имена кадров остались от спрайтов: ригу они приходят строкой.
	assert_true(FigurePoses.of("walk_0").is_close_to(FigurePoses.walking(0.0)))
	assert_true(FigurePoses.of("walk_2").is_close_to(FigurePoses.walking(2.0)))


func test_blend_ends_where_it_started_and_where_it_goes() -> void:
	var idle := FigurePoses.of("idle")
	var kick := FigurePoses.of("kick")
	assert_true(idle.blend(kick, 0.0).is_close_to(idle))
	assert_true(idle.blend(kick, 1.0).is_close_to(kick))
	var half := idle.blend(kick, 0.5)
	assert_almost_eq(half.legs.x, (idle.legs.x + kick.legs.x) * 0.5, 0.001)
	assert_almost_eq(half.lean, (idle.lean + kick.lean) * 0.5, 0.001)


func test_blend_weight_is_clamped() -> void:
	var idle := FigurePoses.of("idle")
	var kick := FigurePoses.of("kick")
	assert_true(idle.blend(kick, 2.0).is_close_to(kick), "перелёт за цель не выносит за неё")
	assert_true(idle.blend(kick, -1.0).is_close_to(idle))


func test_lift_is_an_extra_above_the_ground_not_a_fix_for_sinking() -> void:
	# Зазор лежащему даёт риг заземлением, а не таблица: у таблицы для поз без
	# ходьбы подъёма нет.
	assert_almost_eq(FigurePoses.of("dead_1").lift, 0.0, 0.001)
	assert_almost_eq(FigurePoses.of("prone").lift, 0.0, 0.001)


func test_the_dead_lie_and_the_crushed_are_flat() -> void:
	assert_almost_eq(absf(FigurePoses.of("dead_1").tilt), 90.0, 0.001, "труп лежит")
	assert_lt(FigurePoses.of("crushed").squash, 0.5, "раздавленный сплющен")
	assert_gt(FigurePoses.of("prone").tilt, 45.0, "залёгший агент — лицом вперёд, не на спине")


func test_the_crouch_folds_the_body() -> void:
	var crouch := FigurePoses.of("crouch")
	assert_gt(crouch.drop, 0.0, "бёдра проседают")
	assert_gt(crouch.legs.x, 30.0, "ноги уходят вперёд")
	assert_gt(crouch.lean, 30.0, "корпус складывается")
