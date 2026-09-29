extends GutTest

## Дуло пистолета — там, откуда вылетает пуля (ADR-0043, решение 16).

const OTTO_MODEL := preload("res://assets/models/otto.glb")
const AGENT_MODEL := preload("res://assets/models/agent.glb")


func _rig(model: PackedScene) -> FigureRig:
	var rig := FigureRig.new()
	rig.model = model
	add_child_autofree(rig)
	return rig


## Дуло пистолета стоит там, откуда вылетает пуля по ROM: стоя, из приседа и
## лёжа, у Otto и у агента (ADR-0043, решение 16). Риг наводит руку сам; пуля
## летит на своей высоте, и бой от наведения не меняется.
func test_the_muzzle_meets_the_bullet_line() -> void:
	var cases := [
		[OTTO_MODEL, "shoot", Proportions.SHOT_HIGH],
		[OTTO_MODEL, ActorPose.CROUCH, Proportions.SHOT_LOW],
		[AGENT_MODEL, "shoot", Proportions.AGENT_SHOT],
		[AGENT_MODEL, ActorPose.CROUCH, Proportions.SHOT_LOW],
		[AGENT_MODEL, ActorPose.PRONE, Proportions.SHOT_PRONE, Proportions.MUZZLE_PRONE],
	]
	for case: Array in cases:
		var rig := _rig(case[0] as PackedScene)
		rig.face(1.0, true)
		var reach := float(case[3]) if case.size() > 3 else Proportions.MUZZLE
		rig.aim_height = float(case[2])
		rig.aim_reach = reach
		rig.show_pose(String(case[1]))
		rig.snap()
		var muzzle := rig.to_local(rig.muzzle_position())
		var wanted := Vector3(0.0, float(case[2]), reach)
		var label := "%s в позе %s" % [(case[0] as PackedScene).resource_path.get_file(), case[1]]
		assert_almost_eq(muzzle.y, wanted.y, 0.03, label + ": дуло на высоте пули")
		assert_almost_eq(muzzle.z, wanted.z, 0.05, label + ": и на выносе ствола")


## Присевший стреляет, не меняя позы: рука наводится и на застывшем риге, а
## выстрел кончился — опускается. Застывший риг кадров не раскладывает, и без
## этого рука не поднималась бы вовсе или висела бы вскинутой до смены позы.
func test_the_arm_aims_on_a_settled_pose() -> void:
	var rig := _rig(OTTO_MODEL)
	rig.face(1.0, true)
	rig.show_pose(ActorPose.CROUCH)
	rig.snap()
	var resting := rig.to_local(rig.muzzle_position())
	rig.aim_height = Proportions.SHOT_LOW
	rig.aim_reach = Proportions.MUZZLE
	rig.advance(1.0 / 60.0)
	var aimed := rig.to_local(rig.muzzle_position())
	assert_almost_eq(aimed.y, Proportions.SHOT_LOW, 0.03, "дуло на высоте пули")
	assert_almost_eq(aimed.z, Proportions.MUZZLE, 0.05, "и на выносе ствола")
	rig.aim_height = NAN
	rig.advance(1.0 / 60.0)
	var lowered := rig.to_local(rig.muzzle_position())
	assert_almost_eq(lowered.distance_to(resting), 0.0, 0.01, "выстрел кончился — рука опустилась")
