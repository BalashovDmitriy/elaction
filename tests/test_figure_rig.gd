extends GutTest

## Actor rig on a live skeleton from `.glb`.
##
## Checks what the milestone is for: a crouch tucks the figure under an agent's bullet, and
## the transition between poses is motion, not a picture swap (ADR-0022).

const OTTO_MODEL := preload("res://assets/models/otto.glb")
const AGENT_MODEL := preload("res://assets/models/agent.glb")
const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const BULLET_SCENE := preload("res://src/systems/combat/bullet.tscn")

## A frame at 60 Hz: over it smoothing must move the bones, but not arrive.
const FRAME: float = 1.0 / 60.0


func _rig(model: PackedScene) -> FigureRig:
	var rig := FigureRig.new()
	rig.model = model
	add_child_autofree(rig)
	return rig


## Otto and agents of all building kinds: the agent models are built by one build
## (ADR-0055, decision 7), and the rig must lift each one the same way as the former one.
func _models() -> Array[PackedScene]:
	var all: Array[PackedScene] = [OTTO_MODEL]
	all.append_array(AgentWardrobe.MODELS)
	return all


## Otto from the scene: his shot and collision heights are taken from him, not
## rewritten into the test as numbers.
func _otto() -> Otto:
	var otto := OTTO_SCENE.instantiate() as Otto
	autofree(otto)
	return otto


## A bullet is a box, and it passes the figure by its edge, not its axis.
func _bullet_half_height() -> float:
	var bullet := BULLET_SCENE.instantiate()
	var shape := (bullet.get_node("Shape") as CollisionShape3D).shape as BoxShape3D
	bullet.free()
	return shape.size.y * 0.5


func test_both_models_carry_every_bone() -> void:
	for model: PackedScene in _models():
		var scene := model.instantiate()
		add_child_autofree(scene)
		var found := scene.find_children("*", "Skeleton3D", true, false)
		assert_eq(found.size(), 1, "%s: one skeleton" % model.resource_path)
		if found.is_empty():
			continue
		var skeleton := found[0] as Skeleton3D
		for bone_name: String in FigureRig.BONES:
			assert_gte(
				skeleton.find_bone(bone_name), 0, "%s: bone %s" % [model.resource_path, bone_name]
			)


func test_the_rig_stands_as_tall_as_the_collision_says() -> void:
	# Figure height is Otto's collision plus the hairdo on top: the height cannot be below the
	# collision, otherwise an agent's bullet would pass over the head.
	var rig := _rig(OTTO_MODEL)
	var otto := OTTO_SCENE.instantiate() as Otto
	var standing := (
		((otto.get_node("StandingShape") as CollisionShape3D).shape as BoxShape3D).size.y
	)
	otto.free()
	assert_gte(rig.height(), standing, "the figure is not lower than the standing collision")
	assert_lt(rig.height(), standing * 1.2, "and not taller than it by more than a hairdo")


## Milestone DoD: Otto crouching is still below an agent's bullet.
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
	assert_lt(
		top,
		bullet_height,
		"the crown of a crouching one is below the agent's bullet (%.2f)" % bullet_height
	)
	assert_lt(
		top,
		crouching * 1.1,
		"and fits the crouch collision %.2f with room for the head" % crouching
	)


## Mirroring Otto (ADR-0016): kneeling, the agent goes under a standing Otto's bullet, lying down —
## under a crouching one's. In M15 a box held this, cut by heights from the building rules; the
## figure has its own height, and it must be checked against the bullet.
func test_a_kneeling_agent_ducks_under_the_standing_shot() -> void:
	var rig := _rig(AGENT_MODEL)
	var shot := _otto().shot_height_standing
	rig.show_pose(ActorPose.CROUCH)
	rig.snap()
	var top := rig.skinned_aabb().end.y
	assert_lt(
		top,
		shot - _bullet_half_height(),
		"a kneeling hat is below the bullet's lower edge (%.2f)" % shot
	)


