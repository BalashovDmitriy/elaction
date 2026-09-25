shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;

// Неоновая вывеска города (M24a, ADR-0037, решение 4): тёмная подложка,
// трубка по краю и буквы — не прочесть, но видно, что это надпись. Длинная
// сторона — строка: у вертикальной вывески буквы идут столбиком. Изредка
// вывеска мигает, как неон на последнем издыхании.
//
// Вывеска мельче десятка пикселей — буквы сливаются в ровное свечение: иначе
// штрихи дальних вывесок мерцали бы на ходу камеры.
//
// INSTANCE_CUSTOM.x — жребий вывески 0–1.

varying vec3 tone;
varying float seed;
varying vec2 size;

void vertex() {
	tone = COLOR.rgb;
	seed = INSTANCE_CUSTOM.x;
	size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 at = UV * size;
	vec2 edge = min(at, size - at);
	float inset = min(size.x, size.y) * 0.12;
	float blur = max(fwidth(at.x), fwidth(at.y));
	float tube = 1.0 - smoothstep(0.05, 0.05 + blur * 1.5, abs(min(edge.x, edge.y) - inset));

	// Строка букв вдоль длинной стороны: ячейка — буква 3×5 штрихов.
	bool upright = size.y > size.x;
	vec2 run = upright ? vec2(at.y, at.x) : at;
	vec2 span = upright ? size.yx : size;
	float margin = span.y * 0.28;
	float letter_width = (span.y - margin * 2.0) * 0.72;
	float letters = max(floor((span.x - margin * 2.0) / letter_width), 1.0);
	float start = (span.x - letters * letter_width) * 0.5;
	vec2 cell = vec2((run.x - start) / letter_width, (run.y - margin) / (span.y - margin * 2.0));
	float index = floor(cell.x);
	vec2 inner = vec2(fract(cell.x), cell.y);
	vec2 stroke = floor(inner * vec2(3.0, 5.0));
	float on = step(0.42, hash(vec2(index + seed * 31.0, stroke.x * 7.0 + stroke.y)));
	// Середина буквы — почти всегда штрих: иначе надпись выходила решетом.
	on = max(on, step(abs(stroke.x - 1.0), 0.0) * step(0.3, hash(vec2(index, seed))));
	vec2 within = fract(inner * vec2(3.0, 5.0));
	float pad = 0.18;
	float dot_in = step(pad, within.x) * step(within.x, 1.0 - pad);
	dot_in *= step(pad, within.y) * step(within.y, 1.0 - pad);
	float inside = step(0.0, cell.x) * step(cell.x, letters) * step(0.08, inner.x);
	inside *= step(inner.x, 0.92) * step(0.0, cell.y) * step(cell.y, 1.0);
	float glyph = on * dot_in * inside;

	// Мелкая вывеска — ровное свечение вместо штрихов.
	float detail = 1.0 - smoothstep(0.04, 0.12, blur / min(size.x, size.y) * 3.0);
	float neon = max(tube, glyph);
	neon = mix(0.55, neon, detail);
	// Мигает каждая восьмая вывеска.
	float flicker = 1.0;
	if (seed > 0.875) {
		flicker = mix(0.15, 1.0, step(0.12, hash(vec2(floor(TIME * 7.0), seed))));
	}
	vec3 plate = tone * 0.06;
	ALBEDO = mix(plate, tone * 2.2, neon * flicker);
}
