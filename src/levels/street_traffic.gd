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
## Жребий потока — от сида здания: каждый прогон одного здания одинаков, а
## сид здания солью партии свой в каждой партии. Первым жребием — дорожная
## ситуация ([enum Density], ADR-0046, решение 3): свободная улица, где просвет
## чаще есть сразу, обычная и плотная, где ждать дольше. Машины — жребием
## модели и краски, каждая своя.
## Двигается поток, только пока выезд в кадре ([method set_active]).

## Дорожная ситуация у выезда: насколько плотно идут машины.
enum Density { LIGHT, NORMAL, HEAVY }

## Звук потока (ADR-0052, решение 7): за сколько секунд до кадра машина
## звучит проездом, докуда её слышно, м, громкость проезда и гудка, дБ.
const PASS_LEAD: float = 1.6
const PASS_REACH: float = 40.0
const PASS_DB: float = -6.0
const HORN_DB: float = -4.0

## Середины полос по Z, м: ближняя — между тротуаром у выезда и осевой, дальняя
## — между осевой и машиной, припаркованной у дальнего бордюра.
const NEAR_LANE_Z: float = -3.2
const FAR_LANE_Z: float = -5.2
## Скорость полос, м/с: жребий по зданию в этих пределах.
const SPEEDS := Vector2(8.0, 11.0)
## Просвет между машинами при въезде, м по бамперам: жребий на каждую, в
## пределах ситуации [enum Density].
const GAPS: Array[Vector2] = [Vector2(20.0, 48.0), Vector2(7.0, 24.0), Vector2(3.5, 11.0)]
## Доли ситуаций в жребии — свободная, обычная, плотная — по времени суток
## ([enum TimeOfDay.Kind], ADR-0052, решение 2): днём улица плотнее всего,
## ночью чаще свободна.
const DENSITY_ODDS: Array[Array] = [
	[0.3, 0.45, 0.25],
	[0.15, 0.4, 0.45],
	[0.3, 0.45, 0.25],
	[0.5, 0.35, 0.15],
]
## Сколько машина Otto ждёт просвета, прежде чем поток его устроит, с, по
## ситуации: в плотном потоке ждать приходится дольше.
const WAIT_LIMITS: Array[float] = [1.5, 2.2, 4.0]
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
	## Прозвучала ли уже, проезжая мимо, и гудела ли (ADR-0052, решение 7).
	var heard: bool = false
	var honked: bool = false


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


## Ситуация этого выезда.
var density: Density = Density.NORMAL
## Горят ли фары потока: днём в ясную погоду — нет (ADR-0052, решение 3).
var headlights: bool = true

## Идёт ли снег: тогда на машинах потока снег (ADR-0054).
var _snowy: bool = false
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
## выезд показался. [param time] — время суток, от него плотность;
## [param lights] — горят ли фары.
func build(
	left: float,
	street: float,
	building_seed: int,
	time: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT,
	lights: bool = true,
	snowy: bool = false
) -> void:
	name = "Traffic"
	_snowy = snowy
	_street = street
	headlights = lights
	_rng.seed = hash([building_seed, SALT])
	density = _draw_density(_rng.randf(), time)
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


## Ситуация по доле [param roll] из [0, 1) во время [param time]: по долям
## [constant DENSITY_ODDS].
static func _draw_density(roll: float, time: TimeOfDay.Kind) -> Density:
	var odds: Array = DENSITY_ODDS[time]
	var upto := 0.0
	for index: int in odds.size():
		upto += float(odds[index])
		if roll < upto:
			return index as Density
	return Density.HEAVY


## Какая ситуация выпадет у здания с сидом [param building_seed] во время
## [param time]: тот же первый жребий, что у [method build]. Тестам — найти
## здание с нужной.
static func density_for(building_seed: int, time: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT) -> Density:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, SALT])
	return _draw_density(rng.randf(), time)


## Сколько машина Otto ждёт просвета, прежде чем поток его устроит, с.
func wait_limit() -> float:
	return WAIT_LIMITS[density]


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
	# Камера — одна на шаг: по ней машины решают, когда звучать проездом.
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	for lane: Lane in [_near, _far]:
		_drive(lane, delta, camera)
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
	for car: Car in _near.cars:
		# Ближняя идёт влево: сзади — правее, впереди — левее. Просвет — по
		# бамперам: от середины до середины минус длина машины.
		var gap := car.x - x
		if gap >= 0.0 and gap - CarModel.LENGTH < CLEAR_BEHIND:
			return false
		if gap < 0.0 and -gap - CarModel.LENGTH < CLEAR_AHEAD:
			return false
	return true


## Держать ли въезд ближней полосы: Otto ждёт слишком долго, и просвет
## должен случиться.
func hold_back(on: bool) -> void:
	# Otto ждёт просвета слишком долго — задние сигналят.
	if on and not _near.held and not _near.cars.is_empty():
		_honk(_near.cars[_near.cars.size() - 1])
	_near.held = on


