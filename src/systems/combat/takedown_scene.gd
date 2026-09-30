class_name TakedownScene
extends Node

## Режиссёр сценки добивания (ADR-0040, с M24i — ADR-0050).
##
## Ставит агента вплотную к Otto, выключает обоим управление — ввод Otto и мозг
## агента — и ведёт двоих по таблице поз [Takedown.Scene]. Мир вокруг на время
## сценки замедлен, а сценка идёт в своём темпе: режиссёр считает время
## поделённым на замедление и так же ускоряет оба рига. На ключевом кадре агент
## погибает, Otto получает очки.
##
## С M24i сценка поставлена, а не проиграна ровно. Замедление неровное: быстрый
## заход, к удару мир почти встаёт, на самом ударе — стоп-кадр на доли секунды,
## потом разгон обратно. На ударе камера толкается и кренится, вспышка у лиц,
## музыка проваливается, удар звучит гулко, у агента слетает шляпа, и падает он
## рэгдоллом, отброшенный от Otto, а не готовой позой. Всю сценку фон темнее и
## бесцветнее, а музыка глуше. Ракурс не меняется: вид остаётся боковым.
##
## Otto в сценке уязвим (решение пользователя): пуля другого агента, долетевшая
## в замедлении, убивает его, и сценка обрывается. Агент, до ключевого кадра не
## доживший до смерти, тогда возвращается в бой.

## Во сколько раз замедляется мир к удару.
const SLOW: float = 0.3
## Замедление на заходе — мягче, чем к удару: сценка начинается быстро.
const APPROACH: float = 0.6
## Стоп-кадр на ударе: сколько длится, с настоящего времени, и во сколько раз
## замедлен мир — почти стоит, но пули и огни не замирают намертво.
const FREEZE_TIME: float = 0.14
const FREEZE_SCALE: float = 0.03
## Крупный план: за сколько камера наезжает, с (времени сценки), и сколько
## держит крупно после ключевого кадра — до отъезда к концу сценки.
const CLOSE_IN: float = 0.25
const CLOSE_HOLD: float = 0.12
## На какой высоте над полом середина крупного плана, м: грудь стоящих.
const CLOSE_HEIGHT: float = 1.0
## На сколько фигура Otto отходит от камеры в сценке сзади, м: тела стоят
## вплотную в одной плоскости, и агент должен быть спереди, а руки Otto — за ним.
const BEHIND_DEPTH: float = 0.14
## На какой высоте щуп ищет стену перед местом агента, м: на уровне колена — ниже
## любого проёма и выше порога.
const WALL_PROBE: float = 0.4
## За сколько агент встаёт на своё место перед Otto, с (своего времени сценки).
const ALIGN_TIME: float = 0.12
## Вспышка на ударе: лепит лица двоих. Цвет, яркость, дальность, м, насколько
## ближе к камере, м, и за сколько гаснет, с настоящего времени.
const FLASH_COLOR := Color(1.0, 0.9, 0.75)
const FLASH_ENERGY: float = 6.0
const FLASH_RANGE: float = 2.4
const FLASH_OUT: float = 0.45
const FLASH_TIME: float = 0.32
## Фон на время сценки: насыщенность и яркость кадра, и за сколько он к ним
## приходит, с настоящего времени. Уходит сразу, на любом выходе из сценки
## ([method _restore_grade]).
const GRADE_SATURATION: float = 0.35
const GRADE_BRIGHTNESS: float = 0.8
const GRADE_TIME: float = 0.2
## Удар — поверх себя же на тон ниже и громче: гулко.
const BOOM_PITCH: float = 0.55
const BOOM_DB: float = 3.0
## Музыка проваливается на ударе, с.
const DUCK_TIME: float = 0.7
## Причина глушения музыки на время сценки ([method Sounds.muffle_music]).
const MUFFLE := "takedown"
## Отброс трупа от Otto: сила вдоль взгляда Otto — доли толчка пули
## ([constant Corpse.HIT_META]).
const HIT_PUSH: float = 1.4
## Шляпа: масса, кг, толчок, м/с, — от Otto и вверх, — и закрутка, рад/с.
const HAT_MASS: float = 0.15
const HAT_PUSH := Vector2(1.6, 2.4)
const HAT_SPIN: float = 9.0

