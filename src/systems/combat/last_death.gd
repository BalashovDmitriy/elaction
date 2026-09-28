class_name LastDeath
extends Node

## Последняя смерть Otto (ADR-0042, решение 5): мир замедляется, камера наезжает
## на Otto, он падает клипом смерти, и только потом — конец партии.
##
## До M24f меню конца выходило в тот же кадр, что и смерть: прыжок — пробел, а
## пробел жмёт «Заново», и игрок, давящий прыжок, перезапускал партию, не
## увидев, как погиб.
##
## Живёт по настоящим часам, а не по часам мира: мир замедлен, и сцена по ним
## растянулась бы втрое. Замедление — относительно прежнего темпа, как у сценки
## добивания: тесты гоняют мир ускоренным.

## Кончилась: пора показывать конец партии.
signal finished

## Во сколько раз замедлен мир.
const SLOW: float = 0.3
## За сколько камера наезжает, с настоящего времени.
const CLOSE_IN: float = 0.8
## Сколько длится вся сцена, с настоящего времени.
const DURATION: float = 1.6
## Насколько выше ступней середина крупного плана, м: лежащий Otto — у низа
## кадра, а не посередине.
const CLOSE_HEIGHT: float = 0.6

var _otto: Node3D = null
var _time: float = 0.0
var _time_scale_before: float = 1.0
var _slowed: bool = false


## Начинает сцену над [param otto]. Узел встаёт в [param parent] и уходит сам,
## когда сцена кончилась.
static func play(parent: Node, otto: Node3D) -> LastDeath:
	var scene := LastDeath.new()
	scene.name = "LastDeath"
	scene._otto = otto
	parent.add_child(scene)
	return scene


func _ready() -> void:
	# Идёт и под паузой: на паузе мир стоит, а сцена всё равно должна кончиться.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_time_scale_before = Engine.time_scale
	Engine.time_scale = _time_scale_before * SLOW
	_slowed = true


## Ведёт сцену на [param real_delta] секунд настоящего времени. Отдан тестам.
func advance(real_delta: float) -> void:
	if not _slowed:
		return
	_time += real_delta
	var camera := _camera()
	if camera != null and is_instance_valid(_otto):
		var at := _otto.global_position
		camera.close_up(smoothstep(0.0, CLOSE_IN, _time), Vector2(at.x, at.y + CLOSE_HEIGHT))
	if _time >= DURATION:
		_speed_up()
		finished.emit()
		queue_free()


func _process(delta: float) -> void:
	# Дельта кадра уже помножена на темп мира — делим обратно.
	advance(delta / maxf(Engine.time_scale, 0.001))


func _notification(what: int) -> void:
	# Сцену выбросили раньше конца — мир не должен остаться медленным.
	if what == NOTIFICATION_EXIT_TREE:
		_speed_up()


func _speed_up() -> void:
	if not _slowed:
		return
	Engine.time_scale = _time_scale_before
	_slowed = false


func _camera() -> SideCamera:
	var viewport := get_viewport()
	return viewport.get_camera_3d() as SideCamera if viewport != null else null
