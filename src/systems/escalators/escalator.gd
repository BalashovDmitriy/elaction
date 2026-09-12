class_name Escalator
extends Node2D

## Эскалатор между двумя этажами.
##
## В оригинале на него не заходят по пути: надо встать на площадку у края и
## нажать «вверх» или «вниз» (ADR-0004, пункт 8). Пока везёт — управления нет,
## позицией Otto распоряжается эскалатор, а не физика.
##
## Узел ставится на верхнюю площадку, нижняя задаётся смещением в [method setup].

## Сколько секунд занимает поездка между площадками.
@export var travel_time: float = 1.1

var _passenger: Otto = null
var _from := Vector2.ZERO
var _to := Vector2.ZERO
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


## Ставит нижнюю площадку со смещением от верхней и протягивает между ними полотно.
func setup(descent: Vector2) -> void:
	_bottom_pad.position = descent
	_ramp.points = PackedVector2Array([Vector2.ZERO, descent])


func _try_board(pad: Area2D, target: Area2D, towards: float) -> bool:
	for body: Node2D in pad.get_overlapping_bodies():
		var rider := body as Otto
		if rider == null or not rider.is_grounded():
			continue
		var intent := rider.vertical_intent()
		if absf(intent) < Intent.PRESS or signf(intent) != towards:
			continue
		_passenger = rider
		_from = pad.global_position
		_to = target.global_position
		_progress = 0.0
		rider.board_escalator()
		return true
	return false


func _carry(delta: float) -> void:
	_progress = minf(_progress + delta / travel_time, 1.0)
	_passenger.global_position = _from.lerp(_to, _progress)
	if _progress < 1.0:
		return
	_passenger.leave_escalator()
	_passenger = null