var _otto: Otto = null
var _agent: Enemy = null
var _scene: Takedown.Scene = null
var _facing: float = 1.0
var _time: float = 0.0
var _killed: bool = false
## Масштаб времени до сценки: тесты гоняют мир ускоренным, и сценка его
## не сбрасывает, а замедляет относительно него.
var _time_scale_before: float = 1.0
var _slowed: bool = false
## Во сколько раз замедлен мир прямо сейчас: по кривой сценки.
var _world: float = APPROACH
## Во сколько раз был замедлен мир в начале этого кадра, и какого. Масштаб
## времени движок читает раз на кадр: шаг физики, идущий в кадре после того,
## как сценка сменила замедление, приходит ещё со старым. Поделённый на новое,
## второй шаг кадра удара шёл бы вдесятеро длиннее и проскакивал стоп-кадр
## целиком, а исход сценки зависел бы от числа шагов в кадре (авторевью M24i).
var _frame_world: float = 1.0
var _frame_number: int = -1
## Сколько ещё идёт стоп-кадр, с настоящего времени.
var _freeze_left: float = 0.0
var _from_x: float = 0.0
var _to_x: float = 0.0
var _flash: OmniLight3D = null
var _flash_ticks: int = 0
## Кадр сцены и его прежние насыщенность и яркость: сценка их возвращает.
var _environment: Environment = null
var _saturation_before: float = 1.0
var _brightness_before: float = 1.0
var _grade_ticks: int = 0


## Начинает сценку [param scene] над агентом [param agent]. Узел встаёт в дерево
## рядом с Otto и уходит из него сам, когда сценка кончилась или оборвалась.
static func play(otto: Otto, agent: Enemy, scene: Takedown.Scene) -> TakedownScene:
	var director := TakedownScene.new()
	director.name = "Takedown"
	director._otto = otto
	director._agent = agent
	director._scene = scene
	director._facing = otto.facing()
	otto.get_parent().add_child(director)
	return director


## Какая сценка идёт. Тестам.
func scene() -> Takedown.Scene:
	return _scene


## Погиб ли уже агент.
func killed() -> bool:
	return _killed


## Идёт ли стоп-кадр удара. Тестам.
func is_frozen() -> bool:
	return _freeze_left > 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_otto.takedown = self
	_agent.held_facing = -_facing if _scene.faces_otto else _facing
	_agent.held = true
	_from_x = _agent.global_position.x
	_to_x = _free_spot(_otto.global_position.x + _facing * _scene.offset)
	_otto.died.connect(_abort)
	if _scene.side == Takedown.Side.BACK:
		_otto.figure.position.z = -BEHIND_DEPTH
	# Рука, наведённая до сценки — агент замахивался, Otto только что стрелял, —
	# висела бы вскинутой поверх её клипов: вид в сценке ни тот ни другой не
	# обновляет (ADR-0043, решение 16).
	_otto.figure.aim_height = NAN
	_agent.figure.aim_height = NAN
	_grade_in()
	Sounds.muffle_music(MUFFLE, true)
	# Сценка начинается посреди шага физики Otto: до конца кадра мир идёт ещё
	# без замедления.
	_frame_number = Engine.get_process_frames()
	_frame_world = 1.0
	_slow_down()
	_show(0.0)


