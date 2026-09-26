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
## Читаемость в темноте держит обводка ([method GreyboxLook.outline]) поверх
## каждого меша: она не подчиняется свету (ADR-0022, решение 4).

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


## Модель актёра. Без неё риг — пустой узел, и это ошибка сцены.
@export var model: PackedScene

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
		mesh_instance.material_overlay = GreyboxLook.outline()
		_meshes.append(mesh_instance)
		for surface in mesh_instance.mesh.get_surface_count():
			_surfaces.append(SkinnedSurface.of(mesh_instance, surface))

	_stand = _clip_frame(FigurePoses.CLIP_STAND, 0.0)
	_stand_globals = _globals(_stand)
	_current = _wanted()
	_settled = true
	_apply(_current, true)
	_height = skinned_aabb().end.y


func _process(delta: float) -> void:
	advance(delta)


## Шаг перехода: кости идут от кадра, где риг стоял при смене позы, к кадру
## позы за время перехода, по сглаженной кривой — и приходят ровно в срок.
## Зовётся из [method Node._process]; тестам отдан наружу, потому что длина
## кадра в headless-прогоне не 1/60, а «сколько получится».
func advance(delta: float) -> void:
	if _skeleton == null:
		return
	# Неподвижная цель — поза кодом, конец клипа: долетев до неё, риг замирает.
	# Проверка до шага часов: клип «один раз» успевает встать в последний кадр.
	var frozen := _settled and _is_still()
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
func face(direction: float) -> void:
	var wanted := FACE_RIGHT if direction >= 0.0 else -FACE_RIGHT
	if not _faced:
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


## Доводит риг до целевой позы сразу, без сглаживания. Нужно тестам и съёмке:
## кадр должен показывать позу, а не путь к ней.
func snap() -> void:
	if _skeleton == null:
		return
	_current = _wanted()
	_settled = true
	_turned = MoveLocks.TURN_TIME
	rotation.y = _yaw_to if _faced else rotation.y
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


## Стоит ли поза на полу сама: любой клип — да. С M24c `build_actors.py`
## ставит на пол каждый кадр каждого клипа по вершинам (ADR-0039), и лежащий в
## конце смерти больше не уходит в пол на 6 см, как у клипа пака.
func _grounded_by_the_clip() -> bool:
	var clip := FigurePoses.clip_of(_pose_name)
	return clip != null and _clips.has(clip.name)


## Кадр позы кодом: стойка, на которую легли углы [FigurePoses.Pose].
func _code_frame(pose_name: String) -> Frame:
	var key := pose_name if FigurePoses.clip_of(pose_name) == null else "stand"
	if _code_frames.has(key):
		return _code_frames[key]
	var pose := FigurePoses.of(key)
	var frame := _stand.copy()
	_swing(frame, LEG_L, pose.legs.x)
	_swing(frame, LEG_R, pose.legs.y)
	# Колено сгибается назад: для кости, растущей вниз, это «вперёд» с минусом.
	_swing(frame, KNEE_L, -pose.knees.x)
	_swing(frame, KNEE_R, -pose.knees.y)
	_swing(frame, ARM_L, pose.arms.x)
	_swing(frame, ARM_R, pose.arms.y)
	_swing(frame, ELBOW_L, pose.elbows.x)
	_swing(frame, ELBOW_R, pose.elbows.y)
	for bone_name: String in LEAN_SHARE:
		_swing(frame, bone_name, pose.lean * float(LEAN_SHARE[bone_name]))
	for bone_name: String in HEAD_SHARE:
		_swing(frame, bone_name, pose.head * float(HEAD_SHARE[bone_name]))
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
	if not _bones.has(bone_name) or is_zero_approx(degrees):
		return
	var bone: int = _bones[bone_name]
	var basis := _stand_globals[bone].basis
	var upward := basis.y.y >= 0.0
	var axis := basis.inverse() * (Vector3.RIGHT if upward else Vector3.LEFT)
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
## тестов. На ходу хватает крайних, а клип, в который риг уже пришёл, не
## заземляется вовсе — его поставил на пол `build_actors.py`. Заземляются поза
## кодом и переход: смесь двух кадров на полу сама не стоит.
func _apply(frame: Frame, exact: bool) -> void:
	for bone in frame.rotations.size():
		_skeleton.set_bone_pose_rotation(bone, frame.rotations[bone])
		_skeleton.set_bone_pose_position(bone, frame.positions[bone])

	# Наклон вперёд вокруг пяток: начало модели — в ногах, и поворот вокруг X
	# кладёт макушку в +Z, то есть по взгляду. Раздавленный сплющен по высоте
	# и раздаётся вширь: объём тела никуда не девается.
	var widen := 1.0 + (1.0 - frame.squash) * 0.36
	_instance.rotation.x = deg_to_rad(frame.tilt)
	_instance.scale = Vector3(widen, frame.squash, widen)
	_instance.position.y = 0.0
	if _settled and not exact and _grounded_by_the_clip():
		return
	_skeleton.force_update_all_bone_transforms()

	# Заземление: поза встаёт на пол низшей точкой. Лежащий на спине опирается
	# спиной, залёгший — грудью, присевший — подошвами, и глубина у всех своя.
	var low := skinned_aabb(not exact).position.y
	_instance.position.y = -low + frame.lift * _height
