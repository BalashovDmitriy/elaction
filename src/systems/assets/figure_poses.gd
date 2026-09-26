class_name FigurePoses
extends RefCounted

## Позы фигуры: чем отыгрывается каждая поза [ActorPose].
##
## С M21 (ADR-0032, решение 1) поз две природы. Там, где ROM не диктует высот,
## двигается клип — с M24c из Universal Animation Library (ADR-0039): стойка,
## ходьба, выстрел, смерть, толчок, полёт и приземление, удары и реакции сценок
## добивания (ADR-0040). Там, где диктует, — поза кодом из этой таблицы: присед
## и залёгший под пулями ROM, раздавленный; и позы добиваний, которых нет ни в
## одной свободной библиотеке: захват, удушение, свёрнутая шея.
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
	## Поворот головы вбок, вокруг вертикали: свёрнутая шея (ADR-0040).
	var twist: float = 0.0
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

	## Поворот головы вбок.
	func twisted(head_twist: float) -> Pose:
		twist = head_twist
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
		return twin.twisted(twist).tilted(tilt).lifted(lift).squashed(squash)


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
	## С какого момента клипа начинать, с: у толчка UAL в начале присед-замах,
	## а прыжок в игре мгновенный.
	var start: float = 0.0
	## Во сколько раз быстрее записанного играть.
	var rate: float = 1.0

	static func make(
		clip_name: String, clip_mode: int, from: float = 0.0, speed: float = 1.0
	) -> Clip:
		var clip := Clip.new()
		clip.name = clip_name
		clip.mode = clip_mode
		clip.start = from
		clip.rate = speed
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
## Клипы сценок добивания (ADR-0040): удары Otto и реакции агента.
const CLIP_PUNCH_JAB := "punch_jab"
const CLIP_PUNCH_CROSS := "punch_cross"
const CLIP_HIT_HEAD := "hit_head"
const CLIP_HIT_CHEST := "hit_chest"
const CLIP_KNOCKBACK := "knockback"
const CLIP_NAMES: PackedStringArray = [
	CLIP_STAND,
	CLIP_IDLE,
	CLIP_WALK,
	CLIP_SHOOT,
	CLIP_DEATH,
	CLIP_JUMP_START,
	CLIP_JUMP_AIR,
	CLIP_JUMP_LAND,
	CLIP_PUNCH_JAB,
	CLIP_PUNCH_CROSS,
	CLIP_HIT_HEAD,
	CLIP_HIT_CHEST,
	CLIP_KNOCKBACK,
]

## С какой скоростью идёт клип ходьбы относительно записанной. Пак шагает
## прогулочно, а Otto и агент идут 2.2 м/с (`Arcade.WALK_PX`): на родной
## скорости подошвы ехали бы по полу. Множитель — скорость актёра, поделённая на
## скорость опорной стопы в клипе: та едет назад 1.27 м/с, замер
## `tools/walk_stride.gd`.
const WALK_CLIP_RATE: float = 1.75

## Толчок UAL: первые три кадра (0.125 с) — присед перед отрывом. Прыжок в игре
## мгновенный, и клип начинается с отрыва.
const JUMP_FROM: float = 0.125
## Приземление UAL сидит в глубоком приседе до 0.45 с и выпрямляется к 0.9 с —
## те самые «колени» и «медленно выпрямляется», на которые жаловался игрок.
## Клип идёт с полуприседа и вдвое быстрее: касание пола видно, а на коленях
## Otto не сидит. Кадры M24C: под низким потолком прыжок короткий, и с начала
## клипа Otto приземлялся почти на колени.
const LAND_FROM: float = 0.45
const LAND_RATE: float = 2.0
## Сколько показывать приземление, с: столько клип идёт от [constant LAND_FROM]
## до стойки. Дольше — стойка, раньше — шаг, если пауза кончилась.
const LAND_SHOW: float = 0.225

## Сколько длится переход в позу, с (ADR-0039, решение 5). Смесь идёт по
## времени, а не гаснущей экспонентой: переход кончается, а не подползает.
## В приземление и выстрел — почти сразу: они про момент; в стойку — мягче.
const BLEND_DEFAULT: float = 0.12
const BLEND_TIMES: Dictionary = {
	"idle": 0.15,
	"walk": 0.1,
	"shoot": 0.05,
	"jump": 0.06,
	"fall": 0.15,
	"land": 0.04,
	"crouch": 0.08,
	"prone": 0.12,
	"dead_0": 0.08,
	"dead_1": 0.3,
	"crushed": 0.05,
	"whip_raise": 0.16,
	"whip_strike": 0.06,
	"punch_jab": 0.06,
	"punch_cross": 0.06,
}

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


## Сколько длится переход в позу, с. Кадры ходьбы — одна поза «walk».
static func blend_time(pose_name: String) -> float:
	var key := "walk" if pose_name.begins_with("walk_") else pose_name
	return float(BLEND_TIMES.get(key, BLEND_DEFAULT))


