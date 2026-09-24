extends GutTest

## Риг актёра на живом скелете из `.glb`.
##
## Проверяется то, ради чего веха: присед укладывает фигуру под пулю агента, а
## переход между позами — движение, а не подмена картинки (ADR-0022).

const OTTO_MODEL := preload("res://assets/models/otto.glb")
const AGENT_MODEL := preload("res://assets/models/agent.glb")
const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const BULLET_SCENE := preload("res://src/systems/combat/bullet.tscn")

## Кадр в 60 Гц: за него сглаживание обязано сдвинуть кости, но не долететь.
const FRAME: float = 1.0 / 60.0


func _rig(model: PackedScene) -> FigureRig:
	var rig := FigureRig.new()
	rig.model = model
	add_child_autofree(rig)
	return rig


## Otto из сцены: высоты его выстрелов и коллизий берутся у него, а не
## переписываются в тест числами.
func _otto() -> Otto:
	var otto := OTTO_SCENE.instantiate() as Otto
	autofree(otto)
	return otto


## Пуля — коробка, и мимо фигуры она проходит краем, а не осью.
func _bullet_half_height() -> float:
	var bullet := BULLET_SCENE.instantiate()
	var shape := (bullet.get_node("Shape") as CollisionShape3D).shape as BoxShape3D
	bullet.free()
	return shape.size.y * 0.5


func test_both_models_carry_every_bone() -> void:
	for model: PackedScene in [OTTO_MODEL, AGENT_MODEL]:
		var scene := model.instantiate()
		add_child_autofree(scene)
		var found := scene.find_children("*", "Skeleton3D", true, false)
		assert_eq(found.size(), 1, "%s: один скелет" % model.resource_path)
		if found.is_empty():
			continue
		var skeleton := found[0] as Skeleton3D
		for bone_name: String in FigureRig.BONES:
			assert_gte(
				skeleton.find_bone(bone_name), 0, "%s: кость %s" % [model.resource_path, bone_name]
			)


func test_the_rig_stands_as_tall_as_the_collision_says() -> void:
	# Рост фигуры — коллизия Otto плюс причёска сверху: ниже коллизии рост
	# быть не может, иначе пуля агента шла бы над головой.
	var rig := _rig(OTTO_MODEL)
	var otto := OTTO_SCENE.instantiate() as Otto
	var standing := (
		((otto.get_node("StandingShape") as CollisionShape3D).shape as BoxShape3D).size.y
	)
	otto.free()
	assert_gte(rig.height(), standing, "фигура не ниже коллизии стоя")
	assert_lt(rig.height(), standing * 1.2, "и не выше её больше чем на причёску")


## DoD вехи: Otto в приседе по-прежнему ниже пули агента.
func test_a_crouching_figure_ducks_under_the_agent_bullet() -> void:
	var rig := _rig(OTTO_MODEL)
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	var bullet_height := enemy.shot_height
	enemy.free()
	var otto := OTTO_SCENE.instantiate() as Otto
	var crouching := (
		((otto.get_node("CrouchingShape") as CollisionShape3D).shape as BoxShape3D).size.y
	)
	otto.free()

	rig.show_pose(ActorPose.CROUCH)
	rig.snap()
	var top := rig.skinned_aabb().end.y
	assert_lt(top, bullet_height, "макушка присевшего ниже пули агента (%.2f)" % bullet_height)
	assert_lt(
		top,
		crouching * 1.1,
		"и укладывается в коллизию приседа %.2f с запасом на голову" % crouching
	)


## Зеркально к Otto (ADR-0016): на колене агент уходит под пулю стоящего
## Otto, залёгши — под пулю присевшего. В M15 это держала коробка, резавшаяся по
## ростам из правил здания; у фигуры рост свой, и сверять его надо с пулей.
func test_a_kneeling_agent_ducks_under_the_standing_shot() -> void:
	var rig := _rig(AGENT_MODEL)
	var shot := _otto().shot_height_standing
	rig.show_pose(ActorPose.CROUCH)
	rig.snap()
	var top := rig.skinned_aabb().end.y
	assert_lt(
		top, shot - _bullet_half_height(), "шляпа на колене ниже нижнего края пули (%.2f)" % shot
	)


func test_a_prone_agent_lies_under_the_crouching_shot() -> void:
	var rig := _rig(AGENT_MODEL)
	var shot := _otto().shot_height_crouching
	rig.show_pose(ActorPose.PRONE)
	rig.snap()
	var lying := rig.skinned_aabb()
	# Лицом вниз поля шляпы встают вертикально, и ниже их диаметра фигура не
	# ляжет: макушка залёгшего — это кромка полей, 0.66 м против пули на 0.66
	# (M18c: агент вырос до роста Otto, и поля вместе с ним).
	# Поэтому мерка — верхний край пули, не нижний: тело под ней целиком, задеть
	# она может только кромку. Опустить ниже можно только другой моделью шляпы.
	assert_lt(
		lying.end.y, shot + _bullet_half_height(), "залёгший ниже верхнего края пули (%.2f)" % shot
	)
	assert_gt(lying.size.z, rig.height() * 0.9, "и вытянут вдоль пола: руки со стволом вперёд")
	rig.show_pose(ActorPose.CROUCH)
	rig.snap()
	assert_lt(lying.end.y, rig.skinned_aabb().end.y, "и ниже, чем на колене")


