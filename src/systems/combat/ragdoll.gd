class_name Ragdoll
extends RefCounted

## Тело на суставах: каждая часть — своё физическое тело (ADR-0043, решение 12).
##
## Брусок вместо тела ложился на другой труп доской. Рэгдолл собирается из
## [PhysicalBone3D] на скелете фигуры пака: таз, туловище, голова, руки и ноги
## по две части и стопы — тринадцать тел, связанных конусами с пределами.
## Остальные кости (пальцы, шея, плечевой пояс) едут за своей частью.
##
## Стопы пака висят не на голенях, а на корне скелета (он собран под IK):
## своего родителя-тела у них нет, и к голени их крепит отдельный шарнир.
##
## Части лежат на слое трупов ([constant Corpse.LAYER]) и видят пол и другие
## трупы; живые их не видят. Друг с другом части одного тела не сталкиваются —
## их держат суставы. Каждая часть заперта в плоскости игры по Z: руки и ноги
## ложатся вглубь коридора на своей глубине, а тело не укатывается к камере.

## Части тела: кость, до какой кости мерить длину (пусто — [code]length[/code]),
## радиус и длина капсулы, м, масса, кг, и сустав. [code]swing[/code] — конус
## плеча и локтя, градусы. [code]bend[/code] — сустав как у человека, не
## поровну во все стороны: наклон вокруг оси X модели от и до (вперёд у спины
## и головы — плюс, у бедра — минус, колено гнётся только в плюс), поворот
## вокруг вертикали и вбок — в обе стороны поровну. Оси — модели, а не кости:
## у костей пака свои оси повёрнуты кто как.
const PARTS: Array[Dictionary] = [
	{"bone": "Body", "to": "", "length": 0.2, "radius": 0.13, "mass": 12.0},
	{
		"bone": "Torso",
		"to": "Neck",
		"radius": 0.14,
		"mass": 20.0,
		"bend": [-60.0, 20.0, 25.0, 20.0]
	},
	{
		"bone": "Head",
		"to": "",
		"length": 0.22,
		"radius": 0.11,
		"mass": 5.0,
		"bend": [-50.0, 35.0, 50.0, 30.0]
	},
	{"bone": "UpperArm.L", "to": "LowerArm.L", "radius": 0.05, "mass": 2.5, "swing": 80.0},
	{"bone": "UpperArm.R", "to": "LowerArm.R", "radius": 0.05, "mass": 2.5, "swing": 80.0},
	{"bone": "LowerArm.L", "to": "", "length": 0.3, "radius": 0.045, "mass": 2.0, "swing": 70.0},
	{"bone": "LowerArm.R", "to": "", "length": 0.3, "radius": 0.045, "mass": 2.0, "swing": 70.0},
	{
		"bone": "UpperLeg.L",
		"to": "LowerLeg.L",
		"radius": 0.075,
		"mass": 8.0,
		"bend": [-20.0, 110.0, 20.0, 35.0]
	},
	{
		"bone": "UpperLeg.R",
		"to": "LowerLeg.R",
		"radius": 0.075,
		"mass": 8.0,
		"bend": [-20.0, 110.0, 20.0, 35.0]
	},
	{
		"bone": "LowerLeg.L",
		"to": "Foot.L",
		"radius": 0.06,
		"mass": 4.0,
		"bend": [-140.0, 0.0, 5.0, 5.0]
	},
	{
		"bone": "LowerLeg.R",
		"to": "Foot.R",
		"radius": 0.06,
		"mass": 4.0,
		"bend": [-140.0, 0.0, 5.0, 5.0]
	},
	{"bone": "Foot.L", "to": "", "length": 0.16, "radius": 0.045, "mass": 1.0},
	{"bone": "Foot.R", "to": "", "length": 0.16, "radius": 0.045, "mass": 1.0},
]
## Стопа и голень, к которой её крепит шарнир.
const ANKLES := {"Foot.L": "LowerLeg.L", "Foot.R": "LowerLeg.R"}

## Тяжесть частей: мир игры падает быстрее земного (у агента и Otto 27 м/с²).
const GRAVITY_SCALE: float = 2.75
const FRICTION: float = 0.9
const LINEAR_DAMP: float = 0.2
const ANGULAR_DAMP: float = 2.0
## Предел скорости части, м/с: быстрее тело за шаг физики пролетало бы плиту
## перекрытия насквозь. У живых предел падения тот же порядка (12.6 м/с).
const MAX_SPEED: float = 8.0
## Часть медленнее этого, м/с, считается улёгшейся.
const RESTING_SPEED: float = 0.15

