class_name WallFeatures
extends Node3D

## The corridor back wall by its fixtures (ADR-0056, decision 4): what makes a hotel wall
## a hotel wall and a residential building wall a stairwell, not just the texture under
## them.
##
## - Hotel: arched niches with warm lighting from below and a vase on a shelf, mirrors in
##   gilded frames (a glint, not a reflection).
## - Residential building: pipe risers from floor to ceiling, electrical panels with
##   cables going up, windows onto the fire escape (the black grating of the landing on
##   night glass), a steel stair door with a STAIRS sign and a garbage chute hatch. The
##   doors do not open and resemble agent doors neither in color nor by a light.
##
## The office has nothing here: its wall is glass ([OpenSpace]).
##
## The layout is scene-less, by plan and seed ([method lay]), like the dressing:
## an element takes a free spot on the wall, does not touch doors, shafts, solid
## walls or the escalator span, does not overlap paintings and does not hide behind
## furniture ([method behind_furniture]). Look only: no bodies, no shadows, multimeshes,
## one per detail.


## A wall element: what, floor, middle in x.
class Feature:
	extends RefCounted
	var kind: String = ""
	var floor_index: int = 0
	var x: float = 0.0


## What a kind has and with what weight in the draw.
const HOTEL: Dictionary = {"niche": 3, "mirror": 2}
const RESIDENTIAL: Dictionary = {"risers": 2, "panel": 2, "window": 3, "stairs": 1, "chute": 1}
## Half width of an element, m: the gap from what is occupied on the wall follows it.
const HALF: Dictionary = {
	"niche": 0.34,
	"mirror": 0.33,
	"risers": 0.2,
	"panel": 0.3,
	"window": 0.52,
	"stairs": 0.5,
	"chute": 0.25,
}
## The chance that a free spot on the wall gets an element.
const CHANCE: float = 0.75
## An element does not stand closer than this to the middle of a painting on the wall, m.
const DECOR_CLEAR: float = 0.75
## Gap from a door, shaft and wall, m: the casing and a strip beyond it.
const ZONE_CLEAR: float = 0.1
const SALT: int = 0xFEA7

## Hotel niche: width, height of the straight part, bottom above the floor, m; lighting,
## frame. The bottom is above the rail of the hotel's high panel
## ([member BuildingStyle.wainscot_height] with [constant BuildingRibs.RAIL_HEIGHT],
## 1.33 m): lower, the niche shelf and the mirror frame went behind the rail.
const NICHE := Vector3(0.6, 0.85, 1.4)
const NICHE_GLOW := Color(1.0, 0.72, 0.42)
const GILT := Color(0.78, 0.6, 0.26)
const VASE := Color(0.82, 0.8, 0.74)
## Hotel mirror: width, height, bottom above the floor, m.
const MIRROR := Vector3(0.56, 0.95, 1.4)
const MIRROR_GLASS := Color(0.72, 0.78, 0.82)
## Residential building: pipes, panel, window, stair door, hatch.
const PIPE := Color(0.5, 0.48, 0.44)
const PANEL_GREY := Color(0.46, 0.48, 0.47)
const CABLE := Color(0.08, 0.08, 0.09)
const WINDOW := Vector3(0.95, 1.15, 1.05)
const WINDOW_FRAME := Color(0.82, 0.8, 0.74)
const NIGHT := Color(0.07, 0.09, 0.14)
const IRON := Color(0.04, 0.04, 0.05)
const STAIR_DOOR := Vector2(0.92, 2.05)
## The stair door reaches the floor, and the lower wall panel with the rail sticks out
## of the wall by [constant BuildingRibs.RAIL_DEPTH]: the door with its casing is in
## front of it, otherwise the panel ran across the bottom of the door.
const STAIR_FACE: float = BuildingRibs.RAIL_DEPTH
const STAIR_STEEL := Color(0.42, 0.38, 0.34)
const PLATE := Color(0.82, 0.8, 0.72)
## Garbage chute hatch: width and height, m, and its middle above the floor; the bottom
## is above the panel rail (0.98 m).
const CHUTE := Vector2(0.46, 0.4)
const CHUTE_RISE: float = 1.2