func test_the_kick_puts_the_foot_forward() -> void:
	# Знак углов: «вперёд» обязано быть вперёд, куда бы ни смотрела локальная
	# ось кости. В покое фигура смотрит в +Z, и мерка — относительно покоя.
	var rig := _rig(OTTO_MODEL)
	rig.snap()
	var standing := rig.skinned_aabb()
	rig.show_pose("kick")
	rig.snap()
	var kicking := rig.skinned_aabb()
	assert_gt(kicking.end.z, standing.end.z + 0.1, "нога в ударе вынесена вперёд, за габарит тела")


func test_a_lying_figure_is_long_and_low() -> void:
	var rig := _rig(OTTO_MODEL)
	rig.show_pose("dead_1")
	rig.snap()
	var box := rig.skinned_aabb()
	assert_lt(box.end.y, rig.height() * 0.5, "лежащий низкий")
	# Клип смерти пака роняет тело не строго назад, а с поворотом: длина —
	# по диагонали пола, а не только вдоль взгляда.
	assert_gt(Vector2(box.size.x, box.size.z).length(), rig.height() * 0.8, "и длинный по полу")
	assert_gte(box.position.y, -0.01, "и не утоплен в пол")


## Заземление общее: у каждой позы своя глубина, и ни одна не уходит под пол.
func test_no_pose_sinks_below_the_floor() -> void:
	var rig := _rig(OTTO_MODEL)
	for pose_name: String in ActorPose.OTTO_POSES:
		rig.show_pose(pose_name)
		rig.snap()
		var floor_level := rig.skinned_aabb().position.y
		assert_gte(floor_level, -0.01, "%s утоплена в пол на %.3f" % [pose_name, -floor_level])
		assert_lt(floor_level, 0.06, "%s висит над полом на %.3f" % [pose_name, floor_level])


func test_a_pose_change_is_a_motion_not_a_swap() -> void:
	# «На стоп-кадре видно, что это движение, а не подмена картинки»: за один
	# кадр кости сдвигаются к цели, но не долетают.
	var rig := _rig(OTTO_MODEL)
	rig.show_pose("idle")
	rig.snap()
	var start := rig.bone_rotation(FigureRig.LEG_L)
	rig.show_pose("kick")
	var target := rig.target_rotation(FigureRig.LEG_L)
	var whole := start.angle_to(target)
	assert_gt(whole, deg_to_rad(40.0), "удар уводит бедро далеко от стойки")
	# Шаг сглаживания задаётся здесь, а не ждётся кадром: в headless-прогоне
	# кадр длится «сколько получится», и на нём риг успел бы долететь.
	rig.advance(FRAME)
	var moved := start.angle_to(rig.bone_rotation(FigureRig.LEG_L))
	assert_gt(moved, deg_to_rad(3.0), "бедро уже пошло к удару")
	assert_lt(moved, whole - deg_to_rad(3.0), "но за один кадр туда не долетело")
	for _frame in 120:
		rig.advance(FRAME)
	assert_almost_eq(
		rig.bone_rotation(FigureRig.LEG_L).angle_to(target),
		0.0,
		0.01,
		"а за две секунды — долетело"
	)


func test_walking_moves_the_legs_with_the_phase() -> void:
	var rig := _rig(OTTO_MODEL)
	rig.show_pose("walk_0")
	rig.set_walk_phase(0.0)
	rig.snap()
	var before := rig.bone_rotation(FigureRig.LEG_L)
	# Полтора кадра ходьбы — четверть шага клипа: бедро проходит заметный угол.
	rig.set_walk_phase(1.5)
	rig.snap()
	var after := rig.bone_rotation(FigureRig.LEG_L)
	assert_gt(before.angle_to(after), deg_to_rad(5.0), "фаза ходьбы двигает ноги")


func test_a_standing_actor_keeps_walking_where_he_stopped() -> void:
	# Часы ходьбы копятся из фазы актёра: встал — встали и ноги, а не прыгнули
	# в начало клипа.
	var rig := _rig(OTTO_MODEL)
	rig.show_pose("walk_0")
	rig.set_walk_phase(1.0)
	rig.snap()
	var stopped := rig.bone_rotation(FigureRig.LEG_L)
	rig.set_walk_phase(1.0)
	rig.snap()
	assert_almost_eq(rig.bone_rotation(FigureRig.LEG_L).angle_to(stopped), 0.0, 0.001)


