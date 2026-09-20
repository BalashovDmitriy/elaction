class_name FigureRig
extends Node3D

## Скелет актёра, ведомый таблицей поз.
##
## Модель приходит из `.glb`, собранного `tools/build_actors.py`: один меш,
## привязанный к костям бёдер, корпуса, головы, рук и ног. Риг находит кости по
## имени и каждый кадр ведёт их к углам позы [FigurePoses] со сглаживанием;
## ходьба — непрерывный цикл по фазе [ActorPose] (ADR-0022, решение 2).
##
## Начало узла — в ногах актёра, как у коробки греев-бокса до него: актёр
## ставит риг на свой пол, а поворот к камере и наклон тела — дело рига.
##
## Читаемость в темноте держит обводка ([method GreyboxLook.outline]) поверх
## каждого меша: она не подчиняется свету (ADR-0022, решение 4).

## Кости, которых риг ждёт от модели. Те же имена пишет `build_actors.py`.
const HIPS := "hips"
const TORSO := "torso"
const HEAD := "head"
const ARM_L := "arm_l"
const ARM_R := "arm_r"
const LEG_L := "leg_l"
const LEG_R := "leg_r"
const BONES: PackedStringArray = [HIPS, TORSO, HEAD, ARM_L, ARM_R, LEG_L, LEG_R]


## Поверхность меша, снятая один раз: вершины, привязка к костям и веса.
##
## [method Mesh.surface_get_arrays] копирует все массивы поверхности — нормали,
## касательные, развёртку — на каждый вызов, а габарит по вершинам нужен на
## каждом кадре перехода между позами. Снятое при рождении копируется один раз.
class SkinnedSurface:
	extends RefCounted

	var mesh_instance: MeshInstance3D
	var vertices := PackedVector3Array()
	var bone_ids := PackedInt32Array()
	var weights := PackedFloat32Array()
	## Костей на вершину: 0 у поверхности без привязки — она стоит как есть.
	var per_vertex: int = 0

	static func of(instance: MeshInstance3D, surface: int) -> SkinnedSurface:
		var made := SkinnedSurface.new()
		made.mesh_instance = instance
		var arrays := instance.mesh.surface_get_arrays(surface)
		made.vertices = arrays[Mesh.ARRAY_VERTEX]
		# У поверхности без скина костей и весов нет вовсе — там null, не пустой
		# массив, и в типизированное поле его не положить.
		var bones: Variant = arrays[Mesh.ARRAY_BONES]
		var bone_weights: Variant = arrays[Mesh.ARRAY_WEIGHTS]
		if instance.skin == null or bones == null or bone_weights == null:
			return made
		# Индексы костей движок отдаёт целыми либо вещественными — как лёг импорт.
		made.bone_ids = bones if bones is PackedInt32Array else PackedInt32Array(Array(bones))
		made.weights = bone_weights
		made.per_vertex = made.bone_ids.size() / maxi(made.vertices.size(), 1)
		return made


## Скорость сглаживания, 1/с. Переход между позами укладывается в несколько
## кадров: медленнее — и удар ногой опаздывает к удару, быстрее — и это уже
## подмена картинки.
@export var smoothing: float = 16.0

## Модель актёра. Без неё риг — пустой узел, и это ошибка сцены.
@export var model: PackedScene

## Наклон вперёд «вокруг пяток» и подъём над полом идут не костям, а самой
## модели: у скелета нет кости, которой можно уложить тело целиком.
var _instance: Node3D = null
var _skeleton: Skeleton3D = null
var _meshes: Array[MeshInstance3D] = []
var _surfaces: Array[SkinnedSurface] = []
var _bones: Dictionary = {}
var _rest: Dictionary = {}
## Высота бёдер и рост в покое, м: доли позы переводятся в метры ими.
var _hip_height: float = 0.0
var _height: float = 0.0

var _pose_name := "idle"
var _target: FigurePoses.Pose = FigurePoses.of("idle")
var _current: FigurePoses.Pose = FigurePoses.of("idle")
var _walk_phase: float = 0.0
## Кости уже стоят в целевой позе: пока цель не сменится, раскладывать нечего.
## Стоящих и лежащих в кадре больше, чем идущих, и без этого каждый из них
## перебирал бы все вершины меша каждый кадр ради нулевого сдвига.
var _settled: bool = false


func _ready() -> void:
	if model == null:
		push_error("FigureRig без модели: %s" % get_path())
		return
	_instance = model.instantiate() as Node3D
	add_child(_instance)

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
		_rest[bone_name] = _skeleton.get_bone_rest(index)

	for node in _instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		mesh_instance.material_overlay = GreyboxLook.outline()
		_meshes.append(mesh_instance)
		for surface in mesh_instance.mesh.get_surface_count():
			_surfaces.append(SkinnedSurface.of(mesh_instance, surface))

	_hip_height = (_rest[HIPS] as Transform3D).origin.y if _rest.has(HIPS) else 0.0
	_height = skinned_aabb().end.y
	_apply(_current)


func _process(delta: float) -> void:
	advance(delta)


