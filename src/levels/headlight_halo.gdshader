shader_type spatial;
// Headlight halo (ADR-0043, decision 5): a soft spot at the glass, always facing the
// camera, brighter toward the middle and fading out toward the edge. It glows on its own
// and occludes nothing.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.9, 0.7, 0.5);

void vertex() {
	// Facing the camera: the plane turns to follow the view.
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
