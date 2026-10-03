shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, ambient_light_disabled;

// A snowflake (M24l, ADR-0054): not a round dot but a loose clump of several soft
// blobs, each flake with its own, which slowly spins and sways in flight. It is lit by
// the scene's light: from lamps and the sun, brightest against the light, when a lamp is
// behind it, and with no light, by the faint sky light ([param ambient]). Near flakes are
// large, soft and pale: out of focus.
//
// The quad is turned to the camera here, not in the particle material: the flake's
// rotation and sway are computed in the screen plane.

uniform vec3 tint : source_color = vec3(0.93, 0.95, 1.0);
// Sky light on a flake with no lamps: small at night, large by day.
uniform float ambient = 0.6;
// How much lamp and sun light a flake gives back, and the cap for one lamp.
uniform float lit_gain = 0.4;
uniform float cap = 0.7;
uniform float opacity = 0.8;
// Share of near flakes: three times larger, softer and paler.
uniform float near_share = 0.08;
// Sway: amplitude, m, and frequency, Hz; rotation, turns per second.
uniform float sway = 0.12;
uniform float sway_rate = 0.7;
uniform float spin = 0.25;

varying float seed;
varying float near;

float hash(float n) {
	return fract(sin(n * 91.3458) * 47453.5453);
}

void vertex() {
	seed = hash(float(INSTANCE_ID) + 0.5);
	near = step(seed, near_share);
	float grow = mix(mix(0.7, 1.3, hash(seed * 7.1)), 3.0, near);
	float turn = seed * TAU + TIME * spin * mix(-1.0, 1.0, hash(seed * 3.3));
	VERTEX.xy = mat2(vec2(cos(turn), sin(turn)), vec2(-sin(turn), cos(turn))) * VERTEX.xy * grow;
	// Sway is in the screen plane: the quad faces the camera, its x is sideways in the frame.
	float phase = TIME * sway_rate * mix(0.7, 1.3, hash(seed * 5.7)) * TAU + seed * 40.0;
	float scale = max(length(MODEL_MATRIX[0].xyz), 0.0001);
	VERTEX.x += sin(phase) * sway / scale;
	VERTEX.y += sin(phase * 0.5 + 1.3) * sway * 0.3 / scale;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]
	);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(scale, 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

// A soft blob with center [param at] and radius [param size].
float blob(vec2 uv, vec2 at, float size) {
	float d = length(uv - at) / size;
	return exp(-d * d * 2.5);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	// A clump of five blobs around the center: dense in places, loose in others.
	float body = blob(uv, vec2(0.0), mix(0.38, 0.5, hash(seed * 2.1)));
	for (int index = 0; index < 4; index++) {
		float n = seed * 17.0 + float(index) * 3.7;
		float angle = hash(n) * TAU;
		float reach = mix(0.18, 0.48, hash(n + 1.1));
		vec2 at = vec2(cos(angle), sin(angle)) * reach;
		body += blob(uv, at, mix(0.16, 0.32, hash(n + 2.3))) * mix(0.5, 1.0, hash(n + 4.9));
	}
	float edge = 1.0 - smoothstep(0.75, 1.0, length(uv));
	float soft = mix(1.0, 0.45, near);
	float shape = clamp(body, 0.0, 1.0);
	// The edge is soft: a hard threshold on a flake ten pixels across gave crumbs with sharp
	// edges, confetti rather than snow.
	shape = mix(smoothstep(0.05, 0.85, shape), shape, near);
	ALBEDO = tint;
	EMISSION = tint * ambient;
	ALPHA = clamp(shape * edge * opacity * soft * COLOR.a, 0.0, 1.0);
}

void light() {
	float facing = dot(LIGHT, VIEW);
	// A lamp behind the flake (facing toward −1) shines through it more than from the front.
	float forward = pow(clamp(0.5 - 0.5 * facing, 0.0, 1.0), 2.0);
	float phase = 0.35 + 1.8 * forward;
	vec3 lit = LIGHT_COLOR * ATTENUATION * phase * lit_gain / PI;
	DIFFUSE_LIGHT += min(lit, vec3(cap));
}