func test_a_prone_agent_lies_under_the_crouching_shot() -> void:
	var rig := _rig(AGENT_MODEL)
	var shot := _otto().shot_height_crouching
	rig.show_pose(ActorPose.PRONE)
	rig.snap()
	var lying := rig.skinned_aabb()
	# Face down, the hat brim stands vertical, and the figure will not lie lower than its diameter:
	# the top of a lying one is the brim edge, 0.66 m against a bullet at 0.66 (M18c: the agent grew
	# to Otto's height, and the brim with him). Hence the measure is the bullet's top edge, not the
	# bottom: the body is wholly under it, it can only graze the brim edge. Going lower is possible
	# only with a different hat model.
	assert_lt(
		lying.end.y,
		shot + _bullet_half_height(),
		"a prone one is below the bullet's upper edge (%.2f)" % shot
	)
	assert_gt(
		lying.size.z, rig.height() * 0.9, "and stretched along the floor: arms with the gun forward"
	)
	rig.show_pose(ActorPose.CROUCH)
	rig.snap()
	assert_lt(lying.end.y, rig.skinned_aabb().end.y, "and lower than kneeling")


func test_the_choke_puts_the_arms_forward() -> void:
	# Sign of angles: "forward" must be forward, wherever the bone's local axis
	# points. At rest the figure faces +Z, and the measure is relative to rest.
	# Since M24d there is no kick (ADR-0040): the neck hold checks the sign.
	var rig := _rig(OTTO_MODEL)
	rig.show_pose("stand")
	rig.snap()
	var standing := rig.skinned_aabb()
	rig.show_pose("choke_hold")
	rig.snap()
	var holding := rig.skinned_aabb()
	assert_gt(
		holding.end.z, standing.end.z, "arms in the grab are pushed forward, beyond the body bounds"
	)
	# Arm up is also a sign: the pistol raised for a butt strike is above the top of the head
	# (the pack model's arms are short: level with the hat brim, no higher).
	rig.show_pose("whip_raise")
	rig.snap()
	assert_gt(rig.skinned_aabb().end.y, standing.end.y, "a raised arm is above the crown")


func test_a_lying_figure_is_long_and_low() -> void:
	var rig := _rig(OTTO_MODEL)
	rig.show_pose("dead_1")
	rig.snap()
	var box := rig.skinned_aabb()
	assert_lt(box.end.y, rig.height() * 0.5, "a lying one is low")
	# The pack's death clip drops the body not straight back but with a twist: the length is
	# along the floor diagonal, not just along the gaze.
	assert_gt(
		Vector2(box.size.x, box.size.z).length(), rig.height() * 0.8, "and long along the floor"
	)
	assert_gte(box.position.y, -0.01, "and not sunk into the floor")


## Grounding is shared: each pose has its own depth, and none goes below the floor.
func test_no_pose_sinks_below_the_floor() -> void:
	var rig := _rig(OTTO_MODEL)
	for pose_name: String in ActorPose.OTTO_POSES:
		rig.show_pose(pose_name)
		rig.snap()
		var floor_level := rig.skinned_aabb().position.y
		assert_gte(
			floor_level, -0.01, "%s is sunk into the floor by %.3f" % [pose_name, -floor_level]
		)
		assert_lt(floor_level, 0.06, "%s hangs above the floor by %.3f" % [pose_name, floor_level])


func test_a_pose_change_is_a_motion_not_a_swap() -> void:
	# "A still frame shows it is motion, not a picture swap": over one
	# frame the bones move toward the target but do not arrive.
	var rig := _rig(OTTO_MODEL)
	rig.show_pose("idle")
	rig.snap()
	var start := rig.bone_rotation(FigureRig.LEG_L)
	rig.show_pose("crouch")
	var target := rig.target_rotation(FigureRig.LEG_L)
	var whole := start.angle_to(target)
	assert_gt(whole, deg_to_rad(40.0), "a crouch moves the thigh far from standing")
	# The smoothing step is set here rather than awaited as a frame: in a headless run
	# a frame lasts "however long it takes", and in it the rig would manage to arrive.
	rig.advance(FRAME)
	var moved := start.angle_to(rig.bone_rotation(FigureRig.LEG_L))
	assert_gt(moved, deg_to_rad(3.0), "the thigh has already gone towards the strike")
	assert_lt(moved, whole - deg_to_rad(3.0), "but it did not get there in one frame")
	for _frame in 120:
		rig.advance(FRAME)
	assert_almost_eq(
		rig.bone_rotation(FigureRig.LEG_L).angle_to(target), 0.0, 0.01, "and in two seconds it did"
	)


