shader_type spatial;
// Материал фигуры, которую порвала кабина (ADR-0043, решения 8 и 11).
//
// Повторяет материалы моделей пака — цвет, цвет вершин, шероховатость, без
// фактур — и отбрасывает то, чего у тела больше нет, в координатах мира.
// Изнанка видна в срезе и показывается мясом, а не цветом костюма: грани не
// отсекаются.
render_mode cull_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform vec3 flesh : source_color = vec3(0.32, 0.02, 0.03);

// Под днищем: между стенками кабины по X и выше днища по Y; w — включён ли.
instance uniform vec4 carve = vec4(0.0, 0.0, 0.0, 0.0);
// Разрыв по стенке: от тела осталась только полоса X между x и y; w — включён ли.
instance uniform vec4 keep = vec4(0.0, 0.0, 0.0, 0.0);

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (carve.w > 0.5 && world.x > carve.x && world.x < carve.y && world.y > carve.z) {
		discard;
	}
	if (keep.w > 0.5 && (world.x < keep.x || world.x > keep.y)) {
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
