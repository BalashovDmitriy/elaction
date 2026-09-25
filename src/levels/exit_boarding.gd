class_name ExitBoarding
extends RefCounted

## Выход из здания: Otto садится в машину и уезжает (ADR-0038, решение 4).
##
## До машины он идёт сам. У водительской двери со всеми документами управление
## забирают: Otto делает последний шаг к двери, поворачивается к машине,
## дверца распахивается, он шагает в глубину к борту и скрывается за ней —
## дверца захлопывается, машина качнулась, — ворота гаража открываются,
## стартер заводит мотор, загораются фары, и машина уезжает, разгоняясь, по
## пандусу наверх. Здание сдано, когда она ушла из кадра: следующее собирается
## после отъезда, а не в тот же кадр (ADR-0011, пункт 14).
##
## Машина стоит за плоскостью игры, и раньше Otto, шагнув к двери, просто
## пропадал перед кузовом. Теперь посадку видно: поворот, дверца, шаг в глубину.
##
## С посадки кадр раздвигается влево за торец здания ([method exit_frame]):
## ворота, их свет и пандус за ними — в кадре, и машина уезжает по пандусу у
## всех на виду, а не в край кадра. Границы вернёт следующее здание — у него
## свой Otto и своя камера.
##
## С шага к двери Otto недосягаем: сначала его «везут», как на эскалаторе, —
## формы тела выключены, — потом он в машине, и снаружи его нет вовсе. Агенты
## по спрятанному не стреляют ([method Otto.is_hidden]).
##
## Своим классом, а не в уровне: у выхода своё состояние по шагам, которое
## уровню знать незачем, а уровень упёрся в предел строк. Узлов не держит —
## ход ему даёт уровень из своего шага физики.

## Что случилось за шаг: ничего, машина тронулась, машина ушла из кадра.
enum Event { NONE, STARTED, LEFT }

enum Phase { WAITING, STEPPING_IN, GETTING_IN, SEATING, STARTING, LEAVING, GONE }

## Ширина места у водительской двери, где Otto садится, м. Шире шага бота за
## кадр ([constant OttoBot.REACHED] и его последний шаг), но уже машины: садятся
## у двери, а не у багажника.
const DOOR_REACH: float = 0.9
## Насколько ступни могут быть выше или ниже пола подвала, м: садится стоящий,
## а не пролетающий мимо в прыжке.
const FOOTING: float = 0.2
## Посадка по шагам, с от её начала: Otto поворачивается к машине, дверца
## открывается, он шагает к борту, скрывается за дверцей, и она закрывается.
const TURN_TIME: float = 0.25
const DOOR_OPEN_TIME: float = 0.35
const STEP_BACK_FROM: float = 0.2
const STEP_BACK_TIME: float = 0.45
const DOOR_CLOSE_TIME: float = 0.2
## Насколько Otto пригибается, ныряя в машину, м: кузов ниже его, и без этого
## голова торчала бы над крышей до самого хлопка.
const DUCK: float = 0.55
## Вся посадка: от поворота до хлопка дверцы.
const GET_IN_TIME: float = STEP_BACK_FROM + STEP_BACK_TIME + DOOR_CLOSE_TIME
## Сколько Otto садится, с: от хлопка дверцы до стартера.
const SEAT_TIME: float = 0.5
## Середина кадра на выезде — насколько правее торца здания, м. Кадр ставится
## серединой, а не краем, и в кадре 16:9 от торца влево — 10.75 м: ворота,
## площадка и больше половины подъёма ([constant GarageGate.RAMP_APRON] +
## [constant GarageGate.RAMP_RUN]), а справа — машина у ворот и паркинг.
## Машина уходит из кадра на подъёме, у всех на виду.
const FRAME_SHIFT: float = 1.0
## Сколько мотор заводится, с: стартер и газовка ([constant Sounds.CAR_START],
## 2.8 с) — машина трогается на газовке, не дожидаясь её конца.
const START_TIME: float = 2.0

var phase: Phase = Phase.WAITING

var _car: ExitCar = null
## Пол подвала в плоскости правил.
var _surface: float = 0.0
var _seat_left: float = 0.0
## Паркинг, чьи ворота открываются перед машиной. Его строит уровень до
## машины ([method GreyboxLevel._build_garage]); нет его — машина просто уезжает.
var _garage: Garage = null
## Границы камеры на выезде; пустые — камера не трогается.
var _frame := Rect2()
## Сколько идёт посадка, с.
var _getting_in: float = 0.0


func _init(car: ExitCar, surface: float, garage: Garage = null, frame: Rect2 = Rect2()) -> void:
	_car = car
	_surface = surface
	_garage = garage
	_frame = frame


