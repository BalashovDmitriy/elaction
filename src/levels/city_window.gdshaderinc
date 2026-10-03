// A city window (M24a, ADR-0037, decision 4): a frame and mullions, and life behind
// the glass. A lit window — ceiling light and a lamp, blinds, curtains, a person in
// the room, the flicker of a TV or a fluorescent tube; a dark one — dark glass
// with the reflected sky and a slanted glint.
//
// What is behind the window is decided by the window's lot ([CityLook.window_custom]),
// not by the shader: the city repeats by seed down to the window. [CityBackdrop] writes it.
//
// INSTANCE_CUSTOM: x — the window's lot 0–1, y — what is behind the glass
// ([CityLook.Inside]), z — mullions (0 — none, 1 — a post, 2 — a cross), w — whether lit.

uniform vec3 frame_colour : source_color = vec3(0.012, 0.014, 0.02);
// Lightning flash: dark panes light up with the reflected sky.
uniform float flash = 0.0;
uniform vec3 flash_colour : source_color = vec3(0.55, 0.6, 0.75);
// Windows switch on and off (M24g, ADR-0043, decision 6): this share of windows, by
// their own lot, changes state once per their own period — a lit one goes dark, a dark
// one lights up. The period is from half to one and a half [code]switch_period[/code], s.
uniform float switch_share = 0.14;
uniform float switch_period = 40.0;
// What a dark window lights up with: it has no room colour of its own.
uniform vec3 switch_tone : source_color = vec3(0.95, 0.72, 0.42);
// How many times darker than its own light the glass of a dark window is.
const float SWITCHED_OFF = 0.06;

varying vec4 custom;
varying vec3 tone;

void vertex() {
	custom = INSTANCE_CUSTOM;
	tone = COLOR.rgb;
}

float hash1(float n) {
	return fract(sin(n) * 43758.5453123);
}

// A band of [param width] around zero, smoothed in screen space.
float bar(float distance, float width) {
	float blur = fwidth(distance);
	return 1.0 - smoothstep(width, width + blur * 1.5, abs(distance));
}

// Whether the window is switched now: 1 — opposite to its own state. The lot is the
// window's, not the frame's: the city repeats by seed even in who turns the light off when.
float switched(float seed) {
	if (hash1(seed * 91.7) > switch_share) {
		return 0.0;
	}
	float period = switch_period * mix(0.5, 1.5, hash1(seed * 17.3));
	float cycle = floor(TIME / period + hash1(seed * 5.9));
	return step(0.5, hash1(cycle * 13.1 + seed * 71.0));
}

vec3 lit_room(vec2 uv, float seed, float inside, vec3 light) {
	vec3 c = light;
	// Ceiling light and a lamp's spot: a room, not a flat fill.
	float ceiling = mix(1.2, 0.72, uv.y);
	float lamp_x = mix(0.25, 0.75, fract(seed * 7.13));
	float lamp = exp(-pow((uv.x - lamp_x) * 3.2, 2.0) - pow((uv.y - 0.1) * 3.0, 2.0)) * 0.45;
	c *= ceiling + lamp;
	if (inside < 0.5) {
		return c;
	}
	if (inside < 1.5) {
		// Blinds lowered to their own height.
		float drawn = mix(0.3, 1.0, fract(seed * 13.7));
		float slat = 0.5 + 0.5 * step(0.42, fract(uv.y * 15.0));
		return c * (uv.y < drawn ? slat * 0.85 : 1.0);
	}
	if (inside < 2.5) {
		// Curtains at the sides with folds, warm against the light.
		float open = mix(0.12, 0.38, fract(seed * 5.31));
		float edge = min(uv.x, 1.0 - uv.x);
		float drape = 1.0 - smoothstep(open - 0.04, open, edge);
		float fold = 0.78 + 0.22 * sin(uv.x * 55.0 + seed * 9.0);
		vec3 cloth = c * mix(vec3(1.0, 0.62, 0.45), vec3(0.7, 0.8, 1.0), step(0.6, seed)) * 0.6;
		return mix(c, cloth * fold, drape);
	}
	if (inside < 3.5) {
		// A person in the room: head and shoulders against the light.
		float px = mix(0.3, 0.7, fract(seed * 11.3));
		float head = 1.0 - smoothstep(0.075, 0.095, length((uv - vec2(px, 0.46)) * vec2(1.0, 0.8)));
		float shoulders = 1.0 - smoothstep(0.17, 0.19, abs(uv.x - px) + max(0.62 - uv.y, 0.0) * 3.0);
		float body = max(head, shoulders * step(0.56, uv.y));
		return c * (1.0 - 0.82 * body);
	}
	if (inside < 4.5) {
		// A TV: blue light that breathes and jumps.
		float t = TIME * (4.0 + seed * 3.0);
		float flick = 0.6 + 0.2 * sin(t) * sin(t * 2.7 + seed * 20.0);
		flick += 0.25 * hash1(floor(TIME * 5.0) + seed * 100.0);
		return mix(c * 0.3, vec3(0.42, 0.6, 1.0) * flick, 0.75);
	}
	// A fluorescent tube about to burn out.
	float on = step(0.1, hash1(floor(TIME * 9.0) + seed * 57.0));
	return mix(vec3(0.82, 0.93, 1.0), c, 0.35) * mix(0.2, 1.0, on);
}

vec3 dark_glass(vec2 uv, float seed, vec3 base) {
	vec3 c = base;
	// Sky in the glass at the top and a slanted glint.
	c += vec3(0.018, 0.022, 0.034) * (1.0 - uv.y);
	float sheen = 1.0 - smoothstep(0.0, 0.08, abs(uv.x + uv.y * 0.6 - fract(seed * 3.7) * 1.6));
	c += vec3(0.02, 0.024, 0.036) * sheen;
	return c + flash_colour * flash * 4.0 * (0.4 + 0.6 * (1.0 - uv.y));
}

void fragment() {
	vec2 uv = UV;
	float seed = custom.x;
	float lit = custom.w;
	// A window smaller than ten pixels loses its frame and mullions: thin lines
	// would shimmer as the camera moves.
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
	float was_lit = lit;
	if (switched(seed) > 0.5) {
		lit = 1.0 - lit;
	}
	// A window lit by itself shines its own colour, a dark one that lit up — warm.
	vec3 light = was_lit > 0.5 ? tone : switch_tone;
	// A lit one that went dark is dark glass, not a room of its colour.
	vec3 base = was_lit > 0.5 ? tone * SWITCHED_OFF : tone;
	vec3 glass = lit > 0.5 ? lit_room(uv, seed, custom.y, light) : dark_glass(uv, seed, base);
	float cover = max(frame, bars) * detail;
	ALBEDO = mix(glass, frame_colour, cover);
}
