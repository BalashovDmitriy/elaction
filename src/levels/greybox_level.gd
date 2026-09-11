class_name GreyboxLevel
extends Node2D

## Временный «серый ящик» для M1.
##
## Геометрия описывается прямоугольниками и собирается в рантайме. Настоящие
## уровни на данных появятся в M5; до тех пор этого хватает, чтобы проверить
## ходьбу, приседание, прыжок и работу камеры.

const SOLID_COLOR := Color(0.22, 0.24, 0.30)

@export var solids: Array[Rect2] = [
	Rect2(0, 0, 1280, 16),
	Rect2(0, 320, 1280, 40),
	Rect2(0, 0, 16, 360),
	Rect2(1264, 0, 16, 360),
	Rect2(300, 250, 120, 12),
	Rect2(520, 190, 120, 12),
	Rect2(800, 250, 160, 12),
]
@export var camera_bounds := Rect2(0, 0, 1280, 360)

@onready var otto: Otto = $Otto


func _ready() -> void:
	for rect in solids:
		_build_solid(rect)
	otto.apply_camera_bounds(camera_bounds)


func _build_solid(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.position = rect.position + rect.size * 0.5
	# Тела добавляются в дерево после Otto, то есть рисовались бы поверх него.
	# Геометрия всегда за актёрами, но перед фоном (у фона z_index = -10).
	body.z_index = -1

	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)

	var visual := ColorRect.new()
	visual.color = SOLID_COLOR
	visual.size = rect.size
	visual.position = -rect.size * 0.5
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(visual)

	add_child(body)
