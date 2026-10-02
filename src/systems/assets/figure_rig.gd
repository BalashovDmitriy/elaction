class_name FigureRig
extends Node3D

## Скелет актёра: клипы пака и позы кодом (ADR-0032, решение 1).
##
## Модель приходит из `.glb`, собранного `tools/build_actors.py` из пака
## Quaternius: скелет в 62 кости и четыре клипа. Какой позе что играть, решает
## [FigurePoses]; риг превращает позу любой природы в одно и то же — кадр,
## набор поворотов и сдвигов костей, — и каждый кадр ведёт скелет к нему
## сферической интерполяцией по каждой кости. Поэтому переход из клипа в позу
## кодом такое же движение, как было сглаживание углов с M16.
##
## Клип читается напрямую, `Animation.rotation_track_interpolate` на нужный
## момент, без [AnimationPlayer] и [AnimationTree]: так `snap()` ставит позу
## сразу, а габарит по скиннутым вершинам считается от того же кадра.
##
## Начало узла — в ногах актёра: актёр ставит риг на свой пол, а поворот к
## камере и наклон тела — дело рига.
##
## Обводки с M24f нет (ADR-0042, решение 7): на свету она читалась неестественно.
## Читаемость в темноте держит свет — меши фигуры лежат на своём слое
## [constant RENDER_LAYER], и на него светит слабый свет камеры
## ([method SideCamera.actor_fill]), которому окружение не подчиняется.

## Слой рендера фигур: на него и только на него светит свет камеры.
const RENDER_LAYER: int = 1 << 11

## Кости пака, которые двигают позы кодом. Те же имена у всех персонажей пака.
const HIPS := "Hips"
const ABDOMEN := "Abdomen"
const TORSO := "Torso"
const CHEST := "Chest"
const NECK := "Neck"
const HEAD := "Head"
const ARM_L := "UpperArm.L"
const ARM_R := "UpperArm.R"
const ELBOW_L := "LowerArm.L"
const ELBOW_R := "LowerArm.R"
const LEG_L := "UpperLeg.L"
const LEG_R := "UpperLeg.R"
const KNEE_L := "LowerLeg.L"
const KNEE_R := "LowerLeg.R"
## Стопы пака прицеплены не к голеням, а к корню: скелет собран под IK. В
## клипах поворот запечён, а в позе кодом стопу ставит на конец голени риг.
const FOOT_L := "Foot.L"
const FOOT_R := "Foot.R"
## Кисть с пистолетом: ствол лежит вдоль пальцев (`build_actors.py`, `_gun`).
const GUN_HAND := "Wrist.R"
## Вторая кисть, которой держат рукоять снизу, и насколько она ниже первой, м.
const SUPPORT_HAND := "Wrist.L"
const SUPPORT_DROP: float = 0.04
const BONES: PackedStringArray = [
	HIPS,
	ABDOMEN,
	TORSO,
	CHEST,
	NECK,
	HEAD,
	ARM_L,
	ARM_R,
	ELBOW_L,
	ELBOW_R,
	LEG_L,
	LEG_R,
	KNEE_L,
	KNEE_R,
	FOOT_L,
	FOOT_R,
]

## Как наклон корпуса делится между позвонками: гнётся спина, а не шарнир.
const LEAN_SHARE := {ABDOMEN: 0.45, TORSO: 0.35, CHEST: 0.2}
const HEAD_SHARE := {NECK: 0.5, HEAD: 0.5}

## Направлений, по которым выбираются крайние вершины каждой кости для
## заземления: шесть осей и восемь углов куба.
const HULL_DIRECTIONS: Array[Vector3] = [
	Vector3.RIGHT,
	Vector3.LEFT,
	Vector3.UP,
	Vector3.DOWN,
	Vector3.FORWARD,
	Vector3.BACK,
	Vector3(1, 1, 1),
	Vector3(1, 1, -1),
	Vector3(1, -1, 1),
	Vector3(1, -1, -1),
	Vector3(-1, 1, 1),
	Vector3(-1, 1, -1),
	Vector3(-1, -1, 1),
	Vector3(-1, -1, -1),
]
## Ещё двенадцать — середины рёбер куба: для жёстких частей на одной кости
## ([method SkinnedSurface._pick_hull]).
const HULL_EDGES: Array[Vector3] = [
	Vector3(1, 1, 0),
	Vector3(1, -1, 0),
	Vector3(-1, 1, 0),
	Vector3(-1, -1, 0),
	Vector3(1, 0, 1),
	Vector3(1, 0, -1),
	Vector3(-1, 0, 1),
	Vector3(-1, 0, -1),
	Vector3(0, 1, 1),
	Vector3(0, 1, -1),
	Vector3(0, -1, 1),
	Vector3(0, -1, -1),
]

## Шейдер порванной фигуры (ADR-0043, решения 8 и 11).
const CARVE_SHADER := preload("res://src/systems/combat/carve.gdshader")

## Куда смотрит модель, повёрнутая лицом вправо и влево: поворот на четверть
## оборота кладёт взгляд вдоль этажа, а в покое она смотрит в камеру (+Z).
const FACE_RIGHT: float = PI * 0.5


