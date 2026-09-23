class_name Enemy
extends CharacterBody3D

## Враг-агент.
##
## Выходит из обычной двери, идёт по своему этажу к Otto и стреляет, когда тот
## оказывается на одной с ним линии. Решает [EnemyBrain], узел исполняет.
##
## Телом агент не вредит: в оригинале жизнь снимает только выстрел (ADR-0006,
## пункт 4), поэтому зоны урона у него нет — только оружие.
##
## Как и Otto, живёт в плоскости игры: Z заперт (ADR-0021, решение 1).

## Агент убит. Передаёт себя, чтобы дверь знала, кого выпускать заново.
signal died(agent: Enemy)

## Агент дошёл до двери и ушёл в неё (ADR-0027, решение 3а). Убирает его уровень.
signal left_building(agent: Enemy)

const BULLET_SCENE := preload("res://src/systems/combat/bullet.tscn")
## Слой врагов в `project.godot`. Агент сходит с него, пока стоит в проёме.
const ENEMY_LAYER: int = 3
## Сколько агент падает, прежде чем лечь: смерть — две позы (ADR-0011, п. 12).
const FALLING_TIME: float = 0.25

## Сколько держится поза выстрела, с.
const SHOOT_POSE_TIME: float = 0.25

## Ходьба — та же, что у Otto: в ROM у них одна процедура шага (ADR-0027).
@export var walk_speed: float = Arcade.speed(Arcade.WALK_PX)
@export var gravity: float = 27.0
@export var max_fall_speed: float = 12.6

## Высота выстрела от ног стоя: попадает в стоящего Otto и проходит над
## присевшим. Из приседа и лёжа — свои высоты ROM ([Proportions]): из приседа
## пуля проходит над лежачим, лёжа — бьёт и присевшего (ADR-0027, решение 3).
@export var shot_height: float = Proportions.AGENT_SHOT
@export var muzzle_offset: float = Proportions.MUZZLE

## Сколько тело лежит, прежде чем исчезнуть, с.
@export var corpse_time: float = 0.5

## Настройки решений, которые не зависят от здания: сколько агент выбирается из
## двери и какой разброс по высоте считается «на одной линии». Узел держит их у
## себя и отдаёт [EnemyBrain] — так же, как дверь отдаёт свои [DoorVisit].
##
## Числа боя — замах, пауза, поза, увёртка, скорость пули — считает [Arcade]
## по злости агента и навыку здания (ADR-0027).
@export var emerge_time: float = 0.6
@export var same_line: float = 0.45

## Правила здания, из которого вышел агент. Пустых не бывает: без них он
## достаёт значения по умолчанию — те же, что у здания по умолчанию.
var _rules: BuildingRules = null

var _brain := EnemyBrain.new()
var _target: Otto = null
var _corpse_left: float = 0.0
var _in_the_dark: bool = false
## Стоит ли Otto в темноте. От этого, а не от собственной тени агента, зависит,
## видит ли он Otto: из тени освещённого видно, освещённый в тень не видит.
var _target_in_the_dark: bool = false
var _target_behind_a_wall: bool = false
## Куда идти, чтобы уехать: ось стоящей кабины или NAN, если ехать некуда.
var _lift_x: float = NAN
## Куда идти, чтобы уйти из здания: дверь или NAN (@041F).
var _exit_x: float = NAN
## Фаза ходьбы, поза выстрела и падения, признак раздавленного — всё как у Otto.
var _walk_phase: float = 0.0
var _walking: bool = false
var _shooting: float = 0.0
var _falling_over: float = 0.0
var _crushed: bool = false
## С какой злостью агент вышел и сколько он уже живёт, с: злость растёт с
## возрастом (@5AFC). Навык здания — для скорости пули, тревога — сирена.
var _spawn_anger: int = 0
var _age: float = 0.0
var _skill: int = 0
var _alarmed: bool = false
## Сколько ещё длится тревога агентов, с (ADR-0027, решение 5).
var _alert_left: float = 0.0
## Последняя выпущенная пуля: в полёте она у агента одна (@1BAE).
var _bullet: Bullet = null

@onready var _body: FigureRig = $Body
@onready var _floor_probe: RayCast3D = $FloorProbe
@onready var _shape: CollisionShape3D = $Shape


