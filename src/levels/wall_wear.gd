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
## Голый кирпич, где осыпалась штукатурка (ADR-0056, решение 4).
const BRICKS: PackedStringArray = ["brick_0", "brick_1"]
const BRICK_RISE := Vector2(1.55, 2.05)
const BRICK_WIDTH: float = 1.0

## Сколько следов на этаже: с каким шансом свободное место его получает.
const CHANCE: float = 0.45
## Тэг — на уровне руки, пятно — под потолком, где течёт сверху, трещина — где
## придётся. Ширина, м, и середина над полом, м.
const TAG_WIDTH: float = 1.05
## Низ рисунка тэга — росчерк под строкой — на такую долю ширины ниже середины
## картинки (`tools/build_wear.py`).
const TAG_INK: float = 0.3
## Тэг — над панелью стены с поручнем: картинка лежит на штукатурке, а панель
## ([constant BuildingRibs.SKIRTING_HEIGHT]) выступает перед ней и срезала
## низ букв (кадры авторевью M24m).
const TAG_RISE := Vector2(
	BuildingRibs.SKIRTING_HEIGHT + BuildingRibs.RAIL_HEIGHT + TAG_WIDTH * TAG_INK + 0.04, 1.55
)
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


## Следы здания: только у жилого дома, у остальных — пусто. [param features] —
## устройство стены ([WallFeatures]): окна, щитки и двери стоят на тех же
## местах, и тэг под окном или кирпич под дверью лестницы торчали бы из-за них.
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
	# Что висит на стене, по этажам: иначе каждое место обходило бы всё здание.
	var hung := {}
	if dressing != null:
		for spot: BuildingDressing.PropSpot in dressing.decor:
			if not hung.has(spot.floor_index):
				hung[spot.floor_index] = PackedFloat64Array()
			(hung[spot.floor_index] as PackedFloat64Array).append(spot.x)
	# Устройство стены — занятые отрезки по этажам, как двери и шахты.
	var built := {}
	for feature: WallFeatures.Feature in features:
		if not built.has(feature.floor_index):
			built[feature.floor_index] = [] as Array[Vector2]
		var half: float = WallFeatures.HALF[feature.kind]
		(built[feature.floor_index] as Array[Vector2]).append(
			Vector2(feature.x - half, feature.x + half)
		)
	# Этаж выхода — гараж: там своя отделка (ADR-0038).
	for index: int in rules.floors - 1:
		# На особом этаже стены нет — следам лечь не на что (ADR-0057).
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


## Висит ли что-то из [param decor] этажа (середины по x) ближе
## [constant DECOR_CLEAR] к месту [param x].
static func _near_decor(decor: PackedFloat64Array, x: float) -> bool:
	for hung_x: float in decor:
		if absf(hung_x - x) < DECOR_CLEAR:
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
	for index: int in places.size():
		many.set_instance_transform(index, places[index])
	var node := MultiMeshInstance3D.new()
	node.name = image.capitalize()
	node.multimesh = many
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
