shader_type spatial;
render_mode unshaded, cull_back;

// Фасад дома города (M24a, ADR-0037, решение 4): межэтажные пояса, простенки
// между колонками окон, подоконники, карниз наверху и светлое ребро угла —
// дом читается домом, а не тёмной коробкой. Всё считается по месту на фасаде,
// без фактур: сетка окон та же, что у [CityPlan.window_grid].
//
// Зарево улиц подсвечивает фасад снизу и гаснет кверху. Мелкая деталь тает,
// когда фасад в кадре мельче пикселя, — иначе тонкие линии дальних рядов
// мерцали бы на ходу камеры.

uniform vec2 window_step = vec2(2.4, 3.2);
// Высота окна по типу дома ([CityLook.WINDOW_SIZES]): по ней подоконник.
uniform vec4 window_heights = vec4(1.5);
uniform vec3 street_glow : source_color = vec3(1.0, 0.55, 0.25);
uniform float glow_height = 34.0;
uniform float glow_strength = 0.05;

varying vec3 local;
varying vec3 size;
varying vec3 tint;
varying float kind;

void vertex() {
	local = VERTEX;
	size = vec3(
		length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz)
	);
	tint = COLOR.rgb;
	kind = INSTANCE_CUSTOM.x;
}

// Тонкая линия шириной [param width] вокруг нуля, сглаженная по экрану.
float line(float distance, float width) {
	float blur = fwidth(distance);
	return 1.0 - smoothstep(width, width + blur * 1.5, abs(distance));
}

void fragment() {
	vec3 base = tint;
	vec2 at = (local.xy + 0.5) * size.xy;
	float front = step(0.49, local.z);
	float side = step(0.49, abs(local.x));
	float roof = step(0.49, local.y);

	// Сколько метров фасада в пикселе: по ней тает мелкая деталь.
	float metres = max(fwidth(at.x), fwidth(at.y));
	float detail = 1.0 - smoothstep(0.08, 0.3, metres);

	// Этажи: окна по центру на высоте шага, пояса — на полпути между ними.
	float row = at.y / window_step.y;
	float between = fract(row) - 0.5;
	float band = line(between * window_step.y, 0.16);
	// Подоконник — под окном, на полвысоты окна ниже его середины.
	float height = window_heights[int(clamp(kind, 0.0, 3.0))];
	float bottom = 0.5 - height * 0.5 / window_step.y;
	float sill = line((fract(row - bottom) - 0.5) * window_step.y, 0.04);

	// Колонки: сетка окон по середине фасада, простенки — между окнами.
	float columns = max(floor(size.x / window_step.x) - 1.0, 1.0);
	float left = size.x * 0.5 - (columns - 1.0) * window_step.x * 0.5;
	float column = (at.x - left) / window_step.x;
	float pier = line((fract(column + 0.5) - 0.5) * window_step.x, 0.22);
	float inside = step(left - window_step.x * 0.5, at.x)
		* step(at.x, size.x - left + window_step.x * 0.5);

	// Стекло стеновой панели у стеклянных башен — тонкая сетка стоек.
	float glass = step(1.5, kind) * step(kind, 2.5);
	float mullion = line((fract(at.x / 1.2) - 0.5) * 1.2, 0.03) * glass;

	// Карниз наверху и ребро угла: небо ловится гранью, и силуэт отделяется
	// от дома позади.
	float cornice = 1.0 - smoothstep(0.0, 1.0, size.y - at.y);
	float under = line(size.y - at.y - 1.25, 0.08);
	float corner = 1.0 - smoothstep(0.0, 0.45, min(at.x, size.x - at.x));

	vec3 colour = base;
	colour *= 1.0 + detail * (band * 0.7 + sill * 1.2 + pier * inside * 0.22 + mullion * 1.0);
	colour *= 1.0 - under * 0.5 * detail;
	colour += base * (cornice * 1.6 + corner * 0.9);
	// Зарево улиц снизу.
	colour += street_glow * glow_strength * exp(-at.y / glow_height);

	// Бок дома темнее лица, крыша — ещё темнее.
	colour = mix(colour, base * 0.7, side * (1.0 - front));
	colour = mix(colour, base * 0.6, roof);
	ALBEDO = colour;
}
