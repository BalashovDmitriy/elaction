shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, ambient_light_disabled, specular_disabled;

// Струя дождя (M24a, ADR-0037, решение 3, дополнение): капля — крошечная
// линза. Её видно не своим цветом, а светом: она светится от ламп сцены — ярче
// всего против света, когда лампа за ней, — и несёт размытую копию того, что
// за ней. Перед окнами и неоном капли искрят, перед тёмным небом пропадают.
//
// Квад повёрнут по скорости частицы ([code]TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY[/code])
// и сдвинут назад, так что сама частица — голова струи: капля гаснет,
// коснувшись крыши, а не когда хвост дошёл до неё. Ширина и длина растягиваются
// от головы, и голова остаётся на месте.
//
// Туман на капли не ложится: сложение с туманом высветляло город вдвое.
// Окружающий свет тоже: во вспышке молнии он растёт в разы, и дождь горел бы
// белым.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.75, 0.82, 1.0);
// Сколько света ламп капля отдаёт и насколько круче лампы он гаснет с
// расстоянием: у лампы капли светятся, в метре за её краем — уже нет.
uniform float lit_gain = 1.0;
uniform float falloff = 1.0;
// Потолок света одной лампы: вплотную к ней капля не становится белой.
uniform float cap = 1.5;
// Сколько капля несёт того, что за ней, насколько размыто и со сдвигом на
// сколько пикселей — преломление.
uniform float back_gain = 1.4;
uniform float back_lod = 2.5;
uniform float back_cap = 2.0;
uniform float refract_px = 6.0;
// Собственный слабый блеск: капля не пропадает совсем в темноте.
uniform float base = 0.015;
uniform float opacity = 0.9;
// Доля ближних капель: широких, мягких и бледных — не в фокусе.
uniform float near_share = 0.1;
uniform float scale_len = 1.0;
// Порывы: две бегущие волны густоты дождя. 0 — дождь ровный.
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
	// След за выдержку кадра: почти ровный по длине, с мягкими концами.
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
	// Лампа за каплей (facing к −1) светит в неё куда сильнее, чем спереди.
	float forward = pow(clamp(0.5 - 0.5 * facing, 0.0, 1.0), 3.0);
	float phase = 0.25 + 3.0 * forward;
	vec3 lit = LIGHT_COLOR * pow(ATTENUATION, falloff) * phase * lit_gain / PI;
	DIFFUSE_LIGHT += min(lit, vec3(cap));
}
