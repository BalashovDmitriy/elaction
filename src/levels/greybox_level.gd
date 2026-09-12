class_name GreyboxLevel
extends Node2D

## Временный «серый ящик»: три этажа, шахта лифта, кабина.
##
## Геометрия описывается прямоугольниками и собирается в рантайме. Настоящие
## уровни на данных появятся в M5; до тех пор этого хватает, чтобы проверить
## движение, лифт и падение в шахту.

const SOLID_COLOR := Color(0.22, 0.24, 0.30)
const CAR_SCENE := preload("res://src/systems/elevators/elevator_car.tscn")

## Поверхности этажей сверху вниз. По ним же кабина выбирает остановки.
const FLOOR_SURFACES: Array[float] = [100.0, 220.0, 340.0]
const SLAB_HEIGHT: float = 20.0
const LEVEL_WIDTH: float = 1280.0
const LEVEL_HEIGHT: float = 360.0
const WALL_WIDTH: float = 16.0

## Проём шахты. Ширина совпадает с кабиной: кто встал на краю крыши и поехал
## вверх, тот окажется зажат между крышей и перекрытием (ADR-0004, пункт 7).
const SHAFT_LEFT: float = 560.0
const SHAFT_WIDTH: float = 40.0

@export var camera_bounds := Rect2(0, 0, LEVEL_WIDTH, LEVEL_HEIGHT)

@onready var otto: Otto = $Otto


func _ready() -> void:
	for rect in _building_solids():
		_build_solid(rect)
	_spawn_car()
	otto.apply_camera_bounds(camera_bounds)


## Геометрия здания: перекрытия с проёмом шахты и стены по краям уровня.
func _building_solids() -> Array[Rect2]:
	var rects: Array[Rect2] = [
		Rect2(0.0, 0.0, WALL_WIDTH, LEVEL_HEIGHT),
		Rect2(LEVEL_WIDTH - WALL_WIDTH, 0.0, WALL_WIDTH, LEVEL_HEIGHT),
	]
	var bottom := FLOOR_SURFACES.size() - 1
	var shaft_right := SHAFT_LEFT + SHAFT_WIDTH
	for index: int in FLOOR_SURFACES.size():
		var surface := FLOOR_SURFACES[index]
		if index == bottom:
			# Нижний этаж сплошной: это дно шахты, падать дальше некуда.
			rects.append(Rect2(0.0, surface, LEVEL_WIDTH, SLAB_HEIGHT))
			continue
		rects.append(Rect2(0.0, surface, SHAFT_LEFT, SLAB_HEIGHT))
		rects.append(Rect2(shaft_right, surface, LEVEL_WIDTH - shaft_right, SLAB_HEIGHT))
	return rects


func _spawn_car() -> void:
	var car := CAR_SCENE.instantiate() as ElevatorCar
	car.position.x = SHAFT_LEFT + SHAFT_WIDTH * 0.5
	add_child(car)
	# Кабина ждёт на верхнем этаже: оттуда Otto и начинает спуск.
	car.setup(PackedFloat32Array(FLOOR_SURFACES))


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
