class_name FigurePoses
extends RefCounted

## Позы фигуры: чем отыгрывается каждая поза [ActorPose].
##
## С M21 (ADR-0032, решение 1) поз две природы. Там, где ROM не диктует высот,
## двигается клип пака Quaternius — стойка, ходьба, выстрел, смерть. Там, где
## диктует, — поза кодом из этой таблицы: присед и залёгший под пулями ROM,
## прыжок и удар ногой, которых в паке нет, раздавленный.
##
## Поза кодом строится не от покоя скелета, а от первого кадра стойки: покой
## пака — T-поза с руками в стороны. Углы — в градусах, **положительный уводит
## конечность вперёд**, по ходу взгляда; колено положительным сгибается (голень
## уходит назад), локоть — тоже (предплечье уходит вперёд). Наклоны корпуса и
## тела вперёд положительные; залёгший под пулю агент наклонён вперёд.
##
## Без узлов, без сцены: проверяется тем же приёмом, что [OttoStateMachine].


## Одна поза кодом.
class Pose:
	extends RefCounted

	## Бёдра, колени, плечи, локти: левая, правая.
	var legs := Vector2.ZERO
	var knees := Vector2.ZERO
	var arms := Vector2.ZERO
	var elbows := Vector2.ZERO
	## Наклон корпуса вперёд от таза.
	var lean: float = 0.0
	## Наклон головы вперёд относительно корпуса.
	var head: float = 0.0
	## Наклон всего тела вокруг пяток: 90 — лежит вперёд лицом.
	var tilt: float = 0.0
	## Подъём всего тела над полом, в долях роста — сверх заземления: риг сам
	## ставит любую позу на пол по её габариту, а это добавка к тому.
	var lift: float = 0.0
	## Сжатие по высоте: раздавленный — 0.3.
	var squash: float = 1.0

	static func make(leg_angles: Vector2, arm_angles: Vector2) -> Pose:
		var pose := Pose.new()
		pose.legs = leg_angles
		pose.arms = arm_angles
		return pose

	## Сгиб колен и локтей. Возвращает себя: позы собираются цепочкой.
	func bent_at(knee_angles: Vector2, elbow_angles: Vector2 = Vector2.ZERO) -> Pose:
		knees = knee_angles
		elbows = elbow_angles
		return self

	## Наклон корпуса и головы.
	func leaned(torso_lean: float, head_tilt: float = 0.0) -> Pose:
		lean = torso_lean
		head = head_tilt
		return self

	## Наклон тела целиком вокруг пяток.
	func tilted(body_tilt: float) -> Pose:
		tilt = body_tilt
		return self

	## Подъём над полом.
	func lifted(body_lift: float) -> Pose:
		lift = body_lift
		return self

	## Сжатие по высоте.
	func squashed(height_squash: float) -> Pose:
		squash = height_squash
		return self

	## Своя копия: таблица поз общая, а актёр работает со своей.
	func copy() -> Pose:
		var twin := Pose.make(legs, arms).bent_at(knees, elbows).leaned(lean, head)
		return twin.tilted(tilt).lifted(lift).squashed(squash)


## Клип пака: какой и как его играть.
class Clip:
	extends RefCounted

	## Играет по кругу, по часам рига.
	const LOOP := 0
	## Играет один раз с начала позы и замирает на последнем кадре.
	const ONCE := 1
	## Стоит на последнем кадре.
	const END := 2
	## Идёт по фазе ходьбы актёра.
	const WALK := 3

	var name: String
	var mode: int

	static func make(clip_name: String, clip_mode: int) -> Clip:
		var clip := Clip.new()
		clip.name = clip_name
		clip.mode = clip_mode
		return clip


## Имена клипов в `.glb` — те, что пишет `tools/build_actors.py`.
## С M24c клипы — из Universal Animation Library, перенесённые на скелет пака
## (ADR-0039, решение 1).
##
## Нейтральная стойка, руки вниз: основа поз кодом. В кадре она не играет —
## стойка в игре держит пистолет двумя руками, и углы рук от неё ничего бы не
## значили.
const CLIP_STAND := "stand"
const CLIP_IDLE := "idle"
const CLIP_WALK := "walk"
const CLIP_SHOOT := "shoot"
const CLIP_DEATH := "death"
const CLIP_JUMP_START := "jump_start"
const CLIP_JUMP_AIR := "jump_air"
const CLIP_JUMP_LAND := "jump_land"
const CLIP_CROUCH := "crouch"
const CLIP_NAMES: PackedStringArray = [
	CLIP_STAND,
	CLIP_IDLE,
	CLIP_WALK,
	CLIP_SHOOT,
	CLIP_DEATH,
	CLIP_JUMP_START,
	CLIP_JUMP_AIR,
	CLIP_JUMP_LAND,
	CLIP_CROUCH,
]

