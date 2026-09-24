class_name HudIcon
extends Control

## Значок HUD, нарисованный кодом: жизнь — силуэт головы и плеч, документ —
## папка. Картинок нет: значок растёт с разрешением без лесенки, а цвет берёт
## из кромки HUD — розовый у отеля, голубой у офиса.

enum Kind { LIFE, DOCUMENT }

var kind: Kind = Kind.LIFE
## Горит ли значок: жизнь есть, документ собран. Погасший — контур.
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


## Голова и плечи: круг над трапецией.
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


## Папка с язычком; у собранной — галочка.
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
