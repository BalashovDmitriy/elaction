class_name StreetTraffic
extends Node3D

## Поток машин по улице у выезда (M24h, ADR-0044, решения 1 и 2).
##
## В оригинале улицы с движением нет: машина Otto уезжает по пустой мостовой.
## Здесь две полосы. Ближняя идёт влево — туда же, куда уезжает Otto, и в неё
## он вливается, дождавшись просвета ([method is_clear_for], [method join]).
## Дальняя идёт навстречу, вправо. Машины — модели Cars Pack, как у выхода,
## фары и стоп-сигналы светятся эмиссией, у фары — ореол; настоящих источников
## у потока нет: машин в кадре с полдюжины, и каждая с прожектором съела бы
## бюджет света.
##
## Улица кончается у торца здания: за ним на уровне улицы — первый этаж.
## Машины въезжают на мостовую и уезжают с неё за этим торцом, будто улица
## уходит за угол; ближняя полоса выезжает из-за угла, дальняя за него уходит.
## Левый конец улицы — за краем самого широкого кадра выезда
## ([constant ExitStreet.FROM]).
##
## В ближней полосе машины держат дистанцию до передней — и до машины Otto,
## когда та влилась: подъехавшая сзади притормаживает, а не проходит насквозь.
## Дальней держать некого: скорость полосы одна на всех.
##
## Жребий потока — от сида здания: каждый прогон одного здания одинаков.
## Двигается поток, только пока выезд в кадре ([method set_active]).

## Середины полос по Z, м: ближняя — между тротуаром у выезда и осевой, дальняя
## — между осевой и машиной, припаркованной у дальнего бордюра.
const NEAR_LANE_Z: float = -3.2
const FAR_LANE_Z: float = -5.2
## Скорость полос, м/с: жребий по зданию в этих пределах.
const SPEEDS := Vector2(8.0, 11.0)
## Просвет между машинами при въезде, м по бамперам: жребий на каждую.
const GAPS := Vector2(7.0, 24.0)
## Ближе этого машина к передней не подъедет, м по бамперам; с [constant
## SAFE_GAP] и дальше — едет полным ходом.
const MIN_GAP: float = 2.5
const SAFE_GAP: float = 9.0
## Разгон и торможение, м/с².
const ACCELERATION: float = 4.0
const BRAKING: float = 9.0
## Сколько пустой полосы нужно машине Otto, чтобы влиться, м: до машины,
## которая подъезжает сзади, и до той, что уже проехала вперёд.
const CLEAR_BEHIND: float = 16.0
const CLEAR_AHEAD: float = 8.0
## Насколько за торцом здания машина въезжает и пропадает, м: целиком за
## боковой стеной.
const BEHIND_CORNER: float = CarModel.LENGTH
## Ореол у фары: высота над мостовой и вынос вперёд от середины, доли длины.
const HALO_HEIGHT: float = 0.55
const HALO_REACH: float = 0.47
## Соль жребия потока: своя, чтобы поток не ходил в ногу с улицей.
const SALT: int = 0x7EAF_F1C0


## Одна машина потока.
class Car:
	extends RefCounted

	var node: Node3D
	var x: float = 0.0
	var speed: float = 0.0
	var wheels: Array[Node3D] = []
	var hubs := PackedVector3Array()
	var radius: float = 0.3


## Одна полоса: куда идёт, где, с какой скоростью и кто на ней.
class Lane:
	extends RefCounted

	var z: float = 0.0
	## -1 — влево, +1 — вправо.
	var towards: float = -1.0
	var speed: float = 9.0
	## Где машины въезжают и где пропадают, по X.
	var entry: float = 0.0
	var exit: float = 0.0
	## Машины, первой — самая передняя по ходу.
	var cars: Array[Car] = []
	## Сколько пустой полосы оставить за последней въехавшей, м.
	var next_gap: float = 10.0
	## Держат ли въезд: на полосу, в которую вливается Otto, новые не
	## въезжают, пока он ждёт слишком долго.
	var held: bool = false


