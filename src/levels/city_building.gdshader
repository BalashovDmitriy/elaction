shader_type spatial;
render_mode cull_back;

// A city house (ADR-0051, decision 10): a box with the baked facade of the Quaternius
// Downtown pack applied ([code]tools/build_city.py[/code]). Atlas — styles in
// columns, rows from top to bottom: cornice, storey, ground floor. Storeys
// repeat from the ground floor to the cornice, the tile — along the facade.
//
// The light is real: the city sun and sky give volume via the normal map, the windows are
// smooth glass reflecting the sky. At night some windows are lit: what is behind a window
// and whether it is lit — by window index and house seed, the city repeats down to a window.
//
// INSTANCE_CUSTOM: x — style (atlas column), y — house seed 0–1.
// COLOR — wall tone: red, pale and brown brick from one style.

uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_atlas : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_atlas : filter_linear_mipmap_anisotropic, repeat_disable;

uniform float styles = 6.0;
uniform float tile_width = 4.0;
// Margin at the sides of a style column in the atlas, m: a continuation of the same tile so
// the neighbouring style does not bleed into the seam at far mips (tools/build_city.py).
uniform float gutter = 0.5;
// Atlas rows, m, and how many atlas pixels per metre — from the build layout.
uniform float top_height = 1.0;
uniform float floor_height = 3.0;
uniform float ground_height = 3.0;
uniform float density = 64.0;
uniform vec2 atlas_size = vec2(1920.0, 448.0);

uniform vec3 roof_colour : source_color = vec3(0.16, 0.16, 0.17);
// Snow on roofs (M24l, ADR-0054): 0 — dry, 1 — roofs under snow, with
// bare patches by noise — by the vents and along the edges the snow melts.
uniform float snow = 0.0;
uniform vec3 snow_colour : source_color = vec3(0.8, 0.83, 0.88);

// Windows: what share is lit, room light strength, lightning flash in the panes.
uniform float lit_share = 0.35;
uniform float window_glow = 2.4;
uniform float flash = 0.0;
uniform vec3 flash_colour : source_color = vec3(0.55, 0.6, 0.75);
// Windows switch on and off (ADR-0043, decision 6).
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
	// Facade basis: x along the facade, y up — this is how the normal map is baked.
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
		if (snow > 0.0) {
			// Bare patches — on a one and a half metre grid, more often at the edge.
			vec2 cell = floor(at.xz / 1.5);
			float bald = hash1(dot(cell, vec2(12.9898, 78.233)) + custom.y * 31.0);
			vec2 edge = min(at.xz, size.xz - at.xz);
			float rim = smoothstep(0.0, 1.2, min(edge.x, edge.y));
			float cover = snow * mix(0.55, 1.0, step(0.18, bald)) * mix(0.6, 1.0, rim);
			ALBEDO = mix(roof_colour, snow_colour, cover);
			ROUGHNESS = mix(0.92, 0.8, cover);
		}
	} else {
		// Where on the facade: s — along, h — height from the ground.
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
		float column = style * (tile_width + gutter * 2.0) + gutter + mod(s, tile_width);
		// Atlas row and height within it, m: ground floor, storey, cornice.
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
		// Derivatives come from continuous coordinates: at a tile seam a fract jump
		// would give a mip from the smallest level — a light line.
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

		// A window is half a tile: the pack modules have two windows per four metres.
		float slot = floor(s / (tile_width * 0.5));
		float seed = custom.y * 977.0 + slot * 13.17 + storey * 71.3 + face.x * 5.1 + face.z * 3.7;
		// The ground floor is shop windows and lobbies: lit more often.
		float share = storey < 0.0 ? lit_share * 1.6 : lit_share;
		float lit = step(hash1(storey < 0.0 ? seed + 0.5 : seed), share);
		if (hash1(seed * 91.7) < switch_share) {
			// A window that switches on and off is lit in each cycle with the same
			// share as the others. Flipping every other time lit half of such
			// windows at any share — by day five times more of the "ones" were lit.
			float period = switch_period * mix(0.5, 1.5, hash1(seed * 17.3));
			float cycle = floor(TIME / period + hash1(seed * 5.9));
			lit = step(hash1(cycle * 13.1 + seed * 71.0), share);
		}
		vec3 warm = vec3(1.0, 0.72, 0.4);
		vec3 cold = vec3(0.6, 0.76, 1.0);
		vec3 room = mix(warm, cold, step(0.72, hash1(seed * 3.3)));
		room *= mix(0.55, 1.15, hash1(seed * 7.1));
		// Room light from the ceiling: brighter at the top of the window.
		room *= mix(1.2, 0.6, clamp(within / floor_height, 0.0, 1.0));
		EMISSION = room * window * lit * window_glow;
		EMISSION += flash_colour * flash * window * 2.0;
	}
}
