extends GutTest

## The pistol muzzle is where the bullet leaves from (ADR-0043, decision 16).

const OTTO_MODEL := preload("res://assets/models/otto.glb")


func _rig(model: PackedScene) -> FigureRig:
	var rig := FigureRig.new()
	rig.model = model
	add_child_autofree(rig)
	return rig


## The pistol muzzle stands where the bullet leaves from per ROM: standing, crouching and
## lying, for Otto and for an agent (ADR-0043, decision 16). The rig aims the arm itself; the bullet
## flies at its own height, and combat does not change from the aiming.
func test_the_muzzle_meets_the_bullet_line() -> void:
	var cases := [
		[OTTO_MODEL, "shoot", Proportions.SHOT_HIGH],
		[OTTO_MODEL, ActorPose.CROUCH, Proportions.SHOT_LOW],
	]
	# An agent of each building kind (ADR-0055, decision 7): its own model, the same bullet.
	for agent: PackedScene in AgentWardrobe.MODELS:
		cases.append([agent, "shoot", Proportions.AGENT_SHOT])
		cases.append([agent, ActorPose.CROUCH, Proportions.SHOT_LOW])
		cases.append([agent, ActorPose.PRONE, Proportions.SHOT_PRONE, Proportions.MUZZLE_PRONE])
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
		var label := "%s in pose %s" % [(case[0] as PackedScene).resource_path.get_file(), case[1]]
		assert_almost_eq(muzzle.y, wanted.y, 0.03, label + ": muzzle at bullet height")
		assert_almost_eq(muzzle.z, wanted.z, 0.05, label + ": and at the barrel reach")


## A crouching one shoots without changing pose: the arm aims even on a frozen rig, and
## when the shot is over — lowers. A frozen rig does not lay out frames, and without
## this the arm would not rise at all or would hang raised until the pose changed.
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
	assert_almost_eq(aimed.y, Proportions.SHOT_LOW, 0.03, "muzzle at bullet height")
	assert_almost_eq(aimed.z, Proportions.MUZZLE, 0.05, "and at the barrel reach")
	rig.aim_height = NAN
	rig.advance(1.0 / 60.0)
	var lowered := rig.to_local(rig.muzzle_position())
	assert_almost_eq(lowered.distance_to(resting), 0.0, 0.01, "the shot ended: the arm lowered")
