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
	# ляжет: макушка залёгшего — это кромка полей, 0.46 м против пули на 0.45.
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
	assert_gt(box.size.z, rig.height() * 0.8, "и длинный вдоль пола")
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
	# «На стоп-кадре ходьбы видно, что это шаг, а не подмена картинки»: за один
	# кадр кости сдвигаются к цели, но не долетают.
	var rig := _rig(OTTO_MODEL)
	rig.show_pose("idle")
	rig.snap()
	rig.show_pose("kick")
	# Шаг сглаживания задаётся здесь, а не ждётся кадром: в headless-прогоне
	# кадр длится «сколько получится», и на нём риг успел бы долететь.
	rig.advance(FRAME)
	var leg := rig.current_pose().legs.x
	var target := FigurePoses.of("kick").legs.x
	assert_gt(leg, 5.0, "нога уже пошла к удару")
	assert_lt(leg, target - 5.0, "но за один кадр туда не долетела")
	for _frame in 120:
		rig.advance(FRAME)
	assert_almost_eq(rig.current_pose().legs.x, target, 0.5, "а за две секунды — долетела")


func test_walking_moves_the_legs_frame_by_frame() -> void:
	var rig := _rig(OTTO_MODEL)
	rig.show_pose("walk_0")
	rig.set_walk_phase(0.0)
	rig.snap()
	var before := rig.current_pose().legs.x
	rig.set_walk_phase(0.5)
	rig.snap()
	var after := rig.current_pose().legs.x
	assert_ne(before, after, "фаза ходьбы двигает ноги")
	assert_gt(after, before, "к четверти цикла левая нога идёт вперёд")


func test_facing_turns_the_figure_along_the_floor() -> void:
	var rig := _rig(OTTO_MODEL)
	rig.face(1.0)
	assert_almost_eq(rig.rotation.y, PI * 0.5, 0.001, "вправо — четверть оборота")
	rig.face(-1.0)
	assert_almost_eq(rig.rotation.y, -PI * 0.5, 0.001, "влево — в другую сторону")