## Форму тела и щуп пола задаёт [Proportions], а не сцена — как у [Otto].
func _notification(what: int) -> void:
	if what != NOTIFICATION_SCENE_INSTANTIATED:
		return
	var width := Proportions.BODY_WIDTH
	Proportions.fit_box(
		$Shape as CollisionShape3D, Vector3(width, Proportions.BODY, WorldSpace.BODY_DEPTH)
	)
	# Щуп смотрит на три четверти корпуса вперёд и на корпус вниз: ступню,
	# которой агент сейчас шагнёт, и пол под ней.
	var probe := $FloorProbe as RayCast3D
	probe.position = Vector3(width * 0.75, width / 3.0, 0.0)
	probe.target_position = Vector3(0.0, -width, 0.0)


func _ready() -> void:
	_brain.emerge_time = emerge_time
	_brain.same_line = same_line
	# Стоячий рост берётся у самой формы, а не записывается вторым числом:
	# разъехавшись, они дали бы агента, который уклоняется не своим телом.
	_brain.stand_height = (_shape.shape as BoxShape3D).size.y
	_refresh_brain()


func _physics_process(delta: float) -> void:
	if _brain.is_dead():
		# Тело доезжает до пола. Сам агент не прыгает — ни в оригинале, ни у нас
		# (ADR-0026), — но в воздухе бывает: кабина ушла из-под пассажира или
		# вытолкнула его снизу, и убитый в этот миг не должен в нём зависать.
		_apply_gravity(delta)
		move_and_slide()
		_hold_the_plane()
		_walking = false
		_rot(delta)
		_update_look(delta)
		return

	var alive_target := _target != null and not _target.is_dead()
	# Мозгу вектор до цели нужен в координатах правил: там Y растёт вниз, и
	# «на одной линии» он считает так же, как считал в 2D.
	var to_target := Vector2.ZERO
	if alive_target:
		to_target = WorldSpace.direction_to_plane(_target.global_position - global_position)
	# Невидимый Otto для мозга — не цель: он не поворачивается к нему и не
	# стреляет, а идёт, куда шёл (ADR-0023, решение 8).
	var sees_target := alive_target and _sees(to_target)
	_age += delta
	_alert_left = maxf(_alert_left - delta, 0.0)
	_brain.anger = Arcade.aggression(_spawn_anger, _age)
	_brain.alert = _alert_left > 0.0
	var state := _brain.update(
		delta,
		to_target,
		sees_target,
		_incoming_height(),
		alive_target and _in_frame() and not _building_rules().agents_hold_fire,
		not is_instance_valid(_bullet),
		alive_target and _target.is_crouching()
	)
	_fit_shape()
	if _brain.fired():
		_fire()

	# Из проёма агент выходит шагом. EMERGING — это «выйти», а не «постоять»:
	# раньше он эти доли секунды стоял на коврике перед закрытой створкой, и
	# ровно это игрок и назвал «спавнится поверх двери» (ADR-0020).
	var stepping_out := state == EnemyBrain.State.EMERGING
	_shield(stepping_out)

	# Приседая и лёжа агент не ходит: уклонение — это замереть, а не идти
	# дальше пригнувшись. Стоя он идёт, пока мозг не велел постоять.
	var walking := _brain.wants_to_walk()
	# Кабину уровень предлагает, только когда Otto на другом этаже (ADR-0025,
	# решение 6), — по «видит ли он его» решать тут нечего: [code]sees_target[/code]
	# значит «Otto не в тени и не за стеной», и через десять этажей оно тоже
	# истинно. Гейт по нему отключал бы лифты почти всегда.
	var to_the_lift := walking and not stepping_out and not is_nan(_lift_x)
	if to_the_lift:
		walking = _head_for_the_lift()
	elif walking and not stepping_out and not is_nan(_exit_x):
		walking = _head_for(_exit_x)
		if not walking:
			left_building.emit(self)
	if walking and is_on_floor() and _blocked_ahead():
		# Дальше пола нет или стена: агент остаётся на своём этаже (ADR-0006,
		# пункт 6). Видя Otto, он встаёт у края; потеряв — разворачивается и идёт
		# обратно: слепой агент патрулирует этаж, а не караулит проём (ADR-0023).
		if to_the_lift:
			# Идущий к кабине встаёт у проёма и ждёт: кабина ушла, пока он шёл,
			# и шагать в пустую шахту незачем. Разворачивать его нельзя — он
			# тут же забыл бы, зачем пришёл.
			walking = false
		elif stepping_out:
			walking = false
		else:
			# Бродящий агент у края этажа поворачивает: за Otto он не гонится
			# и у проёма его не караулит (ADR-0027, решение 3а).
			_brain.turn_around()
	velocity.x = walk_speed * _brain.facing if walking else 0.0
	_apply_gravity(delta)
	move_and_slide()
	_hold_the_plane()
	_walking = walking
	_update_look(delta)


