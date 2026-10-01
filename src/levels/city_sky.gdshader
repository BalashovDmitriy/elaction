shader_type sky;

// Небо города утром, днём и вечером (ADR-0051): от горизонта к зениту, зарево
// у горизонта на стороне солнца и облака. Ночью неба-шейдера нет — фон города
// сплошной цвет погоды, как до M24j.
//
// Город смотрит прямо вглубь, и в кадр попадает полоса неба над горизонтом:
// облака проецируются на плоскость над городом, у горизонта они гуще и мельче.

uniform vec3 zenith : source_color = vec3(0.3, 0.52, 0.86);
uniform vec3 horizon : source_color = vec3(0.74, 0.84, 0.95);
// Зарево на стороне солнца: цвет и сторона — минус слева, плюс справа.
uniform vec3 glow : source_color = vec3(0.0);
uniform float glow_side = 0.0;
// Сколько неба закрыто облаками, 0–1, и их свет и тень.
uniform float cloud_cover = 0.3;
uniform vec3 cloud_light : source_color = vec3(1.0);
uniform vec3 cloud_shade : source_color = vec3(0.7, 0.74, 0.8);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float weight = 0.5;
	for (int octave = 0; octave < 5; octave++) {
		total += noise(p) * weight;
		p = p * 2.03 + vec2(1.7, 9.2);
		weight *= 0.5;
	}
	return total;
}

void sky() {
	vec3 dir = EYEDIR;
	float up = clamp(dir.y, 0.0, 1.0);
	vec3 colour = mix(horizon, zenith, pow(up, 0.5));
	// Зарево солнца: у самого горизонта и к своей стороне.
	float toward = smoothstep(-0.7, 0.9, dir.x * glow_side);
	colour += glow * exp(-up * 7.0) * toward;

	if (cloud_cover > 0.0 && dir.y > 0.005) {
		vec2 at = dir.xz / dir.y * 0.35 + vec2(TIME * 0.003, 0.0);
		float n = fbm(at * vec2(0.6, 1.4));
		float cover = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.3, n);
		// Край облака светлее середины: свет со стороны солнца.
		vec3 cloud = mix(cloud_shade, cloud_light, smoothstep(0.35, 0.85, n));
		cloud += glow * 0.6 * exp(-up * 4.0) * toward;
		colour = mix(colour, cloud, cover * smoothstep(0.005, 0.06, dir.y));
	}
	COLOR = colour;
}
