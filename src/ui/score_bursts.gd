class_name ScoreBursts
extends Control

## Points in view (user's request, M24m): the increment pops up over the place of
## the event and the score in the HUD does not jump silently.
##
## - Over a killed agent, one crushed by a cab or lamp — "+300" in neon:
##   rises and fades. A document — over Otto. The camera converts the scene point
##   to the frame; off-frame the increment pops up at its edge.
## - The score counts up to the new number, flashes the building sign colour and
##   twitches slightly; next to it for a second — the same increment.
##
## The building bonus gets no pop-up increment: it has its own plate
## ([Hud]). A layer over the HUD, does not catch the mouse.

## How long the score counts up and how long the flash holds, s.
const ROLL_TIME: float = 0.45
const FLASH_TIME: float = 0.6
## How much the score number twitches.
const PULSE: float = 1.18
## Increment over the place: font size, how far it rises, px, and how long it lives, s.
const BURST_SIZE: int = 44
const BURST_RISE: float = 70.0
const BURST_TIME: float = 1.1
## Increment at the score: font size and how long it lives, s.
const CHIP_SIZE: int = 30
const CHIP_TIME: float = 1.0
## Increment margin from the frame edges, px.
const EDGE: float = 40.0

var neon := NeonStyle.INK

var _score: Label = null
var _level: GreyboxLevel = null
var _shown: float = 0.0
var _target: int = 0
var _roll: Tween = null
var _flash: Tween = null


## The score number to control, and the building — Otto for a document is found through it.
func watch(score_label: Label) -> void:
	_score = score_label
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameState.instance().scored.connect(_on_scored)


func follow(level: GreyboxLevel) -> void:
	_level = level


## Sets the score: down and on a new game — at once, up — by counting up.
func show_score(score: int) -> void:
	if _score == null:
		return
	if score <= _target or score < roundi(_shown):
		_stop_roll()
		_target = score
		_shown = score
		_score.text = Hud.format_score(score)
		return
	_target = score
	_stop_roll()
	_roll = create_tween()
	_roll.tween_method(_roll_to, _shown, float(score), ROLL_TIME)


func _roll_to(value: float) -> void:
	_shown = value
	_score.text = Hud.format_score(roundi(value))


func _stop_roll() -> void:
	if _roll != null and _roll.is_valid():
		_roll.kill()
	_roll = null


func _on_scored(points: int, at: Vector3, popup: bool) -> void:
	if points <= 0 or _score == null:
		return
	_flash_score()
	_chip(points)
	if popup:
		_burst(points, at)


## Number flash: sign colour and a twitch, then back.
func _flash_score() -> void:
	if _flash != null and _flash.is_valid():
		_flash.kill()
	_score.pivot_offset = _score.size * Vector2(0.0, 0.5)
	_score.modulate = Color(neon.r, neon.g, neon.b) * 1.6
	_score.scale = Vector2.ONE * PULSE
	_flash = create_tween().set_parallel()
	_flash.tween_property(_score, "modulate", Color.WHITE, FLASH_TIME)
	_flash.tween_property(_score, "scale", Vector2.ONE, FLASH_TIME * 0.5).set_trans(
		Tween.TRANS_BACK
	)


## Increment at the score number: to the right of it, fades in place.
func _chip(points: int) -> void:
	var chip := _plus(points, CHIP_SIZE)
	add_child(chip)
	# Right after the last digit of the final score: the label is wider than the number, and
	# the label edge pushed the increment past the plate.
	var rect := _score.get_global_rect()
	var font := _score.get_theme_font("font")
	var digits := font.get_string_size(
		Hud.format_score(_target),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		_score.get_theme_font_size("font_size")
	)
	chip.position = Vector2(rect.position.x + digits.x + 14.0, rect.position.y + rect.size.y * 0.22)
	var fade := create_tween()
	fade.tween_property(chip, "position:x", chip.position.x + 18.0, CHIP_TIME)
	fade.parallel().tween_property(chip, "modulate:a", 0.0, CHIP_TIME).set_ease(Tween.EASE_IN)
	fade.tween_callback(chip.queue_free)


## Increment over the event place: pops up and fades.
func _burst(points: int, at: Vector3) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var world := at
	if at == GameState.AT_OTTO:
		if _level == null or _level.otto == null:
			return
		world = _level.otto.global_position + GameState.OVER_HEAD
	if camera.is_position_behind(world):
		return
	var spot := camera.unproject_position(world)
	var frame := get_viewport_rect().size
	var burst := _plus(points, BURST_SIZE)
	add_child(burst)
	var size := burst.get_combined_minimum_size()
	spot.x = clampf(spot.x - size.x * 0.5, EDGE, frame.x - EDGE - size.x)
	spot.y = clampf(spot.y - size.y, EDGE + BURST_RISE, frame.y - EDGE - size.y)
	burst.position = spot
	burst.pivot_offset = size * 0.5
	burst.scale = Vector2.ONE * 0.6
	var rise := create_tween().set_parallel()
	rise.tween_property(burst, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)
	rise.tween_property(burst, "position:y", spot.y - BURST_RISE, BURST_TIME).set_ease(
		Tween.EASE_OUT
	)
	rise.tween_property(burst, "modulate:a", 0.0, BURST_TIME * 0.45).set_delay(BURST_TIME * 0.55)
	rise.chain().tween_callback(burst.queue_free)


func _plus(points: int, font_size: int) -> Label:
	var label := NeonStyle.label(font_size, NeonStyle.INK, 800)
	label.text = "+" + Hud.format_score(points)
	label.add_theme_color_override("font_outline_color", Color(neon, 0.9))
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
