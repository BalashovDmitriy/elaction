shader_type spatial;
// Материал фигуры, которую порвала кабина (ADR-0043, решения 8, 11 и 12).
//
// Повторяет материалы моделей пака — цвет, цвет вершин, шероховатость, без
// фактур — и отбрасывает то, чего у тела больше нет: срезанное днищем — в
// координатах мира, оторванное стенкой — по костям скина.
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
// Спрятанные кости рэгдолла (ADR-0043, решение 12): биты привязок скина, по
// 32 в слове. Вершина, которую тянут спрятанные кости, пропадает.
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
	// Пропадает всякий треугольник, хоть одну вершину которого тянет спрятанная
	// кость: интерполяция даёт больше нуля по всей его площади. Прежний порог
	// «больше половины» оставлял полтреугольника на границе, и эта половина
	// тянулась резиной от тела до куска, уехавшего с кабиной (M24h, ADR-0044,
	// решение 9). На границе теперь щель, в неё видно изнанку — мясо.
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