## Машина Otto влилась в ближнюю полосу: подъезжающие сзади держат дистанцию
## и до неё.
func join(car: Node3D) -> void:
	_guest = car


## Ведёт машины полосы на шаг: полный ход, но не ближе дистанции до передней.
## [param camera] — кадр, по нему звучит проезд ([method _pass_by]).
func _drive(lane: Lane, delta: float, camera: Camera3D) -> void:
	for index: int in lane.cars.size():
		var car := lane.cars[index]
		var wanted := lane.speed
		var ahead := _ahead_of(lane, index)
		if not is_nan(ahead):
			var gap := (ahead - car.x) * lane.towards - CarModel.LENGTH
			wanted *= clampf((gap - MIN_GAP) / (SAFE_GAP - MIN_GAP), 0.0, 1.0)
		var change := ACCELERATION if wanted > car.speed else BRAKING
		# Резко тормозит за машиной Otto — гудит. Именно за ней: за машиной
		# потока тормозят молча.
		if wanted < car.speed * 0.4 and not car.honked and _behind_the_guest(lane, ahead):
			_honk(car)
		car.speed = move_toward(car.speed, wanted, change * delta)
		_pass_by(car, camera)
		car.x += lane.towards * car.speed * delta
		car.node.position.x = car.x
		# Колёса катятся, как у машины Otto ([method CarModel.roll]).
		CarModel.roll(car.wheels, car.hubs, car.speed * delta, car.radius)


## Машина подъезжает к кадру — звучит проездом на себе: запись проезда
## достигает пика к середине, и пускается она заранее, по скорости машины.
func _pass_by(car: Car, camera: Camera3D) -> void:
	if car.heard or camera == null:
		return
	if absf(car.x - camera.global_position.x) > maxf(car.speed, 1.0) * PASS_LEAD:
		return
	car.heard = true
	# В снег шины шуршат по каше (ADR-0054).
	var tyres := Sounds.CAR_PASS_SLUSH if _snowy else Sounds.CAR_PASS
	var voice := Sounds.source(car.node, tyres, PASS_REACH)
	voice.volume_db = PASS_DB
	voice.finished.connect(voice.queue_free)
	voice.play()


## Передняя у машины ближней полосы — машина Otto: [param ahead] из
## [method _ahead_of] совпал с ней.
func _behind_the_guest(lane: Lane, ahead: float) -> bool:
	if lane != _near or is_nan(ahead) or _guest == null or not is_instance_valid(_guest):
		return false
	return is_equal_approx(ahead, _guest.position.x)


## Гудок машины [param car] — один раз на машину.
func _honk(car: Car) -> void:
	car.honked = true
	if car.node.is_inside_tree():
		Sounds.play_at(car.node, Sounds.HORN, car.node.global_position, PASS_REACH, HORN_DB)


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
	lane.next_gap = _next_gap()


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
	var x := lane.exit - lane.towards * _rng.randf_range(0.0, GAPS[density].y)
	while (lane.entry - x) * -lane.towards > 0.0:
		lane.cars.append(_add_car(lane, x))
		x -= lane.towards * (CarModel.LENGTH + _next_gap())
	lane.next_gap = _next_gap()


## Просвет до следующей машины, м: жребий в пределах ситуации.
func _next_gap() -> float:
	var span := GAPS[density]
	return _rng.randf_range(span.x, span.y)


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
	if _snowy:
		CarModel.snow_on(model)
	if headlights:
		var halo := ExitCar.halo()
		# Своим именем: «Halo» — ореол дождя ([RainLook]), и в сухую погоду его
		# в здании быть не должно; фары потока светят и в сухую.
		halo.name = "HeadlightGlow"
		halo.position = Vector3(CarModel.LENGTH * HALO_REACH, HALO_HEIGHT, 0.0)
		root.add_child(halo)
	else:
		# Днём в ясную фары не горят.
		Garage.switch_lights_off(model)
	# Капот модели в +X; полосе влево машина развёрнута целиком.
	if lane.towards < 0.0:
		root.rotation.y = PI
	root.position = WorldSpace.to_scene(Vector2(x, _street))
	root.position.z = lane.z
	add_child(root)
	# Машины въезжают и после сборки улицы: солнце им отдаётся сразу.
	Outdoors.mark(root)
	var car := Car.new()
	car.node = root
	car.x = x
	car.speed = lane.speed
	car.wheels = CarModel.wheels(model)
	car.hubs = CarModel.hubs(car.wheels)
	car.radius = CarModel.wheel_radius(car.wheels, car.radius)
	return car


## Глубина модели пака один раз на модель: мерить её на каждую машину потока —
## обходить все сетки заново.
func _depth_of(index: int, model: Node3D) -> float:
	if not _depths.has(index):
		_depths[index] = maxf(Garage.depth_of(model), 0.1)
	return float(_depths[index])