## Куда идти, чтобы уехать: координата стоящей кабины или NAN, если ехать
## некуда. Пересчитывает уровень каждый кадр — он один знает, где Otto и какая
## кабина стоит вровень с этажом (ADR-0025, решение 6).
##
## Кабину агент не вызывает: вызова в оригинале нет ни у кого. Он идёт к той,
## что уже стоит, и едет пассажиром — ходом распоряжается Otto, а пустая кабина
## ходит своим расписанием.
##
## **Выбранную кабину агент держит, пока ему вообще предлагают ехать.** На этаже
## стилобата шахт до пяти, кабины встают вровень и уходят каждая в свой черёд,
## и предложение переезжало с одной на другую по кадрам: агент разворачивался
## туда-сюда и за полминуты не сдвинулся с места. Отменяет выбор только NAN —
## «ехать некуда»: тогда он снова патрулирует этаж.
func set_lift_at(x: float) -> void:
	if is_nan(x):
		_lift_x = NAN
	elif is_nan(_lift_x):
		_lift_x = x


## Показывает агенту дверь, в которую уйти, или NAN — уходить незачем.
func set_exit_at(x: float) -> void:
	_exit_x = x


## Идти ли к точке [param x] по этажу: дошёл — нет.
func _head_for(x: float) -> bool:
	var gap := x - WorldSpace.to_plane(global_position).x
	_brain.face(gap)
	return absf(gap) > Proportions.DOOR_MAT * 0.5


## Идти ли к кабине и стоит ли при этом переставлять ноги. Зовётся только тогда,
## когда кабина выбрана: без выбора идти некуда и спрашивать нечего.
##
## Дойдя, агент замирает и остаётся повёрнутым к шахте: кабина — не место для
## патруля. Иначе он шагал бы от стенки к стенке внутри неё и вываливался
## на первом же этаже, где пол впереди снова появился.
func _head_for_the_lift() -> bool:
	var gap := _lift_x - WorldSpace.to_plane(global_position).x
	_brain.face(gap)
	return absf(gap) > _lift_aboard()


## Насколько близко к оси кабины агент считает, что он уже в ней, м.
##
## Полуширина кабины минус полкорпуса агента: ближе этого он целиком внутри
## габарита, и шагать дальше некуда. Ширина кабины — у правил здания, а не у
## [Proportions]: по правилам её растягивает уровень ([method
## ElevatorCar.fit_to_story]), и с другой шахтой агент вставал бы наполовину
## снаружи.
func _lift_aboard() -> float:
	return maxf(_building_rules().shaft_width * 0.5 - _body_half_width(), 0.0)


## Отдаёт агенту правила здания: из них он берёт навык и рост в стойках.
##
## Зовётся до [method Node.add_child] и после — порядок не решает ничего, как и
## у [method set_threat]: числа переносятся в [EnemyBrain] одним [method _refresh_brain].
func apply_rules(rules: BuildingRules) -> void:
	_rules = rules
	_skill = rules.skill
	_refresh_brain()


## Выпускает агента из двери: он выходит в сторону [param towards].
func setup(target: Otto, towards: float) -> void:
	_target = target
	_brain.start(towards)
	# Щит ставится здесь, а не первым кадром физики: иначе между постановкой
	# в проём и первым [method _physics_process] остаётся шаг, на котором
	# агент — обычная мишень, и пуля с пинком забирают за него очки, ничего
	# при этом не убив (ADR-0020, решение 3).
	_shield(true)


