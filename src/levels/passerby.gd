class_name Passerby
extends RefCounted

## One pedestrian at the exit (ADR-0054, decision 3), assembled from parts: the Quaternius
## townsfolk pack models are modular — head, torso, legs and shoes — four
## parts on one skeleton — and a pedestrian takes them from different models of their sex.
## On top — their own colour of clothes, hair and skin and their own height: a crowd of the same
## eight models would read as clones.

## How a pedestrian is dressed ([method dress_for]; ADR-0054, decision 11):
## [code]LIGHT[/code] — lightly, on a clear morning and day; [code]MILD[/code] — in a jacket,
## in fog and on a clear evening and night; [code]WET[/code] — against rain;
## [code]COLD[/code] — against cold, in snow. Except when dressed lightly, only the face is
## open: hands in sleeves and gloves, legs in trousers, boots on the feet.
enum Dress { LIGHT, MILD, WET, COLD }

const MEN: Array[PackedScene] = [
	preload("res://assets/models/people/men_casual_2.glb"),
	preload("res://assets/models/people/men_casual_hoodie.glb"),
	preload("res://assets/models/people/men_suit.glb"),
	preload("res://assets/models/people/men_worker.glb"),
]
const WOMEN: Array[PackedScene] = [
	preload("res://assets/models/people/women_casual.glb"),
	preload("res://assets/models/people/women_formal.glb"),
	preload("res://assets/models/people/women_suit.glb"),
	preload("res://assets/models/people/women_worker.glb"),
]
## Who is not dressed lightly — indices in [constant MEN] and [constant WOMEN]: in
## cool weather, rain and snow there are no dresses, shorts and T-shirts on the street.
const MEN_COATED: Array[int] = [1, 2, 3]
const WOMEN_COATED: Array[int] = [2, 3]

## Model parts: the mesh name ends with this word.
const PARTS: Array[String] = ["Head", "Body", "Legs", "Feet"]

## Skin and hair tones.
const SKINS: Array[Color] = [
	Color(0.96, 0.8, 0.69),
	Color(0.87, 0.67, 0.53),
	Color(0.72, 0.52, 0.38),
	Color(0.55, 0.38, 0.26),
	Color(0.38, 0.26, 0.18)
]
const HAIRS: Array[Color] = [
	Color(0.08, 0.06, 0.05),
	Color(0.26, 0.16, 0.09),
	Color(0.47, 0.32, 0.18),
	Color(0.78, 0.63, 0.38),
	Color(0.55, 0.55, 0.56),
	Color(0.45, 0.13, 0.07)
]
## Townsperson clothing colours: navy, graphite, black, camel, olive,
## burgundy, denim, grey, beige, white, brown, forest green. Shifting the hue around
## the whole wheel gave blue hair and acid clothing.
const CLOTHES: Array[Color] = [
	Color(0.1, 0.13, 0.24),
	Color(0.17, 0.18, 0.2),
	Color(0.05, 0.05, 0.06),
	Color(0.62, 0.46, 0.3),
	Color(0.3, 0.32, 0.18),
	Color(0.36, 0.08, 0.1),
	Color(0.22, 0.32, 0.48),
	Color(0.45, 0.46, 0.48),
	Color(0.74, 0.68, 0.56),
	Color(0.86, 0.86, 0.84),
	Color(0.3, 0.2, 0.13),
	Color(0.1, 0.24, 0.18)
]
## Sleeves and gloves where a light outfit has a bare arm — without skin colours:
## a brown and beige sleeve read as a bare arm.
const SLEEVES: Array[Color] = [
	Color(0.1, 0.13, 0.24),
	Color(0.17, 0.18, 0.2),
	Color(0.05, 0.05, 0.06),
	Color(0.3, 0.32, 0.18),
	Color(0.36, 0.08, 0.1),
	Color(0.22, 0.32, 0.48),
	Color(0.45, 0.46, 0.48),
	Color(0.1, 0.24, 0.18)
]
## Coats and raincoats: dark winter ones and coloured rain ones.
const COATS: Array[Color] = [
	Color(0.08, 0.08, 0.1),
	Color(0.2, 0.15, 0.11),
	Color(0.12, 0.14, 0.22),
	Color(0.32, 0.3, 0.28),
	Color(0.4, 0.27, 0.16)
]
## Without beige: raincoat sleeves and gloves are one colour, and beige ones read
## as bare hands.
const RAINCOATS: Array[Color] = [
	Color(0.8, 0.65, 0.1), Color(0.12, 0.16, 0.26), Color(0.15, 0.2, 0.14), Color(0.2, 0.2, 0.22)
]
## Hats and scarves.
const KNITS: Array[Color] = [
	Color(0.55, 0.08, 0.1),
	Color(0.1, 0.12, 0.2),
	Color(0.75, 0.73, 0.68),
	Color(0.18, 0.18, 0.2),
	Color(0.3, 0.35, 0.22),
	Color(0.6, 0.45, 0.2)
]
## What share of pedestrians wear a coat, hat and scarf — in cold and in rain.
const COLD_COAT: float = 1.0
const COLD_HAT: float = 0.65
const COLD_SCARF: float = 0.7
const WET_COAT: float = 0.85
## Sizes in the pack model's axes (it is 1.85 tall): the hat — knitted, by the head
## — radius, height and lift above the head bone; the scarf — inner and outer
## radius and lift above the neck bone. Coat skirts are not made as a detail on a bone:
## a stiff hem on the hips read as a bag when walking (M24l frames) — the coat is
## the torso in its colour, sleeves down to the gloves and dark trousers.
const HAT := Vector3(0.172, 0.14, 0.165)
## Hat cuff: ring thickness.
const HAT_CUFF: float = 0.035
const SCARF := Vector3(0.055, 0.1, 0.0)
## What is visible under the coat behind the lapels: a tie. The rest of the torso is in the coat
## colour: a light T-shirt under it would read as a bare chest.
const UNDER_COAT: Array[String] = ["Tie"]
## What covers what is open in a light outfit: trousers or tights, boots.
const LEGWEAR: Array[Color] = [
	Color(0.07, 0.07, 0.08), Color(0.13, 0.14, 0.18), Color(0.22, 0.2, 0.18), Color(0.1, 0.12, 0.2)
]
const BOOTS: Array[Color] = [
	Color(0.05, 0.04, 0.04), Color(0.2, 0.12, 0.07), Color(0.12, 0.12, 0.13)
]

