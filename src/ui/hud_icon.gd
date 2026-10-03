class_name HudIcon
extends Control

## A HUD icon drawn in code: a life is a silhouette of head and shoulders, a document is a folder.
## There are no pictures: the icon scales with resolution without jaggies, and takes its colour from
## the HUD trim — pink for the hotel, light blue for the office.

enum Kind { LIFE, DOCUMENT }

var kind: Kind = Kind.LIFE
## Whether the icon is lit: the life exists, the document is collected. A dim one is an outline.
var lit: bool = true
var colour := Color.WHITE


static func make(icon_kind: Kind, size_px: float) -> HudIcon:
	var icon := HudIcon.new()
	icon.kind = icon_kind
	icon.custom_minimum_size = Vector2(size_px, size_px)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func set_state(on: bool, tint: Color) -> void:
	if on == lit and tint == colour:
		return
	lit = on
	colour = tint
	queue_redraw()


func _draw() -> void:
	var fill := colour if lit else Color(colour, 0.0)
	var edge := colour if lit else Color(colour, 0.45)
	match kind:
		Kind.LIFE:
			_draw_life(fill, edge)
		Kind.DOCUMENT:
			_draw_document(fill, edge)


## Head and shoulders: a circle above a trapezoid.
func _draw_life(fill: Color, edge: Color) -> void:
	var s := size
	var head := Vector2(s.x * 0.5, s.y * 0.3)
	var radius := s.x * 0.2
	var shoulders := PackedVector2Array(
		[
			Vector2(s.x * 0.12, s.y * 0.95),
			Vector2(s.x * 0.22, s.y * 0.6),
			Vector2(s.x * 0.78, s.y * 0.6),
			Vector2(s.x * 0.88, s.y * 0.95),
		]
	)
	if fill.a > 0.0:
		draw_circle(head, radius, fill)
		draw_colored_polygon(shoulders, fill)
	draw_arc(head, radius, 0.0, TAU, 24, edge, 2.0, true)
	var outline := shoulders.duplicate()
	outline.append(shoulders[0])
	draw_polyline(outline, edge, 2.0, true)


## A folder with a tab; a collected one has a check mark.
func _draw_document(fill: Color, edge: Color) -> void:
	var s := size
	var folder := PackedVector2Array(
		[
			Vector2(s.x * 0.08, s.y * 0.22),
			Vector2(s.x * 0.4, s.y * 0.22),
			Vector2(s.x * 0.48, s.y * 0.32),
			Vector2(s.x * 0.92, s.y * 0.32),
			Vector2(s.x * 0.92, s.y * 0.85),
			Vector2(s.x * 0.08, s.y * 0.85),
		]
	)
	if fill.a > 0.0:
		draw_colored_polygon(folder, fill)
		var tick := PackedVector2Array(
			[
				Vector2(s.x * 0.3, s.y * 0.58),
				Vector2(s.x * 0.45, s.y * 0.72),
				Vector2(s.x * 0.72, s.y * 0.44)
			]
		)
		draw_polyline(tick, Color(0.05, 0.05, 0.08), 3.0, true)
	var outline := folder.duplicate()
	outline.append(folder[0])
	draw_polyline(outline, edge, 2.0, true)