var _rng := RandomNumberGenerator.new()
var _street: float = 0.0
var _near := Lane.new()
var _far := Lane.new()
## Машина Otto, влившаяся в ближнюю полосу: за ней держат дистанцию.
var _guest: Node3D = null
## Держит ли поток на ходу машина Otto ([method keep_running]).
var _kept: bool = false
## Глубина каждой модели пака, м: по ней машина ужимается в ширину полосы.
var _depths: Dictionary = {}


## Собирает поток на улице у торца [param left], уровень улицы — [param street]
## в плоскости правил. Полосы заполнены с первого кадра: улица уже живёт, когда
## выезд показался.
func build(left: float, street: float, building_seed: int) -> void:
	name = "Traffic"
	_street = street
	_rng.seed = hash([building_seed, SALT])
	var far_end := left - ExitStreet.FROM - BEHIND_CORNER
	var corner := left + BEHIND_CORNER
	_near.z = NEAR_LANE_Z
	_near.towards = -1.0
	_near.entry = corner
	_near.exit = far_end
	_far.z = FAR_LANE_Z
	_far.towards = 1.0
	_far.entry = far_end
	_far.exit = corner
	for lane: Lane in [_near, _far]:
		lane.speed = _rng.randf_range(SPEEDS.x, SPEEDS.y)
		_fill(lane)
	set_active(false)


## Двигается ли поток: только пока выезд в кадре — или пока его ждёт машина
## Otto ([method keep_running]).
func set_active(on: bool) -> void:
	set_physics_process(on or _kept)


## Поток едет, что бы ни показывал кадр: его ждёт машина Otto, и вставший
## поток держал бы её у края мостовой вечно.
func keep_running() -> void:
	_kept = true
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	step(delta)


## Шаг потока. Отдельно от [method _physics_process]: тесты гоняют его сами.
func step(delta: float) -> void:
	for lane: Lane in [_near, _far]:
		_drive(lane, delta)
		_let_in(lane)
		_let_go(lane)


## Середина ближней полосы по Z: туда вливается машина Otto.
func near_lane_z() -> float:
	return _near.z


## Скорость ближней полосы, м/с: с ней едет влившаяся машина Otto.
func near_speed() -> float:
	return _near.speed


## Машины полосы: ближней при [param near], иначе дальней. Тестам.
func cars(near: bool) -> Array[Car]:
	return _near.cars if near else _far.cars


## Свободна ли ближняя полоса, чтобы влиться в неё в точке [param x]: сзади
## никто не подъезжает ближе [constant CLEAR_BEHIND], впереди никого ближе
## [constant CLEAR_AHEAD].
func is_clear_for(x: float) -> bool:
	var half := CarModel.LENGTH * 0.5
	for car: Car in _near.cars:
		# Ближняя идёт влево: сзади — правее, впереди — левее.
		var gap := car.x - x
		if gap >= 0.0 and gap - CarModel.LENGTH < CLEAR_BEHIND:
			return false
		if gap < 0.0 and -gap - half * 2.0 < CLEAR_AHEAD:
			return false
	return true


## Держать ли въезд ближней полосы: Otto ждёт слишком долго, и просвет
## должен случиться.
func hold_back(on: bool) -> void:
	_near.held = on


## Машина Otto влилась в ближнюю полосу: подъезжающие сзади держат дистанцию
## и до неё.
func join(car: Node3D) -> void:
	_guest = car


## Ведёт машины полосы на шаг: полный ход, но не ближе дистанции до передней.
func _drive(lane: Lane, delta: float) -> void:
	for index: int in lane.cars.size():
		var car := lane.cars[index]
		var wanted := lane.speed
		var ahead := _ahead_of(lane, index)
		if not is_nan(ahead):
			var gap := (ahead - car.x) * lane.towards - CarModel.LENGTH
			wanted *= clampf((gap - MIN_GAP) / (SAFE_GAP - MIN_GAP), 0.0, 1.0)
		var change := ACCELERATION if wanted > car.speed else BRAKING
		car.speed = move_toward(car.speed, wanted, change * delta)
		car.x += lane.towards * car.speed * delta
		car.node.position.x = car.x
		_spin(car, delta)


