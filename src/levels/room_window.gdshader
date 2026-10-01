shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_opaque, shadows_disabled;

// Стекло окна комнаты за дверью (ADR-0047; с M24k — ADR-0052, решение 5):
// прозрачное, и за ним настоящий город — тот же, что за зданием, с фасадами
// пака, небом, погодой и временем суток. Стекло лишь чуть тонирует вид и
// ловит косой блик. У офиса поверх — жалюзи полосами.

uniform vec3 tint : source_color = vec3(0.55, 0.62, 0.7);
uniform float tint_share = 0.12;
uniform float seed = 0.0;
// Жалюзи: 0 — нет, 1 — есть. Доля полосы, закрытая пластиной.
uniform float blinds = 0.0;
uniform float slat_share = 0.55;
uniform vec3 slat : source_color = vec3(0.55, 0.57, 0.6);

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	// Косой блик по стеклу: полоса под углом, своя у каждого окна.
	float sheen = 1.0 - smoothstep(0.0, 0.07, abs(uv.x + uv.y * 0.5 - fract(seed * 0.37) * 1.5));
	vec3 colour = tint;
	float alpha = tint_share + sheen * 0.1;
	if (blinds > 0.5) {
		float band = fract(uv.y * 18.0);
		float cover = step(band, slat_share);
		colour = mix(colour, slat * 0.35, cover);
		alpha = mix(alpha, 1.0, cover);
	}
	ALBEDO = colour;
	ALPHA = alpha;
}
