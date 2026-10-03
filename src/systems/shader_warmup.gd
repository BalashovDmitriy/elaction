class_name ShaderWarmup
extends RefCounted

## Shader warm-up for rare effects (ADR-0039, decision 8).
##
## The first shot made the frame stutter: the shaders of the muzzle flash, smoke, sparks, blood and
## lightning discharge are compiled at the moment of first display. The warm-up shows each such
## effect once while the frame is black — and removes it before the frame opens. The engine's
## pipeline cache is shared per process, so the warm-up runs once per game launch. The second half
## of the decision is the Shader Baker in the export presets.
##
## An effect's pipeline is compiled only if it was actually drawn, so it is placed in the camera's
## view rather than hidden: a hidden one ([member Node3D.visible] off) or one out of view is not
## drawn and warms up nothing.

## How long the frame stays black and the warm-up effects live, s. Shader compilation happens in the
## first frames; there is no point holding it longer.
const HOLD: float = 0.2
## How far in front of the camera the effects are placed, m.
const AHEAD: float = 4.0

static var _done: bool = false


## Warms up if it has not been done yet and there is something to draw with. Returns whether the
## warm-up started: then the caller keeps the frame black for [constant HOLD] seconds.
static func run(host: Node3D) -> bool:
	if _done or DisplayServer.get_name() == "headless" or host == null:
		return false
	var camera := host.get_viewport().get_camera_3d()
	if camera == null:
		return false
	_done = true
	var at := camera.global_position - camera.global_basis.z * AHEAD
	var shown := spawn(host, at)
	host.get_tree().create_timer(HOLD).timeout.connect(
		func() -> void:
			for node: Node in shown:
				if is_instance_valid(node):
					node.queue_free()
	)
	return true


## Places one of each rare effect at point [param at] under node [param host] and returns everything
## placed. No checks — for tests.
static func spawn(host: Node3D, at: Vector3) -> Array[Node]:
	# New children go at the end: everything placed is the tail of the list after this mark.
	var before := host.get_child_count()
	ShotFx.muzzle(host, at, 1.0)
	# No sound: the warm-up runs under a black frame, a ricochet there would be heard from nowhere.
	ShotFx.impact(host, at, -1.0, null, false)
	Sparks.burst(host, at)
	# Blood is warmed up even when disabled: if it is turned on in the middle of a game, the frame must
	# not stutter then either.
	var blood := Blood.enabled
	Blood.enabled = true
	Blood.spray(host, at, 1.0)
	Blood.enabled = blood
	var bullet := BulletLook.make(1.0)
	host.add_child(bullet)
	bullet.global_position = at
	bullet.follow(BulletLook.TRAIL_LENGTH)
	var laser := AimLaser.make()
	laser.visible = true
	host.add_child(laser)
	laser.global_position = at
	var shown := host.get_children().slice(before)
	# The discharge lives in the city window, with its own world and frame: it has to be warmed up
	# there. In dry weather there is no lightning, and nothing to warm up.
	for node: Node in host.find_children("Lightning", "", true, false):
		if node is Lightning:
			shown.append((node as Lightning).warm_up())
	return shown
