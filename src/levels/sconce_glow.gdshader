shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

// Sconce spot on the wall (ADR-0048): an elongated oval, brighter at the shade and
// softly fading to nothing toward the edge. Added to the wall — the sconce has no light
// source.

uniform vec4 tint : source_color = vec4(1.0, 0.72, 0.4, 0.55);

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float fall = 1.0 - smoothstep(0.0, 1.0, length(p));
	ALBEDO = tint.rgb * tint.a * fall * fall;
}
