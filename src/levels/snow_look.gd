class_name SnowLook
extends RefCounted

## The look of snow: flakes above the roof ([RoofSnow]) and the city snowfall
## ([CityBackdrop]) (ADR-0054). One place for both, as with rain ([RainLook]):
## split them, and the roof and city flakes would diverge at the first change.
##
## A flake is a soft spot turned to the camera. It falls slowly and drifts with the
## wind, with a spread of direction and speed: snow that flies in formation reads as
## screen noise, not as snow.

const FLAKE_SHADER := preload("res://src/levels/snow_flake.gdshader")

## Snow color: a slightly cold white.
const TINT := Color(0.84, 0.9, 1.0)

## Flake brightness at night and by day: at night snow is visible by the light of the
## city and lamps; by itself it is gray.
const NIGHT_BRIGHTNESS: float = 0.42
const DAY_BRIGHTNESS: float = 1.0
## What share of the brightness is sky light; lamps and the sun give the flake the rest.
const AMBIENT_SHARE: float = 0.75

## Spread of flake direction, degrees. Snow has no particle noise ([member
## ParticleProcessMaterial.turbulence_enabled]): in Godot it is mixed into the velocity
## every step, and even half a percent per step erased the fall: the flakes hung in a
## heap by the sky (M24l measurement).
const SPREAD: float = 10.0

## Layers of the city snowfall, from the city camera inward, as with rain
## ([constant RainLook.CITY_LAYERS]): how many flakes, how far past the camera the
## layer middle is and the half-depth, m, the flake size. Near ones are large, far ones
## smaller and sink into the haze.
const CITY_LAYERS: Array[Dictionary] = [
	{"flakes": 900, "depth": 22.0, "reach": 10.0, "size": 0.22},
	{"flakes": 1800, "depth": 52.0, "reach": 18.0, "size": 0.32},
	{"flakes": 1600, "depth": 110.0, "reach": 30.0, "size": 0.5},
]
## Fall speed in the city, m/s, and sideways wind, m/s.
const CITY_FALL := Vector2(1.6, 2.6)
const CITY_WIND: float = 1.1


## Flakes: [param amount] of them from the box [param extents] fall at speed
## [param fall] with sideways wind [param wind] and live for [param lifetime].
## [param size] is the flake size, [param brightness] its brightness.
static func flakes(
	amount: int,
	lifetime: float,
	extents: Vector3,
	fall: Vector2,
	wind: float,
	size: float,
	brightness: float
) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extents
	var middle := (fall.x + fall.y) * 0.5
	process.direction = Vector3(wind / middle, -1.0, 0.0).normalized()
	process.spread = SPREAD
	process.initial_velocity_min = fall.x
	process.initial_velocity_max = fall.y
	process.gravity = Vector3.ZERO
	process.scale_min = 0.6
	process.scale_max = 1.4

	var snow := GPUParticles3D.new()
	snow.amount = amount
	snow.set_meta(RainLook.FULL, amount)
	snow.lifetime = lifetime
	snow.preprocess = lifetime
	snow.local_coords = false
	snow.process_material = process
	snow.draw_pass_1 = flake_mesh(size, brightness)
	snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The sun shines only on the outdoor layer ([Outdoors]): without it, by day the flakes
	# would be flat spots with no light.
	snow.layers |= Outdoors.LAYER
	return snow


## Flake drift per meter of fall at fall [param fall] and wind [param wind]: the
## smallest and the largest. A flake flies at the mean angle of [method flakes] with
## a spread of [constant SPREAD] both ways, and drifts from 2 to 6 m over
## eight meters rather than by a single number.
static func slant(fall: Vector2, wind: float) -> Vector2:
	var mean := atan(wind / ((fall.x + fall.y) * 0.5))
	var spread := deg_to_rad(SPREAD)
	return Vector2(tan(mean - spread), tan(mean + spread))


## Vertical speed of the slowest and most slanted flake, m/s: the flakes' lifetime is
## computed from it. With the fall speed [param fall].x alone, the lifetime ended before
## a slanted flake arrived, and it went out in the air, a meter above the roof and two
## above the sidewalk (M24l code review).
static func slowest_fall(fall: Vector2, wind: float) -> float:
	var steepest := atan(wind / ((fall.x + fall.y) * 0.5)) + deg_to_rad(SPREAD)
	return fall.x * cos(steepest)


## Flake quad: a loose clump of soft blobs, facing the camera, spinning and
## swaying ([code]snow_flake.gdshader[/code]). [param brightness] is the sky light on
## it without lamps.
static func flake_mesh(size: float, brightness: float) -> QuadMesh:
	var look := ShaderMaterial.new()
	look.shader = FLAKE_SHADER
	look.set_shader_parameter("tint", TINT)
	look.set_shader_parameter("ambient", brightness * AMBIENT_SHARE)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	quad.material = look
	return quad


## Flake brightness at time of day [param time].
static func brightness(time: TimeOfDay.Kind) -> float:
	return lerpf(NIGHT_BRIGHTNESS, DAY_BRIGHTNESS, TimeOfDay.daylight(time))


## City snowfall: flake layers at the camera. The layers are children of [param camera]:
## they ride with it, while the flakes fall in the world. Returns the layers: the city
## recalculates their flake counts by quality level, like the rain streaks.
static func city(camera: Camera3D, time: TimeOfDay.Kind) -> Array[GPUParticles3D]:
	var made: Array[GPUParticles3D] = []
	for index in CITY_LAYERS.size():
		var layer := CITY_LAYERS[index]
		var reach := float(layer["depth"])
		var snow := flakes(
			int(layer["flakes"]),
			28.0 / CITY_FALL.x,
			Vector3(reach * 0.9 + 20.0, 2.0, float(layer["reach"])),
			CITY_FALL,
			CITY_WIND,
			float(layer["size"]),
			brightness(time)
		)
		snow.name = "Snow%d" % index
		snow.position = Vector3(0.0, 26.0, -reach)
		snow.visibility_aabb = AABB(
			Vector3(-reach * 2.0 - 40.0, -80.0, -reach - 40.0),
			Vector3(reach * 4.0 + 80.0, 120.0, reach * 2.0 + 80.0)
		)
		camera.add_child(snow)
		made.append(snow)
	return made