## Ходьба клипом, а заземления нет: клип стоит на полу сам. Если пак однажды
## придёт с ходьбой над полом, это видно здесь, а не на кадре.
##
## Мерка — после шага `advance`, а не после `snap`: снимок заземляет по всем
## вершинам, и по нему низ был бы в нуле при любом клипе (авторевью M21).
func test_the_walk_clip_keeps_its_feet_on_the_floor() -> void:
	var rig := _rig(OTTO_MODEL)
	rig.show_pose("walk_0")
	for step in 6:
		rig.set_walk_phase(step * 0.5)
		rig.snap()
		rig.advance(0.0)
		var floor_level := rig.skinned_aabb().position.y
		assert_gt(floor_level, -0.03, "фаза %.1f: подошва не в полу" % (step * 0.5))
		assert_lt(floor_level, 0.05, "фаза %.1f: и не над ним" % (step * 0.5))


## Переход кончается: и к позе кодом, и к клипу риг долетает за полсекунды.
## Порог в углах мельче шума float32 не срабатывал никогда, а ходьба уходила от
## сглаживания вперёд, и каждый актёр, хоть раз сменивший позу, до конца жизни
## перебирал кости и вершины каждый кадр (авторевью M21).
func test_a_transition_ends_for_poses_and_clips() -> void:
	var rig := _rig(OTTO_MODEL)
	var phase := 0.0
	for pose_name: String in ["kick", "idle", "walk_0", "crouch", "dead_1"]:
		rig.show_pose(pose_name)
		for _frame in 45:
			phase = ActorPose.advance(phase, FRAME)
			rig.set_walk_phase(phase)
			rig.advance(FRAME)
		assert_true(rig.settled(), "%s: переход кончился за три четверти секунды" % pose_name)
		assert_almost_eq(
			rig.bone_rotation(FigureRig.LEG_L).angle_to(rig.target_rotation(FigureRig.LEG_L)),
			0.0,
			0.01,
			"%s: бедро в кадре позы, а не позади него" % pose_name
		)


## В игре лежащий заземлён так же, как на снимке: конец клипа смерти пака уходит
## в пол на 6 см, и риг, долетев до него, обязан тело поднять.
func test_a_settled_corpse_lies_on_the_floor() -> void:
	var rig := _rig(OTTO_MODEL)
	rig.show_pose("dead_1")
	for _frame in 60:
		rig.advance(FRAME)
	assert_true(rig.settled(), "тело легло")
	var floor_level := rig.skinned_aabb().position.y
	assert_gt(floor_level, -0.015, "лежащий не утоплен в пол")
	assert_lt(floor_level, 0.03, "и не висит над ним")


## Заземление на ходу — по крайним вершинам костей, а не по всем: расхождение
## низа с полным габаритом обязано быть в миллиметрах, иначе актёр висит или
## тонет. Верх по крайним не сверяется: риг берёт у них только низ.
func test_the_hull_grounds_like_the_whole_mesh() -> void:
	for model: PackedScene in [OTTO_MODEL, AGENT_MODEL]:
		var rig := _rig(model)
		for pose_name: String in ActorPose.AGENT_POSES + PackedStringArray(["jump", "kick"]):
			rig.show_pose(pose_name)
			rig.snap()
			var whole := rig.skinned_aabb()
			var hull := rig.skinned_aabb(true)
			assert_almost_eq(
				hull.position.y, whole.position.y, 0.01, "%s: низ по крайним" % pose_name
			)


func test_every_clip_is_in_both_models() -> void:
	for model: PackedScene in [OTTO_MODEL, AGENT_MODEL]:
		var scene := model.instantiate()
		add_child_autofree(scene)
		var players := scene.find_children("*", "AnimationPlayer", true, false)
		assert_eq(players.size(), 1, "%s: один проигрыватель" % model.resource_path)
		if players.is_empty():
			continue
		for clip_name: String in FigurePoses.CLIP_NAMES:
			assert_true(
				(players[0] as AnimationPlayer).has_animation(clip_name),
				"%s: клип %s" % [model.resource_path, clip_name]
			)


## Шляпа — то, чем агент отличается от Otto в темноте (ADR-0032, решение 3).
func test_the_agent_stands_taller_by_his_hat() -> void:
	var otto := _rig(OTTO_MODEL)
	var agent := _rig(AGENT_MODEL)
	assert_gt(agent.height(), otto.height() + 0.02, "федора над головой")


func test_facing_turns_the_figure_along_the_floor() -> void:
	var rig := _rig(OTTO_MODEL)
	rig.face(1.0)
	assert_almost_eq(rig.rotation.y, PI * 0.5, 0.001, "вправо — четверть оборота")
	rig.face(-1.0)
	assert_almost_eq(rig.rotation.y, -PI * 0.5, 0.001, "влево — в другую сторону")
