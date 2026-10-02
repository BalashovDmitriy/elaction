class_name Passerby
extends RefCounted

## Один прохожий у выезда (ADR-0054, решение 3), собранный из частей: модели
## паков горожан Quaternius модульные — голова, корпус, ноги и обувь — четыре
## части на одном скелете, — и прохожий берёт их от разных моделей своего пола.
## Поверх — свой цвет одежды, волос и кожи и свой рост: толпа из одних и тех же
## восьми моделей читалась бы клонами.

## Как одет прохожий по погоде: налегке, от дождя или от холода
## ([method dress_for]).
enum Dress { LIGHT, WET, COLD }

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
## Кто одет по непогоде — номера в [constant MEN] и [constant WOMEN]: в дождь
## и снег платьев, шорт и футболок на улице нет.
const MEN_COATED: Array[int] = [1, 2, 3]
const WOMEN_COATED: Array[int] = [2, 3]

## Части модели: имя меша кончается этим словом.
const PARTS: Array[String] = ["Head", "Body", "Legs", "Feet"]

## Тона кожи и волос.
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
## Цвета одежды горожанина: тёмно-синий, графит, чёрный, верблюжий, оливковый,
## бордо, деним, серый, бежевый, белый, коричневый, хвойный. Сдвиг тона по
## всему кругу давал голубые волосы и кислотную одежду.
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
## Пальто и плащи: тёмные зимние и цветные дождевые.
const COATS: Array[Color] = [
	Color(0.08, 0.08, 0.1),
	Color(0.2, 0.15, 0.11),
	Color(0.12, 0.14, 0.22),
	Color(0.32, 0.3, 0.28),
	Color(0.4, 0.27, 0.16)
]
const RAINCOATS: Array[Color] = [
	Color(0.72, 0.6, 0.38), Color(0.8, 0.65, 0.1), Color(0.12, 0.16, 0.26), Color(0.15, 0.2, 0.14)
]
## Шапки и шарфы.
const KNITS: Array[Color] = [
	Color(0.55, 0.08, 0.1),
	Color(0.1, 0.12, 0.2),
	Color(0.75, 0.73, 0.68),
	Color(0.18, 0.18, 0.2),
	Color(0.3, 0.35, 0.22),
	Color(0.6, 0.45, 0.2)
]
## Какая доля прохожих в пальто, шапке и шарфе — в холод и в дождь.
const COLD_COAT: float = 1.0
const COLD_HAT: float = 0.65
const COLD_SCARF: float = 0.7
const WET_COAT: float = 0.85
## Размеры в осях модели пака (она ростом 1.85): полы пальто — от бёдер до
## колена, шапка — на макушке, шарф — на шее.
const COAT_HEM := Vector3(0.2, 0.27, 0.52)
const COAT_DROP: float = -0.27
const HAT := Vector2(0.2, 0.15)
const SCARF := Vector2(0.075, 0.14)
## Материалы корпуса, что под пальто не перекрашиваются: воротник рубашки и
## галстук видны из-за отворотов.
const UNDER_COAT: Array[String] = ["White", "Tie"]

## Головы, которых прохожему не надо: у рабочих — каска.
const HELMET_HEADS: Array[String] = ["Worker"]

## Насколько прохожие разного роста, доля.
const HEIGHT_SPREAD: float = 0.05

static var _donors: Dictionary = {}


## Во что одеты на улице в погоду [param weather]: в снег — от холода, в
## дождь — от дождя, иначе налегке.
static func dress_for(weather: Weather.Kind) -> Dress:
	if Weather.is_snowing(weather):
		return Dress.COLD
	if Weather.is_raining(weather):
		return Dress.WET
	return Dress.LIGHT


## Собирает прохожего ростом около [param height], одетого по [param dress].
static func make(rng: RandomNumberGenerator, height: float, dress: Dress) -> Node3D:
	var wet := dress != Dress.LIGHT
	var woman := rng.randf() < 0.5
	var pool := WOMEN if woman else MEN
	var allowed: Array[int] = []
	if wet:
		allowed = WOMEN_COATED if woman else MEN_COATED
	else:
		for index in pool.size():
			allowed.append(index)
	var base := pool[allowed[rng.randi_range(0, allowed.size() - 1)]].instantiate() as Node3D
	for part in PARTS:
		var donor := _part_of(pool[allowed[rng.randi_range(0, allowed.size() - 1)]], part)
		if part == "Head" and donor != null and _helmeted(donor):
			donor = _part_of(pool[_bare_head(pool, rng)], part)
		var mine := _find_part(base, part)
		if donor != null and mine != null:
			mine.mesh = donor.mesh
			mine.skin = donor.skin
	_recolour(base, rng)
	_wrap_up(base, rng, dress)
	var tall := _height_of(base)
	if tall > 0.0:
		var spread := rng.randf_range(1.0 - HEIGHT_SPREAD, 1.0 + HEIGHT_SPREAD)
		base.scale = Vector3.ONE * (height / tall * spread)
	return base


## Часть [param part] модели [param scene] из библиотеки: модели
## разворачиваются один раз и держатся вне дерева только ради своих мешей.
static func _part_of(scene: PackedScene, part: String) -> MeshInstance3D:
	if not _donors.has(scene):
		_donors[scene] = scene.instantiate()
	return _find_part(_donors[scene] as Node, part)


