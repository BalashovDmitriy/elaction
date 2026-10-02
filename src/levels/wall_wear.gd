class_name WallWear
extends Node3D

## Следы жизни на стенах жилого дома (ADR-0055, решение 4): тэги граффити
## понизу, ржавые пятна и трещины в штукатурке — коридор восьмидесятых, а не
## гостиничный.
##
## Только вид: картинки — плоскости с прозрачностью прямо на штукатурке, без
## тел. Раскладка — без сцены, по плану и сиду ([method lay]), как обстановка
## ([BuildingDressing]): след не ложится на проём двери, портал шахты и
## глухую стену и не налезает на то, что висит на стене. Картинки рисует
## `tools/build_wear.py` в `assets/textures/wear/`.


## След на стене: картинка, этаж, середина по x и по высоте над полом, ширина.
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

## Сколько следов на этаже: с каким шансом свободное место его получает.
const CHANCE: float = 0.45
## Тэг — понизу, на уровне руки, пятно — под потолком, где течёт сверху,
## трещина — где придётся. Середина над полом, м, и ширина, м.
const TAG_RISE := Vector2(0.95, 1.3)
const TAG_WIDTH: float = 1.05
const STAIN_RISE := Vector2(1.9, 2.25)
const STAIN_WIDTH: float = 0.7
const CRACK_RISE := Vector2(1.2, 2.0)
const CRACK_WIDTH: float = 0.9
## Ближе этого к середине предмета на стене след не ложится, м.
const DECOR_CLEAR: float = 0.6
## Зазор следа от занятого на стене: наличник двери и полоса за ним, м.
const ZONE_CLEAR: float = 0.12
## Плоскость — на волосок перед штукатуркой: иначе мерцала бы с ней.
const STANDOFF: float = 0.006
## Свой жребий: следы не ходят в ногу с обстановкой.
const SALT: int = 0x57A1_7E

var marks: Array[Mark] = []


## Следы здания: только у жилого дома, у остальных — пусто.
static func lay(
	rules: BuildingRules,
	plan: BuildingPlan,
	building_seed: int,
	identity: BuildingIdentity,
	dressing: BuildingDressing
) -> Array[Mark]:
	var found: Array[Mark] = []
	if identity == null or identity.kind != BuildingIdentity.Kind.RESIDENTIAL:
		return found
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, SALT])
	# Этаж выхода — гараж: там своя отделка (ADR-0038).
	for index in rules.floors - 1:
		var zones := BuildingDressing.blocked_zones(rules, plan, index)
		for x: float in BuildingDressing.wall_spots(rules, plan, index):
			if rng.randf() >= CHANCE or _near_decor(dressing, index, x):
				continue
			var mark := _draw(rng, index, x)
			if not clashes(zones, mark):
				found.append(mark)
	return found


## Задевает ли след [param mark] занятое на стене: проём двери с наличником,
## портал шахты, глухую стену, пролёт эскалатора. Тэг в проёме висел бы в
## воздухе открытой двери.
static func clashes(zones: Array[Vector2], mark: Mark) -> bool:
	var half := mark.width * 0.5 + ZONE_CLEAR
	for zone: Vector2 in zones:
		if mark.x + half > zone.x and mark.x - half < zone.y:
			return true
	return false


## Ставит плоскости по [param list]: по одному мультимешу на картинку.
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
	elif roll < 0.8:
		mark.image = STAINS[rng.randi_range(0, STAINS.size() - 1)]
		mark.rise = rng.randf_range(STAIN_RISE.x, STAIN_RISE.y)
		mark.width = STAIN_WIDTH
	else:
		mark.image = CRACKS[rng.randi_range(0, CRACKS.size() - 1)]
		mark.rise = rng.randf_range(CRACK_RISE.x, CRACK_RISE.y)
		mark.width = CRACK_WIDTH
	return mark


static func _near_decor(dressing: BuildingDressing, index: int, x: float) -> bool:
	if dressing == null:
		return false
	for hung: BuildingDressing.PropSpot in dressing.decor:
		if hung.floor_index == index and absf(hung.x - x) < DECOR_CLEAR:
			return true
	return false


func _commit(image: String, places: Array[Transform3D]) -> void:
	var quad := QuadMesh.new()
	var look := StandardMaterial3D.new()
	look.albedo_texture = load("%s/%s.png" % [DIR, image]) as Texture2D
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.roughness = 0.9
	look.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	quad.material = look
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.mesh = quad
	many.instance_count = places.size()
	for index in places.size():
		many.set_instance_transform(index, places[index])
	var node := MultiMeshInstance3D.new()
	node.name = image.capitalize()
	node.multimesh = many
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
