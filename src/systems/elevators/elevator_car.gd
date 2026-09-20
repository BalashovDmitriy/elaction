class_name ElevatorCar
extends AnimatableBody3D

## Кабина лифта.
##
## Решение о движении принимает [ElevatorMotion]; узел только переносит его в
## координату и раздаёт события. Кабина слушается Otto, пока он внутри, и ездит
## сама, когда пуста (ADR-0004, пункты 1 и 4).
##
## Стоящего на крыше переносит физика: [member AnimatableBody3D.sync_to_physics].
## Управлять кабиной с крыши нельзя — в оригинале так же.
##
## [ElevatorMotion] считает в координатах правил, где вниз — это рост Y. Узел
## переводит это в сцену в одном месте, [method _place], и больше о развороте
## Y не знает: правило движения при переезде не тронуто (ADR-0021, решение 2).

## Кабина совпала с этажом и из неё можно выйти.
signal floor_reached(index: int)

## Докуда слышно гул кабины, м. Дальше по этажу он уже не мешает.
const HUM_REACH: float = 10.8

## Докуда слышно «динь», м. Шире гула, но всё же не на всё здание: пустые
## кабины катаются сами, и каждая отбивает этажи — глобальный звонок из пяти
## шахт звенел бы в ухо без остановки.
const DING_REACH: float = 19.2

## Насколько гаснет указатель, когда в эту сторону ходу нет.
const ARROW_DIM: float = 0.18

@export var speed: float = 1.8
@export var floor_pause: float = 1.5
## Встаёт ли кабина между этажами. Сверкой не подтверждено — см. ADR-0004.
@export var stops_between_floors: bool = true

var _motion := ElevatorMotion.new()
var _occupant: PhysicsBody3D = null
var _command: float = 0.0
var _aligned_floor: int = -1

var _hum: AudioStreamPlayer3D = null
var _ding: AudioStreamPlayer3D = null
@onready var _interior: Area3D = $Interior
@onready var _crush_zone: Area3D = $CrushZone
@onready var _up_arrow: MeshInstance3D = $UpArrow
@onready var _down_arrow: MeshInstance3D = $DownArrow


func _ready() -> void:
	_interior.body_entered.connect(_on_body_entered)
	_interior.body_exited.connect(_on_body_exited)
	_hum = Sounds.source(self, Sounds.ELEVATOR_HUM, HUM_REACH)
	_ding = Sounds.source(self, Sounds.ELEVATOR_DING, DING_REACH)
	# Кабина — то, на чём стоят и в чём едут: читаться она обязана и на
	# погашенном этаже (ADR-0019, решение 5).
	var slab := GreyboxLook.marker(GreyboxLook.CAR)
	($FloorVisual as MeshInstance3D).material_override = slab
	($RoofVisual as MeshInstance3D).material_override = slab
	var arrow := GreyboxLook.marker(GreyboxLook.DOOR)
	_up_arrow.material_override = arrow
	_down_arrow.material_override = arrow


func _physics_process(delta: float) -> void:
	var occupied := _occupant != null
	_place(_motion.update(delta, _command if occupied else 0.0, occupied))

	var reached := _motion.aligned_floor()
	if reached != _aligned_floor:
		_aligned_floor = reached
		if reached >= 0:
			# «Динь» — один из двух эффектов, которые источники называют прямо.
			_ding.play()
			floor_reached.emit(reached)

	# Гул идёт, пока кабина едет. Источник позиционный: шахт в здании пять,
	# и слышно должно быть только ту, рядом с которой стоишь.
	Sounds.keep_playing(_hum, not is_zero_approx(_motion.velocity))

	# Указатели: погасшая стрелка объясняет, почему кабина не идёт дальше.
	_up_arrow.transparency = 0.0 if _motion.can_go(Intent.UP) else 1.0 - ARROW_DIM
	_down_arrow.transparency = 0.0 if _motion.can_go(Intent.DOWN) else 1.0 - ARROW_DIM

	_crush_those_underneath()


## Задаёт шахту: координаты этажей-остановок в правилах и этаж, с которого
## кабина начинает.
func setup(stops: PackedFloat32Array, start_floor: int = 0) -> void:
	_motion.speed = speed
	_motion.floor_pause = floor_pause
	_motion.stops_between_floors = stops_between_floors
	_motion.setup(stops, start_floor)
	_place(_motion.position)
	_aligned_floor = _motion.aligned_floor()


## Задержка отклика на команду, с. По тревоге кабина слушается хуже.
func set_response_delay(value: float) -> void:
	_motion.response_delay = maxf(value, 0.0)
	# Чтобы новая задержка застала и ту поездку, что уже идёт.
	_motion.forget_command()


## Команда от пассажира на этот кадр: -1 вверх, +1 вниз, 0 отпущено.
##
## Кабина её принимает, но выполняет только от того, кто внутри.
func drive(command: float) -> void:
	_command = command


## Совпал ли пол кабины с полом этажа.
func is_aligned() -> bool:
	return _motion.is_aligned()


## Ставит кабину на высоту, посчитанную правилами.
func _place(height_in_plane: float) -> void:
	position.y = WorldSpace.height_to_scene(height_in_plane)


## Давит тех, кто оказался под днищем едущей вниз кабины.
func _crush_those_underneath() -> void:
	if _motion.velocity <= 0.0:
		return
	for body: Node3D in _crush_zone.get_overlapping_bodies():
		var victim := body as Otto
		if victim == null:
			continue
		if ShaftHazards.crushes(_motion.velocity, victim.is_grounded(), victim == _occupant):
			victim.kill(true)


func _on_body_entered(body: Node3D) -> void:
	var rider := body as Otto
	if rider == null:
		return
	_occupant = rider
	rider.board(self)


func _on_body_exited(body: Node3D) -> void:
	var rider := body as Otto
	if rider == null or rider != _occupant:
		return
	_occupant = null
	_command = 0.0
	rider.leave(self)
