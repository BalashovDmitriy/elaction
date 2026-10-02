shader_type spatial;
render_mode blend_mix, depth_draw_never, specular_disabled;

// Снег на машине (M24l, ADR-0054): накладной материал поверх кузова. Белое
// ложится на всё, что смотрит вверх, — крышу, капот, багажник, — с рваным
// краем по шуму в осях машины: снег едет с ней, а не скользит по ней, как
// наклейка в мире.

uniform vec3 colour : source_color = vec3(0.84, 0.87, 0.92);
// С какого наклона грань уже под снегом: 1 — только горизонталь.
uniform float threshold = 0.62;

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
	ALPHA = cover * 0.95;
}