func test_walking_moves_the_legs_with_the_phase() -> void:
	var rig := _rig(OTTO_MODEL)
	rig.show_pose("walk_0")
	rig.set_walk_phase(0.0)
	rig.snap()
	var before := rig.bone_rotation(FigureRig.LEG_L)
	# One and a half walk frames — a quarter of a clip step: the thigh sweeps a noticeable angle.
	rig.set_walk_phase(1.5)
	rig.snap()
	var after := rig.bone_rotation(FigureRig.LEG_L)
	assert_gt(before.angle_to(after), deg_to_rad(5.0), "the walk phase moves the legs")


func test_a_standing_actor_keeps_walking_where_he_stopped() -> void:
	# The walk clock accumulates from the actor's phase: stopped — the legs stopped too, rather than
	# jumping to the start of the clip.
	var rig := _rig(OTTO_MODEL)
	rig.show_pose("walk_0")
	rig.set_walk_phase(1.0)
	rig.snap()
	var stopped := rig.bone_rotation(FigureRig.LEG_L)
	rig.set_walk_phase(1.0)
	rig.snap()
	assert_almost_eq(rig.bone_rotation(FigureRig.LEG_L).angle_to(stopped), 0.0, 0.001)


## Walking by clip, and there is no grounding: the clip stands on the floor by itself. If the pack
## ever comes with a walk above the floor, it shows here, not in a shot.
##
## The measure is after an `advance` step, not after `snap`: a snapshot grounds by all
## vertices, and by it the bottom would be at zero for any clip (M21 code review).
func test_the_walk_clip_keeps_its_feet_on_the_floor() -> void:
	var rig := _rig(OTTO_MODEL)
	rig.show_pose("walk_0")
	for step in 6:
		rig.set_walk_phase(step * 0.5)
		rig.snap()
		rig.advance(0.0)
		var floor_level := rig.skinned_aabb().position.y
		assert_gt(floor_level, -0.03, "phase %.1f: the sole is not in the floor" % (step * 0.5))
		assert_lt(floor_level, 0.05, "phase %.1f: and not above it" % (step * 0.5))


## The transition ends: both to a code pose and to a clip, the rig arrives within half a second.
## A threshold in angles finer than float32 noise never fired, and walking ran ahead of
## smoothing, and every actor that had changed pose even once went on for the rest of its life
## iterating bones and vertices every frame (M21 code review).
func test_a_transition_ends_for_poses_and_clips() -> void:
	var rig := _rig(OTTO_MODEL)
	var phase := 0.0
	for pose_name: String in ["crouch", "idle", "walk_0", "choke_hold", "dead_1"]:
		rig.show_pose(pose_name)
		for _frame in 45:
			phase = ActorPose.advance(phase, FRAME)
			rig.set_walk_phase(phase)
			rig.advance(FRAME)
		assert_true(
			rig.settled(), "%s: the transition ended within three quarters of a second" % pose_name
		)
		assert_almost_eq(
			rig.bone_rotation(FigureRig.LEG_L).angle_to(rig.target_rotation(FigureRig.LEG_L)),
			0.0,
			0.01,
			"%s: the thigh is in the pose frame, not behind it" % pose_name
		)


## In the game a lying one is grounded the same as in a snapshot: the end of the pack's death clip
## goes 6 cm into the floor, and the rig, having arrived at it, must lift the body.
func test_a_settled_corpse_lies_on_the_floor() -> void:
	var rig := _rig(OTTO_MODEL)
	rig.show_pose("dead_1")
	for _frame in 60:
		rig.advance(FRAME)
	assert_true(rig.settled(), "the body lay down")
	var floor_level := rig.skinned_aabb().position.y
	assert_gt(floor_level, -0.015, "a lying one is not sunk into the floor")
	assert_lt(floor_level, 0.03, "and does not hang above it")


