shader_type spatial;

// Cast concrete of the garage exit (M24b): the tunnel wall and the ramp's retaining
// wall. A bare pour across half the frame read as unfinished construction, so the wall has
// what a real one has: formwork panels with seams, rows of tie holes,
// pour bands, streaks from the top, damp at the floor and stains. Everything is computed by
// world position, without textures of its own: the grain is the shaft concrete texture
// ([BuildingFinish.shaft_concrete]).
//
// A wet wall (rain) is darker and smoother — lights catch in it.

uniform vec3 tone : source_color = vec3(0.5);
uniform sampler2D grain : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grain_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float grain_repeat = 1.6;
// Formwork panel, m: pour width and height.
uniform vec2 panel = vec2(2.4, 1.2);
// Tie pitch, m, and their radius.
uniform vec2 tie_step = vec2(0.6, 0.6);
uniform float tie_radius = 0.022;
// Top and bottom of the wall in the scene, m: streaks run from the top, damp at the bottom.
uniform float top_y = 1.0;
uniform float bottom_y = 0.0;
// How wet the wall is: 0 — dry, 1 — in rain.
uniform float wetness = 0.0;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// A thin line of width [param width] around zero, smoothed in screen space.
float line(float distance, float width) {
	float blur = fwidth(distance);
	return 1.0 - smoothstep(width, width + blur * 1.5, abs(distance));
}

void fragment() {
	vec2 at = world.xy;
	vec2 uv = at / grain_repeat;
	vec3 colour = texture(grain, uv).rgb * tone;

	// Stains: concrete from different batches.
	float blotch = noise(at * 0.9) * 0.6 + noise(at * 3.1) * 0.4;
	colour *= mix(0.82, 1.12, blotch);

	// Panels: vertical seams, horizontal pour bands, a slight tone shift
	// from panel to panel.
	vec2 cell = floor(at / panel);
	colour *= mix(0.92, 1.06, hash(cell));
	float joint = line((fract(at.x / panel.x + 0.5) - 0.5) * panel.x, 0.012);
	float pour = line((fract(at.y / panel.y + 0.5) - 0.5) * panel.y, 0.006);
	colour *= 1.0 - joint * 0.55 - pour * 0.25;

	// Ties: a dark dot with a rim on a grid inside the panel.
	vec2 tie = (fract(at / tie_step) - 0.5) * tie_step;
	float hole = 1.0 - smoothstep(tie_radius, tie_radius + fwidth(at.x) * 1.5, length(tie));
	float rim = 1.0 - smoothstep(tie_radius * 2.2, tie_radius * 2.8, length(tie));
	colour *= 1.0 - hole * 0.6 + (rim - hole) * 0.08;

	// Streaks from the top: bands of different length, wandering slightly along x.
	float wobble = (noise(vec2(at.y * 2.0, at.x)) - 0.5) * 0.06;
	float column = floor((at.x + wobble) / 0.23);
	float reach = mix(0.2, 1.9, hash(vec2(column, 3.0)));
	float strength = step(0.35, hash(vec2(column, 7.0))) * mix(0.15, 0.4, hash(vec2(column, 11.0)));
	float below = top_y - at.y;
	float streak = strength * (1.0 - smoothstep(0.0, reach, below)) * step(0.0, below);
	colour *= 1.0 - streak;

	// Damp at the floor: a dark edge with a ragged border.
	float damp_height = 0.25 + noise(vec2(at.x * 1.7, 0.0)) * 0.35;
	float damp = 1.0 - smoothstep(0.0, damp_height, at.y - bottom_y);
	colour *= 1.0 - damp * 0.35;

	float wet = clamp(wetness, 0.0, 1.0);
	ALBEDO = colour * mix(1.0, 0.6, wet);
	NORMAL_MAP = texture(grain_normal, uv).rgb;
	ROUGHNESS = mix(0.92, 0.35, wet) + joint * 0.05;
	METALLIC = 0.0;
}
