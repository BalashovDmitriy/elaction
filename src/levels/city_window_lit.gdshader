shader_type spatial;
// Горящие окна города: мимо дымки — огни ночного города не тонут в ней.
render_mode unshaded, fog_disabled, cull_back;

#include "res://src/levels/city_window.gdshaderinc"
