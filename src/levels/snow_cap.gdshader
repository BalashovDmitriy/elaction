shader_type spatial;
render_mode blend_mix, depth_draw_never, specular_disabled;

// Snow on a car (M24l, ADR-0054): an overlay material on top of the body. White
// falls on everything facing up — roof, bonnet, boot — with a ragged
// edge by noise in the car's axes: the snow rides with it rather than sliding over it like
// a decal in the world.

uniform vec3 colour : source_color = vec3(0.84, 0.87, 0.92);
// From what tilt a face is already under snow: 1 — only horizontal.
uniform float threshold = 0.62;
// How much snow lies: 1 — a cap, less — a dusting through which the paint shows.
uniform float amount = 1.0;

varying vec3 world_normal;
varying vec3 local_at;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	local_at = VERTEX;
}

void fragment() {
	float up = normalize(world_normal).y;
	float cover = smoothstep(threshold, threshold + 0.2, up);
	float grain = hash(floor(local_at * 9.0));
	cover *= mix(0.65, 1.0, grain);
	ALBEDO = colour;
	ROUGHNESS = 0.85;
	ALPHA = cover * 0.95 * amount;
}
