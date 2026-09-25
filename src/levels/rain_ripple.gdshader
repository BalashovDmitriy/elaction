shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Круг на луже (M24a, ADR-0037, решение 3): кольцо расходится от места удара
// и гаснет, за ним — второе, поменьше. Квад лежит на настиле; возраст —
// доля жизни частицы.

uniform vec4 tint : source_color = vec4(0.62, 0.7, 0.9, 0.16);

varying float age;

void vertex() {
	age = INSTANCE_CUSTOM.y;
}

float ring(float radius, float at) {
	float width = 0.05 + fwidth(radius) * 1.5;
	return 1.0 - smoothstep(0.0, width, abs(radius - at));
}

void fragment() {
	float radius = length(UV - 0.5) * 2.0;
	float grow = sqrt(age);
	float rings = ring(radius, grow) + ring(radius, grow * 0.55) * 0.5;
	float fade = (1.0 - age) * step(radius, 1.0);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * rings * fade * COLOR.a;
}