## Поверхность меша, снятая один раз: вершины, привязка к костям и веса.
##
## [method Mesh.surface_get_arrays] копирует все массивы поверхности на каждый
## вызов, а габарит по вершинам нужен на переходах между позами. Снятое при
## рождении копируется один раз.
class SkinnedSurface:
	extends RefCounted

	var mesh_instance: MeshInstance3D
	## Номер поверхности в меше.
	var index: int = 0
	var vertices := PackedVector3Array()
	var bone_ids := PackedInt32Array()
	var weights := PackedFloat32Array()
	## Костей на вершину: 0 у поверхности без привязки — она стоит как есть.
	var per_vertex: int = 0
	## Крайние вершины каждой кости: по ним риг заземляет позу на ходу.
	var hull := PackedInt32Array()

	static func of(instance: MeshInstance3D, surface: int) -> SkinnedSurface:
		var made := SkinnedSurface.new()
		made.mesh_instance = instance
		made.index = surface
		var arrays := instance.mesh.surface_get_arrays(surface)
		made.vertices = arrays[Mesh.ARRAY_VERTEX]
		# У поверхности без скина костей и весов нет вовсе — там null, не пустой
		# массив, и в типизированное поле его не положить.
		var bones: Variant = arrays[Mesh.ARRAY_BONES]
		var bone_weights: Variant = arrays[Mesh.ARRAY_WEIGHTS]
		if instance.skin == null or bones == null or bone_weights == null:
			made.hull = PackedInt32Array(range(made.vertices.size()))
			return made
		# Индексы костей движок отдаёт целыми либо вещественными — как лёг импорт.
		made.bone_ids = bones if bones is PackedInt32Array else PackedInt32Array(Array(bones))
		made.weights = bone_weights
		made.per_vertex = made.bone_ids.size() / maxi(made.vertices.size(), 1)
		made.hull = made._pick_hull()
		return made

	## Главная привязка вершины — кость с наибольшим весом.
	func main_bind(index: int) -> int:
		var best := 0
		var best_weight := -1.0
		for slot in per_vertex:
			var weight := weights[index * per_vertex + slot]
			if weight > best_weight:
				best_weight = weight
				best = bone_ids[index * per_vertex + slot]
		return best

	## Вершины, крайние по [constant HULL_DIRECTIONS] среди своей кости.
	## Кость поворачивается почти жёстко, и крайняя в покое остаётся крайней
	## в позе: габарит по ним расходится с полным на миллиметры, а вершин
	## в десять раз меньше.
	func _pick_hull() -> PackedInt32Array:
		var best := {}
		for index in vertices.size():
			var bind := main_bind(index)
			if not best.has(bind):
				var fresh: Array[int] = []
				fresh.resize(HULL_DIRECTIONS.size())
				fresh.fill(index)
				best[bind] = fresh
			var picks: Array[int] = best[bind]
			for slot in HULL_DIRECTIONS.size():
				var direction := HULL_DIRECTIONS[slot]
				if vertices[index].dot(direction) > vertices[picks[slot]].dot(direction):
					picks[slot] = index
		var chosen := {}
		for picks: Array[int] in best.values():
			for index in picks:
				chosen[index] = true
		# Жёсткая часть на одной кости — шляпа, кепка — лёжа касается пола точкой
		# между осями и углами куба: по ним одним кепка жилого дома уходила в пол
		# на полтора сантиметра (авторевью M24m). Ей — и рёбра куба: вершин на ней
		# сотни, а не тысячи, и лишних в крайних — дюжина.
		if best.size() == 1:
			for direction: Vector3 in HULL_EDGES:
				var pick := 0
				for index: int in vertices.size():
					if vertices[index].dot(direction) > vertices[pick].dot(direction):
						pick = index
				chosen[pick] = true
		return PackedInt32Array(chosen.keys())


## Кадр скелета: поворот и сдвиг каждой кости и то, что идёт всей модели.
class Frame:
	extends RefCounted

	var rotations: Array[Quaternion] = []
	var positions := PackedVector3Array()
	var tilt: float = 0.0
	var lift: float = 0.0
	var squash: float = 1.0

	## Своя копия: массивы копируются целиком, без интерполяции по костям.
	func copy() -> Frame:
		var twin := Frame.new()
		twin.rotations = rotations.duplicate()
		twin.positions = positions.duplicate()
		twin.tilt = tilt
		twin.lift = lift
		twin.squash = squash
		return twin

	## Смесь двух кадров: [param weight] 0 — этот, 1 — [param other].
	func blend(other: Frame, weight: float) -> Frame:
		var t := clampf(weight, 0.0, 1.0)
		var mixed := Frame.new()
		mixed.rotations.resize(rotations.size())
		mixed.positions.resize(positions.size())
		for bone in rotations.size():
			mixed.rotations[bone] = rotations[bone].slerp(other.rotations[bone], t)
			mixed.positions[bone] = positions[bone].lerp(other.positions[bone], t)
		mixed.tilt = lerpf(tilt, other.tilt, t)
		mixed.lift = lerpf(lift, other.lift, t)
		mixed.squash = lerpf(squash, other.squash, t)
		return mixed


## Клип, разобранный на дорожки: какая дорожка какую кость ведёт.
class ClipTracks:
	extends RefCounted

	var animation: Animation
	var rotation_tracks := PackedInt32Array()
	var rotation_bones := PackedInt32Array()
	var position_tracks := PackedInt32Array()
	var position_bones := PackedInt32Array()

	func length() -> float:
		return animation.length


## Материалы порванных фигур по исходным: один шейдер на материал пака, а срез у
## каждой фигуры свой — параметрами экземпляра.
static var _carve_materials: Dictionary = {}

## Модель актёра. Без неё риг — пустой узел, и это ошибка сцены.
@export var model: PackedScene

