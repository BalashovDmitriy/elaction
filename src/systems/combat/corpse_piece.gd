class_name CorpsePiece
extends CharacterBody3D

## Кусок тела, оторванный стенкой кабины (ADR-0043, решение 11).
##
## Копия фигуры, замершая в позе тела кость в кость и срезанная до своей
## полосы по X, и лежачая форма той же полосы. Дальше это обычное лежащее тело
## ([Corpse]): едет на полу кабины, падает в шахту, ложится на другие трупы,
## попадает под днище. Лежит до конца здания, как и трупы (ADR-0037, решение 6).

## Тяжесть и предел скорости падения — те же, что у агента.
const GRAVITY: float = 27.0
const MAX_FALL_SPEED: float = 12.6

var corpse: Corpse = null


## Отрывает от фигуры [param from] полосу [param part] по X в мире и кладёт её
## в [param host] отдельным телом на том же месте, на полу кабины [param car].
static func tear_off(from: FigureRig, host: Node, part: Vector2, car: ElevatorCar) -> CorpsePiece:
	var piece := CorpsePiece.new()
	piece.name = "CorpsePiece"
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(0.1, Proportions.PRONE, WorldSpace.BODY_DEPTH)
	piece.add_child(shape)
	var figure := FigureRig.new()
	figure.model = from.model
	piece.add_child(figure)
	piece.collision_mask = Corpse.GEOMETRY_MASK
	host.add_child(piece)
	# Начало куска — в ногах тела, как у актёра: фигура стоит в нём так же,
	# как стояла в теле, и поза копируется без пересчёта.
	var feet := from.get_parent() as Node3D
	piece.global_position = feet.global_position
	figure.transform = from.transform
	figure.copy_pose_of(from)
	figure.keep_between(part.x, part.y)
	piece.corpse = Corpse.new(piece, shape, figure, GRAVITY, MAX_FALL_SPEED)
	piece.corpse.enter()
	piece.corpse.set_span(part.x - piece.global_position.x, part.y - piece.global_position.x)
	piece.corpse.ride_on(car)
	return piece


func _physics_process(delta: float) -> void:
	if corpse == null:
		return
	corpse.step(delta, true, 1.0)
	if corpse.at_rest:
		set_physics_process(false)
