shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_opaque, shadows_disabled;

// Glass of the room window behind a door (ADR-0047; since M24k, ADR-0052, decision 5):
// transparent, and behind it is the real city, the same one as behind the building, with
// the pack's facades, sky, weather and time of day. The glass only slightly tints the view
// and catches a slanted glint. Offices get blinds in stripes on top.

uniform vec3 tint : source_color = vec3(0.55, 0.62, 0.7);
uniform float tint_share = 0.12;
uniform float seed = 0.0;
// Blinds: 0 means none, 1 means present. Fraction of a stripe covered by a slat.
uniform float blinds = 0.0;
uniform float slat_share = 0.55;
uniform vec3 slat : source_color = vec3(0.55, 0.57, 0.6);

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	// Slanted glint on the glass: a band at an angle, different for every window.
	float sheen = 1.0 - smoothstep(0.0, 0.07, abs(uv.x + uv.y * 0.5 - fract(seed * 0.37) * 1.5));
	vec3 colour = tint;
	float alpha = tint_share + sheen * 0.1;
	if (blinds > 0.5) {
		float band = fract(uv.y * 18.0);
		float cover = step(band, slat_share);
		colour = mix(colour, slat * 0.35, cover);
		alpha = mix(alpha, 1.0, cover);
	}
	ALBEDO = colour;
	ALPHA = alpha;
}
