// Окно города (M24a, ADR-0037, решение 4): рама и переплёт, а за стеклом —
// жизнь. Горящее окно — свет с потолка и лампа, жалюзи, шторы, человек в
// комнате, мерцание телевизора или лампы дневного света; погасшее — тёмное
// стекло с отражённым небом и косым бликом.
//
// Что за окном, решает жребий окна ([CityLook.window_custom]), а не шейдер:
// город по сиду повторяется до окна. Пишет в него [CityBackdrop].
//
// INSTANCE_CUSTOM: x — жребий окна 0–1, y — что за стеклом ([CityLook.Inside]),
// z — переплёт (0 — нет, 1 — стойка, 2 — крест), w — горит ли окно.

uniform vec3 frame_colour : source_color = vec3(0.012, 0.014, 0.02);
// Вспышка молнии: погасшие стёкла загораются отражённым небом.
uniform float flash = 0.0;
uniform vec3 flash_colour : source_color = vec3(0.55, 0.6, 0.75);

varying vec4 custom;
varying vec3 tone;

void vertex() {
	custom = INSTANCE_CUSTOM;
	tone = COLOR.rgb;
}

float hash1(float n) {
	return fract(sin(n) * 43758.5453123);
}

// Полоса шириной [param width] вокруг нуля, сглаженная по экрану.
float bar(float distance, float width) {
	float blur = fwidth(distance);
	return 1.0 - smoothstep(width, width + blur * 1.5, abs(distance));
}

vec3 lit_room(vec2 uv, float seed, float inside) {
	vec3 c = tone;
	// Свет с потолка и пятно лампы: комната, а не заливка.
	float ceiling = mix(1.2, 0.72, uv.y);
	float lamp_x = mix(0.25, 0.75, fract(seed * 7.13));
	float lamp = exp(-pow((uv.x - lamp_x) * 3.2, 2.0) - pow((uv.y - 0.1) * 3.0, 2.0)) * 0.45;
	c *= ceiling + lamp;
	if (inside < 0.5) {
		return c;
	}
	if (inside < 1.5) {
		// Жалюзи, опущенные до своей высоты.
		float drawn = mix(0.3, 1.0, fract(seed * 13.7));
		float slat = 0.5 + 0.5 * step(0.42, fract(uv.y * 15.0));
		return c * (uv.y < drawn ? slat * 0.85 : 1.0);
	}
	if (inside < 2.5) {
		// Шторы по бокам со складками, тёплые на просвет.
		float open = mix(0.12, 0.38, fract(seed * 5.31));
		float edge = min(uv.x, 1.0 - uv.x);
		float drape = 1.0 - smoothstep(open - 0.04, open, edge);
		float fold = 0.78 + 0.22 * sin(uv.x * 55.0 + seed * 9.0);
		vec3 cloth = c * mix(vec3(1.0, 0.62, 0.45), vec3(0.7, 0.8, 1.0), step(0.6, seed)) * 0.6;
		return mix(c, cloth * fold, drape);
	}
	if (inside < 3.5) {
		// Человек в комнате: голова и плечи против света.
		float px = mix(0.3, 0.7, fract(seed * 11.3));
		float head = 1.0 - smoothstep(0.075, 0.095, length((uv - vec2(px, 0.46)) * vec2(1.0, 0.8)));
		float shoulders = 1.0 - smoothstep(0.17, 0.19, abs(uv.x - px) + max(0.62 - uv.y, 0.0) * 3.0);
		float body = max(head, shoulders * step(0.56, uv.y));
		return c * (1.0 - 0.82 * body);
	}
	if (inside < 4.5) {
		// Телевизор: голубой свет, который дышит и перескакивает.
		float t = TIME * (4.0 + seed * 3.0);
		float flick = 0.6 + 0.2 * sin(t) * sin(t * 2.7 + seed * 20.0);
		flick += 0.25 * hash1(floor(TIME * 5.0) + seed * 100.0);
		return mix(c * 0.3, vec3(0.42, 0.6, 1.0) * flick, 0.75);
	}
	// Лампа дневного света, которая вот-вот перегорит.
	float on = step(0.1, hash1(floor(TIME * 9.0) + seed * 57.0));
	return mix(vec3(0.82, 0.93, 1.0), c, 0.35) * mix(0.2, 1.0, on);
}

vec3 dark_glass(vec2 uv, float seed) {
	vec3 c = tone;
	// Небо в стекле сверху и косой блик.
	c += vec3(0.018, 0.022, 0.034) * (1.0 - uv.y);
	float sheen = 1.0 - smoothstep(0.0, 0.08, abs(uv.x + uv.y * 0.6 - fract(seed * 3.7) * 1.6));
	c += vec3(0.02, 0.024, 0.036) * sheen;
	return c + flash_colour * flash * 4.0 * (0.4 + 0.6 * (1.0 - uv.y));
}

void fragment() {
	vec2 uv = UV;
	float seed = custom.x;
	float lit = custom.w;
	// Окно мельче десятка пикселей — рама и переплёт тают: тонкие линии
	// мерцали бы на ходу камеры.
	float detail = 1.0 - smoothstep(0.05, 0.14, max(fwidth(uv.x), fwidth(uv.y)));
	vec2 edge = min(uv, 1.0 - uv);
	float frame = 1.0 - smoothstep(0.06, 0.06 + fwidth(uv.x) * 1.5, min(edge.x * 1.25, edge.y));
	float bars = 0.0;
	if (custom.z > 0.5) {
		bars = bar(uv.x - 0.5, 0.025);
	}
	if (custom.z > 1.5) {
		bars = max(bars, bar(uv.y - 0.34, 0.02));
	}
	vec3 glass = lit > 0.5 ? lit_room(uv, seed, custom.y) : dark_glass(uv, seed);
	float cover = max(frame, bars) * detail;
	ALBEDO = mix(glass, frame_colour, cover);
}