## A rig that has arrived at a clip does not ground it at all: since M24c `build_actors.py` puts
## any clip on the floor (ADR-0039). The measure is after `advance` steps, as in the game, and
## not after `snap`: a snapshot grounds by all vertices and does not see a build miss.
func test_every_clip_stands_on_the_floor_by_itself() -> void:
	for model: PackedScene in _models():
		var rig := _rig(model)
		var who := model.resource_path.get_file()
		for pose_name: String in ["idle", "shoot", "jump", "land", "dead_0", "dead_1"]:
			assert_not_null(FigurePoses.clip_of(pose_name), "%s: clip" % pose_name)
			rig.show_pose(pose_name)
			for _frame in 30:
				rig.advance(FRAME)
			assert_true(rig.settled(), "%s %s: the transition ended" % [who, pose_name])
			var low := rig.skinned_aabb().position.y
			assert_gt(low, -0.03, "%s %s: not in the floor (%.3f)" % [who, pose_name, low])
			assert_lt(low, 0.05, "%s %s: and not above it (%.3f)" % [who, pose_name, low])


## Grounding on the move is by the bones' outermost vertices, not by all: the gap between
## the bottom and the full extent must be in millimetres, otherwise the actor floats or
## sinks. The top is not checked by the outermost ones: the rig takes only the bottom from them.
func test_the_hull_grounds_like_the_whole_mesh() -> void:
	for model: PackedScene in _models():
		var rig := _rig(model)
		for pose_name: String in ActorPose.AGENT_POSES + PackedStringArray(["jump", "fall"]):
			rig.show_pose(pose_name)
			rig.snap()
			var whole := rig.skinned_aabb()
			var hull := rig.skinned_aabb(true)
			assert_almost_eq(
				hull.position.y,
				whole.position.y,
				0.01,
				"%s %s: the bottom by the extremes" % [model.resource_path.get_file(), pose_name]
			)


func test_every_clip_is_in_both_models() -> void:
	for model: PackedScene in _models():
		var scene := model.instantiate()
		add_child_autofree(scene)
		var players := scene.find_children("*", "AnimationPlayer", true, false)
		assert_eq(players.size(), 1, "%s: one player" % model.resource_path)
		if players.is_empty():
			continue
		for clip_name: String in FigurePoses.CLIP_NAMES:
			assert_true(
				(players[0] as AnimationPlayer).has_animation(clip_name),
				"%s: clip %s" % [model.resource_path, clip_name]
			)


## The hat is what tells an agent from Otto in darkness (ADR-0032, decision 3).
func test_the_agent_stands_taller_by_his_hat() -> void:
	var otto := _rig(OTTO_MODEL)
	var agent := _rig(AGENT_MODEL)
	assert_gt(agent.height(), otto.height() + 0.02, "a fedora above the head")


func test_facing_turns_the_figure_along_the_floor() -> void:
	var rig := _rig(OTTO_MODEL)
	rig.face(1.0)
	assert_almost_eq(rig.rotation.y, PI * 0.5, 0.001, "right: a quarter turn, at once")
	rig.face(-1.0)
	rig.snap()
	assert_almost_eq(rig.rotation.y, -PI * 0.5, 0.001, "left: the other way")


## A turn is body motion over the turn pause, through "facing the camera"
## (ADR-0039, decision 3), not a side swap.
func test_a_turn_swings_the_body_through_the_camera() -> void:
	var rig := _rig(OTTO_MODEL)
	rig.face(1.0)
	rig.face(-1.0)
	assert_almost_eq(
		rig.rotation.y, PI * 0.5, 0.001, "in the first frame of the turn it still looks right"
	)
	rig.advance(MoveLocks.TURN_TIME * 0.5)
	rig.face(-1.0)
	assert_almost_eq(rig.rotation.y, 0.0, 0.05, "halfway: face to the camera, not back")
	rig.advance(MoveLocks.TURN_TIME * 0.5 + 0.001)
	rig.face(-1.0)
	assert_almost_eq(rig.rotation.y, -PI * 0.5, 0.001, "after the turn pause: left")
