class_name FigurePoses
extends RefCounted

## Позы фигуры: как стоит скелет в каждой позе [ActorPose].
##
## Таблица переехала из спрайтового генератора (`render_actors.py`), где те же
## углы задавали коробкам конечностей их наклон для рендера. Теперь их исполняет
## [FigureRig] на живом скелете, а между позами интерполирует (ADR-0022, решение 2).
##
## Углы — в градусах, **положительный уводит конечность вперёд**, по ходу
## взгляда. Наклоны корпуса и тела — тоже вперёд положительные; лежащий на
## спине труп наклонён назад, залёгший под пулю агент — вперёд.
##
## Без узлов, без сцены: проверяется тем же приёмом, что [OttoStateMachine].


## Одна поза скелета.
class Pose:
	extends RefCounted

	## Ноги и руки: левая, правая.
	var legs := Vector2.ZERO
	var arms := Vector2.ZERO
	## Наклон корпуса вперёд от бёдер.
	var lean: float = 0.0
	## Наклон головы вперёд относительно корпуса.
	var head: float = 0.0
	## Наклон всего тела вокруг пяток: 90 — лежит вперёд лицом, -90 — на спине.
	var tilt: float = 0.0
	## Просадка бёдер вниз, в долях высоты бёдер: 0 — стоит, 1 — сел на пол.
	var drop: float = 0.0
	## Подъём всего тела над полом, в долях роста — сверх заземления: риг сам
	## ставит любую позу на пол по её габариту, а это добавка к тому. Ходьба
	## приподнимает тело, когда ноги сходятся.
	var lift: float = 0.0
	## Сжатие по высоте: раздавленный — 0.3.
	var squash: float = 1.0

	static func make(leg_angles: Vector2, arm_angles: Vector2) -> Pose:
		var pose := Pose.new()
		pose.legs = leg_angles
		pose.arms = arm_angles
		return pose

	## Наклон корпуса и головы. Возвращает себя: позы собираются цепочкой.
	func bent(torso_lean: float, head_tilt: float = 0.0) -> Pose:
		lean = torso_lean
		head = head_tilt
		return self

	## Наклон тела целиком вокруг пяток.
	func tilted(body_tilt: float) -> Pose:
		tilt = body_tilt
		return self

	## Просадка бёдер.
	func dropped(hip_drop: float) -> Pose:
		drop = hip_drop
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
		return blend(self, 0.0)

	## Смесь двух поз: [param weight] 0 — эта, 1 — [param other].
	func blend(other: Pose, weight: float) -> Pose:
		var t := clampf(weight, 0.0, 1.0)
		var mixed := Pose.make(legs.lerp(other.legs, t), arms.lerp(other.arms, t))
		mixed.lean = lerpf(lean, other.lean, t)
		mixed.head = lerpf(head, other.head, t)
		mixed.tilt = lerpf(tilt, other.tilt, t)
		mixed.drop = lerpf(drop, other.drop, t)
		mixed.lift = lerpf(lift, other.lift, t)
		mixed.squash = lerpf(squash, other.squash, t)
		return mixed

	## Совпадают ли позы с точностью до долей градуса.
	func is_close_to(other: Pose, tolerance: float = 0.01) -> bool:
		return (
			legs.distance_to(other.legs) <= tolerance
			and arms.distance_to(other.arms) <= tolerance
			and absf(lean - other.lean) <= tolerance
			and absf(head - other.head) <= tolerance
			and absf(tilt - other.tilt) <= tolerance
			and absf(drop - other.drop) <= tolerance
			and absf(lift - other.lift) <= tolerance
			and absf(squash - other.squash) <= tolerance
		)


## Размах ноги в шаге и руки ей навстречу, градусов. Те же 26 и 20, что были
## у крайних кадров спрайтовой ходьбы.
const STRIDE: float = 26.0
const ARM_SWING: float = 20.0

## На сколько тело приподнимается на середине шага, в долях роста.
const STEP_LIFT: float = 0.02

## Присед: бёдра проседают наполовину, ноги уходят вперёд, корпус складывается,
## голова смотрит вперёд из-под него. Подобрано так, чтобы фигура улеглась в
## коллизию приседа — 1.08 м у Otto против 1.68 стоя — и чтобы агент на колене
## (та же поза) целиком ушёл под пулю стоящего Otto, 1.12 м. При наклоне 64°
## (M16) макушка шляпы резала край пули; при 70° резала снова, когда агент
## вырос до роста Otto (M18c): 1.16 против 1.09 у нижнего края. При 76° — 1.04,
## а у Otto 0.97, и это ~62% роста против ~64% приседа в оригинале. Бёдра
## высоту не решают вовсе: заземление поднимает фигуру по пяткам обратно.
## Держит это тест по габариту скелета, а не глаз.
const CROUCH_LEGS: float = 62.0
const CROUCH_DROP: float = 0.5
const CROUCH_LEAN: float = 76.0
const CROUCH_HEAD: float = -14.0

