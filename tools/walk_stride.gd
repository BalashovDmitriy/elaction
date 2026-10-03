extends SceneTree

## Walk clip stride measurement: how fast the support foot moves backward.
##
## The pack's clip walks in place, and the foot standing on the floor moves back under the body
## at exactly the speed the body would walk forward. Dividing the actor's speed
## (`Arcade.WALK_PX`) by it, we get [constant FigurePoses.WALK_CLIP_RATE]:
## at it the soles do not slide on the floor.
##
## Run:
##     godot --headless --script res://tools/walk_stride.gd


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := (load("res://assets/models/otto.glb") as PackedScene).instantiate()
	root.add_child(scene)
	var player := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var skeleton := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var animation := player.get_animation(FigurePoses.CLIP_WALK)
	player.play(FigurePoses.CLIP_WALK)
	var steps := 120
	var dt := animation.length / steps
	var samples: Array[Vector3] = []
	for step in steps + 1:
		player.seek(step * dt, true)
		skeleton.force_update_all_bone_transforms()
		samples.append(skeleton.get_bone_global_pose(skeleton.find_bone("Foot.L")).origin)
	var lowest := INF
	for sample in samples:
		lowest = minf(lowest, sample.y)
	# Support — frames where the foot is right at the floor; speed — the average over them.
	var speed_sum := 0.0
	var count := 0
	for step in steps:
		if samples[step].y < lowest + 0.02 and samples[step + 1].y < lowest + 0.02:
			speed_sum += absf(samples[step + 1].z - samples[step].z) / dt
			count += 1
	var clip_speed := speed_sum / maxi(count, 1)
	var actor_speed := Arcade.speed(Arcade.WALK_PX)
	print("клип %.2f с, опорных кадров %d" % [animation.length, count])
	print("скорость опоры в клипе %.3f м/с, актёра %.3f м/с" % [clip_speed, actor_speed])
	print("WALK_CLIP_RATE = %.2f" % (actor_speed / maxf(clip_speed, 0.001)))
	quit()
