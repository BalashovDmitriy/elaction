shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Завеса дождя между рядами домов города (M24a, ADR-0037, решение 3): полосы
// бегут вниз, каждая своей скоростью и со своим наклоном. Дальняя завеса — в
// дымке города и размыта его расфокусом: частицами на таком расстоянии каждая
// капля была бы мельче пикселя.
//
// Тонкие полосы сглажены по экрану: иначе на ходу камеры они мерцали бы, как
// тонкие окна до M24a.

uniform vec4 tint : source_color = vec4(0.62, 0.68, 0.82, 0.1);
uniform float speed = 24.0;
// Полос на метр по ширине, длина полосы, м, и наклон — снос на метр падения.
uniform float density = 0.9;
uniform float streak = 7.0;
uniform float slant = 0.12;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	float x = world.x + world.y * slant;
	float column = floor(x * density);
	float h = hash(column);
	float within = fract(x * density) - (0.2 + 0.6 * h);
	float width = 0.035 * density + fwidth(x * density) * 1.2;
	float line = 1.0 - smoothstep(0.0, width, abs(within));
	float length_here = streak * (0.6 + h * 0.8);
	float fall = world.y + TIME * speed * (0.85 + 0.3 * h) + h * 97.0;
	float along = fract(fall / length_here);
	float drop = smoothstep(0.0, 0.25, along) * (1.0 - smoothstep(0.55, 1.0, along));
	// Край завесы тает сверху и снизу: у неё нет видимой кромки.
	float edge = smoothstep(0.0, 0.15, UV.y) * (1.0 - smoothstep(0.85, 1.0, UV.y));
	ALBEDO = tint.rgb;
	ALPHA = tint.a * line * drop * edge * (0.5 + 0.5 * hash(column + 3.1));
}