## Где передняя по ходу у машины [param index], по X; NAN — впереди никого.
## Машина Otto считается передней для всех ближней полосы, кто за ней.
func _ahead_of(lane: Lane, index: int) -> float:
	var ahead := NAN
	if index > 0:
		ahead = lane.cars[index - 1].x
	if lane == _near and _guest != null and is_instance_valid(_guest):
		var guest := _guest.position.x
		var car := lane.cars[index].x
		if (guest - car) * lane.towards > 0.0:
			if is_nan(ahead) or (ahead - guest) * lane.towards > 0.0:
				ahead = guest
	return ahead


## Впускает на полосу новую машину, когда за последней набралось просвета.
func _let_in(lane: Lane) -> void:
	if lane.held:
		return
	if not lane.cars.is_empty():
		var last := lane.cars[lane.cars.size() - 1]
		if (last.x - lane.entry) * lane.towards < lane.next_gap + CarModel.LENGTH:
			return
	lane.cars.append(_add_car(lane, lane.entry))
	lane.next_gap = _rng.randf_range(GAPS.x, GAPS.y)


## Убирает уехавших за конец улицы.
func _let_go(lane: Lane) -> void:
	while not lane.cars.is_empty():
		var first := lane.cars[0]
		if (first.x - lane.exit) * lane.towards < 0.0:
			return
		first.node.queue_free()
		lane.cars.remove_at(0)


## Заполняет полосу машинами от конца к въезду с жребием просветов.
func _fill(lane: Lane) -> void:
	var x := lane.exit - lane.towards * _rng.randf_range(0.0, GAPS.y)
	while (lane.entry - x) * -lane.towards > 0.0:
		lane.cars.append(_add_car(lane, x))
		x -= lane.towards * (CarModel.LENGTH + _rng.randf_range(GAPS.x, GAPS.y))
	lane.next_gap = _rng.randf_range(GAPS.x, GAPS.y)


func _add_car(lane: Lane, x: float) -> Car:
	var choice := CarModel.Choice.new()
	choice.model = _rng.randi_range(0, CarModel.MODELS.size() - 1)
	# Без чёрной — последней: ночью на мостовой она пропадала бы.
	choice.paint = _rng.randi_range(0, CarModel.PAINTS.size() - 2)
	var root := Node3D.new()
	root.name = "TrafficCar"
	var model := CarModel.build(choice)
	model.scale = Vector3(1.0, 1.0, Garage.CAR_WIDTH / _depth_of(choice.model, model))
	root.add_child(model)
	var halo := ExitCar.halo()
	halo.position = Vector3(CarModel.LENGTH * HALO_REACH, HALO_HEIGHT, 0.0)
	root.add_child(halo)
	# Капот модели в +X; полосе влево машина развёрнута целиком.
	if lane.towards < 0.0:
		root.rotation.y = PI
	root.position = WorldSpace.to_scene(Vector2(x, _street))
	root.position.z = lane.z
	add_child(root)
	var car := Car.new()
	car.node = root
	car.x = x
	car.speed = lane.speed
	car.wheels = CarModel.wheels(model)
	for wheel: Node3D in car.wheels:
		var mesh := wheel as MeshInstance3D
		var box := mesh.mesh.get_aabb() if mesh != null else AABB()
		car.hubs.append(box.get_center())
		if mesh != null:
			car.radius = maxf(box.size.y * 0.5, 0.05)
	return car


## Глубина модели пака один раз на модель: мерить её на каждую машину потока —
## обходить все сетки заново.
func _depth_of(index: int, model: Node3D) -> float:
	if not _depths.has(index):
		_depths[index] = maxf(Garage.depth_of(model), 0.1)
	return float(_depths[index])


## Колёса катятся: угол — путь, делённый на радиус, как у машины Otto
## ([method ExitCar.advance]).
func _spin(car: Car, delta: float) -> void:
	var spin := Basis(Vector3.BACK, -car.speed * delta / car.radius)
	for index: int in car.wheels.size():
		var hub := car.hubs[index]
		car.wheels[index].transform *= Transform3D(spin, hub - spin * hub)
