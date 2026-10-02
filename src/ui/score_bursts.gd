class_name ScoreBursts
extends Control

## Очки на виду (просьба пользователя, M24m): прибавка всплывает над местом
## события и счёт в HUD не перескакивает молча.
##
## - Над убитым агентом, раздавленным кабиной или лампой — «+300» неоном:
##   поднимается и гаснет. Документ — над Otto. Точку сцены переводит в кадр
##   камера; за кадром прибавка всплывает у его края.
## - Счёт набегает к новому числу, вспыхивает цветом вывески здания и чуть
##   вздрагивает; рядом на секунду — та же прибавка.
##
## Бонус за здание всплывающей прибавки не получает: у него своя плашка
## ([Hud]). Слой поверх HUD, мыши не ловит.

## За сколько набегает счёт и сколько держится вспышка, с.
const ROLL_TIME: float = 0.45
const FLASH_TIME: float = 0.6
## Насколько вздрагивает число счёта.
const PULSE: float = 1.18
## Прибавка над местом: кегль, на сколько поднимается, px, и сколько живёт, с.
const BURST_SIZE: int = 44
const BURST_RISE: float = 70.0
const BURST_TIME: float = 1.1
## Прибавка у счёта: кегль и сколько живёт, с.
const CHIP_SIZE: int = 30
const CHIP_TIME: float = 1.0
## Отступ прибавки от краёв кадра, px.
const EDGE: float = 40.0

var neon := NeonStyle.INK

var _score: Label = null
var _level: GreyboxLevel = null
var _shown: float = 0.0
var _target: int = 0
var _roll: Tween = null
var _flash: Tween = null


## Число счёта, которым управлять, и здание — по нему Otto для документа.
func watch(score_label: Label) -> void:
	_score = score_label
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameState.instance().scored.connect(_on_scored)


func follow(level: GreyboxLevel) -> void:
	_level = level


## Ставит счёт: вниз и при новой партии — сразу, вверх — набегом.
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


## Вспышка числа: цвет вывески и вздрагивание, затем обратно.
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


## Прибавка у числа счёта: справа от него, гаснет на месте.
func _chip(points: int) -> void:
	var chip := _plus(points, CHIP_SIZE)
	add_child(chip)
	# Сразу за последней цифрой окончательного счёта: подпись шире числа, и
	# край подписи уводил прибавку за плашку.
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


## Прибавка над местом события: всплывает и гаснет.
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
