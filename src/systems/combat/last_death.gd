class_name LastDeath
extends Node

## Otto's last death (ADR-0042, decision 5): the world slows down, the camera pushes in on Otto, he
## falls with the death clip, and only then — game over.
##
## Before M24f the game over menu came up in the same frame as the death: jump is the space bar, and
## the space bar presses "Restart", and a player mashing jump restarted the game without seeing how
## he died.
##
## Runs on the real clock, not the world clock: the world is slowed down, and by it the scene would
## stretch threefold. The slow-down is relative to the previous pace, as with the takedown scene:
## tests run the world sped up.

## Finished: time to show game over.
signal finished

## How many times the world is slowed down.
const SLOW: float = 0.3
## How long the camera push-in takes, s of real time.
const CLOSE_IN: float = 0.8
## How long the whole scene lasts, s of real time.
const DURATION: float = 1.6
## How far above the feet the middle of the close-up is, m: the lying Otto is at the bottom of the
## frame, not in the middle.
const CLOSE_HEIGHT: float = 0.6

var _otto: Node3D = null
var _time: float = 0.0
var _time_scale_before: float = 1.0
var _slowed: bool = false


## Starts the scene over [param otto]. The node goes into [param parent] and leaves by itself when
## the scene has finished.
static func play(parent: Node, otto: Node3D) -> LastDeath:
	var scene := LastDeath.new()
	scene.name = "LastDeath"
	scene._otto = otto
	parent.add_child(scene)
	return scene


func _ready() -> void:
	# Runs during pause too: on pause the world stands still, but the scene must still finish.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_time_scale_before = Engine.time_scale
	Engine.time_scale = _time_scale_before * SLOW
	_slowed = true
	Sounds.play(Sounds.SLOWMO)


## Runs the scene for [param real_delta] seconds of real time. Exposed for tests.
func advance(real_delta: float) -> void:
	if not _slowed:
		return
	_time += real_delta
	var camera := _camera()
	if camera != null and is_instance_valid(_otto):
		var at := _otto.global_position
		camera.close_up(smoothstep(0.0, CLOSE_IN, _time), Vector2(at.x, at.y + CLOSE_HEIGHT))
	if _time >= DURATION:
		_speed_up()
		finished.emit()
		queue_free()


func _process(delta: float) -> void:
	# The frame delta is already multiplied by the world pace — divide it back.
	advance(delta / maxf(Engine.time_scale, 0.001))


func _notification(what: int) -> void:
	# The scene was thrown out before the end — the world must not stay slow.
	if what == NOTIFICATION_EXIT_TREE:
		_speed_up()


func _speed_up() -> void:
	if not _slowed:
		return
	Engine.time_scale = _time_scale_before
	_slowed = false


func _camera() -> SideCamera:
	var viewport := get_viewport()
	return viewport.get_camera_3d() as SideCamera if viewport != null else null
