shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Lamp halo in rain (M24a, ADR-0037, decision 3, addendum): a soft glow around the lamp, broken
// into falling streaks — rain lit by the lamp. Drawn rather than computed as fog: the background
// behind the roof is the city canvas, and the building's volumetric fog does not fall on it. That
// way the halo exists at any quality level, even on low, where there is no fog.

uniform vec3 colour : source_color = vec3(0.72, 0.78, 0.95);
uniform float strength = 0.25;
uniform float slant = 0.08;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	vec2 centre = (UV - 0.5) * 2.0;
	centre.y *= 0.8;
	float r = length(centre);
	float glow = exp(-r * r * 4.0);
	float x = (world.x + world.y * slant) * 14.0;
	float h = hash(floor(x));
	float line = exp(-pow((fract(x) - 0.5) / 0.18, 2.0));
	float fall = fract((world.y + TIME * 17.0 * (0.8 + 0.4 * h) + h * 50.0) / (1.2 + h));
	float streak = smoothstep(0.0, 0.15, fall) * (1.0 - smoothstep(0.35, 0.55, fall));
	float rain = 0.25 + 0.75 * line * streak;
	ALBEDO = colour * strength * glow * rain;
}
