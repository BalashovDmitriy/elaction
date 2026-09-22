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

## Индикаторы на крыше кабины: габарит, разнос от середины и на сколько их
## середина выше крыши, м. Два красных огонька — читаемость кабины на
## погашенном этаже (ADR-0023, решение 6); стрелки — как были.
const INDICATOR_SIZE := Vector3(0.1, 0.06, 0.1)
const INDICATOR_SPREAD: float = 0.42
const INDICATOR_RISE: float = 0.03

## Тяги между ярусами пары: сечение, разнос от середины и глубина, м.
##
## Ярусы скреплены и едут вместе, но стоят через этаж — между крышей нижнего и
## днищем верхнего остаётся 1.8 м пустоты. Без тяг это две отдельные кабины,
## которые почему-то ходят вместе (ADR-0025, решение 1).
const TIE_WIDTH: float = 0.1
const TIE_SPREAD: float = 0.54
const TIE_DEPTH: float = 0.6

@export var speed: float = 1.8
@export var floor_pause: float = 1.5
## Встаёт ли кабина между этажами. Сверкой не подтверждено — см. ADR-0004.
@export var stops_between_floors: bool = true

var _motion := ElevatorMotion.new()
var _occupant: PhysicsBody3D = null
var _command: float = 0.0
var _aligned_floor: int = -1

## Ведущий ярус пары. Пустой — кабина обычная и ходит сама.
var _leader: ElevatorCar = null
## Нижний ярус пары, если он есть. Держит его ведущий.
var _deck: ElevatorCar = null
## На сколько нижний ярус ниже ведущего, м.
var _deck_drop: float = 0.0

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
	# погашенном этаже (ADR-0019, решение 5). Держат это два индикатора на
	# крыше, а сама кабина — металл, как шахта.
	var slab := GreyboxLook.metal(GreyboxLook.CAR)
	var roof := $RoofVisual as MeshInstance3D
	($FloorVisual as MeshInstance3D).material_override = slab
	roof.material_override = slab
	var arrow := GreyboxLook.marker(GreyboxLook.DOOR)
	_up_arrow.material_override = arrow
	_down_arrow.material_override = arrow

	var roof_top := roof.position.y + (roof.mesh as BoxMesh).size.y * 0.5
	for side: float in [-1.0, 1.0]:
		var indicator := GreyboxLook.box(INDICATOR_SIZE, GreyboxLook.light(GreyboxLook.INDICATOR))
		indicator.position = Vector3(
			side * INDICATOR_SPREAD, roof_top + INDICATOR_RISE + INDICATOR_SIZE.y * 0.5, 0.3
		)
		add_child(indicator)


func _physics_process(delta: float) -> void:
	if _leader != null:
		_ride_along()
		return

	# Пассажир любого яруса ведёт всю пару: ярусы скреплены, и своего хода
	# у нижнего нет.
	var occupied := has_rider() or (_deck != null and _deck.has_rider())
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

	_show_arrows()
	_crush_those_underneath(_motion.velocity)


## Задаёт шахту: координаты этажей-остановок в правилах и этаж, с которого
## кабина начинает.
func setup(stops: PackedFloat32Array, start_floor: int = 0) -> void:
	_motion.speed = speed
	_motion.floor_pause = floor_pause
	_motion.stops_between_floors = stops_between_floors
	_motion.setup(stops, start_floor)
	_place(_motion.position)
	_aligned_floor = _motion.aligned_floor()


## Делает кабину нижним ярусом пары: своего хода у неё больше нет, она держится
## на [param drop] метров ниже ведущего и отдаёт ему всё, что от неё хотят.
##
## Своим узлом, а не вторым телом внутри ведущего: в кабину входят, на её крыше
## стоят и под её днищем гибнут — ярусу нужны и свой [Area3D] входа, и своя
## зона сдавливания, и своя крыша. Копия сцены даёт всё это разом.
func serve_as_deck(leader: ElevatorCar, drop: float) -> void:
	_leader = leader
	_deck_drop = drop
	leader.take_a_deck(self, drop)
	_ride_along()


## Есть ли кто-нибудь в этой кабине.
func has_rider() -> bool:
	return _occupant != null


## Может ли кабина ещё пойти в эту сторону. У яруса пары решает ведущий.
func can_go(towards: float) -> bool:
	return _leader.can_go(towards) if _leader != null else _motion.can_go(towards)


