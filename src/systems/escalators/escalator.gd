class_name Escalator
extends Node2D

## Эскалатор между двумя этажами.
##
## В оригинале на него не заходят по пути: надо встать на площадку у края и
## нажать «вверх» или «вниз» (ADR-0005, пункт 8). Пока везёт — управления нет,
## позицией Otto распоряжается эскалатор, а не физика.
##
## Узел ставится на верхнюю площадку, нижняя и точка перегиба задаются в
## [method setup]. Поездка идёт по тому же пути, который нарисован полотном, и
## начинается с того места, где пассажир стоял: иначе его дёргало бы к центру
## площадки, а полотно резало бы перекрытие мимо проёма (найдено авторевью M2).

## Сколько секунд занимает поездка между площадками.
@export var travel_time: float = 1.1

var _passenger: Otto = null
var _path: PackedVector2Array = PackedVector2Array()
var _progress: float = 0.0

@onready var _top_pad: Area2D = $TopPad
@onready var _bottom_pad: Area2D = $BottomPad
@onready var _ramp: Line2D = $Ramp


func _physics_process(delta: float) -> void:
	if _passenger != null:
		_carry(delta)
		return
	# Наверх зовут с нижней площадки, вниз — с верхней.
	if not _try_board(_bottom_pad, _top_pad, Intent.UP):
		_try_board(_top_pad, _bottom_pad, Intent.DOWN)


## Задаёт геометрию. [param descent] — смещение нижней площадки от верхней,
## [param via] — точка перегиба в проёме перекрытия: через неё идут и полотно,
## и сама поездка, поэтому пассажир проходит сквозь дыру, а не сквозь плиту.
func setup(descent: Vector2, via: Vector2) -> void:
	_bottom_pad.position = descent
	_ramp.points = PackedVector2Array([Vector2.ZERO, via, descent])
	# Полотно тянется тайлом вдоль линии: ступени идут ровным шагом при любой
	# длине пролёта, а растянутый на весь пролёт тайл шага бы не дал.
	_ramp.texture = EnvTextures.tile("escalator_belt")
	_ramp.texture_mode = Line2D.LINE_TEXTURE_TILE
	_ramp.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


## Везёт ли эскалатор кого-нибудь прямо сейчас.
func is_busy() -> bool:
	return _passenger != null


func _try_board(pad: Area2D, target: Area2D, towards: float) -> bool:
	for body: Node2D in pad.get_overlapping_bodies():
		var rider := body as Otto
		if rider == null or not rider.is_grounded():
			continue
		var intent := rider.vertical_intent()
		if absf(intent) < Intent.PRESS or signf(intent) != towards:
			continue

		_passenger = rider
		_path = _route_from(rider.global_position, target)
		_progress = 0.0
		rider.board_escalator()
		return true
	return false


## Путь поездки: от места, где пассажир стоял, через перегиб к дальней площадке.
##
## Перегиб берётся из полотна, поэтому едут ровно там, где нарисовано. Без
## [method setup] полотна нет — тогда путь прямой, лишь бы не падать по индексу.
func _route_from(start: Vector2, target: Area2D) -> PackedVector2Array:
	if _ramp.points.size() < 3:
		return PackedVector2Array([start, target.global_position])
	return PackedVector2Array([start, to_global(_ramp.points[1]), target.global_position])


func _carry(delta: float) -> void:
	_progress = minf(_progress + delta / travel_time, 1.0)
	_passenger.global_position = _point_at(_progress)
	if _progress < 1.0:
		return
	_passenger.leave_escalator()
	_passenger = null


## Точка на ломаной по доле пути: длина считается по самим отрезкам, поэтому
## на изломе скорость не прыгает.
func _point_at(ratio: float) -> Vector2:
	var total := 0.0
	for index in _path.size() - 1:
		total += _path[index].distance_to(_path[index + 1])
	if is_zero_approx(total):
		return _path[_path.size() - 1]

	var travelled := total * ratio
	for index in _path.size() - 1:
		var length := _path[index].distance_to(_path[index + 1])
		if travelled <= length or index == _path.size() - 2:
			var part := travelled / length if length > 0.0 else 1.0
			return _path[index].lerp(_path[index + 1], minf(part, 1.0))
		travelled -= length
	return _path[_path.size() - 1]
