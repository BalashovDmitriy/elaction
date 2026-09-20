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

const BULLET_SCENE := preload("res://src/systems/combat/bullet.tscn")
## Слой врагов в `project.godot`. Агент сходит с него, пока стоит в проёме.
const ENEMY_LAYER: int = 3
## Сколько агент падает, прежде чем лечь: смерть — две позы (ADR-0011, п. 12).
const FALLING_TIME: float = 0.25

## Сколько держится поза выстрела, с.
const SHOOT_POSE_TIME: float = 0.25

@export var walk_speed: float = 1.65
@export var gravity: float = 27.0
@export var max_fall_speed: float = 12.6

## Высота выстрела от ног: попадает в стоящего Otto и проходит над присевшим.
##
## Выше середины его роста нарочно (1.26 у Otto против 1.05 у пули). Пуля агента
## обязана делать три вещи разом: брать стоящего, проходить над присевшим и
## проходить над тем, кто стоит ниже этажа — в проёме шахты или в кабине,
## вставшей между этажами. На M13, когда Otto вырос в полтора раза, пуля
## перестала успевать за ним и начала снимать его в голову прямо в проёме.
@export var shot_height: float = 1.05
@export var muzzle_offset: float = 0.4

## Сколько тело лежит, прежде чем исчезнуть, с.
@export var corpse_time: float = 0.5

## Настройки решений, которые не зависят от здания: сколько агент выбирается из
## двери и какой разброс по высоте считается «на одной линии». Узел держит их у
## себя и отдаёт [EnemyBrain] — так же, как дверь отдаёт свои [DoorVisit].
##
## Остальные числа боя — дальность, пауза, замах, скорость пули и пороги
## уклонения — приходят из [BuildingRules] ([method apply_rules]): их растит
## сложность, и лежать в сцене одного агента они не могут (ADR-0016, пункт 5).
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
## Фаза ходьбы, поза выстрела и падения, признак раздавленного — всё как у Otto.
var _walk_phase: float = 0.0
var _walking: bool = false
var _shooting: float = 0.0
var _falling_over: float = 0.0
var _crushed: bool = false
## Насколько агент злее обычного: 1 — как в первом здании, больше — злее.
var _menace: float = 1.0

@onready var _body: FigureRig = $Body
@onready var _floor_probe: RayCast3D = $FloorProbe
@onready var _shape: CollisionShape3D = $Shape


func _ready() -> void:
	_brain.emerge_time = emerge_time
	_brain.same_line = same_line
	# Стоячий рост берётся у самой формы, а не записывается вторым числом:
	# разъехавшись, они дали бы агента, который уклоняется не своим телом.
	_brain.stand_height = (_shape.shape as BoxShape3D).size.y
	_refresh_brain()


func _physics_process(delta: float) -> void:
	if _brain.is_dead():
		# Тело доезжает до пола: убитый в прыжке не должен зависать в воздухе.
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
	var state := _brain.update(delta, to_target, sees_target, _incoming_height())
	_fit_shape()
	if _brain.fired():
		_fire()

	# Из проёма агент выходит шагом. EMERGING — это «выйти», а не «постоять»:
	# раньше он эти доли секунды стоял на коврике перед закрытой створкой, и
	# ровно это игрок и назвал «спавнится поверх двери» (ADR-0020).
	var stepping_out := state == EnemyBrain.State.EMERGING
	_shield(stepping_out)

	# Приседая и лёжа агент не ходит: уклонение — это замереть, а не идти
	# дальше пригнувшись.
	var walking := (state == EnemyBrain.State.WALK or stepping_out) and _brain.is_standing()
	if walking and is_on_floor() and _blocked_ahead():
		# Дальше пола нет или стена: агент остаётся на своём этаже (ADR-0006,
		# пункт 6). Видя Otto, он встаёт у края; потеряв — разворачивается и идёт
		# обратно: слепой агент патрулирует этаж, а не караулит проём (ADR-0023).
		if sees_target or stepping_out:
			walking = false
		else:
			_brain.turn_around()
	velocity.x = walk_speed * _brain.facing if walking else 0.0
	_apply_gravity(delta)
	move_and_slide()
	_hold_the_plane()
	_walking = walking
	_update_look(delta)


## Отдаёт агенту правила здания: из них он берёт все числа боя.
##
## Зовётся до [method Node.add_child] и после — порядок не решает ничего, как и
## у [method set_menace]: числа переносятся в [EnemyBrain] одним [method _refresh_brain].
func apply_rules(rules: BuildingRules) -> void:
	_rules = rules
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


## Куда агент смотрит: -1 влево, +1 вправо.
func facing() -> float:
	return _brain.facing


## Насколько агент злее обычного. Растёт от здания к зданию и по тревоге.
func set_menace(value: float) -> void:
	_menace = maxf(value, 0.1)
	_refresh_brain()


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
	if _target.is_hidden():
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
	var nearest := _building_rules().agent_dodge_sight
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


## Переносит в [EnemyBrain] все числа боя: и те, что приходят из правил здания,
## и те, что зависят от злости. Считается в одном месте, чтобы порядок вызовов
## [method _ready], [method apply_rules] и [method set_menace] ничего не решал —
## иначе настроенный до [method Node.add_child] агент терял бы половину чисел.
func _refresh_brain() -> void:
	var rules := _building_rules()
	# Дальность не растёт со злостью: в оригинале сложность добавляют
	# скорострельность, скорость пули и уклонение, а дальности среди них нет
	# (ADR-0016, пункт 1). Пока она росла, к поздним зданиям агент простреливал
	# этаж насквозь, и подойти к нему было нечем.
	_brain.fire_range = rules.agent_fire_range
	_brain.fire_cooldown = rules.agent_fire_cooldown / _menace
	_brain.aim_time = rules.agent_aim_time
	_brain.kneel_height = rules.agent_kneel_height
	_brain.prone_height = rules.agent_prone_height
	# Уклоняться агент учится не сразу: это третья ось сложности оригинала,
	# и в первых зданиях его берут стоящим.
	_brain.can_kneel = _menace >= rules.agent_kneels_from_menace
	_brain.can_go_prone = _menace >= rules.agent_goes_prone_from_menace


## Правила, по которым живёт агент. Выпущенному уровнем их отдали, а
## поставленному руками — в тесте или в редакторе — достаются значения
## по умолчанию, те же, что у здания по умолчанию.
func _building_rules() -> BuildingRules:
	if _rules == null:
		_rules = BuildingRules.new()
	return _rules


## Скорость пули этого агента: растёт со злостью, как в оригинале. Отбирает
## время на реакцию, но не саму возможность подойти.
func _bullet_speed() -> float:
	return _building_rules().agent_bullet_speed * _menace


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
		global_position + Vector3(_brain.facing * muzzle_offset, shot_height, 0.0)
	)


## Попадание своей пули. Очков за Otto никто не получает — он просто гибнет.
func _on_bullet_hit(target: Node3D) -> void:
	var victim := target as Otto
	if victim == null:
		return
	victim.kill()
