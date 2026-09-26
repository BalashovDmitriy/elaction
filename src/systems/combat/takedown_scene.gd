class_name TakedownScene
extends Node

## Режиссёр сценки добивания (ADR-0040).
##
## Ставит агента вплотную к Otto, выключает обоим управление — ввод Otto и мозг
## агента — и ведёт двоих по таблице поз [Takedown.Scene]. Мир вокруг на время
## сценки замедлен, а сценка идёт в своём темпе: режиссёр считает время
## поделённым на замедление и так же ускоряет оба рига. На ключевом кадре агент
## погибает, Otto получает очки.
##
## Otto в сценке уязвим (решение пользователя): пуля другого агента, долетевшая
## в замедлении, убивает его, и сценка обрывается. Агент, до ключевого кадра не
## доживший до смерти, тогда возвращается в бой.

## Во сколько раз замедляется мир на время сценки.
const SLOW: float = 0.3
## Крупный план: за сколько камера наезжает, с (времени сценки), и сколько
## держит крупно после ключевого кадра — до отъезда к концу сценки.
const CLOSE_IN: float = 0.25
const CLOSE_HOLD: float = 0.12
## На какой высоте над полом середина крупного плана, м: грудь стоящих.
const CLOSE_HEIGHT: float = 1.0
## На сколько фигура Otto отходит от камеры в сценке сзади, м: тела стоят
## вплотную в одной плоскости, и агент должен быть спереди, а руки Otto — за ним.
const BEHIND_DEPTH: float = 0.14
## За сколько агент встаёт на своё место перед Otto, с (своего времени сценки).
const ALIGN_TIME: float = 0.12

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
var _from_x: float = 0.0
var _to_x: float = 0.0


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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_otto.takedown = self
	_agent.held_facing = -_facing if _scene.faces_otto else _facing
	_agent.held = true
	_from_x = _agent.global_position.x
	_to_x = _otto.global_position.x + _facing * _scene.offset
	_otto.died.connect(_abort)
	if _scene.side == Takedown.Side.BACK:
		_otto.figure.position.z = -BEHIND_DEPTH
	_slow_down()
	_show(0.0)


## Ведёт сценку на [param delta] секунд мира. Отдан наружу тестам: длина кадра
## в headless-прогоне — «сколько получится».
func advance(delta: float) -> void:
	if _scene == null:
		return
	_time += delta / SLOW if _slowed else delta
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


func _process(delta: float) -> void:
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
			# Здание выбросили посреди сценки: мир не должен остаться медленным.
			_speed_up()


func _show(time: float) -> void:
	_otto.figure.show_pose(Takedown.Scene.pose_at(_scene.otto, time))
	_agent.figure.show_pose(Takedown.Scene.pose_at(_scene.agent, time))


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


func _kill() -> void:
	_killed = true
	var score := Takedown.score(_scene.side, _agent.is_in_the_dark())
	_agent.kill(false, _scene.corpse)
	GameState.instance().add_score(score)
	Sounds.play(Sounds.BLOW)


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
	otto.takedown = null
	if is_instance_valid(agent):
		agent.held = false
	queue_free()


func _release() -> void:
	_speed_up()
	if is_instance_valid(_otto):
		_otto.figure.position.z = 0.0
	var camera := _camera()
	if camera != null:
		camera.close_up(0.0, Vector2.ZERO)
	if _otto != null and _otto.died.is_connected(_abort):
		_otto.died.disconnect(_abort)
	_scene = null


func _slow_down() -> void:
	if _slowed:
		return
	_time_scale_before = Engine.time_scale
	Engine.time_scale = _time_scale_before * SLOW
	_slowed = true
	_set_rig_speed(1.0 / SLOW)


func _speed_up() -> void:
	if not _slowed:
		return
	Engine.time_scale = _time_scale_before
	_slowed = false
	_set_rig_speed(1.0)


func _set_rig_speed(speed: float) -> void:
	if is_instance_valid(_otto):
		_otto.figure.speed = speed
	if is_instance_valid(_agent):
		_agent.figure.speed = speed
