shader_type spatial;
render_mode cull_back;

// Дом города (ADR-0051, решение 10): коробка, на которую ложится запечённый
// фасад пака Quaternius Downtown ([code]tools/build_city.py[/code]). Атлас —
// стили столбцами, ряды сверху вниз: карниз, этаж, первый этаж. Этажи
// повторяются от первого до карниза, плитка — вдоль фасада.
//
// Свет настоящий: солнце и небо города кладут объём по карте нормалей, окна —
// гладкое стекло, в нём отражается небо. Ночью горит часть окон: что за окно
// и горит ли — по номеру окна и сиду дома, город повторяется до окна.
//
// INSTANCE_CUSTOM: x — стиль (столбец атласа), y — сид дома 0–1.
// COLOR — тон стен: кирпич красный, бледный, бурый из одного стиля.

uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_atlas : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_atlas : filter_linear_mipmap_anisotropic, repeat_disable;

uniform float styles = 6.0;
uniform float tile_width = 4.0;
// Ряды атласа, м, и сколько пикселей атласа на метр — из раскладки сборки.
uniform float top_height = 1.0;
uniform float floor_height = 3.0;
uniform float ground_height = 3.0;
uniform float density = 64.0;
uniform vec2 atlas_size = vec2(1536.0, 448.0);

uniform vec3 roof_colour : source_color = vec3(0.16, 0.16, 0.17);

// Окна: какая доля горит, сила света комнаты, вспышка молнии в стёклах.
uniform float lit_share = 0.35;
uniform float window_glow = 2.4;
uniform float flash = 0.0;
uniform vec3 flash_colour : source_color = vec3(0.55, 0.6, 0.75);
// Окна включаются и выключаются (ADR-0043, решение 6).
uniform float switch_share = 0.14;
uniform float switch_period = 40.0;

varying vec3 local;
varying vec3 size;
varying vec3 face;
varying vec4 custom;
varying vec3 tint;

void vertex() {
	local = VERTEX;
	face = NORMAL;
	size = vec3(
		length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz)
	);
	custom = INSTANCE_CUSTOM;
	tint = COLOR.rgb;
	// Базис фасада: x вдоль фасада, y вверх, — так запечена карта нормалей.
	if (abs(NORMAL.y) > 0.5) {
		TANGENT = vec3(1.0, 0.0, 0.0);
		BINORMAL = vec3(0.0, 0.0, -sign(NORMAL.y));
	} else if (abs(NORMAL.z) > 0.5) {
		TANGENT = vec3(sign(NORMAL.z), 0.0, 0.0);
		BINORMAL = vec3(0.0, 1.0, 0.0);
	} else {
		TANGENT = vec3(0.0, 0.0, -sign(NORMAL.x));
		BINORMAL = vec3(0.0, 1.0, 0.0);
	}
}

float hash1(float n) {
	return fract(sin(n) * 43758.5453123);
}

void fragment() {
	vec3 at = (local + 0.5) * size;
	if (face.y > 0.5) {
		ALBEDO = roof_colour;
		ROUGHNESS = 0.92;
	} else {
		// Где на фасаде: s — вдоль, h — высота от земли.
		float s = at.x;
		if (face.z < -0.5) {
			s = size.x - at.x;
		} else if (face.x > 0.5) {
			s = size.z - at.z;
		} else if (face.x < -0.5) {
			s = at.z;
		}
		float h = at.y;
		float style = clamp(custom.x, 0.0, styles - 1.0);
		float column = style * tile_width + mod(s, tile_width);
		// Ряд атласа и высота внутри него, м: первый этаж, этаж, карниз.
		float row_top = 0.0;
		float within = 0.0;
		float storey = -1.0;
		if (h < ground_height) {
			row_top = top_height + floor_height;
			within = ground_height - h;
		} else if (h > size.y - top_height) {
			row_top = 0.0;
			within = size.y - h;
		} else {
			float above = h - ground_height;
			storey = floor(above / floor_height);
			row_top = top_height;
			within = floor_height - mod(above, floor_height);
		}
		vec2 uv = vec2(column, row_top + within) * density / atlas_size;
		// Производные — от сплошных координат: на шве плитки обрывок fract
		// давал бы мип из самого мелкого уровня — светлую черту.
		vec2 smooth_uv = vec2(s, -h) * density / atlas_size;
		vec2 dx = dFdx(smooth_uv);
		vec2 dy = dFdy(smooth_uv);
		vec4 paint = textureGrad(albedo_atlas, uv, dx, dy);
		vec3 orm = textureGrad(orm_atlas, uv, dx, dy).rgb;
		float window = paint.a;
		ALBEDO = mix(paint.rgb * tint, paint.rgb, window);
		NORMAL_MAP = textureGrad(normal_atlas, uv, dx, dy).rgb;
		AO = orm.r;
		AO_LIGHT_AFFECT = 0.6;
		ROUGHNESS = orm.g;
		METALLIC = orm.b;
		SPECULAR = mix(0.5, 0.8, window);

		// Окно — пол-плитки: у модулей пака по два окна на четыре метра.
		float slot = floor(s / (tile_width * 0.5));
		float seed = custom.y * 977.0 + slot * 13.17 + storey * 71.3 + face.x * 5.1 + face.z * 3.7;
		// Первый этаж — витрины и холлы: горят чаще.
		float share = storey < 0.0 ? lit_share * 1.6 : lit_share;
		float lit = step(hash1(storey < 0.0 ? seed + 0.5 : seed), share);
		if (hash1(seed * 91.7) < switch_share) {
			// Окно, которое включают и выключают, в каждом цикле горит с той же
			// долей, что и прочие. Переворот через раз зажигал половину таких
			// окон при любой доле — днём горело впятеро больше «единиц».
			float period = switch_period * mix(0.5, 1.5, hash1(seed * 17.3));
			float cycle = floor(TIME / period + hash1(seed * 5.9));
			lit = step(hash1(cycle * 13.1 + seed * 71.0), share);
		}
		vec3 warm = vec3(1.0, 0.72, 0.4);
		vec3 cold = vec3(0.6, 0.76, 1.0);
		vec3 room = mix(warm, cold, step(0.72, hash1(seed * 3.3)));
		room *= mix(0.55, 1.15, hash1(seed * 7.1));
		// Свет комнаты с потолка: у верха окна ярче.
		room *= mix(1.2, 0.6, clamp(within / floor_height, 0.0, 1.0));
		EMISSION = room * window * lit * window_glow;
		EMISSION += flash_colour * flash * window * 2.0;
	}
}
