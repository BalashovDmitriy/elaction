class_name FadeCurtain
extends CanvasLayer

## Fade between buildings (ADR-0038, decision 4).
##
## The car with Otto has driven off, the bonus is counted: the frame fades to black, the
## next building is assembled under the black, and the frame comes out of black already
## on it. Previously the building changed abruptly, in a single frame.
##
## The layer is above the HUD and below the menu: the bonus fades to black together with
## the scene, and a pause taken in the middle of the fade shows on top of it. During a
## pause the fade holds.

## Canvas layer: HUD is 3, menu is 5.
const LAYER: int = 4
## How long the frame takes to fade into black and to come out of it, s.
const FADE_OUT: float = 0.45
const FADE_IN: float = 0.45

var _veil: ColorRect = null
var _tween: Tween = null


func _init() -> void:
	name = "FadeCurtain"
	layer = LAYER
	_veil = ColorRect.new()
	_veil.name = "Veil"
	_veil.color = Color(0.0, 0.0, 0.0, 0.0)
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)


## After waiting [param hold], fades the frame to black, calls [param swap] and brings
## the frame back. A fade started earlier is cancelled.
func cover(hold: float, swap: Callable) -> void:
	cancel()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	if hold > 0.0:
		_tween.tween_interval(hold)
	_tween.tween_property(_veil, "color:a", 1.0, FADE_OUT)
	_tween.tween_callback(swap)
	_tween.tween_property(_veil, "color:a", 0.0, FADE_IN)


## Starts from black: holds it for [param hold] seconds and brings the frame in. This is
## how the first building of a game opens while shaders warm up under the black
## ([ShaderWarmup]).
func reveal(hold: float) -> void:
	cancel()
	_veil.color.a = 1.0
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	_tween.tween_interval(hold)
	_tween.tween_property(_veil, "color:a", 0.0, FADE_IN)


## Removes the fade at once: the game was dropped to the menu or restarted in the middle
## of a building change, so there is no point in changing the building any more.
func cancel() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	_veil.color.a = 0.0


## Whether a fade is in progress.
func is_running() -> bool:
	return _tween != null and _tween.is_running()


## How far the frame is in black now: 0 is open, 1 is black.
func opacity() -> float:
	return _veil.color.a