## Части по кости, пока они есть: отрезанная кабиной уходит из словаря.
var parts: Dictionary = {}
## Тело, которому принадлежит рэгдолл: по нему кабина узнаёт, чью часть задела.
var corpse: Corpse = null

var _figure: FigureRig
var _skeleton: Skeleton3D
var _simulator: PhysicalBoneSimulator3D
var _joints: Dictionary = {}
## Кости скелета, которые ведёт каждая часть: она сама и потомки без своей
## части. Прячутся вместе с ней.
var _owned: Dictionary = {}
var _hidden := PackedStringArray()


## Собирает рэгдолл на фигуре [param figure]. [param only] — только эти части
## (кусок, оторванный от тела); пусто — все.
func _init(figure: FigureRig, only: PackedStringArray = PackedStringArray()) -> void:
	_figure = figure
	_skeleton = figure.skeleton()
	_simulator = PhysicalBoneSimulator3D.new()
	_simulator.name = "Ragdoll"
	_skeleton.add_child(_simulator)
	for spec: Dictionary in PARTS:
		var bone_name := spec["bone"] as String
		if not only.is_empty() and not only.has(bone_name):
			continue
		parts[bone_name] = _part(spec)
	for bone_name: String in parts:
		for other: String in parts:
			if other != bone_name:
				(parts[bone_name] as PhysicalBone3D).add_collision_exception_with(parts[other])
	_own_bones()


## Пускает тело в физику со скоростью [param velocity] и толчком [param impulse]:
## в точку [param at] ближайшей к ней части, а без точки — в туловище. До этого
## части ни с чем не сталкиваются: живой ходит своей формой.
func start(velocity: Vector3, impulse: Vector3 = Vector3.ZERO, at: Variant = null) -> void:
	for part: PhysicalBone3D in parts.values():
		part.collision_layer = 1 << (Corpse.LAYER - 1)
		part.collision_mask = Corpse.GEOMETRY_MASK | (1 << (Corpse.LAYER - 1))
	_simulator.physical_bones_start_simulation()
	for ankle: String in ANKLES:
		_pin_ankle(ankle)
	var limiter := SpeedLimit.new()
	limiter.ragdoll = self
	_simulator.add_child(limiter)
	for part: PhysicalBone3D in parts.values():
		part.linear_velocity = velocity
	if impulse == Vector3.ZERO:
		return
	if not at is Vector3:
		var chest := parts.get("Torso") as PhysicalBone3D
		if chest != null:
			chest.apply_central_impulse(impulse)
		return
	var point := at as Vector3
	var struck: PhysicalBone3D = null
	for part: PhysicalBone3D in parts.values():
		if (
			struck == null
			or (
				center_of(part).distance_squared_to(point)
				< center_of(struck).distance_squared_to(point)
			)
		):
			struck = part
	# Попадание — у самой части: точка по высоте и глубине пули, но не дальше
	# капсулы, иначе рычаг крутил бы часть волчком.
	var offset := (point - struck.global_position).limit_length(0.3)
	struck.apply_impulse(impulse, offset)


## Убирает части [param bones]: их кости прячутся, тела исчезают. Потомки
## остаются и повисают на своих суставах свободными.
func remove(bones: PackedStringArray) -> void:
	for bone_name: String in bones:
		var part := parts.get(bone_name) as PhysicalBone3D
		if part == null:
			continue
		parts.erase(bone_name)
		var joint := _joints.get(bone_name) as Joint3D
		if joint != null:
			joint.queue_free()
			_joints.erase(bone_name)
		for foot: String in ANKLES:
			if ANKLES[foot] == bone_name and _joints.has(foot):
				(_joints[foot] as Joint3D).queue_free()
				_joints.erase(foot)
		part.queue_free()
		_hidden.append_array(_owned[bone_name] as PackedStringArray)
	_figure.hide_bones(_hidden)


## Ставит свои части туда, где стоят те же части [param source], с их
## скоростями: оторванный кусок продолжает движение тела.
func follow(source: Ragdoll) -> void:
	for bone_name: String in parts:
		var from := source.parts.get(bone_name) as PhysicalBone3D
		if from == null:
			continue
		var part := parts[bone_name] as PhysicalBone3D
		part.global_transform = from.global_transform
		part.linear_velocity = from.linear_velocity
		part.angular_velocity = from.angular_velocity


## Имена частей, которые ещё есть.
func names() -> PackedStringArray:
	return PackedStringArray(parts.keys())


## Прячет кости частей, которых нет в [param kept]: у оторванного куска
## остальное тело — чужое.
func hide_all_but(kept: PackedStringArray) -> void:
	for bone_name: String in _owned:
		if not kept.has(bone_name):
			_hidden.append_array(_owned[bone_name] as PackedStringArray)
	_figure.hide_bones(_hidden)


