shader_type spatial;

// Грунт разрезом под пандусом и улицей (M24b): пласты разного тона с рваными
// границами и камни в них. Ровная тёмная заливка читалась дырой в кадре; разрез
// с пластами читается землёй, как разрез здания — зданием.
//
// Пласты считаются от уровня улицы вниз ([member street_y], сцена): под
// асфальтом — щебёночная подушка, ниже — суглинок, глина и снова суглинок.

uniform vec3 tone : source_color = vec3(0.085, 0.075, 0.068);
uniform float street_y = 0.0;

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

void fragment() {
	vec2 at = world.xy;
	float depth = street_y - at.y + (noise(vec2(at.x * 0.8, 1.0)) - 0.5) * 0.35;
	// Пласты: подушка светлее, глина — рыжее, суглинок — тёмный.
	vec3 colour = tone;
	colour = mix(colour, tone * vec3(1.9, 1.8, 1.7), 1.0 - smoothstep(0.35, 0.45, depth));
	float clay = smoothstep(1.4, 1.55, depth) * (1.0 - smoothstep(2.6, 2.75, depth));
	colour = mix(colour, tone * vec3(1.45, 1.1, 0.8), clay);
	// Зерно и камни: мелкие светлые пятна, в подушке — гуще.
	float grain = noise(at * 22.0);
	colour *= mix(0.85, 1.12, grain);
	vec2 cell = floor(at * 5.0);
	vec2 inner = fract(at * 5.0) - 0.5;
	float stone_here = step(depth < 0.45 ? 0.55 : 0.88, hash(cell));
	float stone = stone_here * (1.0 - smoothstep(0.16, 0.24, length(inner * vec2(1.0, 1.4))));
	colour = mix(colour, tone * 2.2, stone * 0.7);
	ALBEDO = colour;
	ROUGHNESS = 1.0;
}