## Шаг сглаживания: кости идут к позе на долю пути за [param delta] секунд.
## Зовётся из [method Node._process]; тестам отдан наружу, потому что длина
## кадра в headless-прогоне не 1/60, а «сколько получится».
func advance(delta: float) -> void:
	if _skeleton == null:
		return
	var wanted := _wanted()
	if _settled and _current.is_close_to(wanted):
		return
	_current = _current.blend(wanted, 1.0 - exp(-smoothing * delta))
	# Долетев с точностью до долей градуса, риг встаёт в цель ровно и замирает:
	# экспоненциальное сглаживание само по себе не доходит никогда.
	_settled = _current.is_close_to(wanted)
	if _settled:
		_current = wanted
	_apply(_current)


## Какую позу показывать. Имена — из [ActorPose]; ходьба берёт фазу из
## [method set_walk_phase] и идёт непрерывным циклом.
func show_pose(pose_name: String) -> void:
	if pose_name == _pose_name:
		return
	_pose_name = pose_name
	_target = FigurePoses.of(pose_name)


## Фаза ходьбы, 0..[constant ActorPose.WALK_FRAMES]. Актёр ведёт её сам,
## как вёл для кадров спрайта.
func set_walk_phase(phase: float) -> void:
	_walk_phase = phase


## Куда актёр смотрит: -1 влево, +1 вправо. Модель в покое смотрит в камеру
## (+Z), поворот на четверть оборота кладёт взгляд вдоль этажа.
func face(direction: float) -> void:
	rotation.y = PI * 0.5 if direction >= 0.0 else -PI * 0.5


## Прозрачность всех мешей: 0 — сплошной, 1 — невидим. Так мигает неуязвимый.
func set_transparency(value: float) -> void:
	for mesh_instance in _meshes:
		mesh_instance.transparency = value


## Доводит риг до целевой позы сразу, без сглаживания. Нужно тестам и съёмке:
## кадр должен показывать позу, а не путь к ней.
func snap() -> void:
	if _skeleton == null:
		return
	_current = _wanted()
	_settled = true
	_apply(_current)


## Поза, в которой риг стоит прямо сейчас — со сглаживанием.
func current_pose() -> FigurePoses.Pose:
	return _current


## Рост фигуры в покое, м.
func height() -> float:
	return _height


## Габарит фигуры в её текущей позе, в координатах узла.
##
## Считается по самим вершинам, прогнанным через скелет: [method MeshInstance3D.get_aabb]
## у скиннутого меша отдаёт покой, а не позу, и присевший по нему стоял бы в
## полный рост. Именно этим тест проверяет, что присед укладывается под пулю.
func skinned_aabb() -> AABB:
	var box := AABB()
	var first := true
	for surface in _surfaces:
		var to_rig := global_transform.affine_inverse() * surface.mesh_instance.global_transform
		var binds: Array[Transform3D] = []
		if surface.per_vertex > 0:
			binds = _bind_poses(surface.mesh_instance.skin)
		for index in surface.vertices.size():
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


func _wanted() -> FigurePoses.Pose:
	if _pose_name.begins_with("walk_"):
		return FigurePoses.walking(_walk_phase)
	return _target


## Раскладывает позу по костям и по самой модели.
func _apply(pose: FigurePoses.Pose) -> void:
	_swing(LEG_L, pose.legs.x)
	_swing(LEG_R, pose.legs.y)
	_swing(ARM_L, pose.arms.x)
	_swing(ARM_R, pose.arms.y)
	_swing(TORSO, pose.lean)
	_swing(HEAD, pose.head)

	if _bones.has(HIPS):
		var rest := _rest[HIPS] as Transform3D
		_skeleton.set_bone_pose_position(
			_bones[HIPS], rest.origin - Vector3(0.0, pose.drop * _hip_height, 0.0)
		)

	# Наклон вперёд вокруг пяток: начало модели — в ногах, и поворот вокруг X
	# кладёт макушку в +Z, то есть по взгляду. Раздавленный сплющен по высоте
	# и раздаётся вширь: объём тела никуда не девается.
	var widen := 1.0 + (1.0 - pose.squash) * 0.36
	_instance.rotation.x = deg_to_rad(pose.tilt)
	_instance.scale = Vector3(widen, pose.squash, widen)
	_instance.position.y = 0.0
	_skeleton.force_update_all_bone_transforms()

	# Заземление: ничто не уходит под пол. Лежащий на спине опирается спиной,
	# залёгший — грудью, присевший — пятками, и глубина у всех своя; зазор,
	# подобранный константой на одну позу, топил бы другую. Считается по тем же
	# скиннутым вершинам, что и габарит.
	var sunk := skinned_aabb().position.y
	_instance.position.y = maxf(-sunk, 0.0) + pose.lift * _height


## Поворачивает кость вокруг её оси X — бока фигуры — на угол вперёд.
##
## «Вперёд» у костей разное: у корпуса и головы локальная Z смотрит по взгляду,
## у ног и рук, растущих вниз, — против него, и тот же поворот уводит их назад.
## Знак берётся у покоя кости (`tools/dump_model.gd` показывает это пробой),
## а не пишется руками на каждую кость: сменится риг — сменится и знак.
func _swing(bone_name: String, degrees: float) -> void:
	if not _bones.has(bone_name):
		return
	var rest := _rest[bone_name] as Transform3D
	var forward := signf(rest.basis.z.z)
	var turned := (
		rest.basis.get_rotation_quaternion()
		* Quaternion(Vector3.RIGHT, deg_to_rad(degrees) * forward)
	)
	_skeleton.set_bone_pose_rotation(_bones[bone_name], turned)