## Куда наводить дуло, пока актёр стреляет: высота над ступнями и вынос
## вперёд, м, — точка, откуда вылетает пуля по правилам ROM (ADR-0043,
## решение 16). NAN — не наводить: рука ходит клипом.
var aim_height: float = NAN
var aim_reach: float = Proportions.MUZZLE

## Во сколько раз быстрее мира идут часы рига. Сценка добивания замедляет мир,
## а двое в ней двигаются в своём темпе (ADR-0040).
var speed: float = 1.0

## Наклон вперёд «вокруг пяток» и подъём над полом идут не костям, а самой
## модели: у скелета нет кости, которой можно уложить тело целиком.
var _instance: Node3D = null
var _skeleton: Skeleton3D = null
var _meshes: Array[MeshInstance3D] = []
var _surfaces: Array[SkinnedSurface] = []
var _bones: Dictionary = {}
var _clips: Dictionary = {}
## Кадр покоя скелета: основа кадров клипа. Снят один раз — клип на ходу
## собирается каждый кадр, а покой не меняется.
var _rest: Frame = null
## Первый кадр стойки: основа поз кодом. Его глобальные положения костей
## посчитаны один раз — от них берутся оси поворотов.
var _stand: Frame = null
var _stand_globals: Array[Transform3D] = []
## Позы кодом неизменны: кадр каждой считается один раз на риг.
var _code_frames: Dictionary = {}
## Рост в покое, м.
var _height: float = 0.0

var _pose_name := "idle"
## Сколько секунд стоит текущая поза: по ним идут клипы «один раз».
var _pose_time: float = 0.0
## Часы рига: по ним крутится стойка.
var _clock: float = 0.0
## Часы ходьбы, с: копятся из фазы актёра, а не из кадров, — встал актёр,
## встали и ноги.
var _walk_clock: float = 0.0
var _walk_phase: float = 0.0
var _current: Frame = null
## Кадр, в котором риг стоял, когда сменилась поза: из него идёт переход.
var _from: Frame = null
## Сколько длится переход в текущую позу, с ([method FigurePoses.blend_time]).
var _blend: float = FigurePoses.BLEND_DEFAULT
## Разворот (ADR-0039, решение 3): откуда и куда поворачивается тело и сколько
## секунд он уже идёт. Поворот идёт через «лицом в камеру», а не спиной к ней.
var _yaw_from: float = FACE_RIGHT
var _yaw_to: float = FACE_RIGHT
var _turned: float = MoveLocks.TURN_TIME
## Смотрел ли риг уже куда-нибудь: первый взгляд ставится сразу, без разворота.
var _faced: bool = false
## Переход кончился: риг стоит в кадре позы. У неподвижной цели (поза кодом,
## конец клипа) раскладывать больше нечего — стоящих и лежащих каждый кадр
## перебирали бы вершины впустую; клип стойки и ходьбы риг дальше просто играет.
var _settled: bool = false
## Что от тела отрезано под днищем кабины: x от, x до, высота днища. Пусто —
## не резано.
var _carved := Vector4.ZERO
## Дуло пистолета в системе кисти [constant GUN_HAND]; NAN — пистолета нет.
var _muzzle := Vector3(NAN, NAN, NAN)
## Наведена ли рука в последнем разложенном кадре: застывший риг раскладывает
## кадр ещё раз, когда наведение снимают, — иначе рука так и висела бы вскинутой.
var _aim_shown: bool = false


func _ready() -> void:
	if model == null:
		push_error("FigureRig без модели: %s" % get_path())
		return
	_instance = model.instantiate() as Node3D
	add_child(_instance)
	# Проигрыватель импорта не нужен: клипы читает риг. Остановленный, он не
	# тронет скелет и не потратит кадр.
	for player in _instance.find_children("*", "AnimationPlayer", true, false):
		(player as AnimationPlayer).stop()
		(player as AnimationPlayer).process_mode = Node.PROCESS_MODE_DISABLED

	var found := _instance.find_children("*", "Skeleton3D", true, false)
	_skeleton = found[0] as Skeleton3D if not found.is_empty() else null
	if _skeleton == null:
		push_error("в модели нет скелета: %s" % model.resource_path)
		return
	for bone_name in BONES:
		var index := _skeleton.find_bone(bone_name)
		if index < 0:
			push_error("в модели нет кости %s: %s" % [bone_name, model.resource_path])
			continue
		_bones[bone_name] = index
	_rest = _read_rest()
	_read_clips()

	for node in _instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		mesh_instance.layers |= RENDER_LAYER
		_meshes.append(mesh_instance)
		for surface in mesh_instance.mesh.get_surface_count():
			_surfaces.append(SkinnedSurface.of(mesh_instance, surface))

	_muzzle = _find_muzzle()
	_stand = _clip_frame(FigurePoses.CLIP_STAND, 0.0)
	_stand_globals = _globals(_stand)
	_current = _wanted()
	_settled = true
	_apply(_current, true)
	_height = skinned_aabb().end.y


func _process(delta: float) -> void:
	advance(delta * speed)