## Ведёт сценку на [param delta] секунд мира. Отдан наружу тестам.
func advance(delta: float) -> void:
	if _scene == null:
		return
	# Агента или Otto выбросили посреди сценки — ушёл за дверь, здание сменилось,
	# тест разобрал сцену: сценка снимается, а не обращается к освобождённому.
	if not is_instance_valid(_agent) or not is_instance_valid(_otto):
		_abort()
		return
	var frame := Engine.get_process_frames()
	if frame != _frame_number:
		_frame_number = frame
		_frame_world = _world if _slowed else 1.0
	var real := delta / _frame_world
	_fade_effects()
	if _freeze_left > 0.0:
		_freeze_left -= real
		if _freeze_left <= 0.0:
			_apply_world()
		return
	_time += real
	if not _killed:
		var align := clampf(_time / ALIGN_TIME, 0.0, 1.0)
		var at := _agent.global_position
		at.x = lerpf(_from_x, _to_x, smoothstep(0.0, 1.0, align))
		_agent.global_position = at
	_show(_time)
	_frame(_time)
	if not _killed and _time >= _scene.kill_at:
		_kill()
	if _time >= _scene.duration:
		_finish()
		return
	_apply_world()


## Шагами физики, а не кадрами: смерть агента, очки и конец сценки решают исход
## партии, и по настенным часам прогон бота переставал бы повторяться
## (`docs/testing.md`, правило из M18b).
func _physics_process(delta: float) -> void:
	advance(delta)


func _notification(what: int) -> void:
	# Замедление — это время мира, а меню паузы живёт на том же движке: на паузе
	# оно шло бы втрое медленнее. Пауза снимает замедление, продолжение
	# возвращает.
	match what:
		NOTIFICATION_PAUSED:
			_speed_up()
		NOTIFICATION_UNPAUSED:
			if _scene != null:
				_slow_down()
		NOTIFICATION_EXIT_TREE:
			# Здание выбросили посреди сценки: мир не должен остаться медленным, а
			# кадр — бесцветным.
			_speed_up()
			_restore_grade()
			Sounds.muffle_music(MUFFLE, false)


## Позы по времени. Погибший агент — уже рэгдолл: его ведёт физика, не таблица.
func _show(time: float) -> void:
	_otto.figure.show_pose(Takedown.Scene.pose_at(_scene.otto, time))
	if not _killed:
		_agent.figure.show_pose(Takedown.Scene.pose_at(_scene.agent, time))


