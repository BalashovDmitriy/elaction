shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, ambient_light_disabled, specular_disabled;

// A rain streak (M24a, ADR-0037, decision 3, addendum): a drop is a tiny lens. It is seen not by
// its own colour but by light: it is lit by the scene lamps — brightest against the light, when the
// lamp is behind it — and carries a blurred copy of what is behind it. In front of windows and neon
// the drops sparkle, in front of a dark sky they vanish.
//
// The quad is turned along the particle velocity
// ([code]TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY[/code]) and shifted back, so the particle itself
// is the head of the streak: the drop dies when it touches the roof, not when the tail reaches it.
// Width and length stretch from the head, and the head stays in place.
//
// Fog does not apply to the drops: adding fog brightened the city twofold. Ambient light neither:
// in a lightning flash it grows several times, and the rain would burn white.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.75, 0.82, 1.0);
// How much lamp light a drop gives off and how much more steeply than the lamp it falls off with
// distance: near a lamp drops glow, a metre beyond its edge — no longer.
uniform float lit_gain = 1.0;
uniform float falloff = 1.0;
// Cap on the light of one lamp: right next to it a drop does not turn white.
uniform float cap = 1.5;
// How much of what is behind it a drop carries, how blurred and shifted by how many pixels —
// refraction.
uniform float back_gain = 1.4;
uniform float back_lod = 2.5;
uniform float back_cap = 2.0;
uniform float refract_px = 6.0;
// A faint sheen of its own: the drop does not vanish completely in the dark.
uniform float base = 0.015;
uniform float opacity = 0.9;
// Share of near drops: wide, soft and pale — out of focus.
uniform float near_share = 0.1;
uniform float scale_len = 1.0;
// Gusts: two running waves of rain density. 0 — even rain.
uniform float gust_amount = 0.0;
uniform float gust_speed = 3.0;

varying float seed;
varying float near;
varying vec3 world;

float hash(float n) {
	return fract(sin(n * 91.3458) * 47453.5453);
}

void vertex() {
	seed = hash(float(INSTANCE_ID) + 0.5);
	float spread = hash(float(INSTANCE_ID) * 1.7 + 3.1);
	near = step(seed, near_share);
	float width = mix(mix(0.5, 1.2, spread), mix(2.5, 4.0, spread), near);
	float length_here = mix(mix(0.55, 1.35, spread), mix(1.3, 1.8, spread), near) * scale_len;
	VERTEX.x *= width;
	VERTEX.y *= length_here;
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;
	float core = exp(-across * across * mix(5.0, 2.5, near));
	// Trail over the frame exposure: almost even along its length, with soft ends.
	float ends = smoothstep(0.0, 0.18, UV.y) * (1.0 - smoothstep(0.72, 1.0, UV.y));
	float fade = mix(mix(0.35, 1.0, hash(seed * 13.0)), 0.25, near);
	float wave = sin(world.x * 0.45 + world.y * 0.12 - TIME * gust_speed);
	float swell = sin(world.x * 0.17 - world.y * 0.05 - TIME * gust_speed * 0.43 + 1.7);
	float gust = clamp(0.55 + 0.35 * wave + 0.3 * swell, 0.0, 1.4);
	float mask = core * ends * fade * opacity * COLOR.a * mix(1.0, gust * gust, gust_amount);
	vec2 pixel = 1.0 / vec2(textureSize(screen, 0));
	vec2 bent = vec2((UV.x - 0.5) * refract_px, -refract_px) * pixel;
	vec3 behind = textureLod(screen, SCREEN_UV + bent, back_lod).rgb;
	ALBEDO = tint;
	EMISSION = min(behind * back_gain, vec3(back_cap)) + tint * base;
	ALPHA = clamp(mask, 0.0, 1.0);
}

void light() {
	float facing = dot(LIGHT, VIEW);
	// A lamp behind the drop (facing toward −1) shines into it much more strongly than from the front.
	float forward = pow(clamp(0.5 - 0.5 * facing, 0.0, 1.0), 3.0);
	float phase = 0.25 + 3.0 * forward;
	vec3 lit = LIGHT_COLOR * pow(ATTENUATION, falloff) * phase * lit_gain / PI;
	DIFFUSE_LIGHT += min(lit, vec3(cap));
}
