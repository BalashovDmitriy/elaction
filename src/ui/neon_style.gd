class_name NeonStyle
extends RefCounted

## The interface language is neon noir: dark glass, a neon edge, Exo 2.
##
## One place for the HUD and the menu (ADR-0035, decision 4). While panels lived in [Hud],
## the menu drew its own — with another font and another frame, and two halves of one
## interface looked like two games.

const FONT := preload("res://assets/fonts/Exo2.ttf")

const INK := Color(0.93, 0.94, 0.97)
const INK_DIM := Color(0.62, 0.66, 0.76)
const PLATE := Color(0.03, 0.035, 0.06, 0.62)

## Panel edge width: regular and selected.
const EDGE: int = 3
const EDGE_LIT: int = 6

## Variable Exo 2 faces by weight: one per weight, not one per caption.
static var _fonts: Dictionary = {}
## The same for in-scene text ([method scene_font]) and their common base.
static var _scene_fonts: Dictionary = {}
static var _scene_base: FontFile = null


## Exo 2 of the needed weight: 400 — text, 600 — captions, 700–800 — digits and headings.
static func font(weight: int) -> FontVariation:
	var found: Variant = _fonts.get(weight)
	if found != null:
		return found as FontVariation
	var variation := FontVariation.new()
	variation.base_font = FONT
	variation.variation_opentype = {"wght": weight}
	_fonts[weight] = variation
	return variation


## Exo 2 for in-scene text — signs, indicator boards, shop signs: with mipmaps. The font
## is imported without them, and small or distant text in 3D flickered; enabling them
## in the import would soften the whole HUD and menu too, which are drawn at their own
## size. So mipmaps are only on the copy for the scene (ADR-0053, decision 9).
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


## HUD panel: glass [param background], an edge on the left and a glow in colour [param neon].
## A menu item glows brighter and smoothly — its style is built by [MenuRow] from the same
## [constant EDGE] and [constant EDGE_LIT].
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


## Caption: Exo 2 of the needed weight and size, with a shadow under the text.
static func label(font_size: int, colour: Color, weight: int) -> Label:
	var made := Label.new()
	made.add_theme_font_override("font", font(weight))
	made.add_theme_font_size_override("font_size", font_size)
	made.add_theme_color_override("font_color", colour)
	made.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	made.add_theme_constant_override("shadow_offset_y", 2)
	made.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return made
