shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;

// A city neon sign (M24a, ADR-0037, decision 4): a dark backing,
// a tube along the edge and letters — unreadable, but clearly lettering. The long
// side is the line: on a vertical sign the letters go in a column. Occasionally
// a sign blinks, like neon on its last legs.
//
// A sign smaller than a dozen pixels — the letters merge into an even glow: otherwise
// the strokes of distant signs would flicker as the camera moves.
//
// INSTANCE_CUSTOM.x — sign draw 0–1.

// How much neon is lit, 0–1, and how much daylight (ADR-0051): by day a sign is a board
// with letters, the tubes are pale.
uniform float power = 1.0;
uniform float daylight = 0.0;

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

	// A line of letters along the long side: a cell is a letter of 3×5 strokes.
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
	// The middle of a letter is almost always a stroke: otherwise the lettering came out
	// like a sieve.
	on = max(on, step(abs(stroke.x - 1.0), 0.0) * step(0.3, hash(vec2(index, seed))));
	vec2 within = fract(inner * vec2(3.0, 5.0));
	float pad = 0.18;
	float dot_in = step(pad, within.x) * step(within.x, 1.0 - pad);
	dot_in *= step(pad, within.y) * step(within.y, 1.0 - pad);
	float inside = step(0.0, cell.x) * step(cell.x, letters) * step(0.08, inner.x);
	inside *= step(inner.x, 0.92) * step(0.0, cell.y) * step(cell.y, 1.0);
	float glyph = on * dot_in * inside;

	// A small sign — an even glow instead of strokes.
	float detail = 1.0 - smoothstep(0.04, 0.12, blur / min(size.x, size.y) * 3.0);
	float neon = max(tube, glyph);
	neon = mix(0.55, neon, detail);
	// Every eighth sign blinks.
	float flicker = 1.0;
	if (seed > 0.875) {
		flicker = mix(0.15, 1.0, step(0.12, hash(vec2(floor(TIME * 7.0), seed))));
	}
	vec3 plate = mix(tone * 0.06, vec3(0.16) + tone * 0.1, daylight);
	vec3 lit_tube = mix(tone * 0.5 + 0.2, tone * 2.2, power);
	ALBEDO = mix(plate, lit_tube, neon * mix(1.0, flicker, power));
}
