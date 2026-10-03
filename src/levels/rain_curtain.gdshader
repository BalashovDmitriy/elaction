shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Rain curtain between the rows of the city's houses (M24a, ADR-0037, decision 3, addendum): thin
// streaks run down, each at its own speed. They have almost no colour of their own — the curtain is
// visible only where it is bright behind it: windows, neon, the glow of streets, a lightning flash.
// Like rain shot against the light: on a dark sky it is not there.
//
// There are two layers of streaks of different frequency, the density drifts in slow gusts. The
// thin streaks are antialiased in screen space: otherwise they would flicker as the camera moves,
// like the thin windows before M24a. Fog does not apply to the curtain — adding fog brightened the
// city.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.75, 0.82, 1.0);
// How much of the light behind it the curtain carries, and its own faint sheen.
uniform float gain = 3.0;
uniform float base = 0.015;
uniform float speed = 24.0;
// Streaks per metre of width, streak length, m, and slant — drift per metre of fall.
uniform float density = 0.9;
uniform float streak = 3.0;
uniform float slant = 0.12;
// How blurred the light behind the curtain is.
uniform float lod = 3.0;
// Cap: in a lightning flash the curtain does not burn white.
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
	// The curtain's edge fades at the top and bottom: it has no visible rim.
	float edge = smoothstep(0.0, 0.15, UV.y) * (1.0 - smoothstep(0.85, 1.0, UV.y));
	vec3 behind = textureLod(screen, SCREEN_UV, lod).rgb;
	ALBEDO = (min(behind * gain, vec3(cap)) + tint * base) * rain * gust * edge;
}
