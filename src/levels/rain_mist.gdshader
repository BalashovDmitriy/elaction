shader_type fog;

// Дымка дождя над крышей (M24a, ADR-0037, решение 3, дополнение): у настила
// гуще — там водяная пыль брызг, — и по ней медленно идут косые полосы
// порывов, так что воздух не ровный. Светят в неё лампы сцены через объёмный
// туман: у лампы на крыше в дожде виден конус.
//
// Дымка тонкая и к задней стене тает: гуще — и она проявила бы плоские щиты
// позади крыши.

uniform float density = 0.009;
// Во сколько раз гуще у самого настила и на какой высоте это сходит на нет, м.
uniform float deck_boost = 4.0;
uniform float deck_height = 1.2;
uniform float deck_y = 0.0;
// Где задняя кромка дымки по глубине и за сколько метров от неё она густеет.
uniform float back_z = -3.3;
uniform float back_fade = 3.0;
uniform vec3 albedo : source_color = vec3(0.8, 0.85, 1.0);

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

void fog() {
	vec3 p = WORLD_POSITION;
	float above = p.y - deck_y;
	float spray = exp(-max(above, 0.0) / deck_height) * deck_boost;
	vec3 q = p * vec3(0.35, 0.18, 0.5) + vec3(TIME * 0.35, TIME * 1.1, 0.0);
	float gust = noise(q) * 0.7 + noise(q * 2.3) * 0.3;
	float thick = density * (0.35 + 1.3 * gust) * (1.0 + spray);
	float sides = smoothstep(0.0, 0.2, UVW.x) * smoothstep(1.0, 0.8, UVW.x);
	float top = smoothstep(1.0, 0.85, UVW.y);
	float back = mix(0.3, 1.0, smoothstep(back_z, back_z + back_fade, p.z));
	DENSITY = thick * sides * top * back;
	ALBEDO = albedo;
}
