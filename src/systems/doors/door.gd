class_name Door
extends Node2D

## Дверь этажа.
##
## Красная прячет документ, обычная — засаду: врагов из неё будет выпускать M4.
## Решение о том, кого впустить и когда выпустить, принимает [DoorVisit]; узел
## отвечает за коврик, вид и выдачу документа.

## Документ взят, дверь перестала быть красной.
signal document_taken

## Ассеты створки: состояние двери — это не оттенок одного прямоугольника,
## а разная картинка (ADR-0011).
const CLOSED_ASSET := "door"
const DOCUMENT_ASSET := "door_red"
const OPENING_ASSET := "door_ajar"
const OPEN_ASSET := "door_open"

## Сколько Otto может пересидеть внутри, с.
@export var hide_time: float = 5.0

## Сколько открывается створка, с.
@export var open_time: float = 0.25

## Красная дверь: за ней документ.
@export var has_document: bool = false

var _visit := DoorVisit.new()
var _guest: Otto = null

@onready var _mat: Area2D = $Mat
@onready var _panel: TextureRect = $Panel
@onready var _mat_visual: TextureRect = $MatVisual


func _ready() -> void:
	_visit.hide_time = hide_time
	_visit.open_time = open_time
	_mat_visual.texture = SpriteTextures.tile("door_mat")
	_refresh_look()


func _physics_process(delta: float) -> void:
	if _guest == null:
		_look_for_visitor()
		return

	if _visit.tick(delta, _guest.horizontal_intent()):
		_release()
	else:
		_refresh_look()


## Осталась ли за дверью добыча. По этому признаку выбирают, куда вернуть Otto.
func is_pending() -> bool:
	return has_document


## Точка, где Otto стоит перед дверью: сюда же его возвращают за документом.
func mat_position() -> Vector2:
	return _mat.global_position


func _look_for_visitor() -> void:
	for body: Node2D in _mat.get_overlapping_bodies():
		var visitor := body as Otto
		if visitor == null:
			continue
		if not _visit.knock(visitor.is_grounded(), visitor.vertical_intent()):
			continue
		_admit(visitor)
		return


func _admit(visitor: Otto) -> void:
	_guest = visitor
	visitor.global_position = _mat.global_position
	visitor.enter_door()
	_visit.admit()
	_refresh_look()

	if not has_document:
		return
	# Документ достаётся за вход, и дверь сразу перестаёт быть красной.
	has_document = false
	document_taken.emit()


func _release() -> void:
	_guest.global_position = _mat.global_position
	_guest.leave_door()
	_guest = null
	_visit.release()
	_refresh_look()


func _refresh_look() -> void:
	_panel.texture = SpriteTextures.tile(_look())


func _look() -> String:
	if _visit.phase == DoorVisit.Phase.OPEN:
		return OPEN_ASSET
	if _visit.phase == DoorVisit.Phase.OPENING:
		return OPENING_ASSET
	return DOCUMENT_ASSET if has_document else CLOSED_ASSET
