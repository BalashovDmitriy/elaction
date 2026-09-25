class_name ExitBoarding
extends RefCounted

## Выход из здания: Otto садится в машину и уезжает (ADR-0038, решение 4).
##
## До машины он идёт сам. У водительской двери со всеми документами управление
## забирают: Otto делает последний шаг к двери, садится — машина качнулась и
## хлопнула дверцей, — ворота гаража открываются, стартер заводит мотор,
## загораются фары, и машина уезжает, разгоняясь. Здание сдано, когда она ушла из кадра: следующее
## собирается после отъезда, а не в тот же кадр (ADR-0011, пункт 14).
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

enum Phase { WAITING, STEPPING_IN, SEATING, STARTING, LEAVING, GONE }

## Ширина места у водительской двери, где Otto садится, м. Шире шага бота за
## кадр ([constant OttoBot.REACHED] и его последний шаг), но уже машины: садятся
## у двери, а не у багажника.
const DOOR_REACH: float = 0.9
## Насколько ступни могут быть выше или ниже пола подвала, м: садится стоящий,
## а не пролетающий мимо в прыжке.
const FOOTING: float = 0.2
## Сколько Otto садится, с: от хлопка дверцы до стартера.
const SEAT_TIME: float = 0.5
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


func _init(car: ExitCar, surface: float, garage: Garage = null) -> void:
	_car = car
	_surface = surface
	_garage = garage


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
				phase = Phase.STEPPING_IN
		Phase.STEPPING_IN:
			if _step_to_the_door(otto, delta):
				otto.stay_indoors(true)
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


## Открывает ворота паркинга, если он есть.
func _open_the_gate() -> void:
	if _garage != null and is_instance_valid(_garage):
		_garage.open_gate()
