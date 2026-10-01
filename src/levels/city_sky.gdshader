shader_type sky;

// Небо города — HDRI-панорама Poly Haven (ADR-0051, решение 11), повёрнутая
// так, чтобы её солнце стояло там же, где свет солнца города ([CitySky]).
// Своим шейдером, а не панорамой движка: так поворот задаётся одной долей
// оборота от известного направления, без угадывания, куда смотрит шов.

uniform sampler2D panorama : filter_linear, repeat_enable;
uniform float energy = 1.0;
// Сдвиг панорамы по кругу, доля оборота.
uniform float shift = 0.0;
// Вспышка молнии: небо светлеет целиком.
uniform float flash = 0.0;

void sky() {
	vec3 dir = normalize(EYEDIR);
	// Азимут от «прямо в город» (минус z) направо, к плюс x.
	float azimuth = atan(dir.x, -dir.z);
	float u = fract(azimuth / TAU + shift);
	float v = acos(clamp(dir.y, -1.0, 1.0)) / PI;
	COLOR = texture(panorama, vec2(u, v)).rgb * energy * (1.0 + flash * 3.0);
}