## Шаг перехода: кости идут от кадра, где риг стоял при смене позы, к кадру
## позы за время перехода, по сглаженной кривой — и приходят ровно в срок.
## Зовётся из [method Node._process]; тестам отдан наружу, потому что длина
## кадра в headless-прогоне не 1/60, а «сколько получится».
func advance(delta: float) -> void:
	if _skeleton == null:
		return
	# Неподвижная цель — поза кодом, конец клипа: долетев до неё, риг замирает.
	# Проверка до шага часов: клип «один раз» успевает встать в последний кадр.
	# Наводимая рука не замирает: присевший стреляет, не меняя позы (ADR-0043,
	# решение 16), и опускает её, когда выстрел кончился.
	var frozen := _settled and _is_still() and not _aims() and not _aim_shown
	_pose_time += delta
	_clock += delta
	_turned += delta
	if frozen:
		return
	var wanted := _wanted()
	if not _settled:
		# Переход — смесь кадра, из которого риг ушёл, с живым кадром цели. Клип
		# идёт своим ходом и во время перехода: гоняясь за ним сглаживанием, риг
		# волочился бы за ходьбой с отставанием в 15° и не догонял бы никогда.
		var progress := _pose_time / _blend if _blend > 0.0 else 1.0
		_settled = _from == null or progress >= 1.0
		if not _settled:
			wanted = _from.blend(wanted, smoothstep(0.0, 1.0, progress))
	_current = wanted
	_apply(_current, false)


## Какую позу показывать. Имена — из [ActorPose]; ходьба берёт фазу из
## [method set_walk_phase] и идёт клипом.
func show_pose(pose_name: String) -> void:
	if pose_name == _pose_name:
		return
	var was_walking := _pose_name.begins_with("walk_")
	_pose_name = pose_name
	# Кадры ходьбы — одна поза клипом: смена кадра не перезапускает переход.
	if was_walking and pose_name.begins_with("walk_"):
		return
	_from = _current
	_pose_time = 0.0
	_blend = FigurePoses.blend_time(pose_name)
	_settled = false


## Фаза ходьбы, 0..[constant ActorPose.WALK_FRAMES]. Актёр ведёт её сам; риг
## копит из её приращений свои часы ходьбы.
func set_walk_phase(phase: float) -> void:
	var step := phase - _walk_phase
	if step < 0.0:
		step += float(ActorPose.WALK_FRAMES)
	_walk_phase = phase
	_walk_clock += step / ActorPose.WALK_FPS


## Куда актёр смотрит: -1 влево, +1 вправо. Смена стороны — разворот телом за
## [constant MoveLocks.TURN_TIME]: столько же актёр стоит на месте. Зовётся
## каждый кадр; поворот копится по часам рига, а ставится здесь, чтобы актёр
## мог довернуть тело поверх (Otto у машины поворачивается спиной к камере).
##
## [param instant] — встать сразу, без разворота: так ложится убитый, которого
## [Enemy] переворачивает, чтобы тело упало на пол, а не над проёмом. Разворот —
## движение живого, и труп, крутящийся волчком в падении, был бы ошибкой.
func face(direction: float, instant: bool = false) -> void:
	var wanted := FACE_RIGHT if direction >= 0.0 else -FACE_RIGHT
	if not _faced or instant:
		_faced = true
		_yaw_from = wanted
		_yaw_to = wanted
	elif not is_equal_approx(wanted, _yaw_to):
		_yaw_from = rotation.y
		_yaw_to = wanted
		_turned = 0.0
	var progress := clampf(_turned / MoveLocks.TURN_TIME, 0.0, 1.0)
	rotation.y = lerpf(_yaw_from, _yaw_to, smoothstep(0.0, 1.0, progress))


## Прозрачность всех мешей: 0 — сплошной, 1 — невидим. Так мигает неуязвимый.
func set_transparency(value: float) -> void:
	for mesh_instance in _meshes:
		mesh_instance.transparency = value


## Срезает всё, что между [param from_x] и [param to_x] выше [param bottom], в
## координатах мира: так тело режет днище кабины ([CarCut]).
func carve_under(from_x: float, to_x: float, bottom: float) -> void:
	_carved = Vector4(from_x, to_x, bottom, 1.0)
	_cut_materials()
	for mesh_instance in _meshes:
		mesh_instance.set_instance_shader_parameter(&"carve", _carved)


## Прячет кости [param names] и всё, что они тянут: так пропадает часть тела,
## отрезанная от рэгдолла ([Ragdoll]). Пустой список — всё видно.
func hide_bones(names: PackedStringArray) -> void:
	if not names.is_empty():
		_cut_materials()
	for mesh_instance in _meshes:
		var mask := Vector2i.ZERO
		var skin := mesh_instance.skin
		if skin != null:
			for bind in skin.get_bind_count():
				var bone := skin.get_bind_bone(bind)
				var bone_name := (
					_skeleton.get_bone_name(bone) if bone >= 0 else String(skin.get_bind_name(bind))
				)
				if names.has(bone_name):
					if bind < 32:
						mask.x |= 1 << bind
					else:
						mask.y |= 1 << (bind - 32)
		mesh_instance.set_instance_shader_parameter(&"hidden_bones", mask)


## Где дуло пистолета сейчас, в мире; NAN, если пистолета нет.
func muzzle_position() -> Vector3:
	var hand := _skeleton.find_bone(GUN_HAND) if _skeleton != null else -1
	if hand < 0 or is_nan(_muzzle.x):
		return Vector3(NAN, NAN, NAN)
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(hand) * _muzzle


## Скелет фигуры: на нём собирается рэгдолл.
func skeleton() -> Skeleton3D:
	return _skeleton


## Возвращает телу всё отрезанное: воскресший Otto целый.
func heal() -> void:
	_carved = Vector4.ZERO
	for mesh_instance in _meshes:
		# Срез — параметр экземпляра, а не материала: снятый материал его не
		# уносит, и следующий срез тела поднял бы и старый.
		mesh_instance.set_instance_shader_parameter(&"carve", _carved)
		for surface in mesh_instance.mesh.get_surface_count():
			mesh_instance.set_surface_override_material(surface, null)


