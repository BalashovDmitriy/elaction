class_name RainLook
extends RefCounted

## The look of rain: streaks, splashes, ripples on puddles, curtains and the lamp halo
## (M24a, ADR-0037, decision 3). Shared by the roof ([RoofRain]) and the city
## ([CityBackdrop]): rain has one look, and building it twice would make the drops
## diverge at the first edit.
##
## A drop glows not with its own colour but with light (decision 3, amendment — the
## user's choice by shots): from the scene's lamps, brighter against the light, and it
## carries a blurred copy of what is behind it. In front of windows and neon the rain
## sparkles, in front of a dark sky it vanishes — like rain in a photograph of a city
## at night.
##
## A streak is a quad turned along the particle's velocity, shifted backward: the
## particle is the head of the streak. A drop killed by collision dies with its head on
## the roof, and the tail does not go under the deck.

const STREAK_SHADER := preload("res://src/levels/rain_streak.gdshader")
const RIPPLE_SHADER := preload("res://src/levels/rain_ripple.gdshader")
const CURTAIN_SHADER := preload("res://src/levels/rain_curtain.gdshader")
const HALO_SHADER := preload("res://src/levels/rain_halo.gdshader")

## Rain colour: cold, like the sky light over the city.
const TINT := Color(0.75, 0.82, 1.0)

## Spread of drop direction, degrees: rain does not fall in formation.
const SPREAD: float = 1.5

## The name under which the particles store the drop count on "High": by it
## [method scale_amount] recomputes the share by quality level.
const FULL := &"full_amount"

## Rain layers in the city, from the city camera into depth (ADR-0037, decision 3): how
## many drops, how much farther than the camera the layer's middle is and the
## half-depth, m, streak size. Near ones are large, far ones thin, in the city haze.
## There are one and a half times more drops than the streaks of their own colour had:
## only part of them is visible — the part against windows.
const CITY_LAYERS: Array[Dictionary] = [
	{"drops": 420, "depth": 22.0, "reach": 10.0, "size": Vector2(0.07, 2.4)},
	{"drops": 1120, "depth": 52.0, "reach": 18.0, "size": Vector2(0.04, 1.6)},
	{"drops": 960, "depth": 110.0, "reach": 30.0, "size": Vector2(0.06, 2.2)},
]
## City streaks: there are no lamps in the city, drops carry only the light behind
## them — four times over.
const CITY_DROP := {
	"lit_gain": 0.0, "back_gain": 4.0, "back_lod": 2.0, "base": 0.01, "opacity": 0.8
}
## Drop speed in the city, m/s, and drift per metre of fall.
const CITY_SPEED := Vector2(22.0, 27.0)
const CITY_SLANT: float = 0.14

## Curtains between rows of houses: depth, how much of the light behind them they carry,
## stripes per metre.
const CURTAINS: Array[Vector3] = [
	Vector3(86.0, 3.0, 0.9),
	Vector3(130.0, 3.0, 0.7),
	Vector3(190.0, 3.0, 0.5),
]
const CURTAIN_HEIGHT: float = 260.0

## Lamp halo in rain: quad size, m, and brightness.
const HALO_SIZE := Vector2(9.0, 8.1)
const HALO_STRENGTH: float = 0.25


## Rain streaks: [param amount] drops from box [param extents] fall at speed
## [param speed] with drift [param slant] and live [param lifetime].
## Streak size — [param size], look — [param look] from [method drop_look].
static func streaks(
	amount: int,
	lifetime: float,
	extents: Vector3,
	speed: Vector2,
	slant: float,
	size: Vector2,
	look: ShaderMaterial
) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extents
	process.direction = Vector3(slant, -1.0, 0.0).normalized()
	process.spread = SPREAD
	process.initial_velocity_min = speed.x
	process.initial_velocity_max = speed.y
	process.gravity = Vector3.ZERO
	process.scale_min = 0.7
	process.scale_max = 1.3

	var rain := GPUParticles3D.new()
	rain.amount = amount
	rain.set_meta(FULL, amount)
	rain.lifetime = lifetime
	rain.preprocess = lifetime
	rain.local_coords = false
	rain.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	rain.process_material = process
	rain.draw_pass_1 = streak_mesh(size, look)
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return rain