## Где агенту встать перед Otto: на [param wanted], если до него нет стены, или
## у самой стены. Режиссёр ставит агента руками, мимо физики, и без проверки
## прижатый к стене агент уходил бы в неё на четверть метра (авторевью M24d).
func _free_spot(wanted: float) -> float:
	var space := _otto.get_world_3d().direct_space_state
	var height := Vector3(0.0, WALL_PROBE, 0.0)
	var from := _otto.global_position + height
	var to := Vector3(wanted, from.y, from.z)
	var reach := to + Vector3(signf(wanted - from.x) * Proportions.BODY_WIDTH * 0.5, 0.0, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, reach, 1)
	query.exclude = [_otto.get_rid(), _agent.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return wanted
	var wall: Vector3 = hit["position"]
	return wall.x - signf(wanted - from.x) * Proportions.BODY_WIDTH * 0.5


## Крупный план по ходу сценки: наезд, крупно до ключевого кадра, отъезд.
func _frame(time: float) -> void:
	var camera := _camera()
	if camera == null:
		return
	var closing := smoothstep(0.0, CLOSE_IN, time)
	var leaving := 1.0 - smoothstep(_scene.kill_at + CLOSE_HOLD, _scene.duration, time)
	var middle := (_otto.global_position + _agent.global_position) * 0.5
	camera.close_up(minf(closing, leaving), Vector2(middle.x, middle.y + CLOSE_HEIGHT))


func _camera() -> SideCamera:
	var viewport := get_viewport()
	return viewport.get_camera_3d() as SideCamera if viewport != null else null


## Удар: агент погибает и падает рэгдоллом от Otto, мир встаёт стоп-кадром,
## камера толкается, вспышка, провал музыки, гулкий удар, слетает шляпа.
func _kill() -> void:
	_killed = true
	_freeze_left = FREEZE_TIME
	var camera := _camera()
	if camera != null:
		camera.kick(1.0)
	_flash_at_the_faces()
	Sounds.duck_music(DUCK_TIME)
	# Агента уже убило посреди сценки — лампой, кабиной: очки за него взяты там.
	# Тело и его падает на ударе: поз ему сценка больше не ставит, а держать —
	# значит оставить его стоять замершим до конца сценки.
	if _agent.is_dead():
		_agent.held = false
		return
	var score := Takedown.score(_scene.side, _agent.is_in_the_dark())
	_knock_the_hat()
	# Отброс — от Otto, туда, куда он смотрит, и в голову: тело валится, а не
	# оседает на месте.
	_agent.set_meta(Corpse.HIT_META, _facing * HIT_PUSH)
	_agent.set_meta(Corpse.HIT_POINT, _head_of(_agent))
	_agent.kill(false, _scene.corpse)
	_agent.held = false
	GameState.instance().add_score(score)
	Sounds.play(Sounds.BLOW)
	Sounds.play_tuned(Sounds.BLOW, BOOM_PITCH, BOOM_DB)
	_apply_world()


## Где голова актёра, координаты сцены: у кости головы, а без неё — на росте.
static func _head_of(actor: Node3D) -> Vector3:
	var figure := actor.get(&"figure") as FigureRig
	var skeleton := figure.skeleton() if figure != null else null
	if skeleton != null:
		var bone := skeleton.find_bone(FigureRig.HEAD)
		if bone >= 0:
			return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
	return actor.global_position + Vector3(0.0, Proportions.BODY * 0.9, 0.0)


## Вспышка у лиц двоих: тёплая, ближе к камере, гаснет за [constant
## FLASH_TIME] настоящего времени.
func _flash_at_the_faces() -> void:
	if _flash == null:
		_flash = OmniLight3D.new()
		_flash.name = "TakedownFlash"
		_flash.light_color = FLASH_COLOR
		_flash.omni_range = FLASH_RANGE
		_flash.shadow_enabled = false
		_otto.get_parent().add_child(_flash)
	var middle := (_head_of(_otto) + _head_of(_agent)) * 0.5
	_flash.global_position = middle + Vector3(0.0, 0.0, FLASH_OUT)
	_flash.light_energy = FLASH_ENERGY
	_flash_ticks = Time.get_ticks_msec()


## Шляпа слетает с агента: прячется на нём, а её копия улетает телом — от Otto,
## вверх и с закруткой — и остаётся лежать, как труп.
func _knock_the_hat() -> void:
	var figure := _agent.figure
	var hat := figure.find_child("hat", true, false) as MeshInstance3D
	var skeleton := figure.skeleton()
	if hat == null or not hat.visible or skeleton == null:
		return
	var bone := skeleton.find_bone(FigureRig.HEAD)
	if bone < 0:
		return
	hat.visible = false
	# Меш шляпы — в позе покоя скелета: на голову его ставит поза головы
	# относительно её покоя.
	var placed := (
		skeleton.global_transform
		* skeleton.get_bone_global_pose(bone)
		* skeleton.get_bone_global_rest(bone).affine_inverse()
	)
	var box := hat.mesh.get_aabb()
	var body := RigidBody3D.new()
	body.name = "Hat"
	body.mass = HAT_MASS
	body.collision_layer = 0
	body.collision_mask = 1
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = box.get_center()
	var copy := MeshInstance3D.new()
	copy.mesh = hat.mesh
	copy.layers = hat.layers
	for index: int in hat.get_surface_override_material_count():
		copy.set_surface_override_material(index, hat.get_surface_override_material(index))
	body.add_child(copy)
	var shape := CollisionShape3D.new()
	var cube := BoxShape3D.new()
	cube.size = box.size * 0.8
	shape.shape = cube
	shape.position = box.get_center()
	body.add_child(shape)
	_agent.get_parent().add_child(body)
	body.global_transform = placed
	body.apply_central_impulse(Vector3(_facing * HAT_PUSH.x, HAT_PUSH.y, 0.0) * HAT_MASS)
	body.angular_velocity = Vector3(0.0, 0.0, -_facing * HAT_SPIN)


## Вспышка и цвет кадра гаснут по настоящему времени: мир на ударе почти стоит.
func _fade_effects() -> void:
	if _flash != null:
		var age := (Time.get_ticks_msec() - _flash_ticks) / 1000.0
		_flash.light_energy = FLASH_ENERGY * maxf(1.0 - age / FLASH_TIME, 0.0)
	_grade_step()


## Фон темнеет и теряет цвет: насыщенность и яркость кадра — к сценке.
func _grade_in() -> void:
	var viewport := get_viewport()
	var world := viewport.find_world_3d() if viewport != null else null
	_environment = world.environment if world != null else null
	if _environment == null:
		return
	_saturation_before = _environment.adjustment_saturation
	_brightness_before = _environment.adjustment_brightness
	_grade_ticks = Time.get_ticks_msec()
	_grade_step()


func _grade_step() -> void:
	if _environment == null:
		return
	var share := clampf((Time.get_ticks_msec() - _grade_ticks) / 1000.0 / GRADE_TIME, 0.0, 1.0)
	_environment.adjustment_enabled = true
	_environment.adjustment_saturation = lerpf(_saturation_before, GRADE_SATURATION, share)
	_environment.adjustment_brightness = lerpf(_brightness_before, GRADE_BRIGHTNESS, share)


## Кадр — как до сценки: и на конце, и на обрыве.
func _restore_grade() -> void:
	if _environment == null:
		return
	_environment.adjustment_saturation = _saturation_before
	_environment.adjustment_brightness = _brightness_before
	_environment = null


func _finish() -> void:
	var otto := _otto
	var agent := _agent
	_release()
	otto.takedown = null
	if is_instance_valid(agent):
		agent.held = false
	queue_free()


## Otto погиб посреди сценки: агент, ещё живой, возвращается в бой.
func _abort() -> void:
	var agent := _agent
	var otto := _otto
	_release()
	if is_instance_valid(otto):
		otto.takedown = null
	if is_instance_valid(agent):
		agent.held = false
	queue_free()


func _release() -> void:
	_freeze_left = 0.0
	_speed_up()
	_restore_grade()
	Sounds.muffle_music(MUFFLE, false)
	if _flash != null and is_instance_valid(_flash):
		_flash.queue_free()
	_flash = null
	if is_instance_valid(_otto):
		_otto.figure.position.z = 0.0
	var camera := _camera()
	if camera != null:
		camera.close_up(0.0, Vector2.ZERO)
	if is_instance_valid(_otto) and _otto.died.is_connected(_abort):
		_otto.died.disconnect(_abort)
	_scene = null


## Замедление по кривой сценки: быстрый заход — [constant APPROACH], к удару —
## [constant SLOW], на ударе — стоп-кадр, после — разгон к обычному ходу.
func _world_now() -> float:
	if _freeze_left > 0.0:
		return FREEZE_SCALE
	if _scene == null:
		return 1.0
	if not _killed:
		return lerpf(APPROACH, SLOW, smoothstep(0.0, _scene.kill_at, _time))
	return lerpf(SLOW, 1.0, smoothstep(_scene.kill_at, _scene.duration, _time))


## Ставит миру и ригам скорость по кривой. Риги в стоп-кадре стоят.
func _apply_world() -> void:
	if not _slowed:
		return
	_world = _world_now()
	Engine.time_scale = _time_scale_before * _world
	_set_rig_speed(0.0 if _freeze_left > 0.0 else 1.0 / _world)


func _slow_down() -> void:
	if _slowed:
		return
	_time_scale_before = Engine.time_scale
	_slowed = true
	_apply_world()


func _speed_up() -> void:
	if not _slowed:
		return
	Engine.time_scale = _time_scale_before
	_slowed = false
	_world = 1.0
	_set_rig_speed(1.0)


func _set_rig_speed(speed: float) -> void:
	if is_instance_valid(_otto):
		_otto.figure.speed = speed
	if is_instance_valid(_agent) and not _agent.is_dead():
		_agent.figure.speed = speed
