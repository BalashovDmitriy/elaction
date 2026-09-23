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

## Индикаторы на крыше кабины: габарит, разнос от середины в долях ширины
## кабины и на сколько их середина выше крыши, м. Два красных огонька —
## читаемость кабины на погашенном этаже (ADR-0023, решение 6).
const INDICATOR_SIZE := Vector3(0.1, 0.06, 0.1)
const INDICATOR_SPREAD: float = 0.35
const INDICATOR_RISE: float = 0.03

## Стрелки в кабине: разнос от середины в долях ширины кабины.
const ARROW_SPREAD: float = 0.275

## Насколько проём входа и зона сдавливания уже самой кабины, м: у краёв
## остаётся по 6 см, чтобы стоящий на полу этажа вплотную к шахте не считался
## ни пассажиром, ни придавленным.
const INNER_INSET: float = 0.12

## Толщина пола и крыши кабины, м. Задана сценой; здесь она нужна затем, что
## высоту кабина берёт из правил здания, а не из сцены.
const SLAB_THICKNESS: float = 0.18

## Просвет этажа и ширина шахты по умолчанию, м — те же, что у стандартных
## правил. Кабина строится по ним, пока уровень не сказал своё — так одиночная
## кабина, поднятая тестом без здания, всё равно собрана целиком.
const DEFAULT_CLEAR_HEIGHT: float = Proportions.CLEARANCE
const DEFAULT_WIDTH: float = Proportions.SHAFT

## На сколько стрелки утоплены от крыши, м.
const ARROW_DROP: float = 0.3

## Тяги между ярусами пары: сечение, разнос от середины в долях ширины кабины
## и глубина, м.
##
## Ярусы скреплены и едут вместе, но стоят через этаж — между крышей нижнего и
## днищем верхнего остаётся этаж пустоты. Без тяг это две отдельные кабины,
## которые почему-то ходят вместе (ADR-0025, решение 1).
const TIE_WIDTH: float = 0.1
const TIE_SPREAD: float = 0.45
const TIE_DEPTH: float = 0.6

## Ход кабины по ROM: 2 px за тик логики, этаж за 1.6 с (ADR-0027, решение 4).
@export var speed: float = Arcade.speed(Arcade.CAR_PX)
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
## Огоньки на крыше: их двигает [method fit_to_story], когда меняется высота.
var _indicators: Array[MeshInstance3D] = []
## Ширина кабины, м. Задаёт её [method fit_to_story] из правил здания.
var _width: float = DEFAULT_WIDTH
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
	($FloorVisual as MeshInstance3D).material_override = slab
	($RoofVisual as MeshInstance3D).material_override = slab
	var arrow := GreyboxLook.marker(GreyboxLook.DOOR)
	_up_arrow.material_override = arrow
	_down_arrow.material_override = arrow

	for side: float in [-1.0, 1.0]:
		var indicator := GreyboxLook.box(INDICATOR_SIZE, GreyboxLook.light(GreyboxLook.INDICATOR))
		add_child(indicator)
		_indicators.append(indicator)
	fit_to_story(DEFAULT_CLEAR_HEIGHT, DEFAULT_WIDTH)


## Растягивает кабину на просвет этажа и ширину шахты: пол на полу этажа, крыша
## у низа плиты, борта у стенок шахты.
##
## **Кабина занимает просвет целиком — как в оригинале.** Сверка по кадру
## (256×224): шаг этажа 48 px, плита 7, просвет 41, кабина 40. У нас она была
## 1.8 м при просвете 3.0 — ровно вполовину ниже, и это расхождение нигде
## не решалось: размер приехал из 2D-версии M2 и пережил пересчёт пропорций M13
## (ADR-0025, решение 10).
##
## Езде на крыше полная высота не мешает: крыша встаёт у низа плиты, а плита
## в этом месте прорезана шахтой — стоящий на крыше стоит в проёме, и корпус
## уходит в этаж выше. Так же это устроено и в оригинале.
##
## Размеры задаёт уровень из правил здания, а не сцена: [member
## BuildingRules.floor_height], [member BuildingRules.slab_height] и [member
## BuildingRules.shaft_width] — экспортируемые поля, и здание с другими
## пропорциями собирают тесты. Ширина пришла сюда в M18c: шахта выросла
## до 1.8 м, а кабина из сцены осталась бы в 1.2 и болталась бы в ней
## (ADR-0026, решение 3).
func fit_to_story(clear_height: float, car_width: float) -> void:
	_width = car_width
	var roof_middle := clear_height - SLAB_THICKNESS * 0.5
	($RoofShape as CollisionShape3D).position.y = roof_middle
	($RoofVisual as MeshInstance3D).position.y = roof_middle
	for slab: String in ["FloorShape", "RoofShape"]:
		_resize(get_node(slab) as CollisionShape3D, car_width)
	for slab: String in ["FloorVisual", "RoofVisual"]:
		var visual := get_node(slab) as MeshInstance3D
		var mesh := (visual.mesh as BoxMesh).duplicate() as BoxMesh
		mesh.size.x = car_width
		visual.mesh = mesh
	_resize($CrushZone/CrushShape as CollisionShape3D, car_width - INNER_INSET)

	var room := clear_height - SLAB_THICKNESS
	var inside := $Interior/InteriorShape as CollisionShape3D
	_resize(inside, car_width - INNER_INSET, room)
	inside.position.y = room * 0.5

	_up_arrow.position = Vector3(-car_width * ARROW_SPREAD, clear_height - ARROW_DROP, 0.3)
	_down_arrow.position = Vector3(car_width * ARROW_SPREAD, clear_height - ARROW_DROP, 0.3)
	for index in _indicators.size():
		var side := -1.0 if index == 0 else 1.0
		_indicators[index].position = Vector3(
			side * car_width * INDICATOR_SPREAD,
			clear_height + INDICATOR_RISE + INDICATOR_SIZE.y * 0.5,
			0.3
		)


