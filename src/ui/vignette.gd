class_name Vignette
extends CanvasLayer

## A light vignette: the frame edges are slightly darker, the eye goes to the middle, where Otto is
## (ADR-0030, decision 3). No grain — on darkened floors it would be noisy exactly where
## the player is already peering.
##
## A layer between the scene and the HUD ([constant LAYER] below the HUD layer): the vignette
## does not darken the interface.

## Canvas layer: above the scene, below the HUD (it has 3) and the menu (5).
const LAYER: int = 2

## How much the corners darken, 0–1, and from what fraction of the radius darkening starts.
const STRENGTH: float = 0.38
const START: float = 0.45

const SHADER := """
shader_type canvas_item;
uniform float strength = 0.38;
uniform float start = 0.45;
void fragment() {
	vec2 centre = UV - vec2(0.5);
	// The frame is wide: darkening is stronger along the height than the width, otherwise
	// the top and bottom would barely darken.
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