static var _table: Dictionary = _build_table()


## Поза по имени из [ActorPose]. Неизвестное имя — «idle», а не падение:
## актёр без позы в кадре хуже, чем актёр в неверной.
##
## Отдаёт копию: методы сборки ([method Pose.bent] и остальные) правят позу на
## месте, и запись таблицы, ушедшая наружу, менялась бы у всех актёров разом.
static func of(pose_name: String) -> Pose:
	if pose_name.begins_with("walk_"):
		return walking(float(ActorPose.walk_frame_index(pose_name)))
	var found: Variant = _table.get(pose_name, _table["idle"])
	return (found as Pose).copy()


## Есть ли у позы запись. По этому тест сверяет таблицу со списками [ActorPose].
static func knows(pose_name: String) -> bool:
	return pose_name.begins_with("walk_") or _table.has(pose_name)


## Ходьба по фазе [ActorPose] — непрерывный цикл, а не три кадра.
##
## Фаза идёт 0..[constant ActorPose.WALK_FRAMES]; ноги качаются синусом в
## противофазе, руки — навстречу ногам, тело чуть приподнимается, когда ноги
## сходятся. Крайние кадры прежней ходьбы — это четверти этого цикла.
static func walking(phase: float) -> Pose:
	var turn := phase / float(ActorPose.WALK_FRAMES) * TAU
	var swing := sin(turn)
	var pose := Pose.make(
		Vector2(STRIDE * swing, -STRIDE * swing), Vector2(-ARM_SWING * swing, ARM_SWING * swing)
	)
	# Ноги сходятся дважды за цикл — там тело и выше всего.
	return pose.lifted(STEP_LIFT * (1.0 - absf(swing)))


static func _build_table() -> Dictionary:
	var table := {}
	table["idle"] = Pose.make(Vector2.ZERO, Vector2(-4.0, 4.0))
	# Присед — не другая фигура, а поза скелета (ADR-0022, решение 3).
	table["crouch"] = (
		Pose
		. make(Vector2(CROUCH_LEGS, CROUCH_LEGS), Vector2(10.0, -10.0))
		. bent(CROUCH_LEAN, CROUCH_HEAD)
		. dropped(CROUCH_DROP)
	)
	# Прыжок: одна нога подобрана, руки вскинуты.
	table["jump"] = Pose.make(Vector2(25.0, -15.0), Vector2(120.0, 130.0)).bent(-6.0)
	# Удар ногой: нога уходит вперёд почти горизонтально, корпус откинут.
	table["kick"] = Pose.make(Vector2(85.0, -20.0), Vector2(-25.0, 15.0)).bent(-14.0, 8.0)
	# Выстрел: правая рука с пистолетом вперёд, горизонтально.
	table["shoot"] = Pose.make(Vector2.ZERO, Vector2(-4.0, 90.0))
	# Смерть: падение на спину и лежащее тело (ADR-0011, пункт 12).
	table["dead_0"] = Pose.make(Vector2(-15.0, 10.0), Vector2(35.0, -35.0)).tilted(-45.0)
	table["dead_1"] = Pose.make(Vector2(-10.0, 8.0), Vector2(40.0, -30.0)).tilted(-90.0)
	# Раздавленный кабиной или лампой: та же фигура, сплющенная по высоте.
	table["crushed"] = Pose.make(Vector2(-30.0, 30.0), Vector2(60.0, -60.0)).squashed(0.3)
	# Залёгший под пулю агент (ADR-0016, пункт 2). Лежит лицом вниз, руки со
	# стволом вытянуты вперёд по полу — от трупа на спине отличается сразу.
	# Угол рук — наклон тела плюс 90: так рука ложится вдоль пола. Меньше — и
	# она втыкается в пол, а заземление поднимает на ней всё тело: с рукой на
	# 90° залёгший стоял на ней почти в метр ростом. Голова вдоль тела: поднятая
	# ставит поля шляпы вертикально, и фигура растёт с каждым градусом.
	table["prone"] = Pose.make(Vector2(-6.0, 6.0), Vector2(174.0, 180.0)).bent(0.0, -8.0).tilted(
		90.0
	)
	return table