## Задержка отклика на команду, с. По тревоге кабина слушается хуже.
##
## У яруса пары своего хода нет, и задержку принимает ведущий: в списке кабин
## уровня лежат оба, потому что садятся в любой.
func set_response_delay(value: float) -> void:
	if _leader != null:
		_leader.set_response_delay(value)
		return
	_motion.response_delay = maxf(value, 0.0)
	# Чтобы новая задержка застала и ту поездку, что уже идёт.
	_motion.forget_command()


## Команда от пассажира на этот кадр: -1 вверх, +1 вниз, 0 отпущено.
##
## Кабина её принимает, но выполняет только от того, кто внутри. Ярус пары
## передаёт её ведущему: ярусы скреплены, и своей воли у нижнего нет.
func drive(command: float) -> void:
	if _leader != null:
		_leader.drive(command)
		return
	_command = command


## Совпал ли пол кабины с полом этажа.
##
## У яруса пары спрашивать нечего: ход один на двоих, и шаг этажа один и тот же
## по всей высоте здания — значит совпали оба яруса или ни один.
func is_aligned() -> bool:
	return _leader.is_aligned() if _leader != null else _motion.is_aligned()


## Берёт нижний ярус под себя и связывает его с собой тягами.
##
## Зовёт [method serve_as_deck], и только он: пара задаётся с одной стороны,
## иначе половина связи однажды останется незаданной.
func take_a_deck(deck: ElevatorCar, drop: float) -> void:
	_deck = deck
	_deck_drop = drop
	# Зона сдавливания верхнего яруса остаётся: между ярусами 1.8 м пустоты,
	# на крышу нижнего можно встать, и опускающаяся пара прижмёт стоящего.
	var tie := GreyboxLook.metal(GreyboxLook.CAR)
	var length := drop - _body_height()
	if length <= 0.0:
		return
	for side: float in [-1.0, 1.0]:
		var strut := GreyboxLook.box(Vector3(TIE_WIDTH, length, TIE_DEPTH), tie)
		strut.position = Vector3(side * TIE_SPREAD, _under_the_floor() - length * 0.5, 0.0)
		add_child(strut)


## Высота кабины от днища до верха крыши, м.
func _body_height() -> float:
	return _roof_top() - _under_the_floor()


## Верх крыши в своих координатах, м.
func _roof_top() -> float:
	var roof := $RoofVisual as MeshInstance3D
	return roof.position.y + (roof.mesh as BoxMesh).size.y * 0.5


## Низ днища в своих координатах, м.
func _under_the_floor() -> float:
	var slab := $FloorVisual as MeshInstance3D
	return slab.position.y - (slab.mesh as BoxMesh).size.y * 0.5


## Держит нижний ярус под ведущим.
##
## Ведущий стоит в дереве выше и успевает встать на своё место первым, поэтому
## ярус берёт его сегодняшнюю высоту, а не вчерашнюю: разъехаться на кадр им
## нельзя — на этом и держится «совпали оба или ни один».
func _ride_along() -> void:
	position.y = _leader.position.y - _deck_drop
	_show_arrows()
	_crush_those_underneath(_leader.speed_now())


## Скорость кабины за последний кадр: её спрашивает нижний ярус, чтобы решить,
## давит ли он.
func speed_now() -> float:
	return _motion.velocity


## Указатели: погасшая стрелка объясняет, почему кабина не идёт дальше.
func _show_arrows() -> void:
	_up_arrow.transparency = 0.0 if can_go(Intent.UP) else 1.0 - ARROW_DIM
	_down_arrow.transparency = 0.0 if can_go(Intent.DOWN) else 1.0 - ARROW_DIM


## Ставит кабину на высоту, посчитанную правилами.
func _place(height_in_plane: float) -> void:
	position.y = WorldSpace.height_to_scene(height_in_plane)


## Давит тех, кто оказался под днищем едущей вниз кабины.
func _crush_those_underneath(speed: float) -> void:
	if speed <= 0.0:
		return
	for body: Node3D in _crush_zone.get_overlapping_bodies():
		var victim := body as Otto
		if victim == null:
			continue
		if ShaftHazards.crushes(speed, victim.is_grounded(), victim == _occupant):
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