## Details: color and look. Niche lighting glows by itself; on a dark floor it does not.
## The window glass follows the time of day ([method TimeOfDay.window_look]): the color
## here is the night one.
const LOOKS: Dictionary = {
	"glow": [NICHE_GLOW * Color(0.65, 0.65, 0.65), "light"],
	"glow_off": [NICHE_GLOW * Color(0.25, 0.25, 0.25), "surface"],
	"gilt": [GILT, "metal"],
	"vase": [VASE, "polished"],
	"mirror": [MIRROR_GLASS, "metal"],
	"pipe": [PIPE, "metal"],
	"panel": [PANEL_GREY, "metal"],
	"night": [NIGHT, "window"],
	"iron": [IRON, "surface"],
	"frame": [WINDOW_FRAME, "surface"],
	"steel": [STAIR_STEEL, "metal"],
	"plate": [PLATE, "surface"],
}

## The element plane is a hair in front of the wall, m.
const STANDOFF: float = 0.012

var features: Array[Feature] = []
var _parts: Dictionary = {}
## The building's time of day: the glass of the fire-escape windows follows it.
var _time: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT


## Wall elements of a building of kind [param identity]; the office gets none.
static func lay(
	rules: BuildingRules,
	plan: BuildingPlan,
	building_seed: int,
	identity: BuildingIdentity,
	dressing: BuildingDressing
) -> Array[Feature]:
	var found: Array[Feature] = []
	var weights := _weights(identity)
	if weights.is_empty():
		return found
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, SALT])
	var hung := {}
	var stood := {}
	if dressing != null:
		for item: BuildingDressing.PropSpot in dressing.decor:
			if not hung.has(item.floor_index):
				hung[item.floor_index] = [] as Array[float]
			(hung[item.floor_index] as Array[float]).append(item.x)
		for prop: BuildingDressing.PropSpot in dressing.props:
			if not stood.has(prop.floor_index):
				stood[prop.floor_index] = [] as Array[BuildingDressing.PropSpot]
			(stood[prop.floor_index] as Array[BuildingDressing.PropSpot]).append(prop)
	for index: int in rules.floors - 1:
		# On a special floor there is no wall: behind the corridor is a hall (ADR-0057, decision 3).
		if FloorRole.hall_at(rules, index):
			continue
		var zones := BuildingDressing.blocked_zones(rules, plan, index)
		var near: Array[float] = hung.get(index, [] as Array[float])
		var props: Array[BuildingDressing.PropSpot] = stood.get(
			index, [] as Array[BuildingDressing.PropSpot]
		)
		for x: float in BuildingDressing.wall_spots(rules, plan, index):
			if rng.randf() >= CHANCE or _near(near, x):
				continue
			var feature := Feature.new()
			feature.kind = _draw(rng, weights)
			feature.floor_index = index
			feature.x = x
			if not clashes(zones, feature) and not behind_furniture(props, feature):
				found.append(feature)
	return found


## Whether an element is hidden by the floor's furniture [param props]: by any tall
## piece, like a painting ([constant BuildingDressing.TALL]); the stair door reaches the
## floor, and no furniture stands in front of it.
static func behind_furniture(props: Array[BuildingDressing.PropSpot], feature: Feature) -> bool:
	var half: float = HALF[feature.kind]
	for prop: BuildingDressing.PropSpot in props:
		if absf(prop.x - feature.x) >= prop.width * 0.5 + half:
			continue
		if feature.kind == "stairs":
			return true
		if PropCatalog.footprint(prop.name).y > BuildingDressing.TALL:
			return true
	return false


## Whether an element touches what is occupied on the wall.
static func clashes(zones: Array[Vector2], feature: Feature) -> bool:
	var half: float = HALF[feature.kind] + ZONE_CLEAR
	for zone: Vector2 in zones:
		if feature.x + half > zone.x and feature.x - half < zone.y:
			return true
	return false


static func _weights(identity: BuildingIdentity) -> Dictionary:
	if identity == null:
		return {}
	match identity.kind:
		BuildingIdentity.Kind.HOTEL:
			return HOTEL
		BuildingIdentity.Kind.RESIDENTIAL:
			return RESIDENTIAL
	return {}


