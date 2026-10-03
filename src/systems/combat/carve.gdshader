shader_type spatial;
// Material of a figure torn by a cab (ADR-0043, decisions 8, 11 and 12).
//
// Repeats the materials of the pack models — colour, vertex colour, roughness, no
// textures — and discards what the body no longer has: what the cab floor cut off — in
// world coordinates, what a wall tore off — by skin bones.
// The back side is visible in the cut and shown as flesh, not suit colour: faces are not
// culled.
render_mode cull_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform vec3 flesh : source_color = vec3(0.32, 0.02, 0.03);

// Under the floor: between the cab walls along X and above the floor along Y; w — enabled.
instance uniform vec4 carve = vec4(0.0, 0.0, 0.0, 0.0);
// Hidden ragdoll bones (ADR-0043, decision 12): bits of skin bindings,
// 32 per word. A vertex pulled by hidden bones disappears.
instance uniform uvec2 hidden_bones = uvec2(0u, 0u);

varying float gone;

void vertex() {
	gone = 0.0;
	for (int i = 0; i < 4; i++) {
		uint bind = BONE_INDICES[i];
		uint word = bind < 32u ? hidden_bones.x : hidden_bones.y;
		if ((word & (1u << (bind & 31u))) != 0u) {
			gone += BONE_WEIGHTS[i];
		}
	}
}

void fragment() {
	// Any triangle at least one vertex of which is pulled by a hidden bone disappears:
	// interpolation gives more than zero across its whole area. The former threshold
	// "more than half" left half a triangle at the boundary, and that half
	// stretched like rubber from the body to the piece that left with the cab (M24h, ADR-0044,
	// decision 9). Now there is a gap at the boundary, through which the back side — flesh — is
	// visible.
	if (gone > 0.001) {
		discard;
	}
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (carve.w > 0.5 && world.x > carve.x && world.x < carve.y && world.y > carve.z) {
		discard;
	}
	vec3 color = albedo.rgb;
	if (use_vertex_color) {
		color *= COLOR.rgb;
	}
	ALBEDO = FRONT_FACING ? color : flesh;
	ROUGHNESS = roughness;
	SPECULAR = specular;
}