## Сообщает агенту, что под ним темно. От этого зависит только цена его смерти:
## убийство в темноте дороже (ADR-0010, пункт 6). Решений боя темнота под агентом
## больше не меняет — их решает тень Otto (ADR-0023, решение 8), — поэтому здесь
## присваивание и ничего больше: зовут это каждый кадр на каждого живого.
func set_in_the_dark(value: bool) -> void:
	_in_the_dark = value


## Сообщает агенту, что Otto стоит в темноте. Такого он замечает лишь вблизи —
## [member BuildingRules.agent_dark_fire_range] — а дальше не видит вовсе.
func set_target_in_the_dark(value: bool) -> void:
	_target_in_the_dark = value


## Сообщает агенту, что между ним и Otto стоит глухая внутренняя стена.
##
## Сквозь неё не проходит ни пуля, ни взгляд: стрелять в стену незачем, и агент
## ходит по своей половине этажа, пока Otto не обойдёт её через другой уровень
## (ADR-0024, решение 5). Разбирается это тем же путём, что и темнота: не видит —
## не цель (ADR-0023, решение 8).
func set_target_behind_a_wall(value: bool) -> void:
	_target_behind_a_wall = value


## Куда агент смотрит: -1 влево, +1 вправо.
func facing() -> float:
	return _brain.facing


## С какой злостью агент выходит, из какого он навыка здания и звучит ли
## сирена. Злость при выходе — сложность здания в этот миг (@5AA4); дальше она
## растёт с возрастом агента сама.
func set_threat(spawn_anger: int, skill: int, alarmed: bool) -> void:
	_spawn_anger = clampi(spawn_anger, 0, Arcade.TOP)
	_skill = maxi(skill, 0)
	_alarmed = alarmed
	_brain.anger = Arcade.aggression(_spawn_anger, _age)


## Сирена включилась или нет: пуля агента на шаг быстрее (@463D).
func set_alarmed(value: bool) -> void:
	_alarmed = value


## Тревога агентов на [param seconds]: выстрел Otto в кадре или посадка в
## кабину (ADR-0027, решение 5). Не укорачивает уже идущую.
func alert_for(seconds: float) -> void:
	_alert_left = maxf(_alert_left, seconds)


## Третий или четвёртый агент здания: своя таблица поз (table_1D95).
func set_late(value: bool) -> void:
	_brain.late = value


## Сеет решения агента. Зовёт уровень: генератор у каждого свой, но от сида
## здания, и прогон бота повторяется до шага.
func seed_decisions(value: int) -> void:
	_brain.rng.seed = value


## Злость агента сейчас.
func anger() -> int:
	return _brain.anger


## Стоит ли агент в темноте. По этому признаку считается надбавка за убийство.
func is_in_the_dark() -> bool:
	return _in_the_dark


## В какой он стойке. Снаружи это видно и по форме коллизии, но выводить стойку
## из высоты коробки — значит повторять таблицу ростов в каждом, кому она
## понадобилась.
func stance() -> EnemyBrain.Stance:
	return _brain.stance


## Попадание пули. Кто стрелял, тот и получает очки — это решает он сам.
func take_bullet() -> void:
	kill()


## Убивает агента: пулей, ногой или упавшей лампой в M4b.
## [param crushed] — придавило упавшей лампой: у такой смерти своя поза.
func kill(crushed: bool = false) -> void:
	if _brain.is_dead() or _brain.is_emerging():
		return
	_crushed = crushed
	_brain.kill()
	velocity = Vector3.ZERO
	_corpse_left = corpse_time
	_falling_over = FALLING_TIME
	Sounds.play(Sounds.AGENT_DEATH)
	died.emit(self)


func is_dead() -> bool:
	return _brain.is_dead()


## Вышел ли агент из проёма. Пока не вышел — он неуязвим.
func is_emerging() -> bool:
	return _brain.is_emerging()


## Убирает агента со слоя врагов, пока он в проёме.
##
## Не «броня», а отсутствие цели: пуля проходит сквозь, не гаснет и не приносит
## очков. Так неуязвимость видно глазом — выстрел просто пролетает мимо, — и
## её не приходится объяснять правилом (ADR-0020, решение 3).
func _shield(value: bool) -> void:
	# Зовут каждый кадр, а меняется это дважды за жизнь агента: лишнее
	# присваивание — это обращение к серверу физики на каждого живого.
	var on_layer := not value
	if get_collision_layer_value(ENEMY_LAYER) == on_layer:
		return
	set_collision_layer_value(ENEMY_LAYER, on_layer)