static func _find_part(model: Node, part: String) -> MeshInstance3D:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if node.name.ends_with("_" + part):
			return node as MeshInstance3D
	return null


## Голова в каске: её меш назван по модели рабочего.
static func _helmeted(head: MeshInstance3D) -> bool:
	return HELMET_HEADS.any(func(word: String) -> bool: return head.name.begins_with(word))


## Номер модели в [param pool], у которой голова без каски.
static func _bare_head(pool: Array[PackedScene], rng: RandomNumberGenerator) -> int:
	var bare: Array[int] = []
	for index in pool.size():
		var head := _part_of(pool[index], "Head")
		if head != null and not _helmeted(head):
			bare.append(index)
	return bare[rng.randi_range(0, bare.size() - 1)] if not bare.is_empty() else 0


## Одежда — из палитры горожанина, свой цвет на каждую вещь; волосы — всё на
## голове, кроме кожи, глаз и бровей; кожа — из тонов.
static func _recolour(model: Node3D, rng: RandomNumberGenerator) -> void:
	var skin := SKINS[rng.randi_range(0, SKINS.size() - 1)]
	var hair := HAIRS[rng.randi_range(0, HAIRS.size() - 1)]
	var outfit: Dictionary = {}
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var shape := node as MeshInstance3D
		var on_head := shape.name.ends_with("_Head")
		for surface in shape.mesh.get_surface_count():
			var source := shape.mesh.surface_get_material(surface) as BaseMaterial3D
			if source == null:
				continue
			var name := source.resource_name
			var look := source.duplicate() as BaseMaterial3D
			if name.begins_with("Skin"):
				look.albedo_color = skin * (0.85 if name != "Skin" else 1.0)
			elif name == "Eye":
				continue
			elif name.begins_with("Hair") or name == "Eyebrows" or name == "Moustache" or on_head:
				look.albedo_color = hair
			else:
				if not outfit.has(name):
					outfit[name] = CLOTHES[rng.randi_range(0, CLOTHES.size() - 1)]
				look.albedo_color = outfit[name]
			shape.set_surface_override_material(surface, look)


## Одевает по погоде: пальто с полами до колен, шапка и шарф — деталями на
## костях скелета, корпус под пальто — в цвет пальто.
static func _wrap_up(model: Node3D, rng: RandomNumberGenerator, dress: Dress) -> void:
	if dress == Dress.LIGHT:
		return
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var cold := dress == Dress.COLD
	if rng.randf() < (COLD_COAT if cold else WET_COAT):
		var tones := COATS if cold else RAINCOATS
		var coat := tones[rng.randi_range(0, tones.size() - 1)]
		_coat_the_body(model, coat)
		var hem := CylinderMesh.new()
		hem.top_radius = COAT_HEM.x
		hem.bottom_radius = COAT_HEM.y
		hem.height = COAT_HEM.z
		hem.radial_segments = 12
		hem.cap_top = false
		hem.cap_bottom = false
		_wear(skeleton, "Hips", hem, coat, Vector3(0.0, COAT_DROP, 0.0), "Coat")
	if cold and rng.randf() < COLD_HAT:
		var hat := SphereMesh.new()
		hat.radius = HAT.x
		hat.height = HAT.x
		hat.is_hemisphere = true
		var knit := KNITS[rng.randi_range(0, KNITS.size() - 1)]
		_wear(skeleton, "Head", hat, knit, Vector3(0.0, HAT.y, 0.0), "Hat")
	if cold and rng.randf() < COLD_SCARF:
		var scarf := TorusMesh.new()
		scarf.inner_radius = SCARF.x
		scarf.outer_radius = SCARF.y
		var wool := KNITS[rng.randi_range(0, KNITS.size() - 1)]
		_wear(skeleton, "Neck", scarf, wool, Vector3.ZERO, "Scarf")


## Деталь одежды [param mesh] цвета [param tone] на кости [param bone]: едет
## с костью, со сдвигом [param offset] в её осях.
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


## Корпус под пальто — в цвет пальто, кроме воротника и галстука.
static func _coat_the_body(model: Node3D, coat: Color) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var shape := node as MeshInstance3D
		if not shape.name.ends_with("_Body"):
			continue
		for surface in shape.mesh.get_surface_count():
			var source := shape.mesh.surface_get_material(surface) as BaseMaterial3D
			if source == null or source.resource_name.begins_with("Skin"):
				continue
			if UNDER_COAT.has(source.resource_name):
				continue
			var look := shape.get_surface_override_material(surface) as BaseMaterial3D
			if look != null:
				look.albedo_color = coat


## Рост модели по её видимому, м.
static func _height_of(model: Node3D) -> float:
	var top := -INF
	var bottom := INF
	for node in model.find_children("*", "GeometryInstance3D", true, false):
		var shape := node as GeometryInstance3D
		var box := Shelter._relative(model, shape) * shape.get_aabb()
		top = maxf(top, box.end.y)
		bottom = minf(bottom, box.position.y)
	return top - bottom if top > bottom else 0.0
