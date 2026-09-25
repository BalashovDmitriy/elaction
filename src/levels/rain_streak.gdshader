shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Струя дождя (M24a, ADR-0037, решение 3): тонкая, светлая у головы и тающая
// к хвосту — след капли за выдержку кадра. Квад повёрнут по скорости частицы
// ([code]TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY[/code]) и сдвинут назад,
// так что сама частица — голова струи: капля гаснет, коснувшись крыши, а не
// когда хвост дошёл до неё.
//
// У лампы над крышей капли светлеют: дождь виден там, где на него падает свет.
// Прозрачность частицы — из её цвета: у каждой капли своя.

uniform vec4 tint : source_color = vec4(0.7, 0.78, 0.95, 0.3);
// Насколько струя мягкая поперёк: 0 — жёсткий край, 1 — вся размыта.
uniform float softness : hint_range(0.0, 1.0) = 0.7;
uniform vec3 glow_at = vec3(0.0, -10000.0, 0.0);
uniform vec3 glow_colour : source_color = vec3(0.0);
uniform float glow_range = 1.0;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Верх квада — по скорости, то есть голова струи.
	float head = 1.0 - UV.y;
	float across = abs(UV.x - 0.5) * 2.0;
	float width = mix(0.45, 1.0, head);
	float core = 1.0 - smoothstep(width * (1.0 - softness), width, across);
	float trail = pow(head, 1.4);
	vec3 offset = world - glow_at;
	float glow = glow_range * glow_range / (glow_range * glow_range + dot(offset, offset));
	ALBEDO = tint.rgb * COLOR.rgb + glow_colour * glow;
	ALPHA = clamp(tint.a * COLOR.a * core * trail * (1.0 + glow * 1.5), 0.0, 1.0);
}