static func _build_clips() -> Dictionary:
	return {
		"idle": Clip.make(CLIP_IDLE, Clip.LOOP),
		"walk": Clip.make(CLIP_WALK, Clip.WALK),
		"shoot": Clip.make(CLIP_SHOOT, Clip.ONCE),
		# Прыжок тремя фазами (ADR-0039): толчок клипом, в полёте удар ногой
		# позой кодом — в оригинале прыжок и есть удар, — приземление клипом.
		"jump": Clip.make(CLIP_JUMP_START, Clip.ONCE, JUMP_FROM),
		# С M24d удара ногой нет (ADR-0040): на спуске — клип полёта UAL.
		"fall": Clip.make(CLIP_JUMP_AIR, Clip.LOOP),
		"land": Clip.make(CLIP_JUMP_LAND, Clip.ONCE, LAND_FROM, LAND_RATE),
		# Сценки добивания (ADR-0040). Удары — с разгона стойки, без замаха в
		# начале клипа: сценка короткая.
		"punch_jab": Clip.make(CLIP_PUNCH_JAB, Clip.ONCE, 0.05, 1.3),
		"punch_cross": Clip.make(CLIP_PUNCH_CROSS, Clip.ONCE, 0.05, 1.3),
		"hit_head": Clip.make(CLIP_HIT_HEAD, Clip.ONCE, 0.0, 1.2),
		"hit_chest": Clip.make(CLIP_HIT_CHEST, Clip.ONCE, 0.0, 1.2),
		"knockback": Clip.make(CLIP_KNOCKBACK, Clip.ONCE, 0.0, 1.4),
		# Лежит, отброшенный ударом: конец отброса — труп сценки.
		"knocked": Clip.make(CLIP_KNOCKBACK, Clip.END),
		# Смерть показывается двумя позами (ADR-0011, пункт 12): падение — клип
		# с начала, лежащее тело — его последний кадр.
		"dead_0": Clip.make(CLIP_DEATH, Clip.ONCE),
		"dead_1": Clip.make(CLIP_DEATH, Clip.END),
	}


## Позы добиваний (ADR-0040): захват, удушение, свёрнутая шея, добивание сверху.
## Сценка ставит агента вплотную к Otto, и позы рассчитаны на это расстояние:
## руки Otto — на высоте шеи агента того же роста.
static func _add_takedown_poses(table: Dictionary) -> void:
	# Удушение сзади: руки Otto вперёд на уровень шеи, локти согнуты — предплечья
	# охватывают горло; корпус откинут, ноги в упоре.
	table["choke_hold"] = (
		Pose
		. make(Vector2(15.0, -12.0), Vector2(78.0, 72.0))
		. bent_at(Vector2(20.0, 25.0), Vector2(95.0, 100.0))
		. leaned(-10.0, 5.0)
	)
	# Душимый: руки к горлу, голова запрокинута, ноги подгибаются.
	table["choked"] = (
		Pose
		. make(Vector2(12.0, -6.0), Vector2(125.0, 118.0))
		. bent_at(Vector2(25.0, 12.0), Vector2(115.0, 120.0))
		. leaned(-12.0, -28.0)
	)
	# Душимый бьётся: нога брыкается вперёд.
	table["choked_kick"] = (
		Pose
		. make(Vector2(40.0, -18.0), Vector2(110.0, 128.0))
		. bent_at(Vector2(45.0, 8.0), Vector2(105.0, 120.0))
		. leaned(-16.0, -32.0)
	)
	# Свёрнутая шея: Otto берёт голову двумя руками...
	table["snap_grab"] = (
		Pose
		. make(Vector2(12.0, -10.0), Vector2(98.0, 92.0))
		. bent_at(Vector2(15.0, 20.0), Vector2(55.0, 65.0))
		. leaned(4.0)
	)
	# ...и рвёт её вбок: руки проходят вниз, корпус подаётся вперёд.
	table["snap_twist"] = (
		Pose
		. make(Vector2(15.0, -12.0), Vector2(70.0, 110.0))
		. bent_at(Vector2(20.0, 25.0), Vector2(35.0, 80.0))
		. leaned(12.0, 8.0)
	)
	# Агент в захвате за голову: руки дёрнулись, голова чуть запрокинута.
	table["snap_held"] = (
		Pose
		. make(Vector2(5.0, -5.0), Vector2(35.0, 30.0))
		. bent_at(Vector2(10.0, 10.0), Vector2(40.0, 35.0))
		. leaned(-4.0, -12.0)
	)
	# Шея свёрнута: голова повёрнута вбок и уронена, колени подломились.
	table["snap_broken"] = (
		Pose
		. make(Vector2(10.0, 0.0), Vector2(10.0, 5.0))
		. bent_at(Vector2(35.0, 30.0), Vector2(15.0, 10.0))
		. leaned(6.0, 22.0)
		. twisted(78.0)
	)
	# Удар рукоятью: пистолет вскинут над головой, свободная рука держит за
	# ворот...
	table["whip_raise"] = (
		Pose
		. make(Vector2(10.0, -8.0), Vector2(62.0, 170.0))
		. bent_at(Vector2(15.0, 15.0), Vector2(40.0, 8.0))
		. leaned(-6.0, -4.0)
	)
	# ...и рушится вниз: рука с рукоятью проходит перед грудью, корпус следом.
	table["whip_strike"] = (
		Pose
		. make(Vector2(28.0, -12.0), Vector2(45.0, 52.0))
		. bent_at(Vector2(32.0, 18.0), Vector2(35.0, 5.0))
		. leaned(20.0, 10.0)
	)
	# Напрыгнувший сверху добивает: присел над поверженным, бьёт вниз.
	table["pounce_strike"] = (
		Pose
		. make(Vector2(75.0, 35.0), Vector2(55.0, -15.0))
		. bent_at(Vector2(110.0, 85.0), Vector2(10.0, 35.0))
		. leaned(42.0, 10.0)
	)


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
	_add_takedown_poses(table)
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