## Встаёт в позу [param other] кость в кость, с его срезом, и замирает: так
## оторванный кусок начинается тем, чем был в теле.
func copy_pose_of(other: FigureRig) -> void:
	if _skeleton == null or other._skeleton == null:
		return
	for bone in _skeleton.get_bone_count():
		_skeleton.set_bone_pose(bone, other._skeleton.get_bone_pose(bone))
	rotation = other.rotation
	if other._carved.w > 0.0:
		carve_under(other._carved.x, other._carved.y, other._carved.z)
	set_process(false)


## Ставит мешам материалы со срезом вместо материалов пака — один раз.
func _cut_materials() -> void:
	for mesh_instance in _meshes:
		if mesh_instance.get_surface_override_material(0) != null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.get_active_material(surface)
			mesh_instance.set_surface_override_material(surface, _carve_material(source))


static func _carve_material(source: Material) -> ShaderMaterial:
	if _carve_materials.has(source):
		return _carve_materials[source] as ShaderMaterial
	var material := ShaderMaterial.new()
	material.shader = CARVE_SHADER
	var standard := source as BaseMaterial3D
	if standard != null:
		material.set_shader_parameter(&"albedo", standard.albedo_color)
		material.set_shader_parameter(&"use_vertex_color", standard.vertex_color_use_as_albedo)
		material.set_shader_parameter(&"roughness", standard.roughness)
		material.set_shader_parameter(&"specular", standard.metallic_specular)
	_carve_materials[source] = material
	return material


## Доводит риг до целевой позы сразу, без сглаживания. Нужно тестам и съёмке:
## кадр должен показывать позу, а не путь к ней.
func snap() -> void:
	if _skeleton == null:
		return
	_current = _wanted()
	_settled = true
	_turned = MoveLocks.TURN_TIME
	if _faced:
		rotation.y = _yaw_to
	_apply(_current, true)


## Кончился ли переход к текущей позе. Тестам: риг, не долетающий никогда,
## перебирал бы кости и вершины каждый кадр до конца жизни актёра.
func settled() -> bool:
	return _settled


## Поворот кости в текущем кадре, как его видит скелет. Тестам: по нему видно,
## что переход — движение, а не подмена.
func bone_rotation(bone_name: String) -> Quaternion:
	if _skeleton == null or _skeleton.find_bone(bone_name) < 0:
		return Quaternion.IDENTITY
	return _skeleton.get_bone_pose_rotation(_skeleton.find_bone(bone_name))


## Поворот кости в целевом кадре позы — туда, куда риг ведёт скелет.
func target_rotation(bone_name: String) -> Quaternion:
	var bone := _skeleton.find_bone(bone_name) if _skeleton != null else -1
	if bone < 0:
		return Quaternion.IDENTITY
	return _wanted().rotations[bone]


## Рост фигуры в покое, м.
func height() -> float:
	return _height


## Габарит фигуры в её текущей позе, в координатах узла.
##
## Считается по самим вершинам, прогнанным через скелет: [method MeshInstance3D.get_aabb]
## у скиннутого меша отдаёт покой, а не позу, и присевший по нему стоял бы в
## полный рост. Именно этим тест проверяет, что присед укладывается под пулю.
## [param hull_only] — только крайние вершины костей: так риг заземляет на ходу.
## Низ по ним сходится с полным до сантиметра, верх — нет (поля шляпы), и
## брать у такого габарита можно только низ.
func skinned_aabb(hull_only: bool = false) -> AABB:
	var box := AABB()
	var first := true
	for surface in _surfaces:
		var to_rig := global_transform.affine_inverse() * surface.mesh_instance.global_transform
		var binds: Array[Transform3D] = []
		if surface.per_vertex > 0:
			binds = _bind_poses(surface.mesh_instance.skin)
		var indices := surface.hull if hull_only else PackedInt32Array()
		var count := indices.size() if hull_only else surface.vertices.size()
		for slot in count:
			var index := indices[slot] if hull_only else slot
			var vertex := surface.vertices[index]
			if surface.per_vertex > 0:
				vertex = _skinned(vertex, index, surface, binds)
			var placed := to_rig * vertex
			if first:
				box = AABB(placed, Vector3.ZERO)
				first = false
			else:
				box = box.expand(placed)
	return box


## Матрицы скина на этот кадр: поза кости × привязка, по одной на привязку.
## Считаются раз на поверхность, а не на каждую из сотен её вершин.
func _bind_poses(skin: Skin) -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	for bind in skin.get_bind_count():
		# Импорт glTF привязывает по индексу кости; имя — запасной путь для
		# скина, собранного руками. Привязка без кости оставляет вершину в покое.
		var bone := skin.get_bind_bone(bind)
		if bone < 0:
			bone = _skeleton.find_bone(skin.get_bind_name(bind))
		var pose := _skeleton.get_bone_global_pose(bone) if bone >= 0 else Transform3D.IDENTITY
		poses.append(pose * skin.get_bind_pose(bind))
	return poses


## Вершина, прогнанная через скелет: сумма по костям веса × (поза × привязка).
func _skinned(
	vertex: Vector3, index: int, surface: SkinnedSurface, binds: Array[Transform3D]
) -> Vector3:
	var result := Vector3.ZERO
	var per_vertex := surface.per_vertex
	for slot in per_vertex:
		var weight := surface.weights[index * per_vertex + slot]
		if weight <= 0.0:
			continue
		result += (binds[surface.bone_ids[index * per_vertex + slot]] * vertex) * weight
	return result


