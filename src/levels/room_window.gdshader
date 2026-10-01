shader_type spatial;
render_mode unshaded, cull_back;

// Окно комнаты за дверью (ADR-0047): город за стеклом. Небо — градиент, по
// низу — силуэты домов жребием по столбцам, в домах — окна, горящие жребием.
// У офиса поверх — жалюзи полосами. Цвета и доля горящих окон — по времени
// суток и погоде (ADR-0052, решение 5): днём небо светлое, дома в свету.

uniform vec3 sky_top : source_color = vec3(0.02, 0.03, 0.08);
uniform vec3 sky_low : source_color = vec3(0.1, 0.09, 0.2);
uniform vec3 block : source_color = vec3(0.015, 0.018, 0.03);
uniform vec3 lit : source_color = vec3(1.0, 0.78, 0.45);
uniform float lit_share = 0.38;
uniform float seed = 0.0;
// Жалюзи: 0 — нет, 1 — есть. Доля полосы, закрытая пластиной.
uniform float blinds = 0.0;
uniform float slat_share = 0.55;
uniform vec3 slat : source_color = vec3(0.55, 0.57, 0.6);
uniform float glow = 1.4;

float hash(vec2 p) {
	return fract(sin(dot(p + seed, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	vec3 colour = mix(sky_low, sky_top, smoothstep(0.1, 1.0, uv.y));
	// Дома: столбцы по ширине, высота — жребий.
	float columns = 7.0;
	float column = floor(uv.x * columns);
	float top = 0.25 + 0.55 * hash(vec2(column, 3.0));
	if (uv.y < top) {
		colour = block;
		vec2 cell = vec2(uv.x * columns * 4.0, uv.y * 22.0);
		vec2 id = floor(cell);
		vec2 inside = fract(cell);
		float on = step(1.0 - lit_share, hash(id));
		float pane = step(0.2, inside.x) * step(inside.x, 0.8) * step(0.25, inside.y) * step(inside.y, 0.75);
		colour = mix(colour, lit * (0.6 + 0.4 * hash(id + 7.0)), on * pane);
	}
	colour *= glow;
	if (blinds > 0.5) {
		float band = fract(uv.y * 18.0);
		float cover = step(band, slat_share);
		colour = mix(colour, slat * 0.35, cover);
	}
	ALBEDO = colour;
}