## С какой скоростью идёт клип ходьбы относительно записанной. Пак шагает
## прогулочно, а Otto и агент идут 2.2 м/с (`Arcade.WALK_PX`): на родной
## скорости подошвы ехали бы по полу. Множитель — скорость актёра, поделённая на
## скорость опорной стопы в клипе: та едет назад 1.27 м/с, замер
## `tools/walk_stride.gd`.
const WALK_CLIP_RATE: float = 1.75

## Присед: ноги вперёд, колени сложены, корпус над коленями, голова вперёд из-под
## шляпы. С коленями это наконец «на корточках», а не «согнулся» (долг M18c).
## Держит тест по габариту скелета: Otto под пулей агента и в коллизии приседа
## 1.08 м, агент на колене — под пулей стоящего Otto, 1.09 по нижнему краю.
const CROUCH_LEGS: float = 100.0
const CROUCH_KNEES: float = 140.0
const CROUCH_LEAN: float = 45.0
const CROUCH_HEAD: float = -10.0

static var _table: Dictionary = _build_table()
static var _clips: Dictionary = _build_clips()


## Поза кодом по имени из [ActorPose]. Неизвестное имя и поза клипом —
## «stand», первый кадр стойки: актёр без позы в кадре хуже, чем в неверной.
##
## Отдаёт копию: методы сборки правят позу на месте, и запись таблицы, ушедшая
## наружу, менялась бы у всех актёров разом.
static func of(pose_name: String) -> Pose:
	var found: Variant = _table.get(pose_name, _table["stand"])
	return (found as Pose).copy()


## Клип позы или null, если поза кодом.
static func clip_of(pose_name: String) -> Clip:
	if pose_name.begins_with("walk_"):
		return _clips["walk"] as Clip
	return _clips.get(pose_name) as Clip


## Есть ли у позы запись — кодом или клипом. По этому тест сверяет таблицу
## со списками [ActorPose].
static func knows(pose_name: String) -> bool:
	return clip_of(pose_name) != null or _table.has(pose_name)


static func _build_clips() -> Dictionary:
	return {
		"idle": Clip.make(CLIP_IDLE, Clip.LOOP),
		"walk": Clip.make(CLIP_WALK, Clip.WALK),
		"shoot": Clip.make(CLIP_SHOOT, Clip.ONCE),
		# Смерть показывается двумя позами (ADR-0011, пункт 12): падение — клип
		# с начала, лежащее тело — его последний кадр.
		"dead_0": Clip.make(CLIP_DEATH, Clip.ONCE),
		"dead_1": Clip.make(CLIP_DEATH, Clip.END),
	}


static func _build_table() -> Dictionary:
	var table := {}
	# Первый кадр стойки как есть: основа всех поз кодом и запасная поза.
	table["stand"] = Pose.new()
	# Присед — не другая фигура, а поза скелета (ADR-0022, решение 3).
	table["crouch"] = (
		Pose
		. make(Vector2(CROUCH_LEGS, CROUCH_LEGS), Vector2(20.0, 25.0))
		. bent_at(Vector2(CROUCH_KNEES, CROUCH_KNEES), Vector2(30.0, 30.0))
		. leaned(CROUCH_LEAN, CROUCH_HEAD)
	)
	# Прыжок: одна нога подобрана, другая чуть согнута, руки вскинуты.
	table["jump"] = (
		Pose
		. make(Vector2(60.0, -10.0), Vector2(120.0, 130.0))
		. bent_at(Vector2(90.0, 30.0), Vector2(20.0, 20.0))
		. leaned(-6.0)
	)
	# Удар ногой: нога уходит вперёд почти горизонтально и прямая, опорная
	# подогнута, корпус откинут.
	table["kick"] = (
		Pose
		. make(Vector2(85.0, -20.0), Vector2(-25.0, 15.0))
		. bent_at(Vector2(0.0, 40.0), Vector2(30.0, 30.0))
		. leaned(-14.0, 8.0)
	)
	# Раздавленный кабиной или лампой: ноги и руки врозь, сплющен по высоте.
	table["crushed"] = (
		Pose
		. make(Vector2(-30.0, 30.0), Vector2(60.0, -60.0))
		. bent_at(Vector2(40.0, 40.0))
		. squashed(0.3)
	)
	# Залёгший под пулю агент (ADR-0016, пункт 2). Лежит лицом вниз, руки со
	# стволом вытянуты вперёд по полу — от трупа на спине отличается сразу.
	# Угол рук — наклон тела плюс 90: так рука ложится вдоль пола. Голова
	# задрана назад, к стволу: поля шляпы ложатся на затылок, а не встают стеной.
	table["prone"] = (
		Pose
		. make(Vector2(-4.0, 4.0), Vector2(170.0, 176.0))
		. bent_at(Vector2(10.0, 10.0), Vector2(-10.0, -10.0))
		. leaned(0.0, -40.0)
		. tilted(90.0)
	)
	return table