## Клипы модели по именам [constant FigurePoses.CLIP_NAMES], разобранные на
## дорожки костей. Нет клипа — ошибка: поза встанет в стойку, но это надо видеть.
func _read_clips() -> void:
	var players := _instance.find_children("*", "AnimationPlayer", true, false)
	var player := players[0] as AnimationPlayer if not players.is_empty() else null
	for clip_name in FigurePoses.CLIP_NAMES:
		if player == null or not player.has_animation(clip_name):
			push_error("в модели нет клипа %s: %s" % [clip_name, model.resource_path])
			continue
		var tracks := ClipTracks.new()
		tracks.animation = player.get_animation(clip_name)
		for track in tracks.animation.get_track_count():
			var bone := _skeleton.find_bone(
				String(tracks.animation.track_get_path(track).get_concatenated_subnames())
			)
			if bone < 0:
				continue
			match tracks.animation.track_get_type(track):
				Animation.TYPE_ROTATION_3D:
					tracks.rotation_tracks.append(track)
					tracks.rotation_bones.append(bone)
				Animation.TYPE_POSITION_3D:
					tracks.position_tracks.append(track)
					tracks.position_bones.append(bone)
		_clips[clip_name] = tracks


## Кадр покоя скелета: основа, на которую ложатся дорожки клипа.
func _read_rest() -> Frame:
	var frame := Frame.new()
	var count := _skeleton.get_bone_count()
	frame.rotations.resize(count)
	frame.positions.resize(count)
	for bone in count:
		var rest := _skeleton.get_bone_rest(bone)
		frame.rotations[bone] = rest.basis.get_rotation_quaternion()
		frame.positions[bone] = rest.origin
	return frame


## Кадр клипа на момент [param time], с.
func _clip_frame(clip_name: String, time: float) -> Frame:
	var frame := _rest.copy()
	if not _clips.has(clip_name):
		return frame
	var tracks := _clips[clip_name] as ClipTracks
	var animation := tracks.animation
	var at := clampf(time, 0.0, animation.length)
	for slot in tracks.rotation_tracks.size():
		frame.rotations[tracks.rotation_bones[slot]] = animation.rotation_track_interpolate(
			tracks.rotation_tracks[slot], at
		)
	for slot in tracks.position_tracks.size():
		frame.positions[tracks.position_bones[slot]] = animation.position_track_interpolate(
			tracks.position_tracks[slot], at
		)
	return frame


## Кадр, к которому риг ведёт скелет сейчас.
func _wanted() -> Frame:
	var clip := FigurePoses.clip_of(_pose_name)
	if clip == null or not _clips.has(clip.name):
		return _code_frame(_pose_name)
	var length := (_clips[clip.name] as ClipTracks).length()
	var time := 0.0
	match clip.mode:
		FigurePoses.Clip.LOOP:
			time = fmod(_clock * clip.rate, length)
		FigurePoses.Clip.ONCE:
			time = minf(clip.start + _pose_time * clip.rate, length)
		FigurePoses.Clip.END:
			time = length
		FigurePoses.Clip.WALK:
			time = fmod(_walk_clock * FigurePoses.WALK_CLIP_RATE, length)
	return _clip_frame(clip.name, time)


## Стоит ли цель на месте: поза кодом, конец клипа, клип «один раз», доигранный
## до последнего кадра. Стойка и ходьба идут всегда.
func _is_still() -> bool:
	var clip := FigurePoses.clip_of(_pose_name)
	if clip == null or not _clips.has(clip.name):
		return true
	match clip.mode:
		FigurePoses.Clip.END:
			return true
		FigurePoses.Clip.ONCE:
			return clip.start + _pose_time * clip.rate >= (_clips[clip.name] as ClipTracks).length()
	return false


## Стоит ли поза на полу сама: стойка и ходьба — да. С M24c `build_actors.py`
## ставит на пол каждый кадр каждого клипа по вершинам (ADR-0039), но делает это
## до того, как агенту надевают федору: стоя она сверху и ничего не меняет, а
## лежащий на спине агент уходил полями в пол на 9 см (авторевью M24c). Клипы
## «один раз» и конец клипа заземляются, как поза кодом: на ходу это крайние
## вершины, а доигранный клип риг больше не раскладывает вовсе.
func _grounded_by_the_clip() -> bool:
	var clip := FigurePoses.clip_of(_pose_name)
	if clip == null or not _clips.has(clip.name):
		return false
	return clip.mode == FigurePoses.Clip.LOOP or clip.mode == FigurePoses.Clip.WALK


