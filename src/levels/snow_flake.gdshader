shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, ambient_light_disabled;

// Хлопок снега (M24l, ADR-0054): не круглая точка, а рыхлый комок из
// нескольких мягких сгустков — у каждого хлопка свой, — который медленно
// крутится и покачивается в полёте. Светится он светом сцены: от ламп и
// солнца, ярче всего против света, когда лампа за ним, а без света — слабым
// светом неба ([param ambient]). Ближние хлопья — крупные, мягкие и бледные:
// не в фокусе.
//
// Квад повёрнут к камере здесь, а не в материале частиц: поворот хлопка и
// покачивание считаются в плоскости экрана.

uniform vec3 tint : source_color = vec3(0.93, 0.95, 1.0);
// Свет неба на хлопке без ламп: ночью мал, днём велик.
uniform float ambient = 0.6;
// Сколько света ламп и солнца хлопок отдаёт и потолок одной лампы.
uniform float lit_gain = 0.4;
uniform float cap = 0.7;
uniform float opacity = 0.8;
// Доля ближних хлопьев: втрое крупнее, мягче и бледнее.
uniform float near_share = 0.08;
// Покачивание: размах, м, и частота, Гц; вращение, оборотов в секунду.
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
	// Покачивание — в плоскости экрана: квад к камере, его x — вбок кадра.
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

// Мягкий сгусток с серединой [param at] и радиусом [param size].
float blob(vec2 uv, vec2 at, float size) {
	float d = length(uv - at) / size;
	return exp(-d * d * 2.5);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	// Комок из пяти сгустков вокруг середины: где густо, где рыхло.
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
	// Край мягкий: жёсткий порог на хлопке в десяток пикселей давал крошку
	// с резкими краями — конфетти, а не снег.
	shape = mix(smoothstep(0.05, 0.85, shape), shape, near);
	ALBEDO = tint;
	EMISSION = tint * ambient;
	ALPHA = clamp(shape * edge * opacity * soft * COLOR.a, 0.0, 1.0);
}

void light() {
	float facing = dot(LIGHT, VIEW);
	// Лампа за хлопком (facing к −1) просвечивает его сильнее, чем спереди.
	float forward = pow(clamp(0.5 - 0.5 * facing, 0.0, 1.0), 2.0);
	float phase = 0.35 + 1.8 * forward;
	vec3 lit = LIGHT_COLOR * ATTENUATION * phase * lit_gain / PI;
	DIFFUSE_LIGHT += min(lit, vec3(cap));
}
