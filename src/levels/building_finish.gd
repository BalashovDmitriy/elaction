class_name BuildingFinish
extends RefCounted

## Building finish: textured materials (ADR-0033, decisions 5, 6 and 8).
##
## Before M21b walls were a single-color fill and read as "squares". Now a wall has a
## pattern: wallpaper in the hotel, plaster in the office, paint in the residential
## building; the lower panel is wood, plastic or darker paint, pilasters are marble,
## concrete or painted brick; the shaft is metal sheets and concrete,
## the portal threshold is checker-plate steel, the roof is gravel. The textures are
## built by `tools/build_textures.py` into `assets/textures/`.
##
## The mapping is triplanar, in world coordinates: wall boxes have no UV layout of their
## own, and the pattern density must be the same on any box. The round tone
## ([BuildingPalette]) goes onto the texture as a multiplier: where the texture is gray,
## the round gives the color, and rounds still differ by eye (M20).

const DIR := "res://assets/textures"

## After how many meters the pattern repeats.
const WALLPAPER_REPEAT: float = 1.0
const WOOD_REPEAT: float = 1.2
const STONE_REPEAT: float = 1.6
const PLATES_REPEAT: float = 1.2
const GRAVEL_REPEAT: float = 2.0

## Tone of wood and steel: they have their own color in the texture, the round only
## touches it slightly.
const WOOD_TINT := Color(0.85, 0.8, 0.78)
const STEEL_TINT := Color(0.75, 0.78, 0.84)

## Materials per building are a handful, boxes are thousands: without a cache each would
## drag its own copy, and no batch would come together.
static var _cache: Dictionary = {}


## The corridor back wall in tone [param tone].
static func wall(identity: BuildingIdentity, tone: Color) -> StandardMaterial3D:
	return _textured(identity.key() + "_wall", tone, WALLPAPER_REPEAT, 0.0)


## The lower wall panel.
static func wainscot(identity: BuildingIdentity, tone: Color) -> StandardMaterial3D:
	match identity.kind:
		BuildingIdentity.Kind.HOTEL:
			return _textured("hotel_wainscot", WOOD_TINT, WOOD_REPEAT, 0.0)
		BuildingIdentity.Kind.RESIDENTIAL:
			# Two-tone walls (ADR-0055, decision 4): the bottom is painted glazed
			# brick, darker than the top, as in New York stairwells.
			# The round tone is pulled halfway to gray: the pure brick tone over half the wall
			# overwhelmed the frame (M24m shots).
			var paint := tone.lerp(Color(0.42, 0.42, 0.42), 0.55).darkened(0.25)
			return _textured("residential_wainscot", paint, WOOD_REPEAT, 0.0)
	return _textured(
		"office_wainscot", GreyboxLook.SKIRTING.lerp(tone, 0.25).lightened(0.2), WOOD_REPEAT, 0.0
	)


## Pilasters of the piers.
static func pilaster(identity: BuildingIdentity, tone: Color) -> StandardMaterial3D:
	return _textured(identity.key() + "_pilaster", tone.lightened(0.5), STONE_REPEAT, 0.0)


## The shaft back wall: metal sheets with bolts.
static func shaft_plates() -> StandardMaterial3D:
	return _textured("shaft_plates", STEEL_TINT, PLATES_REPEAT, 0.6)


## Concrete of the machine room above the shaft.
static func shaft_concrete(tone: Color) -> StandardMaterial3D:
	return _textured("shaft_concrete", tone, STONE_REPEAT, 0.0)


## Checker-plate steel: the portal threshold.
static func tread_plate() -> StandardMaterial3D:
	return _textured("tread_plate", STEEL_TINT, 0.6, 0.8)


## Roofing gravel: steps of the roof slopes ([BuildingRoof]).
static func roof_gravel(tone: Color) -> StandardMaterial3D:
	return _textured("roof_gravel", tone, GRAVEL_REPEAT, 0.0)


static func _textured(
	name: String, tint: Color, repeat: float, metallic: float
) -> StandardMaterial3D:
	var key := "%s/%s/%.2f" % [name, tint.to_html(), repeat]
	if _cache.has(key):
		return _cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("%s/%s/albedo.png" % [DIR, name]) as Texture2D
	material.albedo_color = tint
	material.normal_enabled = true
	material.normal_texture = load("%s/%s/normal.png" % [DIR, name]) as Texture2D
	material.roughness_texture = load("%s/%s/roughness.png" % [DIR, name]) as Texture2D
	material.roughness = 1.0
	material.metallic = metallic
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / repeat
	_cache[key] = material
	return material