## Кадр позы кодом: стойка, на которую легли углы [FigurePoses.Pose].
func _code_frame(pose_name: String) -> Frame:
	var key := pose_name if FigurePoses.clip_of(pose_name) == null else "stand"
	if _code_frames.has(key):
		return _code_frames[key]
	var pose := FigurePoses.of(key)
	var frame := _stand.copy()
	_swing(frame, LEG_L, pose.legs.x)
	_swing(frame, LEG_R, pose.legs.y)
	# Вбок — вокруг оси взгляда модели: левая нога уходит влево, правая вправо.
	_turn(frame, LEG_L, Vector3.BACK, pose.spread)
	_turn(frame, LEG_R, Vector3.BACK, -pose.spread)
	# Колено сгибается назад: для кости, растущей вниз, это «вперёд» с минусом.
	_swing(frame, KNEE_L, -pose.knees.x)
	_swing(frame, KNEE_R, -pose.knees.y)
	_swing(frame, ARM_L, pose.arms.x)
	_swing(frame, ARM_R, pose.arms.y)
	_swing(frame, ELBOW_L, pose.elbows.x)
	_swing(frame, ELBOW_R, pose.elbows.y)
	_turn(frame, ARM_L, Vector3.BACK, -pose.reach_in)
	_turn(frame, ARM_R, Vector3.BACK, pose.reach_in)
	for bone_name: String in LEAN_SHARE:
		_swing(frame, bone_name, pose.lean * float(LEAN_SHARE[bone_name]))
	for bone_name: String in HEAD_SHARE:
		_swing(frame, bone_name, pose.head * float(HEAD_SHARE[bone_name]))
		_turn(frame, bone_name, Vector3.UP, pose.twist * float(HEAD_SHARE[bone_name]))
	_follow_feet(frame)
	frame.tilt = pose.tilt
	frame.lift = pose.lift
	frame.squash = pose.squash
	_code_frames[key] = frame
	return frame


## Поворачивает кость на угол вперёд вокруг оси бока фигуры.
##
## Ось берётся не у кости, а у фигуры — X модели, — и переводится в систему
## кости по её положению в стойке. Крен и оси костей пака таблице поз не
## важны, а поворот родителя вокруг той же оси складывается с поворотом
## ребёнка: колено гнётся от уже вынесенного бедра.
##
## «Вперёд» у кости, растущей вверх (корпус, голова), — поворот вокруг +X, у
## растущей вниз (ноги, руки) — вокруг −X: тот же поворот уводил бы её назад.
func _swing(frame: Frame, bone_name: String, degrees: float) -> void:
	if not _bones.has(bone_name):
		return
	var bone: int = _bones[bone_name]
	var upward := _stand_globals[bone].basis.y.y >= 0.0
	_turn(frame, bone_name, Vector3.RIGHT if upward else Vector3.LEFT, degrees)


## Поворачивает кость вокруг оси фигуры [param model_axis] — оси модели,
## переведённой в систему кости по её положению в стойке. Вперёд — это
## [method _swing]; вокруг вертикали — поворот головы вбок, свёрнутая шея
## (ADR-0040).
func _turn(frame: Frame, bone_name: String, model_axis: Vector3, degrees: float) -> void:
	if not _bones.has(bone_name) or is_zero_approx(degrees):
		return
	var bone: int = _bones[bone_name]
	var axis := _stand_globals[bone].basis.inverse() * model_axis
	frame.rotations[bone] = (
		frame.rotations[bone] * Quaternion(axis.normalized(), deg_to_rad(degrees))
	)


## Ставит стопы на концы голеней: так, как они стояли друг к другу в стойке.
func _follow_feet(frame: Frame) -> void:
	var globals := _globals(frame)
	for pair: Array in [[KNEE_L, FOOT_L], [KNEE_R, FOOT_R]]:
		if not (_bones.has(pair[0]) and _bones.has(pair[1])):
			continue
		var knee: int = _bones[pair[0]]
		var foot: int = _bones[pair[1]]
		var held := _stand_globals[knee].affine_inverse() * _stand_globals[foot]
		var placed := globals[knee] * held
		var parent := _skeleton.get_bone_parent(foot)
		var local := globals[parent].affine_inverse() * placed if parent >= 0 else placed
		frame.rotations[foot] = local.basis.get_rotation_quaternion()
		frame.positions[foot] = local.origin


## Дуло пистолета в системе кисти: край ствола в сторону пальцев. Ствол
## собран вдоль −X покоя (T-поза, пальцы к −X), и дуло — середина его торца.
func _find_muzzle() -> Vector3:
	var hand := _skeleton.find_bone(GUN_HAND)
	if hand < 0:
		return Vector3(NAN, NAN, NAN)
	for surface in _surfaces:
		var material := surface.mesh_instance.mesh.surface_get_material(surface.index)
		if material == null or material.resource_name != "gun":
			continue
		var tip := INF
		for vertex in surface.vertices:
			tip = minf(tip, vertex.x)
		var end := Vector3.ZERO
		var count := 0
		for vertex in surface.vertices:
			if vertex.x < tip + 0.01:
				end += vertex
				count += 1
		end /= float(maxi(count, 1))
		return _skeleton.get_bone_global_rest(hand).affine_inverse() * end
	return Vector3(NAN, NAN, NAN)


## Кадр с рукой, наведённой на точку вылета пули (ADR-0043, решение 16).
##
## Плечо и предплечье правой руки поворачиваются так, чтобы дуло встало в
## точку [member aim_height] над ступнями и [member aim_reach] впереди; левая
## держит рукоять снизу. Вбок руки остаются, где были: пуля летит в плоскости
## игры, а вбок кадр её не видит.
func _aimed(frame: Frame) -> Frame:
	var hand := _skeleton.find_bone(GUN_HAND)
	var support := _skeleton.find_bone(SUPPORT_HAND)
	if not _bones.has(ARM_R) or not _bones.has(ELBOW_R) or hand < 0:
		return frame
	var aimed := frame.copy()
	# Точка вылета в системе скелета — через мир: между ригом и скелетом лежат
	# модель со своим сдвигом над полом и узел арматуры.
	var to_skeleton := _skeleton.global_transform.affine_inverse() * global_transform
	var target := to_skeleton * Vector3(0.0, aim_height, aim_reach)
	_reach(aimed, _bones[ARM_R], _bones[ELBOW_R], hand, _muzzle, target)
	# Вторая рука держит рукоять снизу: кисть к кисти с пистолетом.
	if support >= 0 and _bones.has(ARM_L) and _bones.has(ELBOW_L):
		var grip := _globals(aimed)[hand].origin + Vector3(0.0, -SUPPORT_DROP, 0.0)
		_reach(aimed, _bones[ARM_L], _bones[ELBOW_L], support, Vector3.ZERO, grip)
	return aimed