## Drop look: the streak shader with parameters [param settings] — names from
## [code]rain_streak.gdshader[/code], the rest at the shader's defaults.
static func drop_look(settings: Dictionary) -> ShaderMaterial:
	var look := ShaderMaterial.new()
	look.shader = STREAK_SHADER
	look.set_shader_parameter("tint", TINT)
	for key: String in settings:
		look.set_shader_parameter(key, settings[key])
	return look


## Streak quad: shifted back by its length so the particle is the head.
static func streak_mesh(size: Vector2, look: ShaderMaterial) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = size
	quad.center_offset = Vector3(0.0, -size.y * 0.5, 0.0)
	quad.material = look
	return quad


## Drop share by quality level: the count on "High" is in the [constant FULL] meta.
static func scale_amount(particles: GPUParticles3D, share: float) -> void:
	var full := int(particles.get_meta(FULL, particles.amount))
	var wanted := maxi(int(float(full) * share), 1)
	if particles.amount != wanted:
		particles.amount = wanted


## City rain: streak layers at the camera and curtains between rows of houses. The
## layers are children of [param camera]: they travel with it, while the drops fall in
## the world.
##
## [param share] — share of the night strength (ADR-0051): drops and curtains carry the
## light of what is behind them, and in the daytime against a light sky they would
## burn white.
static func city(
	camera: Camera3D, ground: float, from_x: float, to_x: float, share: float = 1.0
) -> Node3D:
	var host := Node3D.new()
	host.name = "Rain"
	for index in CITY_LAYERS.size():
		var layer := CITY_LAYERS[index]
		var reach := float(layer["depth"])
		var look := drop_look(CITY_DROP)
		look.set_shader_parameter("back_gain", float(CITY_DROP["back_gain"]) * share)
		var drops := streaks(
			int(layer["drops"]),
			2.2,
			Vector3(reach * 0.9 + 20.0, 2.0, float(layer["reach"])),
			CITY_SPEED,
			CITY_SLANT,
			layer["size"] as Vector2,
			look
		)
		drops.name = "Layer%d" % index
		drops.position = Vector3(0.0, 26.0, -reach)
		drops.visibility_aabb = AABB(
			Vector3(-reach * 2.0 - 40.0, -80.0, -reach - 40.0),
			Vector3(reach * 4.0 + 80.0, 120.0, reach * 2.0 + 80.0)
		)
		camera.add_child(drops)
	for curtain in CURTAINS:
		host.add_child(_curtain(curtain, ground, from_x, to_x, share))
	return host


## City rain streaks, to recompute their share by quality level.
static func city_layers(camera: Camera3D) -> Array[GPUParticles3D]:
	var found: Array[GPUParticles3D] = []
	for child in camera.get_children():
		if child is GPUParticles3D:
			found.append(child as GPUParticles3D)
	return found


## Lamp halo of colour [param colour] in rain: a quad of size [param size] at
## [param at], slightly behind the lamp — between it and the background, brightness
## [param strength].
static func halo(
	at: Vector3, colour: Color, strength: float = HALO_STRENGTH, size: Vector2 = HALO_SIZE
) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var look := ShaderMaterial.new()
	look.shader = HALO_SHADER
	look.set_shader_parameter("colour", colour)
	look.set_shader_parameter("strength", strength)
	quad.material = look
	var glow := MeshInstance3D.new()
	glow.name = "Halo"
	glow.mesh = quad
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.position = at
	return glow


static func _curtain(
	spec: Vector3, ground: float, from_x: float, to_x: float, share: float
) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(to_x - from_x + spec.x * 4.0 + 400.0, CURTAIN_HEIGHT)
	var look := ShaderMaterial.new()
	look.shader = CURTAIN_SHADER
	look.set_shader_parameter("tint", TINT)
	look.set_shader_parameter("gain", spec.y * share)
	look.set_shader_parameter("density", spec.z)
	look.set_shader_parameter("slant", CITY_SLANT)
	quad.material = look
	var curtain := MeshInstance3D.new()
	curtain.name = "Curtain%d" % int(spec.x)
	curtain.mesh = quad
	curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	curtain.position = Vector3((from_x + to_x) * 0.5, ground + CURTAIN_HEIGHT * 0.5, -spec.x)
	return curtain