## Видит ли агент Otto. За дверью его нет; в темноте он заметен только ближе
## [member BuildingRules.agent_dark_fire_range]; освещённого видно как обычно.
##
## Мерится по горизонтали, как и дальность огня в [EnemyBrain]: иначе «1.8 м —
## треть от шести» сравнивало бы разные вещи, и агент этажом ниже считался бы
## слепым там, где стоящий на той же линии видит.
func _sees(to_target: Vector2) -> bool:
	if _target.is_hidden() or _target_behind_a_wall:
		return false
	if not _target_in_the_dark:
		return true
	return absf(to_target.x) <= _building_rules().agent_dark_fire_range


## Возвращает тело в плоскость игры — по той же причине, что у [Otto].
func _hold_the_plane() -> void:
	velocity.z = 0.0
	global_position.z = WorldSpace.PLAY_Z


## Высота ближайшей летящей в агента пули над его ногами, м, или -1, если
## лететь нечему.
##
## Ищется по группе пуль, а не по детям уровня: детей под три сотни, а пуль на
## экране от силы четыре. Своими пулями агент не интересуется — уклоняться от
## них ему незачем, и маска у них та же на всех агентов.
func _incoming_height() -> float:
	var best := -1.0
	# Дальше 20 px ROM агент пулю не замечает (@05F5).
	var nearest := Arcade.DODGE_REACH_PX * Proportions.PX
	for node in get_tree().get_nodes_in_group(Bullet.GROUP):
		var bullet := node as Bullet
		if bullet == null or bullet.collision_mask != Bullet.FROM_OTTO:
			continue
		# В координатах правил, чтобы вся мерка ниже осталась ровно той, что
		# была выверена в 2D: там у пули над ногами y отрицательный.
		var to_bullet := WorldSpace.direction_to_plane(bullet.global_position - global_position)
		# Летит ли она в нас — и не ушла ли уже за спину.
		#
		# Мерка не «с какой стороны», а «сколько ей до нас осталось»: пуля,
		# миновавшая середину, но не вышедшая из габарита, опаснее всех. Пока
		# считалось по стороне, агент в этот самый миг распрямлялся и ловил её
		# собственной грудью — уклонение кончалось смертью от той же пули.
		#
		# Габарит — полширины тела и вся длина пули: середину она минует хвостом
		# вперёд, и пока хвост перекрывает грудь, вставать по-прежнему нельзя.
		var closing := -to_bullet.x * bullet.direction
		if closing < -(_body_half_width() + bullet.half_length()):
			continue
		var reach := absf(to_bullet.x)
		if reach > nearest:
			continue
		# Уворачивается агент только от пули в полосе ROM — 6..24 px над полом
		# (@05F5): выше и ниже она мимо и так.
		var over_floor := -to_bullet.y
		if over_floor < 6.0 * Proportions.PX or over_floor > 24.0 * Proportions.PX:
			continue
		nearest = reach
		# Ноги агента — ноль, вверх положительно: у пули y отрицательный.
		best = -to_bullet.y
	return best


## Половина ширины тела, м. Вместе с длиной пули ([method Bullet.half_length])
## даёт габарит, из которого пуля должна выйти, прежде чем агент распрямится.
func _body_half_width() -> float:
	return (_shape.shape as BoxShape3D).size.x * 0.5


## Подгоняет форму коллизии под стойку.
##
## Низ формы остаётся на полу, поэтому меняется и размер, и смещение: у
## [CollisionShape3D] начало в середине, и одна лишь смена размера утопила бы
## присевшего агента в перекрытие.
func _fit_shape() -> void:
	var box := _shape.shape as BoxShape3D
	var height := _brain.height()
	if is_equal_approx(box.size.y, height):
		return
	# Форма приходит из сцены общей на всех агентов: правя её на месте, мы
	# пригибали бы разом всех, кто её делит.
	var own := box.duplicate() as BoxShape3D
	own.size = Vector3(box.size.x, height, box.size.z)
	_shape.shape = own
	_shape.position.y = height * 0.5