## Сводит конец руки — точку [param tip] в системе кости [param end] — в
## [param target]: плечо и локоть поворачиваются в плоскости взгляда (Y —
## вверх, Z — вперёд модели), вбок рука остаётся, где была. Локоть уходит вниз
## от линии плечо — цель.
func _reach(
	frame: Frame, shoulder_bone: int, elbow_bone: int, end: int, tip: Vector3, target: Vector3
) -> void:
	var globals := _globals(frame)
	var shoulder := globals[shoulder_bone].origin
	var elbow := globals[elbow_bone].origin
	var point := globals[end] * tip
	target.x = point.x
	var upper := _flat(elbow - shoulder)
	var lower := _flat(point - elbow)
	var reach := Vector2(target.z - shoulder.z, target.y - shoulder.y)
	var span := clampf(reach.length(), absf(upper - lower) + 0.001, upper + lower - 0.001)
	var toward := reach.normalized()
	var bend := acos(
		clampf((upper * upper + span * span - lower * lower) / (2.0 * upper * span), -1.0, 1.0)
	)
	var elbow_dir := toward.rotated(-bend)
	var wanted := Vector3(
		elbow.x, shoulder.y + elbow_dir.y * upper, shoulder.z + elbow_dir.x * upper
	)
	_turn_bone(frame, globals, shoulder_bone, elbow - shoulder, wanted - shoulder)
	globals = _globals(frame)
	elbow = globals[elbow_bone].origin
	point = globals[end] * tip
	_turn_bone(frame, globals, elbow_bone, point - elbow, target - elbow)


## Длина отрезка в плоскости взгляда: без бокового сдвига.
static func _flat(offset: Vector3) -> float:
	return Vector2(offset.z, offset.y).length()


## Поворачивает кость [param bone] кадра так, чтобы её отрезок [param from]
## смотрел по [param to]; оба — в системе скелета.
func _turn_bone(
	frame: Frame, globals: Array[Transform3D], bone: int, from: Vector3, to: Vector3
) -> void:
	if from.is_zero_approx() or to.is_zero_approx():
		return
	var turn := Quaternion(from.normalized(), to.normalized())
	var parent := _skeleton.get_bone_parent(bone)
	var parent_basis := globals[parent].basis if parent >= 0 else Basis()
	var turned := Basis(turn) * globals[bone].basis
	frame.rotations[bone] = (parent_basis.inverse() * turned).get_rotation_quaternion()


## Положения костей в системе скелета для кадра — по цепочке родителей.
func _globals(frame: Frame) -> Array[Transform3D]:
	var globals: Array[Transform3D] = []
	globals.resize(frame.rotations.size())
	for bone in frame.rotations.size():
		var local := Transform3D(Basis(frame.rotations[bone]), frame.positions[bone])
		var parent := _skeleton.get_bone_parent(bone)
		# Родитель в скелете glTF всегда раньше ребёнка: порядок импорта.
		globals[bone] = globals[parent] * local if parent >= 0 else local
	return globals


## Раскладывает кадр по костям и по самой модели.
##
## [param exact] — заземлять по всем вершинам, а не по крайним: для снимков и
## тестов. На ходу хватает крайних, а стойка и ходьба, в которые риг уже пришёл,
## не заземляются вовсе — их поставил на пол `build_actors.py`. Заземляются поза
## кодом, клипы «один раз» и конец клипа ([method _grounded_by_the_clip]) и
## переход: смесь двух кадров на полу сама не стоит.
func _apply(frame: Frame, exact: bool) -> void:
	_pose_bones(frame)

	# Наклон вперёд вокруг пяток: начало модели — в ногах, и поворот вокруг X
	# кладёт макушку в +Z, то есть по взгляду. Раздавленный сплющен по высоте
	# и раздаётся вширь: объём тела никуда не девается.
	var widen := 1.0 + (1.0 - frame.squash) * 0.36
	_instance.rotation.x = deg_to_rad(frame.tilt)
	_instance.scale = Vector3(widen, frame.squash, widen)
	_instance.position.y = 0.0
	if not (_settled and not exact and _grounded_by_the_clip()):
		_skeleton.force_update_all_bone_transforms()
		# Заземление: поза встаёт на пол низшей точкой. Лежащий на спине
		# опирается спиной, залёгший — грудью, присевший — подошвами, и глубина
		# у всех своя.
		var low := skinned_aabb(not exact).position.y
		_instance.position.y = -low + frame.lift * _height
	# Руку наводят после заземления: точка вылета — над полом, а модель только
	# что встала на пол. Низшую точку позы рука не меняет.
	_aim_shown = _aims()
	if _aim_shown:
		_pose_bones(_aimed(frame))


## Наводить ли руку: актёр стреляет, и пистолет у фигуры есть.
func _aims() -> bool:
	return not is_nan(aim_height) and not is_nan(_muzzle.x)


func _pose_bones(frame: Frame) -> void:
	for bone in frame.rotations.size():
		_skeleton.set_bone_pose_rotation(bone, frame.rotations[bone])
		_skeleton.set_bone_pose_position(bone, frame.positions[bone])