## Heads a pedestrian does not need: workers have a hard hat.
const HELMET_HEADS: Array[String] = ["Worker"]

## How much pedestrians differ in height, fraction.
const HEIGHT_SPREAD: float = 0.05


## A library model part: mesh, skin and the node name that reveals a hard hat.
class Part:
	extends RefCounted
	var mesh: Mesh = null
	var skin: Skin = null
	var node_name: String = ""


## Library model parts by scene: by part name — a [Part]. Resources are stored,
## not nodes: a model is instantiated once and freed right away.
## Nodes outside the tree do not go away by themselves, and a node cache would hold eight models
## until the game exits, and on exit — as a leak (code review M24l).
static var _donors: Dictionary = {}


## What people wear on the street in weather [param weather] at time of day [param time]:
## in snow — against cold, in rain — against rain, in fog and on clear evenings and nights —
## jackets, on clear mornings and days — lightly.
static func dress_for(weather: Weather.Kind, time: TimeOfDay.Kind = TimeOfDay.Kind.DAY) -> Dress:
	if Weather.is_snowing(weather):
		return Dress.COLD
	if Weather.is_raining(weather):
		return Dress.WET
	if weather == Weather.Kind.FOG or not TimeOfDay.is_daytime(time):
		return Dress.MILD
	return Dress.LIGHT


## Assembles a pedestrian about [param height] tall, dressed per [param dress].
static func make(rng: RandomNumberGenerator, height: float, dress: Dress) -> Node3D:
	var covered := dress != Dress.LIGHT
	var woman := rng.randf() < 0.5
	var pool := WOMEN if woman else MEN
	var allowed: Array[int] = []
	if covered:
		allowed = WOMEN_COATED if woman else MEN_COATED
	else:
		for index in pool.size():
			allowed.append(index)
	var base := pool[allowed[rng.randi_range(0, allowed.size() - 1)]].instantiate() as Node3D
	for part in PARTS:
		var donor := _part_of(pool[allowed[rng.randi_range(0, allowed.size() - 1)]], part)
		# Unless dressed lightly, legs are only in trousers: shorts and a skirt with bare legs under
		# dark "tights" read as patches (M24l frames).
		if part == "Legs" and covered and donor != null and _bare(donor):
			donor = _covered_legs(pool, rng)
		if part == "Head" and donor != null and _helmeted(donor):
			donor = _part_of(pool[_bare_head(pool, rng)], part)
		var mine := _find_part(base, part)
		if donor != null and mine != null:
			mine.mesh = donor.mesh
			mine.skin = donor.skin
	var coat := _coat_for(rng, dress)
	_recolour(base, rng, dress, coat)
	_wrap_up(base, rng, dress)
	var tall := _height_of(base)
	if tall > 0.0:
		var spread := rng.randf_range(1.0 - HEIGHT_SPREAD, 1.0 + HEIGHT_SPREAD)
		base.scale = Vector3.ONE * (height / tall * spread)
	return base


