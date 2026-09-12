class_name Door
extends Node2D

## Дверь этажа.
##
## Красная прячет документ, обычная — засаду: врагов из неё будет выпускать M4.
## Вход с коврика по нажатию «вверх», внутри Otto пересиживает до пяти секунд,
## после чего дверь выставляет его сама. Правила — в ADR-0005, пункты 2-4.

## Документ взят, дверь перестала быть красной.
signal document_taken

enum State { CLOSED, OPENING, OPEN }

const CLOSED_COLOR := Color(0.45, 0.42, 0.40)
const DOCUMENT_COLOR := Color(0.72, 0.25, 0.25)
const OPENING_COLOR := Color(0.62, 0.58, 0.54)
const OPEN_COLOR := Color(0.09, 0.09, 0.12)

## Сколько Otto может пересидеть внутри, с. Ровно ли пять — ждёт сверки в MAME.
@export var hide_time: float = 5.0

## Сколько открывается створка, с.
@export var open_time: float = 0.25

## Красная дверь: за ней документ.
@export var has_document: bool = false

var state: State = State.CLOSED

var _guest: Otto = null
var _inside_left: float = 0.0
## Отпустил ли гость направление после входа. Иначе тот же зажатый «влево»,
## которым он пришёл к двери, вытолкнул бы его обратно в первый же кадр.
var _exit_armed: bool = false
var _opening_left: float = 0.0

@onready var _mat: Area2D = $Mat
@onready var _panel: ColorRect = $Panel


func _ready() -> void:
	_refresh_look()


func _physics_process(delta: float) -> void:
	if _guest == null:
		_try_admit()
		return

	if state == State.OPENING:
		_opening_left -= delta
		if _opening_left <= 0.0:
			_inside_left = hide_time
			_set_state(State.OPEN)
		return

	if state == State.OPEN:
		_inside_left -= delta
		# Наружу просятся нажатием в сторону — в оригинале в сторону ручки.
		var pressed := absf(_guest.horizontal_intent()) >= Intent.PRESS
		if not pressed:
			_exit_armed = true
		if _inside_left <= 0.0 or (pressed and _exit_armed):
			_release()


## Осталась ли за дверью добыча. По этому признаку выбирают, куда вернуть Otto.
func is_pending() -> bool:
	return has_document


## Точка, где Otto стоит перед дверью: сюда же его возвращают за документом.
func mat_position() -> Vector2:
	return _mat.global_position


func _try_admit() -> void:
	for body: Node2D in _mat.get_overlapping_bodies():
		var visitor := body as Otto
		if visitor == null or not visitor.is_grounded():
			continue
		if visitor.vertical_intent() > -Intent.PRESS:
			continue
		_admit(visitor)
		return


func _admit(visitor: Otto) -> void:
	_guest = visitor
	visitor.global_position = _mat.global_position
	visitor.enter_door()
	_opening_left = open_time
	_exit_armed = false
	_set_state(State.OPENING)

	if not has_document:
		return
	# Документ достаётся за вход, и дверь сразу перестаёт быть красной.
	has_document = false
	document_taken.emit()


func _release() -> void:
	_guest.global_position = _mat.global_position
	_guest.leave_door()
	_guest = null
	_set_state(State.CLOSED)


func _set_state(value: State) -> void:
	state = value
	_refresh_look()


func _refresh_look() -> void:
	if state == State.OPEN:
		_panel.color = OPEN_COLOR
	elif state == State.OPENING:
		_panel.color = OPENING_COLOR
	elif has_document:
		_panel.color = DOCUMENT_COLOR
	else:
		_panel.color = CLOSED_COLOR
