shader_type spatial;
// Ореол фары (ADR-0043, решение 5): мягкое пятно у стекла, всегда лицом к
// камере, ярче к середине и сходит на нет к краю. Сияет само и ничего не
// заслоняет.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.9, 0.7, 0.5);

void vertex() {
	// Лицом к камере: плоскость поворачивается вслед за видом.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]
	);
}

void fragment() {
	float away = length(UV - vec2(0.5)) * 2.0;
	float glow = pow(clamp(1.0 - away, 0.0, 1.0), 2.5);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * glow;
}
