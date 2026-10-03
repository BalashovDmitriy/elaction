class_name WallWear
extends Node3D

## Signs of life on the walls of a residential building (ADR-0055, decision 4): graffiti tags low
## down, rust stains and cracks in the plaster — an eighties corridor, not a hotel one.
##
## Look only: the pictures are planes with transparency right on the plaster, without bodies. The
## layout is without a scene, by plan and seed ([method lay]), like the dressing
## ([BuildingDressing]): a mark does not go on a door opening, a shaft portal or a blank wall and
## does not overlap what hangs on the wall. The pictures are drawn by `tools/build_wear.py` into
## `assets/textures/wear/`.


## A mark on the wall: picture, floor, middle by x and by height above the floor, width.
class Mark:
	extends RefCounted
	var image: String = ""
	var floor_index: int = 0
	var x: float = 0.0
	var rise: float = 0.0
	var width: float = 0.0


const DIR := "res://assets/textures/wear"
const TAGS: PackedStringArray = ["tag_0", "tag_1", "tag_2", "tag_3"]
const STAINS: PackedStringArray = ["stain_0", "stain_1"]
const CRACKS: PackedStringArray = ["crack_0", "crack_1"]
## Bare brick where the plaster has crumbled (ADR-0056, decision 4).
const BRICKS: PackedStringArray = ["brick_0", "brick_1"]
const BRICK_RISE := Vector2(1.55, 2.05)
const BRICK_WIDTH: float = 1.0

## How many marks per floor: the chance that a free place gets one.
const CHANCE: float = 0.45
## A tag at hand level, a stain under the ceiling where it leaks from above, a crack wherever.
## Width, m, and middle above the floor, m.
const TAG_WIDTH: float = 1.05
## The bottom of the tag drawing — the flourish under the line — is this share of the width below
## the middle of the picture (`tools/build_wear.py`).
const TAG_INK: float = 0.3
## The tag is above the wall panel with a handrail: the picture lies on the plaster, and the panel
## ([constant BuildingRibs.SKIRTING_HEIGHT]) sticks out in front of it and cut off the bottom of the
## letters (M24m code review shots).
const TAG_RISE := Vector2(
	BuildingRibs.SKIRTING_HEIGHT + BuildingRibs.RAIL_HEIGHT + TAG_WIDTH * TAG_INK + 0.04, 1.55
)
const STAIN_RISE := Vector2(1.9, 2.25)
const STAIN_WIDTH: float = 0.7
const CRACK_RISE := Vector2(1.2, 2.0)
const CRACK_WIDTH: float = 0.9
## A mark is not placed closer than this to the middle of an object on the wall, m.
const DECOR_CLEAR: float = 0.6
## Gap of a mark from what is occupied on the wall: the door casing and the strip beyond it, m.
const ZONE_CLEAR: float = 0.12
## The plane is a hair in front of the plaster: otherwise it would flicker with it.
const STANDOFF: float = 0.006
## Its own draw: marks do not move in step with the dressing.
const SALT: int = 0x57A1_7E

var marks: Array[Mark] = []


## The building's marks: only for a residential building, for the others — empty. [param features] —
## the wall layout ([WallFeatures]): windows, panels and doors stand in the same places, and a tag
## under a window or brick under a stairwell door would stick out from behind them.
static func lay(
	rules: BuildingRules,
	plan: BuildingPlan,
	building_seed: int,
	identity: BuildingIdentity,
	dressing: BuildingDressing,
	features: Array[WallFeatures.Feature] = []
) -> Array[Mark]:
	var found: Array[Mark] = []
	if identity == null or identity.kind != BuildingIdentity.Kind.RESIDENTIAL:
		return found
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, SALT])
	# What hangs on the wall, by floor: otherwise each place would go over the whole building.
	var hung := {}
	if dressing != null:
		for spot: BuildingDressing.PropSpot in dressing.decor:
			if not hung.has(spot.floor_index):
				hung[spot.floor_index] = PackedFloat64Array()
			(hung[spot.floor_index] as PackedFloat64Array).append(spot.x)
	# Wall layout — occupied segments by floor, like doors and shafts.
	var built := {}
	for feature: WallFeatures.Feature in features:
		if not built.has(feature.floor_index):
			built[feature.floor_index] = [] as Array[Vector2]
		var half: float = WallFeatures.HALF[feature.kind]
		(built[feature.floor_index] as Array[Vector2]).append(
			Vector2(feature.x - half, feature.x + half)
		)
	# The exit floor is the garage: it has its own finish (ADR-0038).
	for index: int in rules.floors - 1:
		# On a special floor there is no wall — the marks have nothing to lie on (ADR-0057).
		if FloorRole.hall_at(rules, index):
			continue
		var zones := BuildingDressing.blocked_zones(rules, plan, index)
		zones.append_array(built.get(index, [] as Array[Vector2]))
		var decor: PackedFloat64Array = hung.get(index, PackedFloat64Array())
		for x: float in BuildingDressing.wall_spots(rules, plan, index):
			if rng.randf() >= CHANCE or _near_decor(decor, x):
				continue
			var mark := _draw(rng, index, x)
			if not clashes(zones, mark):
				found.append(mark)
	return found


