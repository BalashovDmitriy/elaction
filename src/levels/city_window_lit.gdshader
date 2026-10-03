shader_type spatial;
// Lit city windows: past the haze — the lights of the night city do not drown in it.
render_mode unshaded, fog_disabled, cull_back;

#include "res://src/levels/city_window.gdshaderinc"