static func _draw(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0
	for kind: String in weights:
		total += int(weights[kind])
	var roll := rng.randi_range(0, total - 1)
	for kind: String in weights:
		roll -= int(weights[kind])
		if roll < 0:
			return kind
	return weights.keys()[0]


static func _near(hung: Array[float], x: float) -> bool:
	for at: float in hung:
		if absf(at - x) < DECOR_CLEAR:
			return true
	return false


## Builds the elements [param list] on the floors; on a dark floor the niche lighting is
## off.
func build(rules: BuildingRules, list: Array[Feature]) -> void:
	name = "WallFeatures"
	features = list
	_time = rules.time_of_day
	for feature: Feature in list:
		var ground := rules.floor_surface(feature.floor_index)
		var lit := not rules.is_unlit(feature.floor_index)
		match feature.kind:
			"niche":
				_niche(feature.x, ground, lit)
			"mirror":
				_mirror(feature.x, ground)
			"risers":
				_risers(feature.x, ground, rules.story_top(feature.floor_index))
			"panel":
				_panel(feature.x, ground, rules.story_top(feature.floor_index))
			"window":
				_window(feature.x, ground)
			"stairs":
				_stairs(feature.x, ground)
			"chute":
				_chute(feature.x, ground)
	for key: String in _parts:
		_commit(key)


func _niche(x: float, ground: float, lit: bool) -> void:
	var bottom := ground - NICHE.z
	var middle := bottom - NICHE.y * 0.5
	var glow := "glow" if lit else "glow_off"
	_add(glow, Vector3(NICHE.x, NICHE.y, 0.01), Vector3(x, middle, 0.0))
	# The vault: a semicircle of steps of the same light, the frame made of gilded bars.
	var radius := NICHE.x * 0.5
	for step: int in 5:
		var angle := PI * (step + 0.5) / 10.0
		var width := NICHE.x * cos(angle - PI * 0.05)
		var rise := radius * sin(angle) - radius * 0.1
		_add(glow, Vector3(width, radius * 0.22, 0.01), Vector3(x, bottom - NICHE.y - rise, 0.0))
	for side: float in [-1.0, 1.0]:
		_add(
			"gilt", Vector3(0.05, NICHE.y, 0.05), Vector3(x + side * (radius + 0.02), middle, 0.02)
		)
	for step: int in 9:
		var angle := PI * step / 8.0
		var at := Vector2(cos(angle) * (radius + 0.02), sin(angle) * (radius + 0.02))
		_add("gilt", Vector3(0.09, 0.05, 0.05), Vector3(x + at.x, bottom - NICHE.y - at.y, 0.02))
	# Shelf and vase.
	_add("gilt", Vector3(NICHE.x + 0.1, 0.04, 0.16), Vector3(x, bottom + 0.02, 0.08))
	_add("vase", Vector3(0.16, 0.3, 0.16), Vector3(x, bottom - 0.15, 0.08))
	_add("vase", Vector3(0.1, 0.08, 0.1), Vector3(x, bottom - 0.34, 0.08))


func _mirror(x: float, ground: float) -> void:
	var middle := ground - MIRROR.z - MIRROR.y * 0.5
	_add("gilt", Vector3(MIRROR.x + 0.12, MIRROR.y + 0.12, 0.04), Vector3(x, middle, 0.015))
	_add("mirror", Vector3(MIRROR.x, MIRROR.y, 0.02), Vector3(x, middle, 0.04))
	_add("gilt", Vector3(0.22, 0.1, 0.05), Vector3(x, middle - MIRROR.y * 0.5 - 0.08, 0.03))


func _risers(x: float, ground: float, top: float) -> void:
	var height := ground - top
	for offset: float in [-0.1, 0.1]:
		_add("pipe", Vector3(0.09, height, 0.09), Vector3(x + offset, top + height * 0.5, 0.06))
		for clamp_at: float in [0.6, 1.9]:
			_add("cable", Vector3(0.12, 0.04, 0.11), Vector3(x + offset, ground - clamp_at, 0.06))
	_add("pipe", Vector3(0.16, 0.12, 0.14), Vector3(x - 0.1, ground - 1.1, 0.08))


func _panel(x: float, ground: float, top: float) -> void:
	var middle := ground - 1.55
	_add("panel", Vector3(0.48, 0.66, 0.12), Vector3(x, middle, 0.06))
	_add("cable", Vector3(0.3, 0.02, 0.01), Vector3(x, middle - 0.18, 0.125))
	for offset: float in [-0.14, 0.0, 0.14]:
		var rise := middle - 0.33 - top
		_add("cable", Vector3(0.025, rise, 0.025), Vector3(x + offset, top + rise * 0.5, 0.04))


func _window(x: float, ground: float) -> void:
	var middle := ground - WINDOW.z - WINDOW.y * 0.5
	_add("night", Vector3(WINDOW.x, WINDOW.y, 0.01), Vector3(x, middle, 0.0))
	# Fire-escape grating behind the glass: landing, railing posts, flight.
	_add("iron", Vector3(WINDOW.x, 0.05, 0.01), Vector3(x, middle + WINDOW.y * 0.2, 0.005))
	_add("iron", Vector3(WINDOW.x, 0.03, 0.01), Vector3(x, middle - WINDOW.y * 0.15, 0.005))
	for step: int in 6:
		var at := x - WINDOW.x * 0.5 + WINDOW.x * (step + 0.5) / 6.0
		_add("iron", Vector3(0.02, WINDOW.y * 0.35, 0.01), Vector3(at, middle + 0.02, 0.005))
	for step: int in 5:
		_add(
			"iron",
			Vector3(0.18, 0.025, 0.01),
			Vector3(x + 0.15 + step * 0.06, middle - WINDOW.y * 0.32 + step * 0.09, 0.005)
		)
	for side: float in [-1.0, 1.0]:
		_add(
			"frame",
			Vector3(0.06, WINDOW.y + 0.12, 0.05),
			Vector3(x + side * (WINDOW.x + 0.06) * 0.5, middle, 0.025)
		)
		_add(
			"frame",
			Vector3(WINDOW.x + 0.12, 0.06, 0.05),
			Vector3(x, middle + side * (WINDOW.y + 0.06) * 0.5, 0.025)
		)
	_add("frame", Vector3(0.04, WINDOW.y, 0.04), Vector3(x, middle, 0.02))
	_add("frame", Vector3(WINDOW.x + 0.2, 0.05, 0.14), Vector3(x, ground - WINDOW.z + 0.03, 0.07))


func _stairs(x: float, ground: float) -> void:
	var middle := ground - STAIR_DOOR.y * 0.5
	var leaf := STAIR_FACE + 0.04
	var casing := STAIR_FACE + 0.06
	_add("steel", Vector3(STAIR_DOOR.x, STAIR_DOOR.y, leaf), Vector3(x, middle, leaf * 0.5))
	_add(
		"frame",
		Vector3(STAIR_DOOR.x + 0.12, 0.06, casing),
		Vector3(x, ground - STAIR_DOOR.y - 0.03, casing * 0.5)
	)
	for side: float in [-1.0, 1.0]:
		_add(
			"frame",
			Vector3(0.06, STAIR_DOOR.y, casing),
			Vector3(x + side * (STAIR_DOOR.x + 0.06) * 0.5, middle, casing * 0.5)
		)
	# A push bar and a sign above the door, with no light.
	_add("cable", Vector3(STAIR_DOOR.x * 0.7, 0.05, 0.06), Vector3(x, ground - 1.0, leaf + 0.03))
	_add("plate", Vector3(0.42, 0.13, 0.02), Vector3(x, ground - STAIR_DOOR.y - 0.18, 0.02))
	_add("cable", Vector3(0.3, 0.025, 0.01), Vector3(x, ground - STAIR_DOOR.y - 0.18, 0.035))


func _chute(x: float, ground: float) -> void:
	var middle := ground - CHUTE_RISE
	_add("steel", Vector3(CHUTE.x, CHUTE.y, 0.05), Vector3(x, middle, 0.025))
	_add("cable", Vector3(CHUTE.x * 0.6, 0.04, 0.05), Vector3(x, middle - CHUTE.y * 0.32, 0.06))
	_add("plate", Vector3(0.3, 0.08, 0.02), Vector3(x, middle - CHUTE.y * 0.5 - 0.12, 0.02))


## Stores a box: [param at] is x and y in the rules plane, z is from the wall.
func _add(kind: String, size: Vector3, at: Vector3) -> void:
	if not _parts.has(kind):
		_parts[kind] = [] as Array[Transform3D]
	var place := WorldSpace.to_scene(Vector2(at.x, at.y))
	place.z = WorldSpace.BACK_WALL_Z + STANDOFF + at.z
	(_parts[kind] as Array[Transform3D]).append(Transform3D(Basis.from_scale(size), place))


## Material of detail [param kind]: color and look: glowing, window, metal, varnish or
## paint.
func _material(kind: String) -> StandardMaterial3D:
	var look: Array = LOOKS.get(kind, [CABLE, "surface"])
	var colour: Color = look[0]
	match look[1]:
		"light":
			return GreyboxLook.light(colour)
		"window":
			return TimeOfDay.window_look(_time, colour)
		"metal":
			return GreyboxLook.metal(colour)
		"polished":
			return GreyboxLook.polished(colour)
	return GreyboxLook.surface(colour)


func _commit(kind: String) -> void:
	var places: Array[Transform3D] = _parts[kind]
	var box := BoxMesh.new()
	box.material = _material(kind)
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.mesh = box
	many.instance_count = places.size()
	for index: int in places.size():
		many.set_instance_transform(index, places[index])
	var node := MultiMeshInstance3D.new()
	node.name = kind.capitalize()
	node.multimesh = many
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