## Part [param part] of model [param scene] from the library, or null.
static func _part_of(scene: PackedScene, part: String) -> Part:
	if not _donors.has(scene):
		var parts: Dictionary = {}
		var model := scene.instantiate()
		for part_name in PARTS:
			var shape := _find_part(model, part_name)
			if shape == null:
				continue
			var piece := Part.new()
			piece.mesh = shape.mesh
			piece.skin = shape.skin
			piece.node_name = shape.name
			parts[part_name] = piece
		model.free()
		_donors[scene] = parts
	return (_donors[scene] as Dictionary).get(part) as Part


static func _find_part(model: Node, part: String) -> MeshInstance3D:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if node.name.ends_with("_" + part):
			return node as MeshInstance3D
	return null


## Whether the part has exposed skin.
static func _bare(part: Part) -> bool:
	for surface in part.mesh.get_surface_count():
		var look := part.mesh.surface_get_material(surface)
		if look != null and look.resource_name.begins_with("Skin"):
			return true
	return false


## Legs in trousers — from any model in [param pool] that has them.
static func _covered_legs(pool: Array[PackedScene], rng: RandomNumberGenerator) -> Part:
	var dressed: Array[Part] = []
	for scene in pool:
		var legs := _part_of(scene, "Legs")
		if legs != null and not _bare(legs):
			dressed.append(legs)
	return dressed[rng.randi_range(0, dressed.size() - 1)] if not dressed.is_empty() else null


## A head in a hard hat: its mesh is named after the worker model.
static func _helmeted(head: Part) -> bool:
	return HELMET_HEADS.any(func(word: String) -> bool: return head.node_name.begins_with(word))


## Index of a model in [param pool] whose head has no hard hat.
static func _bare_head(pool: Array[PackedScene], rng: RandomNumberGenerator) -> int:
	var bare: Array[int] = []
	for index in pool.size():
		var head := _part_of(pool[index], "Head")
		if head != null and not _helmeted(head):
			bare.append(index)
	return bare[rng.randi_range(0, bare.size() - 1)] if not bare.is_empty() else 0


## A coat by weather: in cold — everyone, dark; in rain — a raincoat for most;
## [code]Color(0, 0, 0, 0)[/code] — no coat.
static func _coat_for(rng: RandomNumberGenerator, dress: Dress) -> Color:
	if dress == Dress.COLD and rng.randf() < COLD_COAT:
		return COATS[rng.randi_range(0, COATS.size() - 1)]
	if dress == Dress.WET and rng.randf() < WET_COAT:
		return RAINCOATS[rng.randi_range(0, RAINCOATS.size() - 1)]
	return Color(0.0, 0.0, 0.0, 0.0)