## Ширина кабины, м.
func width() -> float:
	return _width


## Меняет габарит формы по ширине и, если задана, по высоте.
##
## Форма своя на каждую кабину: подресурс сцены общий на все её копии, и
## правка размера на месте растянула бы заодно все остальные кабины здания.
static func _resize(shape: CollisionShape3D, box_width: float, box_height: float = -1.0) -> void:
	var box := (shape.shape as BoxShape3D).duplicate() as BoxShape3D
	box.size.x = box_width
	if box_height > 0.0:
		box.size.y = box_height
	shape.shape = box


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
	# Свои источники звука у яруса остаются, но молчат: гудит и звенит ведущий,
	# а пара в одной шахте звучала бы вдвое громче одиночной кабины.


## Есть ли кто-нибудь в этой кабине.
func has_rider() -> bool:
	return _occupant != null


## Ярус ли это двухэтажной пары. У яруса нет своего хода: он держится
## за ведущим и все вопросы о движении передаёт ему.
func is_deck() -> bool:
	return _leader != null


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
	# Зона сдавливания верхнего яруса остаётся: между ярусами этаж пустоты,
	# на крышу нижнего можно встать, и опускающаяся пара прижмёт стоящего.
	var tie := GreyboxLook.metal(GreyboxLook.CAR)
	var length := drop - _body_height()
	if length <= 0.0:
		return
	for side: float in [-1.0, 1.0]:
		var strut := GreyboxLook.box(Vector3(TIE_WIDTH, length, TIE_DEPTH), tie)
		strut.position = Vector3(side * _width * TIE_SPREAD, _under_the_floor() - length * 0.5, 0.0)
		add_child(strut)


## Высота кабины от днища до верха крыши, м.
func _body_height() -> float:
	return _roof_top() - _under_the_floor()


## Верх крыши в своих координатах, м.
func _roof_top() -> float:
	return ($RoofVisual as MeshInstance3D).position.y + SLAB_THICKNESS * 0.5


## Низ днища в своих координатах, м.
func _under_the_floor() -> float:
	return ($FloorVisual as MeshInstance3D).position.y - SLAB_THICKNESS * 0.5


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
## давит ли он. У яруса пары своего хода нет — отвечает за него ведущий, иначе
## едущий вниз ярус отчитывался бы нулём и никого не придавил.
func speed_now() -> float:
	return _leader.speed_now() if _leader != null else _motion.velocity


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
		var agent := body as Enemy
		if agent != null:
			# Кабина давит и агентов — 300 очков, как в ROM (ADR-0027, решение 6).
			# Зона заходит на полу кабины выше днища, и ноги пассажира в неё
			# попадают: пассажир — тот, кто стоит на полу кабины, а жертва — тот,
			# кто под днищем. Разводит их высота ступней.
			var riding := to_local(agent.global_position).y > -SLAB_THICKNESS
			if not agent.is_dead() and ShaftHazards.crushes(speed, agent.is_on_floor(), riding):
				agent.kill(true)
				GameState.instance().add_score(GameState.CRUSH_SCORE)
			continue
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
	# Через [method drive], а не полем: у яруса пары команду исполняет ведущий,
	# и забытая у него «вниз» тронула бы пару с места в тот кадр, когда в неё
	# войдёт следующий, — ещё до того, как тот успеет нажать хоть что-то.
	drive(0.0)
	rider.leave(self)
