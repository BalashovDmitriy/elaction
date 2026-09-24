class_name Vignette
extends CanvasLayer

## Лёгкая виньетка: края кадра чуть темнее, взгляд идёт к середине, где Otto
## (ADR-0030, решение 3). Зерна нет — на погашенных этажах оно шумело бы там,
## где игрок и так всматривается.
##
## Слой между сценой и HUD ([constant LAYER] ниже слоя HUD): интерфейс виньетка
## не затемняет.

## Слой холста: над сценой, под HUD (у него 3) и меню (5).
const LAYER: int = 2

## Насколько темнеют углы, 0–1, и с какой доли радиуса начинается затемнение.
const STRENGTH: float = 0.38
const START: float = 0.45

const SHADER := """
shader_type canvas_item;
uniform float strength = 0.38;
uniform float start = 0.45;
void fragment() {
	vec2 centre = UV - vec2(0.5);
	// Кадр широкий: по высоте затемнение сильнее, чем по ширине, иначе верх и
	// низ почти не темнели бы.
	centre.x *= 0.8;
	float edge = smoothstep(start, 0.75, length(centre) * 1.4);
	COLOR = vec4(0.0, 0.0, 0.0, edge * strength);
}
"""


func _ready() -> void:
	layer = LAYER
	var rect := ColorRect.new()
	rect.name = "Shade"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("strength", STRENGTH)
	material.set_shader_parameter("start", START)
	rect.material = material
	add_child(rect)