## Clothes — from the townsperson palette, its own colour for each item; hair — everything on
## the head except skin, eyes and brows; skin — from the tones. Unless dressed lightly only the
## face is open: torso skin — sleeves and gloves in the coat or jacket colour,
## leg skin — trousers, feet — boots. Under a coat the whole torso is in its colour.
static func _recolour(model: Node3D, rng: RandomNumberGenerator, dress: Dress, coat: Color) -> void:
	var skin := SKINS[rng.randi_range(0, SKINS.size() - 1)]
	var hair := HAIRS[rng.randi_range(0, HAIRS.size() - 1)]
	var jacket := coat if coat.a > 0.0 else SLEEVES[rng.randi_range(0, SLEEVES.size() - 1)]
	var legwear := LEGWEAR[rng.randi_range(0, LEGWEAR.size() - 1)]
	var boots := BOOTS[rng.randi_range(0, BOOTS.size() - 1)]
	var covered := dress != Dress.LIGHT
	var outfit: Dictionary = {}
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var shape := node as MeshInstance3D
		var part := _part_name(shape)
		for surface in shape.mesh.get_surface_count():
			var source := shape.mesh.surface_get_material(surface) as BaseMaterial3D
			if source == null:
				continue
			var name := source.resource_name
			var look := source.duplicate() as BaseMaterial3D
			var bare := name.begins_with("Skin")
			if part == "Head":
				if name == "Eye":
					continue
				look.albedo_color = skin if bare else hair
			elif bare and covered:
				look.albedo_color = {"Body": jacket, "Legs": legwear}.get(part, boots)
			elif bare:
				look.albedo_color = skin * (0.85 if name != "Skin" else 1.0)
			elif part == "Body" and covered and not UNDER_COAT.has(name) and name != "White":
				# Top and sleeves are one item: the coat, and without it — a long-sleeved
				# sweater. Sleeves of a different colour read as sewn-on arms.
				look.albedo_color = jacket
			elif part == "Feet" and covered:
				look.albedo_color = boots
			else:
				# One item — one colour: worker trousers have knee pads and the vest has
				# inserts in their own material, and in motley colours they read as patches.
				var piece := name if name == "White" or name == "Tie" else part
				if not outfit.has(piece):
					outfit[piece] = CLOTHES[rng.randi_range(0, CLOTHES.size() - 1)]
				look.albedo_color = outfit[piece]
			shape.set_surface_override_material(surface, look)


## The model part the mesh belongs to: Head, Body, Legs, Feet or empty.
static func _part_name(shape: MeshInstance3D) -> String:
	for part in PARTS:
		if shape.name.ends_with("_" + part):
			return part
	return ""


## Dresses for the weather: hat and scarf as details on skeleton bones.
static func _wrap_up(model: Node3D, rng: RandomNumberGenerator, dress: Dress) -> void:
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var cold := dress == Dress.COLD
	if cold and rng.randf() < COLD_HAT:
		# Knitted hat: a dome as wide as the hairstyle from the forehead up, and a cuff
		# ring. As a ball on the head it slid over the eyes like a headband (M24l frames).
		var hat := SphereMesh.new()
		hat.radius = HAT.x
		hat.height = HAT.y
		hat.is_hemisphere = true
		var knit := KNITS[rng.randi_range(0, KNITS.size() - 1)]
		_wear(skeleton, "Head", hat, knit, Vector3(0.0, HAT.z, 0.0), "Hat")
		var cuff := TorusMesh.new()
		cuff.inner_radius = HAT.x - HAT_CUFF
		cuff.outer_radius = HAT.x + HAT_CUFF * 0.3
		_wear(skeleton, "Head", cuff, knit.darkened(0.15), Vector3(0.0, HAT.z, 0.0), "HatCuff")
	if cold and rng.randf() < COLD_SCARF:
		var scarf := TorusMesh.new()
		scarf.inner_radius = SCARF.x
		scarf.outer_radius = SCARF.y
		var wool := KNITS[rng.randi_range(0, KNITS.size() - 1)]
		_wear(skeleton, "Neck", scarf, wool, Vector3(0.0, SCARF.z, 0.0), "Scarf")


## Clothing detail [param mesh] of colour [param tone] on bone [param bone]: moves
## with the bone, offset by [param offset] in its axes.
static func _wear(
	skeleton: Skeleton3D,
	bone: String,
	mesh: PrimitiveMesh,
	tone: Color,
	offset: Vector3,
	name: String
) -> void:
	var holder := BoneAttachment3D.new()
	holder.name = name
	holder.bone_name = bone
	skeleton.add_child(holder)
	var look := StandardMaterial3D.new()
	look.albedo_color = tone
	look.roughness = 0.9
	mesh.material = look
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.position = offset
	holder.add_child(piece)


## Model height by its visible part, m.
static func _height_of(model: Node3D) -> float:
	var top := -INF
	var bottom := INF
	for node in model.find_children("*", "GeometryInstance3D", true, false):
		var shape := node as GeometryInstance3D
		var box := Shelter.relative(model, shape) * shape.get_aabb()
		top = maxf(top, box.end.y)
		bottom = minf(bottom, box.position.y)
	return top - bottom if top > bottom else 0.0
