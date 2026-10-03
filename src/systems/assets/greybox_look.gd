class_name GreyboxLook
extends RefCounted

## Greybox materials: what the boxes are painted with while there are no models and textures.
##
## The look of milestone M15 is grey boxes, and that is fine
## ([ADR-0021](../../../docs/adr/0021-3d-greybox.md)). But "grey" does not mean "identical": without
## a difference in tones the frame reads as a solid fill, and you cannot tell where the floor is,
## where the wall is and where the shaft is. Since M17 roughness and metal were added to the tone
## ([ADR-0023](../../../docs/adr/0023-light-and-readability.md), decision 5): the floor is polished
## for reflections, the walls are rough concrete, the shaft and the trims are metal. There are no
## textures, they are a matter for the M19 dressing.
##
## The second thing decided here matters more than colour.
## [ADR-0019](../../../docs/adr/0019-3d-pivot.md), decision 5: a game object does not depend on the
## scene lighting. In a trial with the lamps off the door vanished completely — and the door is the
## goal of the game. Since M17 readability is held not by fully glowing boxes but by **indicator
## lights** — [method light]: the board above a door, the cab indicators, the exit sign. The lamp
## fixture and the bullet glow by themselves — [method marker]; actors are lit by the camera light
## ([method SideCamera.actor_fill]).

## Environment tones. Chosen so that neighbouring planes differ by eye both in a lit frame and in a
## dark one.
const SLAB := Color(0.22, 0.22, 0.24)
const WALL := Color(0.28, 0.29, 0.32)
const BACK_WALL := Color(0.19, 0.20, 0.23)
## The far wall of the room: darker than the back wall, so the opening reads as depth.
const SKY_WALL := Color(0.11, 0.12, 0.16)
const SHAFT := Color(0.24, 0.27, 0.34)
const ESCALATOR := Color(0.33, 0.31, 0.29)

## Trims (ADR-0023, decision 4): a light strip on the end walls and the skirting, a dark wall
## bottom, pilasters slightly lighter than the wall itself.
const TRIM := Color(0.52, 0.50, 0.46)
const SKIRTING := Color(0.17, 0.17, 0.19)
const PILASTER := Color(0.40, 0.40, 0.42)

## Game object tones. Actors and the car at the exit have been models with their own materials since
## M16; their readability in the dark is held by the camera light (ADR-0042, decision 7).
const DOOR := Color(0.78, 0.66, 0.30)
const DOOR_RED := Color(0.76, 0.24, 0.22)
const LAMP := Color(1.0, 0.93, 0.72)
const CAR := Color(0.70, 0.22, 0.20)

## Indicator lights (ADR-0023, decision 6): the boards of an ordinary and a red door, the exit sign,
## the cab indicators.
const SIGN_WARM := Color(1.0, 0.72, 0.35)
const SIGN_RED := Color(1.0, 0.22, 0.16)
const SIGN_GREEN := Color(0.30, 1.0, 0.50)
const INDICATOR := Color(1.0, 0.25, 0.15)

## How brightly markers glow — the lamp fixture and the bullet. Not a "torch", but exactly enough
## for the silhouette to read on a dark floor: any higher and the frame turns into a garland.
const MARKER_GLOW: float = 0.55

## How brightly an indicator light burns. Brighter than the frame — exactly enough for the glow
## ([Environment] with threshold 1.0) to give it a halo, like the indicators in the reference.
const LIGHT_GLOW: float = 2.0

## Roughness and metal of surfaces. A smooth box under light reads as a blurry blob — this is a
## finding of the trial, so concrete is rough; the floor, on the contrary, is smooth with a drop of
## metal — reflections lie in it.
const SURFACE_ROUGHNESS: float = 0.85
const FLOOR_ROUGHNESS: float = 0.28
const FLOOR_METALLIC: float = 0.2
const METAL_ROUGHNESS: float = 0.45
const METAL_METALLIC: float = 0.35

static var _cache: Dictionary = {}


## Environment material — rough concrete: it needs light, and in the dark it goes dark.
static func surface(color: Color) -> StandardMaterial3D:
	return _made("s%s" % color, color, SURFACE_ROUGHNESS, 0.0, 0.0)


## Polished floor: dark and smooth, for reflections.
static func polished(color: Color) -> StandardMaterial3D:
	return _made("p%s" % color, color, FLOOR_ROUGHNESS, FLOOR_METALLIC, 0.0)


## Metal: shaft, strips, cab.
static func metal(color: Color) -> StandardMaterial3D:
	return _made("e%s" % color, color, METAL_ROUGHNESS, METAL_METALLIC, 0.0)


## Marker: glows by itself, dimly. A lamp fixture is what is a light source in real life too. The
## bullet since M21 is a tracer with its own look ([BulletLook]).
static func marker(color: Color) -> StandardMaterial3D:
	return _made("m%s" % color, color, SURFACE_ROUGHNESS, 0.0, MARKER_GLOW)


## Indicator light: a small light of a game object's own. Emission, it does not obey the scene
## light, so it is visible on a dark floor too.
static func light(color: Color) -> StandardMaterial3D:
	return _made("l%s" % color, color, SURFACE_ROUGHNESS, 0.0, LIGHT_GLOW)


## There are a handful of materials per building and thousands of boxes: without a cache every mesh
## would drag its own copy of the same material, and no batch would come together.
static func _made(
	key: String, color: Color, roughness: float, metallic: float, glow: float
) -> StandardMaterial3D:
	var found: Variant = _cache.get(key)
	if found != null:
		return found as StandardMaterial3D

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	_cache[key] = material
	return material


## A box without a body: a mesh of the required size with a material, ready to go into the scene.
##
## Assembled in one place. The level, the shaft dressing and the escalator each laid it with their
## own five lines — seven copies of the same thing, and the very first edit (layer, shadow,
## material) would diverge between them (M15 code review).
static func box(size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	return part


## Resets the cache. Needed by tests: materials live in statics, which survive a scene change, and
## what accumulated in one test would leak into the next.
static func forget() -> void:
	_cache.clear()
