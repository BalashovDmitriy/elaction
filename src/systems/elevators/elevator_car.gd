class_name ElevatorCar
extends AnimatableBody2D

## Кабина лифта.
##
## Решение о движении принимает [ElevatorMotion]; узел только переносит его в
## координату и раздаёт события. Кабина слушается Otto, пока он внутри, и ездит
## сама, когда пуста (ADR-0004, пункты 1 и 4).
##
## Стоящего на крыше переносит физика: [member AnimatableBody2D.sync_to_physics].
## Управлять кабиной с крыши нельзя — в оригинале так же.

## Кабина совпала с этажом и из неё можно выйти.
signal floor_reached(index: int)

@export var speed: float = 60.0
@export var floor_pause: float = 1.5
## Встаёт ли кабина между этажами. Сверкой не подтверждено — см. ADR-0004.
@export var stops_between_floors: bool = true

var _motion := ElevatorMotion.new()
var _occupant: PhysicsBody2D = null
var _command: float = 0.0
var _aligned_floor: int = -1

@onready var _interior: Area2D = $Interior
@onready var _crush_zone: Area2D = $CrushZone


func _ready() -> void:
	_interior.body_entered.connect(_on_body_entered)
	_interior.body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	var occupied := _occupant != null
	position.y = _motion.update(delta, _command if occupied else 0.0, occupied)

	var reached := _motion.aligned_floor()
	if reached != _aligned_floor:
		_aligned_floor = reached
		if reached >= 0:
			floor_reached.emit(reached)

	_crush_those_underneath()


## Задаёт шахту: координаты этажей-остановок и этаж, с которого кабина начинает.
func setup(stops: PackedFloat32Array, start_floor: int = 0) -> void:
	_motion.speed = speed
	_motion.floor_pause = floor_pause
	_motion.stops_between_floors = stops_between_floors
	_motion.setup(stops, start_floor)
	position.y = _motion.position
	_aligned_floor = _motion.aligned_floor()


## Задержка отклика на команду, с. По тревоге кабина слушается хуже.
func set_response_delay(value: float) -> void:
	_motion.response_delay = maxf(value, 0.0)


## Команда от пассажира на этот кадр: -1 вверх, +1 вниз, 0 отпущено.
##
## Кабина её принимает, но выполняет только от того, кто внутри.
func drive(command: float) -> void:
	_command = command


## Совпал ли пол кабины с полом этажа.
func is_aligned() -> bool:
	return _motion.is_aligned()


## Давит тех, кто оказался под днищем едущей вниз кабины.
func _crush_those_underneath() -> void:
	if _motion.velocity <= 0.0:
		return
	for body: Node2D in _crush_zone.get_overlapping_bodies():
		var victim := body as Otto
		if victim == null:
			continue
		if ShaftHazards.crushes(_motion.velocity, victim.is_grounded(), victim == _occupant):
			victim.kill()


func _on_body_entered(body: Node2D) -> void:
	var rider := body as Otto
	if rider == null:
		return
	_occupant = rider
	rider.board(self)


func _on_body_exited(body: Node2D) -> void:
	var rider := body as Otto
	if rider == null or rider != _occupant:
		return
	_occupant = null
	_command = 0.0
	rider.leave(self)
