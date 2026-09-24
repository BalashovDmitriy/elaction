class_name NeonTitle
extends Control

## Название игры неоновой вывеской (ADR-0035, решение 2).
##
## Рисуется сам, буква за буквой: свечение — несколько обводок с убывающей
## яркостью, поверх — трубка цвета неона и её раскалённая середина. Свечение
## окружения 2D не достаётся, поэтому ореол нарисован, а не выставлен.
##
## Одна буква мигает, как на вывеске здания ([VerticalSign]): вывеска, у которой
## все трубки горят ровно, выглядит картинкой, а не вывеской.

## Слои ореола: толщина обводки и её яркость. Снаружи внутрь.
const GLOW: Array[Vector2] = [Vector2(34.0, 0.05), Vector2(22.0, 0.09), Vector2(12.0, 0.16)]
## Трубка: обводка цвета неона вокруг светлой середины.
const TUBE: float = 5.0
const CORE_TINT: float = 0.72
const WEIGHT: int = 800

## Как мигает трубка: сколько секунд горит, прежде чем моргнуть, и узор самого
## моргания — длительности «погасла, зажглась, погасла…».
const STEADY: Vector2 = Vector2(2.5, 6.0)
const BLINKS: Array[float] = [0.06, 0.05, 0.09, 0.12, 0.05]

@export var text: String = "ELACTION":
	set(value):
		text = value
		update_minimum_size()
		queue_redraw()
@export var font_size: int = 132:
	set(value):
		font_size = value
		update_minimum_size()
		queue_redraw()
@export var neon: Color = VerticalSign.NEON_HOTEL
## Какая буква мигает; −1 — ни одна (снимки и тесты). Смена посреди моргания
## зажигает трубку и перерисовывает вывеску: иначе погасшая буква так и
## оставалась бы на снимке тёмной.
@export var flicker_letter: int = 4:
	set(value):
		flicker_letter = value
		_lit = true
		_blink = -1
		queue_redraw()

var _lit: bool = true
var _wait: float = 0.0
var _blink: int = -1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = hash(text)
	_wait = _rng.randf_range(STEADY.x, STEADY.y)


func _get_minimum_size() -> Vector2:
	var font := NeonStyle.font(WEIGHT)
	var bare := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var halo := GLOW[0].x
	return Vector2(bare.x + halo * 2.0, bare.y + halo)


## Горит ли мигающая буква прямо сейчас. Нужно тесту.
func is_letter_lit() -> bool:
	return _lit


func _process(delta: float) -> void:
	# Вывеска видна только на главной странице, а меню живёт и всю партию:
	# мигать невидимой буквой — перерисовывать её впустую.
	if flicker_letter < 0 or not is_visible_in_tree():
		return
	_wait -= delta
	if _wait > 0.0:
		return
	if _blink < 0:
		_blink = 0
	else:
		_blink += 1
	if _blink >= BLINKS.size():
		_blink = -1
		_lit = true
		_wait = _rng.randf_range(STEADY.x, STEADY.y)
	else:
		# Чётный шаг узора гасит трубку, нечётный зажигает.
		_lit = _blink % 2 == 1
		_wait = BLINKS[_blink]
	queue_redraw()


func _draw() -> void:
	var font := NeonStyle.font(WEIGHT)
	var halo := GLOW[0].x
	var baseline := Vector2(halo, halo * 0.5 + font.get_ascent(font_size))
	var core := neon.lerp(Color.WHITE, CORE_TINT)
	var pen := baseline
	for index: int in text.length():
		var letter := text[index]
		var dark := index == flicker_letter and not _lit
		_draw_letter(font, pen, letter, core, dark)
		pen.x += font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


## Одна буква: ореол, трубка и середина. Погасшая — тёмная трубка без ореола,
## как стекло, в котором нет газа.
func _draw_letter(font: Font, at: Vector2, letter: String, core: Color, dark: bool) -> void:
	if dark:
		var glass := Color(neon.darkened(0.7), 0.8)
		draw_string_outline(
			font, at, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, int(TUBE), glass
		)
		draw_string(
			font, at, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.08, 0.06, 0.08)
		)
		return
	for layer: Vector2 in GLOW:
		draw_string_outline(
			font,
			at,
			letter,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			int(layer.x),
			Color(neon, layer.y)
		)
	draw_string_outline(font, at, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, int(TUBE), neon)
	draw_string(font, at, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, core)
