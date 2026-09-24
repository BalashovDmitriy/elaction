class_name NeonStyle
extends RefCounted

## Язык интерфейса — неон-нуар: тёмное стекло, неоновая кромка, Exo 2.
##
## Одно место на HUD и меню (ADR-0035, решение 4). Пока плашки жили в [Hud],
## меню рисовало свои — другим шрифтом и другой рамкой, и две половины одного
## интерфейса выглядели двумя играми.

const FONT := preload("res://assets/fonts/Exo2.ttf")

const INK := Color(0.93, 0.94, 0.97)
const INK_DIM := Color(0.62, 0.66, 0.76)
const PLATE := Color(0.03, 0.035, 0.06, 0.62)

## Ширина кромки плашки: обычной и выбранной.
const EDGE: int = 3
const EDGE_LIT: int = 6

## Начертания переменного Exo 2 по весу: одно на вес, а не на каждую подпись.
static var _fonts: Dictionary = {}


## Exo 2 нужного веса: 400 — текст, 600 — подписи, 700–800 — цифры и заголовки.
static func font(weight: int) -> FontVariation:
	var found: Variant = _fonts.get(weight)
	if found != null:
		return found as FontVariation
	var variation := FontVariation.new()
	variation.base_font = FONT
	variation.variation_opentype = {"wght": weight}
	_fonts[weight] = variation
	return variation


## Плашка: стекло [param background], кромка слева и ореол в цвет [param neon].
## Выбранная ([param lit]) — кромка шире и ореол ярче: так видно, где фокус.
static func plate(background: Color, neon: Color, lit: bool = false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.set_corner_radius_all(8)
	box.border_width_left = EDGE_LIT if lit else EDGE
	box.border_color = Color(neon, 1.0 if lit else 0.9)
	box.shadow_color = Color(neon, 0.34 if lit else 0.18)
	box.shadow_size = 18 if lit else 14
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 10
	box.content_margin_bottom = 12
	return box


## Подпись: Exo 2 нужного веса и кегля, с тенью под текстом.
static func label(font_size: int, colour: Color, weight: int) -> Label:
	var made := Label.new()
	made.add_theme_font_override("font", font(weight))
	made.add_theme_font_size_override("font_size", font_size)
	made.add_theme_color_override("font_color", colour)
	made.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	made.add_theme_constant_override("shadow_offset_y", 2)
	made.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return made
