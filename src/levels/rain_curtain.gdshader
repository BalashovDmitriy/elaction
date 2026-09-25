shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Завеса дождя между рядами домов города (M24a, ADR-0037, решение 3,
// дополнение): тонкие полосы бегут вниз, каждая своей скоростью. Своего цвета
// у них почти нет — завесу видно только там, где за ней светло: окна, неон,
// зарево улиц, вспышка молнии. Как дождь, снятый против света: на тёмном небе
// его нет.
//
// Полос два слоя разной частоты, густота гуляет медленными порывами. Тонкие
// полосы сглажены по экрану: иначе на ходу камеры они мерцали бы, как тонкие
// окна до M24a. Туман на завесу не ложится — сложение с туманом высветляло
// город.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.75, 0.82, 1.0);
// Сколько завеса несёт света за ней и собственный слабый блеск.
uniform float gain = 3.0;
uniform float base = 0.015;
uniform float speed = 24.0;
// Полос на метр по ширине, длина полосы, м, и наклон — снос на метр падения.
uniform float density = 0.9;
uniform float streak = 3.0;
uniform float slant = 0.12;
// Насколько размыт свет за завесой.
uniform float lod = 3.0;
// Потолок: во вспышке молнии завеса не горит белым.
uniform float cap = 1.5;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

float strands(float scale, float seed) {
	float x = (world.x + world.y * slant) * density * scale + seed;
	float column = floor(x);
	float h = hash(column + seed * 7.0);
	float within = fract(x) - (0.2 + 0.6 * h);
	float width = 0.05 + fwidth(x) * 1.2;
	float line = 1.0 - smoothstep(0.0, width, abs(within));
	float length_here = streak * (0.5 + h) / scale;
	float fall = world.y + TIME * speed * (0.85 + 0.3 * h) + h * 97.0;
	float along = fract(fall / (length_here * 3.0));
	float drop = smoothstep(0.0, 0.1, along) * (1.0 - smoothstep(0.25, 0.33, along));
	return line * drop * (0.4 + 0.6 * hash(column + 3.1));
}

void fragment() {
	float gust = 0.55 + 0.45 * sin(world.x * 0.03 + world.y * 0.01 - TIME * 0.7) * sin(world.x * 0.011 + TIME * 0.23);
	float rain = strands(1.0, 0.0) + strands(1.9, 5.3) * 0.6;
	// Край завесы тает сверху и снизу: у неё нет видимой кромки.
	float edge = smoothstep(0.0, 0.15, UV.y) * (1.0 - smoothstep(0.85, 1.0, UV.y));
	vec3 behind = textureLod(screen, SCREEN_UV, lod).rgb;
	ALBEDO = (min(behind * gain, vec3(cap)) + tint * base) * rain * gust * edge;
}