## Разбирает рэгдолл: фигура снова на ногах, всё спрятанное видно.
func dispose() -> void:
	if is_instance_valid(_simulator):
		_simulator.physical_bones_stop_simulation()
		_simulator.queue_free()
	for joint: Joint3D in _joints.values():
		joint.queue_free()
	parts.clear()
	_joints.clear()
	_hidden = PackedStringArray()
	_figure.hide_bones(_hidden)


## Середина части [param part] в мире: капсула идёт от кости вдоль её Y.
static func center_of(part: PhysicalBone3D) -> Vector3:
	var shape := part.get_child(0) as CollisionShape3D
	return part.global_transform * shape.position


## Габарит тела по частям, в мире.
func bounds() -> AABB:
	var box := AABB()
	var first := true
	for part: PhysicalBone3D in parts.values():
		var shape := part.get_child(0) as CollisionShape3D
		var capsule := shape.shape as CapsuleShape3D
		var reach := Vector3.ONE * capsule.radius
		# Высота капсулы — с полусферами: центры полусфер ближе концов на радиус.
		var spine := capsule.height * 0.5 - capsule.radius
		for end: float in [-spine, spine]:
			var point := part.global_transform * (shape.position + Vector3(0.0, end, 0.0))
			var around := AABB(point - reach, reach * 2.0)
			box = around if first else box.merge(around)
			first = false
	return box


## Будит части: опора ушла из-под улёгшегося тела — люк подвала открылся, — а
## спящее тело физика сама не будит, и оно висело бы в воздухе.
func wake() -> void:
	for part: PhysicalBone3D in parts.values():
		PhysicsServer3D.body_set_state(part.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, false)


## Спят ли все части: тело улеглось.
func asleep() -> bool:
	for part: PhysicalBone3D in parts.values():
		if part.linear_velocity.length() > RESTING_SPEED:
			return false
	return true


## Шаг частей, которого физика не делает сама: предел скорости — у
## [PhysicalBone3D] его нет, — и езда на полу кабины. Кабину двигает код, и
## тело, лежащее на её полу, падало бы на уходящий пол раз за разом, сползая
## с него; часть на полу кабины берёт её ход по вертикали и едет с ней.
##
## Кабина, идущая вверх, зажимает лежащее на её крыше тело под верхом шахты —
## тела тогда больше нет, как и до рэгдолла (ADR-0042): физика вдавила бы его
## и в крышу, и в плиту разом.
class SpeedLimit:
	extends Node

	## Насколько ниже поверхности части ищется пол кабины и насколько выше —
	## потолок, м.
	const REACH: float = 0.08

	var ragdoll: Ragdoll = null

	func _physics_process(_delta: float) -> void:
		var space := get_viewport().world_3d.direct_space_state
		for part: PhysicalBone3D in ragdoll.parts.values():
			# Уснувшая часть лежит на неподвижном: на кабине части не засыпают —
			# её тело кинематическое и будит всё, что на нём лежит. Трупов до
			# конца здания много, и луч под каждую часть каждый шаг стоил бы кадру.
			if PhysicsServer3D.body_get_state(part.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING):
				continue
			if part.linear_velocity.length_squared() > MAX_SPEED * MAX_SPEED:
				part.linear_velocity = part.linear_velocity.limit_length(MAX_SPEED)
			var car := _car_under(space, part)
			if car == null or is_zero_approx(car.speed_now()):
				continue
			if car.speed_now() < 0.0 and _pinned(space, part, car):
				ragdoll.corpse.vanish()
				return
			var velocity := part.linear_velocity
			velocity.y = -car.speed_now()
			velocity.x *= 0.5
			part.linear_velocity = velocity

	## Кабина, на полу которой лежит часть, или null.
	func _car_under(space: PhysicsDirectSpaceState3D, part: PhysicalBone3D) -> ElevatorCar:
		var shape := part.get_child(0) as CollisionShape3D
		var radius := (shape.shape as CapsuleShape3D).radius
		var from := Ragdoll.center_of(part)
		var query := PhysicsRayQueryParameters3D.create(
			from, from - Vector3(0.0, radius + REACH, 0.0), Corpse.GEOMETRY_MASK
		)
		var hit := space.intersect_ray(query)
		return hit.get("collider") as ElevatorCar if not hit.is_empty() else null

	## Упёрлась ли часть, которую везёт вверх кабина [param car], в потолок.
	func _pinned(space: PhysicsDirectSpaceState3D, part: PhysicalBone3D, car: ElevatorCar) -> bool:
		var shape := part.get_child(0) as CollisionShape3D
		var radius := (shape.shape as CapsuleShape3D).radius
		var from := Ragdoll.center_of(part)
		var query := PhysicsRayQueryParameters3D.create(
			from, from + Vector3(0.0, radius + REACH, 0.0), Corpse.GEOMETRY_MASK
		)
		query.exclude = [car.get_rid()]
		return not space.intersect_ray(query).is_empty()


