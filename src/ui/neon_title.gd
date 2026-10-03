class_name NeonTitle
extends Control

## The game title as a neon sign (ADR-0035, decision 2).
##
## Draws itself letter by letter: the glow is several outlines with decreasing
## brightness, and on top are the neon-colored tube and its white-hot core. Environment
## glow does not reach 2D, so the halo is drawn rather than set up.
##
## One letter flickers, like on the building sign ([VerticalSign]): a sign whose tubes
## all burn steadily looks like a picture, not a sign.

## Halo layers: outline thickness and its brightness. From outside in.
const GLOW: Array[Vector2] = [Vector2(34.0, 0.05), Vector2(22.0, 0.09), Vector2(12.0, 0.16)]
## Tube: a neon-colored outline around a light core.
const TUBE: float = 5.0
const CORE_TINT: float = 0.72
const WEIGHT: int = 800

## How the tube flickers: how many seconds it burns before blinking, and the pattern of
## the blink itself, durations of "off, on, off...".
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
## Which letter flickers; −1 means none (shots and tests). A change in the middle of a
## blink lights the tube and redraws the sign: otherwise the extinguished letter would
## stay dark in the shot.
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


## Whether the flickering letter is lit right now. Needed by a test.
func is_letter_lit() -> bool:
	return _lit


func _process(delta: float) -> void:
	# The sign is visible only on the main page, but the menu lives through the whole game:
	# flickering an invisible letter means redrawing it for nothing.
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
		# An even pattern step turns the tube off, an odd one turns it on.
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


## One letter: halo, tube and core. An extinguished one is a dark tube without a halo,
## like glass with no gas in it.
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
