class_name UmbrellaGrip
extends SkeletonModifier3D

## Прохожий несёт зонт (ADR-0054, решение 11; замечания пользователя —
## «человек должен нести зонт, а не модель зонта перемещается вместе с
## человеком», «рука не держит зонт»).
##
## Поверх ходьбы пака одна рука держит трость, как держат зонт: локоть
## согнут и прижат, предплечье вперёд и чуть вверх, кисть у нижних рёбер
## пальцами вверх по трости, пальцы сжаты в кулак вокруг неё. Трость проходит
## через середину кулака и стоит отвесно; зонт покачивается с шагом, потому что
## кисть идёт за грудью. Левая рука по-прежнему машет.
##
## Модификатор работает после анимации ([SkeletonModifier3D]): ходьба пака
## ставит позу, хват правит в ней одну руку. Все точки — в мировых осях, а
## поворот кости — от её нынешнего направления к нужному: оси скелета
## импортированной модели с осями самой модели не совпадают.

## Где кисть относительно груди, доли роста: вперёд, вниз, и какую долю
## расстояния до своего плеча — в сторону.
const HAND_FORWARD: float = 0.12
const HAND_DOWN: float = 0.03
const HAND_SIDE: float = 0.8
## Куда уходит локоть: вниз, назад и наружу — доли.
const ELBOW_DOWN: float = 1.0
const ELBOW_BACK: float = 0.6
const ELBOW_OUT: float = 0.3
## Где в кисти середина кулака: доля пути от запястья к основанию среднего
## пальца.
const PALM: float = 0.85
## Насколько трость выходит под кулаком, доли роста.
const BELOW_FIST: float = 0.05
## Рост модели пака в её единицах.
const MODEL_HEIGHT: float = 1.85

## Пальцы: по суставам от ладони, последний — конец пальца; сторона руки —
## окончанием имени.
const FINGERS: Array[Array] = [
	["Index1", "Index2", "Index3", "Index4"],
	["Middle1", "Middle2", "Middle3", "Middle4"],
	["Ring1", "Ring2", "Ring3", "Ring4"],
	["Pinky1", "Pinky2", "Pinky3", "Pinky4"],
	["Thumb1", "Thumb2", "Thumb3"],
]

## Зонт: его начало — низ трости, под кулаком.
var umbrella: Node3D = null
## Куда идёт прохожий, мировые оси; ставит улица.
var forward := Vector3.FORWARD
## Какой рукой держит: «R» или «L». Улица отдаёт зонт руке, что ближе к
## камере: в дальней руке кулак закрыт корпусом, и трость будто росла из плеча.
var side: String = "R"
## Где в последний кадр оказались кулак и низ трости, мировые оси, — для
## теста: вне модификатора скелет отдаёт позу анимации без правки.
var last_fist := Vector3.ZERO
var last_pole := Vector3.ZERO

var _chest: int = -1
var _upper: int = -1
var _lower: int = -1
var _wrist: int = -1
var _middle: int = -1
var _fingers: Array[PackedInt32Array] = []


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_chest = skeleton.find_bone("Chest")
	_upper = skeleton.find_bone("UpperArm." + side)
	_lower = skeleton.find_bone("LowerArm." + side)
	_wrist = skeleton.find_bone("Wrist." + side)
	_middle = skeleton.find_bone("Middle1." + side)
	for chain: Array in FINGERS:
		var bones := PackedInt32Array()
		for bone_name: String in chain:
			bones.append(skeleton.find_bone(bone_name + "." + side))
		if not bones.has(-1):
			_fingers.append(bones)


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if mini(mini(_chest, _upper), mini(mini(_lower, _wrist), _middle)) < 0:
		return
	var to_bones := skeleton.global_transform.affine_inverse()
	var tall := skeleton.global_transform.basis.get_scale().y * MODEL_HEIGHT
	var chest := _at(skeleton, _chest)
	var shoulder := _at(skeleton, _upper)
	var upper_length := shoulder.distance_to(_at(skeleton, _lower))
	var lower_length := _at(skeleton, _lower).distance_to(_at(skeleton, _wrist))
	var ahead := Vector3(forward.x, 0.0, forward.z).normalized()
	var aside := shoulder - chest
	aside = Vector3(aside.x, 0.0, aside.z)
	aside -= ahead * aside.dot(ahead)
	var target := (
		chest + ahead * HAND_FORWARD * tall + Vector3.DOWN * HAND_DOWN * tall + aside * HAND_SIDE
	)
	var reach := clampf(shoulder.distance_to(target), 0.01, (upper_length + lower_length) * 0.999)
	var along := (target - shoulder).normalized()
	var across := upper_length * upper_length - lower_length * lower_length + reach * reach
	var to_elbow := across / (2.0 * reach)
	var lift := sqrt(maxf(upper_length * upper_length - to_elbow * to_elbow, 0.0))
	var pole := Vector3.DOWN * ELBOW_DOWN - ahead * ELBOW_BACK + aside.normalized() * ELBOW_OUT
	pole -= along * pole.dot(along)
	var elbow := shoulder + along * to_elbow + pole.normalized() * lift
	var wrist := shoulder + along * reach
	_aim(skeleton, _upper, _lower, to_bones * elbow)
	_aim(skeleton, _lower, _wrist, to_bones * wrist)
	# Кисть — пальцами вверх по трости, чуть вперёд: так держат ручку зонта.
	var hand_length := _at(skeleton, _wrist).distance_to(_at(skeleton, _middle))
	var up_the_pole := (Vector3.UP + ahead * 0.25).normalized()
	_aim(skeleton, _wrist, _middle, to_bones * (wrist + up_the_pole * hand_length))
	var fist := wrist + (_at(skeleton, _middle) - wrist) * PALM
	# Пальцы — в кулак: каждый сустав тянется к трости, на её оси под кулаком.
	var hold := fist + Vector3.DOWN * hand_length * 0.15
	for chain in _fingers:
		for index in chain.size() - 1:
			_aim(skeleton, chain[index], chain[index + 1], to_bones * hold)
	last_fist = fist
	last_pole = fist + Vector3.DOWN * BELOW_FIST * tall
	if umbrella != null:
		umbrella.global_position = last_pole


func _at(skeleton: Skeleton3D, bone: int) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin


## Поворачивает кость [param bone] так, чтобы её потомок [param child] пришёл
## в [param point], оси скелета. Поворот — от нынешнего направления кости к
## нужному: так он не зависит от того, по какой оси пак кладёт кости.
func _aim(skeleton: Skeleton3D, bone: int, child: int, point: Vector3) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var now := (skeleton.get_bone_global_pose(child).origin - pose.origin).normalized()
	var wanted := (point - pose.origin).normalized()
	if now.is_zero_approx() or wanted.is_zero_approx():
		return
	var turn := Quaternion(now, wanted)
	skeleton.set_bone_global_pose(bone, Transform3D(Basis(turn) * pose.basis, pose.origin))
