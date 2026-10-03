shader_type sky;

// The city sky is a Poly Haven HDRI panorama (ADR-0051, decision 11), rotated so that
// its sun stands where the city's sunlight is ([CitySky]). As its own shader rather than
// the engine's panorama: that way the rotation is set by one fraction of a turn from a
// known direction, without guessing where the seam faces.

uniform sampler2D panorama : filter_linear, repeat_enable;
uniform float energy = 1.0;
// Panorama shift around the circle, fraction of a turn.
uniform float shift = 0.0;
// Lightning flash: the whole sky brightens.
uniform float flash = 0.0;

void sky() {
	vec3 dir = normalize(EYEDIR);
	// Azimuth from "straight into the city" (minus z) to the right, toward plus x.
	float azimuth = atan(dir.x, -dir.z);
	float u = fract(azimuth / TAU + shift);
	float v = acos(clamp(dir.y, -1.0, 1.0)) / PI;
	COLOR = texture(panorama, vec2(u, v)).rgb * energy * (1.0 + flash * 3.0);
}