## Некуда ли шагать: впереди проём или стена, в которую агент уже упёрся.
##
## Стена берётся с прошлого шага [method CharacterBody3D.move_and_slide]:
## развернувшись, агент уходит от неё, и на следующем кадре она уже не в счёт,
## так что у стены он не дёргается.
func _blocked_ahead() -> bool:
	return not _floor_ahead() or is_on_wall()


## Есть ли пол там, куда агент собирается шагнуть.
##
## Без этой проверки он уходил бы с собственного этажа в проём шахты или
## эскалатора: маска у него только на геометрию, а дыра в перекрытии для
## него ничем не отличается от продолжения пола.
func _floor_ahead() -> bool:
	_floor_probe.position.x = absf(_floor_probe.position.x) * signf(_brain.facing)
	# Луч обновляется в начале кадра, а мы только что его подвинули.
	_floor_probe.force_raycast_update()
	return _floor_probe.is_colliding()


## Переносит в [EnemyBrain] рост в стойках из правил здания. Считается в одном
## месте, чтобы порядок вызовов [method _ready] и [method apply_rules] ничего не
## решал — иначе настроенный до [method Node.add_child] агент терял бы числа.
func _refresh_brain() -> void:
	var rules := _building_rules()
	_brain.kneel_height = rules.agent_kneel_height
	_brain.prone_height = rules.agent_prone_height


## Правила, по которым живёт агент. Выпущенному уровнем их отдали, а
## поставленному руками — в тесте или в редакторе — достаются значения
## по умолчанию, те же, что у здания по умолчанию.
func _building_rules() -> BuildingRules:
	if _rules == null:
		_rules = BuildingRules.new()
	return _rules


## Скорость пули этого агента: по навыку здания, в тревоге на шаг быстрее (@463D).
func _bullet_speed() -> float:
	return Arcade.agent_bullet_speed(_skill, _alarmed)


## В кадре ли агент: в ROM дальности огня нет, этаж целиком на экране, и у нас
## достаёт тот, кого игрок видит (ADR-0027, решение 3а).
func _in_frame() -> bool:
	return _target.camera_view().has_point(WorldSpace.to_plane(global_position))


## Высота вылета пули по стойке: стоя, из приседа и лёжа — таблица ROM.
func _shot_height() -> float:
	match _brain.stance:
		EnemyBrain.Stance.KNEEL:
			return Proportions.SHOT_LOW
		EnemyBrain.Stance.PRONE:
			return Proportions.SHOT_PRONE
		_:
			return shot_height


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)


## Вид на этот кадр: поза, сторона и ход ходьбы. Устроено так же, как у Otto, —
## разница только в наборе поз: агент не приседает и не прыгает, зато ложится.
func _update_look(delta: float) -> void:
	_shooting = maxf(_shooting - delta, 0.0)
	_falling_over = maxf(_falling_over - delta, 0.0)
	if _walking:
		_walk_phase = ActorPose.advance(_walk_phase, delta)
	else:
		_walk_phase = 0.0

	_body.show_pose(_pose())
	_body.set_walk_phase(_walk_phase)
	_body.face(_brain.facing)


func _pose() -> String:
	return ActorPose.of_agent(
		_brain.is_dead(),
		_walking,
		_crushed,
		_falling_over > 0.0,
		_shooting > 0.0,
		_walk_phase,
		_brain.stance
	)


## Досчитывает время, которое тело лежит на полу, и убирает его.
func _rot(delta: float) -> void:
	_corpse_left -= delta
	if _corpse_left <= 0.0:
		queue_free()


func _fire() -> void:
	_shooting = SHOOT_POSE_TIME
	Sounds.play(Sounds.SHOT)
	var bullet := BULLET_SCENE.instantiate() as Bullet
	bullet.direction = _brain.facing
	bullet.speed = _bullet_speed()
	bullet.collision_mask = Bullet.FROM_ENEMY
	bullet.hit_target.connect(_on_bullet_hit)
	get_parent().add_child(bullet)
	bullet.global_position = (
		global_position + Vector3(_brain.facing * muzzle_offset, _shot_height(), 0.0)
	)
	_bullet = bullet


## Попадание своей пули. Очков за Otto никто не получает — он просто гибнет.
func _on_bullet_hit(target: Node3D) -> void:
	var victim := target as Otto
	if victim == null:
		return
	victim.kill()
