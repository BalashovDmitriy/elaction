shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

// Пятно бра на стене (ADR-0048): вытянутый овал, ярче у абажура и мягко
// сходящий на нет к краю. Прибавляется к стене — источника света у бра нет.

uniform vec4 tint : source_color = vec4(1.0, 0.72, 0.4, 0.55);

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float fall = 1.0 - smoothstep(0.0, 1.0, length(p));
	ALBEDO = tint.rgb * tint.a * fall * fall;
}
