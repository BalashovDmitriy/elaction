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
## То же для надписей в сцене ([method scene_font]) и их общая основа.
static var _scene_fonts: Dictionary = {}
static var _scene_base: FontFile = null


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


## Exo 2 для надписей в сцене — табличек, табло, вывесок: с мипмапами. Шрифт
## импортирован без них, и мелкая или дальняя надпись в 3D мерцала; включить их
## в импорте — значит смягчить и весь HUD с меню, которые рисуются в свой
## размер. Поэтому мипмапы — только у копии для сцены (ADR-0053, решение 9).
static func scene_font(weight: int) -> FontVariation:
	var found: Variant = _scene_fonts.get(weight)
	if found != null:
		return found as FontVariation
	if _scene_base == null:
		_scene_base = FONT.duplicate() as FontFile
		_scene_base.generate_mipmaps = true
	var variation := FontVariation.new()
	variation.base_font = _scene_base
	variation.variation_opentype = {"wght": weight}
	_scene_fonts[weight] = variation
	return variation


## Плашка HUD: стекло [param background], кромка слева и ореол в цвет [param neon].
## Пункт меню горит ярче и плавно — его стиль собирает [MenuRow] по тем же
## [constant EDGE] и [constant EDGE_LIT].
static func plate(background: Color, neon: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.set_corner_radius_all(8)
	box.border_width_left = EDGE
	box.border_color = Color(neon, 0.9)
	box.shadow_color = Color(neon, 0.18)
	box.shadow_size = 14
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