## Границы камеры на выезде, в плоскости правил: по вертикали — здание, по
## горизонтали — узкая полоса вокруг точки правее торца на [constant
## FRAME_SHIFT]. Полоса уже любого кадра, и камера встаёт серединой на неё
## ([method CameraBounds.clamp_centre]).
static func exit_frame(rules: BuildingRules) -> Rect2:
	var centre := rules.floor_span(rules.floors - 1).x + FRAME_SHIFT
	return Rect2(centre - 0.5, 0.0, 1.0, rules.total_height())


## Где Otto садится в машину, в плоскости правил: у водительской двери, на
## середине роста над полом подвала.
func door_point() -> Vector2:
	return Vector2(_car.door_x(), _surface - GreyboxLevel.EXIT_HEIGHT * 0.5)


## Стоит ли точка [param feet] у водительской двери, на полу подвала.
func at_the_door(feet: Vector2) -> bool:
	return absf(feet.x - _car.door_x()) <= DOOR_REACH * 0.5 and absf(feet.y - _surface) <= FOOTING


## Сел ли Otto: с этой минуты им распоряжается машина.
func is_boarded() -> bool:
	return phase != Phase.WAITING


## Шаг выхода. [param documents_done] — собраны ли все документы: без них машина не
## ждёт. [param view] — кадр правил, из которого машина уезжает.
func step(delta: float, otto: Otto, documents_done: bool, view: Rect2) -> Event:
	match phase:
		Phase.WAITING:
			var feet := WorldSpace.to_plane(otto.global_position)
			if documents_done and otto.is_on_foot() and otto.is_grounded() and at_the_door(feet):
				# Управление забрано: последний шаг к двери делает уже игра.
				otto.ride(true)
				if _frame.has_area():
					otto.apply_camera_bounds(_frame, false)
				phase = Phase.STEPPING_IN
		Phase.STEPPING_IN:
			if _step_to_the_door(otto, delta):
				_getting_in = 0.0
				phase = Phase.GETTING_IN
		Phase.GETTING_IN:
			_getting_in += delta
			if _get_in(otto):
				_car.set_door(0.0)
				_car.take_the_driver()
				_open_the_gate()
				_seat_left = SEAT_TIME
				phase = Phase.SEATING
		Phase.SEATING:
			_car.settle(delta)
			_seat_left -= delta
			if _seat_left <= 0.0:
				_car.start_engine()
				_seat_left = START_TIME
				phase = Phase.STARTING
		Phase.STARTING:
			_car.settle(delta)
			_seat_left -= delta
			if _seat_left <= 0.0:
				_car.drive_away()
				phase = Phase.LEAVING
				return Event.STARTED
		Phase.LEAVING:
			_car.settle(delta)
			if _car.advance(delta, view):
				phase = Phase.GONE
				return Event.LEFT
	return Event.NONE


## Ведёт Otto к двери шагом; true — дошёл.
func _step_to_the_door(otto: Otto, delta: float) -> bool:
	var at := WorldSpace.to_plane(otto.global_position)
	var gap := _car.door_x() - at.x
	var stride := otto.walk_speed * delta
	if absf(gap) <= stride:
		at.x = _car.door_x()
		otto.global_position = WorldSpace.to_scene(at)
		return true
	at.x += signf(gap) * stride
	otto.global_position = WorldSpace.to_scene(at)
	return false


## Посадка на время [member _getting_in]: поворот к машине, дверца, шаг в
## глубину к борту, дверца закрывается за спрятавшимся. true — дверца закрыта.
func _get_in(otto: Otto) -> bool:
	var t := _getting_in
	otto.turn_into_depth(clampf(t / TURN_TIME, 0.0, 1.0))
	var step := clampf((t - STEP_BACK_FROM) / STEP_BACK_TIME, 0.0, 1.0)
	otto.global_position.z = lerpf(WorldSpace.PLAY_Z, _car.seat_z(), ease(step, -1.6))
	var duck := clampf(step * 2.0 - 1.0, 0.0, 1.0)
	otto.global_position.y = WorldSpace.height_to_scene(_surface) - DUCK * duck
	var closing := t - STEP_BACK_FROM - STEP_BACK_TIME
	if closing < 0.0:
		_car.set_door(t / DOOR_OPEN_TIME)
		return false
	if not otto.is_hidden():
		# За дверцей его уже не видно: дальше он в машине, снаружи его нет.
		otto.stay_indoors(true)
	_car.set_door(1.0 - closing / DOOR_CLOSE_TIME)
	return closing >= DOOR_CLOSE_TIME


## Открывает ворота паркинга, если он есть.
func _open_the_gate() -> void:
	if _garage != null and is_instance_valid(_garage):
		_garage.open_gate()