## Whether mark [param mark] touches what is occupied on the wall: a door opening with its casing, a
## shaft portal, a blank wall, an escalator span. A tag in an opening would hang in the air of an
## open door.
static func clashes(zones: Array[Vector2], mark: Mark) -> bool:
	var half := mark.width * 0.5 + ZONE_CLEAR
	for zone: Vector2 in zones:
		if mark.x + half > zone.x and mark.x - half < zone.y:
			return true
	return false


## Places planes by [param list]: one multimesh per picture.
func build(rules: BuildingRules, list: Array[Mark]) -> void:
	name = "WallWear"
	marks = list
	var by_image := {}
	for mark: Mark in list:
		if not by_image.has(mark.image):
			by_image[mark.image] = [] as Array[Transform3D]
		var centre := WorldSpace.to_scene(
			Vector2(mark.x, rules.floor_surface(mark.floor_index) - mark.rise)
		)
		centre.z = WorldSpace.BACK_WALL_Z + STANDOFF
		var size := Basis.from_scale(Vector3(mark.width, mark.width, 1.0))
		(by_image[mark.image] as Array[Transform3D]).append(Transform3D(size, centre))
	for image: String in by_image:
		_commit(image, by_image[image])


static func _draw(rng: RandomNumberGenerator, index: int, x: float) -> Mark:
	var mark := Mark.new()
	mark.floor_index = index
	mark.x = x + rng.randf_range(-0.15, 0.15)
	var roll := rng.randf()
	if roll < 0.55:
		mark.image = TAGS[rng.randi_range(0, TAGS.size() - 1)]
		mark.rise = rng.randf_range(TAG_RISE.x, TAG_RISE.y)
		mark.width = TAG_WIDTH
	elif roll < 0.68:
		mark.image = STAINS[rng.randi_range(0, STAINS.size() - 1)]
		mark.rise = rng.randf_range(STAIN_RISE.x, STAIN_RISE.y)
		mark.width = STAIN_WIDTH
	elif roll < 0.82:
		mark.image = BRICKS[rng.randi_range(0, BRICKS.size() - 1)]
		mark.rise = rng.randf_range(BRICK_RISE.x, BRICK_RISE.y)
		mark.width = BRICK_WIDTH
	else:
		mark.image = CRACKS[rng.randi_range(0, CRACKS.size() - 1)]
		mark.rise = rng.randf_range(CRACK_RISE.x, CRACK_RISE.y)
		mark.width = CRACK_WIDTH
	return mark


## Whether something from the floor's [param decor] (middles by x) hangs closer than [constant
## DECOR_CLEAR] to place [param x].
static func _near_decor(decor: PackedFloat64Array, x: float) -> bool:
	for hung_x: float in decor:
		if absf(hung_x - x) < DECOR_CLEAR:
			return true
	return false


## Material of mark [param image]: a picture with transparency on a rough surface. The residential
## building's garage graffiti is drawn with it too ([GarageDressing]).
static func tag_look(image: String) -> StandardMaterial3D:
	var look := StandardMaterial3D.new()
	look.albedo_texture = load("%s/%s.png" % [DIR, image]) as Texture2D
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.roughness = 0.9
	look.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return look


func _commit(image: String, places: Array[Transform3D]) -> void:
	var quad := QuadMesh.new()
	quad.material = tag_look(image)
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.mesh = quad
	many.instance_count = places.size()
	for index: int in places.size():
		many.set_instance_transform(index, places[index])
	var node := MultiMeshInstance3D.new()
	node.name = image.capitalize()
	node.multimesh = many
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