func _part(spec: Dictionary) -> PhysicalBone3D:
	var bone_name := spec["bone"] as String
	var bone := _skeleton.find_bone(bone_name)
	var length := float(spec.get("length", 0.0))
	var to := spec["to"] as String
	if not to.is_empty():
		var child := _skeleton.find_bone(to)
		length = (
			(
				_skeleton.get_bone_global_rest(child).origin
				- _skeleton.get_bone_global_rest(bone).origin
			)
			. length()
		)
	var radius := float(spec["radius"])
	var part := PhysicalBone3D.new()
	part.name = bone_name
	part.bone_name = bone_name
	part.mass = float(spec["mass"])
	part.friction = FRICTION
	part.bounce = 0.0
	part.gravity_scale = GRAVITY_SCALE
	part.linear_damp = LINEAR_DAMP
	part.angular_damp = ANGULAR_DAMP
	part.can_sleep = true
	part.collision_layer = 0
	part.collision_mask = 0
	part.axis_lock_linear_z = true
	var swing := float(spec.get("swing", 0.0))
	if spec.has("bend"):
		_bend(part, bone, spec["bend"] as Array)
	elif swing > 0.0:
		part.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
		# Ось скручивания конуса — X сустава, кость идёт вдоль Y.
		part.joint_rotation = Vector3(0.0, 0.0, PI * 0.5)
		part.set(&"joint_constraints/swing_span", swing)
		part.set(&"joint_constraints/twist_span", float(spec.get("twist", 30.0)))
	else:
		part.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = maxf(length, radius * 2.0)
	shape.shape = capsule
	shape.position = Vector3(0.0, length * 0.5, 0.0)
	part.add_child(shape)
	part.set_meta(&"ragdoll", self)
	_simulator.add_child(part)
	return part


## Сустав как у человека: оси модели в осях кости, пределы [param limits] —
## наклон вокруг X модели от и до, поворот вокруг Y и вбок вокруг Z в обе
## стороны, градусы.
func _bend(part: PhysicalBone3D, bone: int, limits: Array) -> void:
	part.joint_type = PhysicalBone3D.JOINT_TYPE_6DOF
	var to_bone := _skeleton.get_bone_global_rest(bone).basis.orthonormalized().inverse()
	var axis_x := (to_bone * Vector3.RIGHT).normalized()
	var axis_y := (to_bone * Vector3.UP).normalized()
	var axis_z := axis_x.cross(axis_y).normalized()
	axis_y = axis_z.cross(axis_x).normalized()
	part.joint_rotation = Basis(axis_x, axis_y, axis_z).get_euler()
	var spans := {
		"x": [float(limits[0]), float(limits[1])],
		"y": [-float(limits[2]), float(limits[2])],
		"z": [-float(limits[3]), float(limits[3])],
	}
	for axis: String in spans:
		var span := spans[axis] as Array
		part.set("joint_constraints/%s/angular_limit_enabled" % axis, true)
		part.set("joint_constraints/%s/angular_limit_lower" % axis, span[0])
		part.set("joint_constraints/%s/angular_limit_upper" % axis, span[1])


## Шарнир стопы к голени: на лодыжке, где стопа начинается.
func _pin_ankle(foot: String) -> void:
	var leg := parts.get(ANKLES[foot]) as PhysicalBone3D
	var sole := parts.get(foot) as PhysicalBone3D
	if leg == null or sole == null:
		return
	var joint := PinJoint3D.new()
	_simulator.add_child(joint)
	joint.global_position = sole.global_position
	joint.node_a = joint.get_path_to(leg)
	joint.node_b = joint.get_path_to(sole)
	_joints[foot] = joint


## Какие кости скелета ведёт каждая часть.
func _own_bones() -> void:
	var owner_of := {}
	for bone: int in _skeleton.get_bone_count():
		var walk := bone
		while walk >= 0:
			var walk_name := _skeleton.get_bone_name(walk)
			if _is_part(walk_name):
				owner_of[bone] = walk_name
				break
			walk = _skeleton.get_bone_parent(walk)
	for spec: Dictionary in PARTS:
		var owned := PackedStringArray()
		for bone: int in owner_of:
			if owner_of[bone] == spec["bone"]:
				owned.append(_skeleton.get_bone_name(bone))
		_owned[spec["bone"]] = owned


static func _is_part(bone_name: String) -> bool:
	for spec: Dictionary in PARTS:
		if spec["bone"] == bone_name:
			return true
	return false
