shader_type canvas_item;

// Игра за паузой: размытая и притушенная, чтобы меню читалось поверх неё
// (ADR-0035, решение 1). Размытие — mip-уровнем экранной текстуры: дёшево и
// без второго прохода.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float blur : hint_range(0.0, 6.0) = 3.2;
uniform vec4 tint : source_color = vec4(0.02, 0.025, 0.05, 0.62);

void fragment() {
	vec3 behind = textureLod(screen, SCREEN_UV, blur).rgb;
	COLOR = vec4(mix(behind, tint.rgb, tint.a), 1.0);
}
