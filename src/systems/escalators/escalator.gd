class_name Escalator
extends Node3D

## Эскалатор между двумя этажами.
##
## В оригинале на него не заходят по пути: надо встать на площадку у края и
## нажать «вверх» или «вниз» (ADR-0005, пункт 8). Пока везёт — управления нет,
## позицией Otto распоряжается эскалатор, а не физика.
##
## Узел ставится на верхнюю площадку, нижняя и точка перегиба задаются в
## [method setup]. Поездка идёт по тому же пути, который выложен полотном, и
## начинается с того места, где пассажир стоял: иначе его дёргало бы к центру
## площадки, а полотно резало бы перекрытие мимо проёма (найдено авторевью M2).

## Докуда слышен стрёкот полотна, м.
const HUM_REACH: float = 9.0

## Толщина и глубина полотна, м. Тела у полотна нет: везёт эскалатор, а не пол.
const BELT_THICKNESS: float = 0.15
const BELT_DEPTH: float = 0.8

## На сколько полотно утоплено за плоскость игры: пассажир едет перед ним.
const BELT_Z: float = -0.5

## Сколько секунд занимает поездка между площадками.
@export var travel_time: float = 1.1

var _passenger: Otto = null
var _path: PackedVector3Array = PackedVector3Array()
var _progress: float = 0.0
## Перегиб полотна в своих координатах. Пустой — [method setup] не звали.
var _via := Vector3.ZERO
var _has_via: bool = false

var _hum: AudioStreamPlayer3D = null
@onready var _top_pad: Area3D = $TopPad
@onready var _bottom_pad: Area3D = $BottomPad
@onready var _ramp: Node3D = $Ramp


func _ready() -> void:
	_hum = Sounds.source(self, Sounds.ESCALATOR_HUM, HUM_REACH)


func _physics_process(delta: float) -> void:
	# Полотно слышно, только пока кто-то едет: в оригинале эскалатор тоже
	# не гудит сам по себе, а здание и без того шумное.
	Sounds.keep_playing(_hum, _passenger != null)

	if _passenger != null:
		_carry(delta)
		return
	# Наверх зовут с нижней площадки, вниз — с верхней.
	if not _try_board(_bottom_pad, _top_pad, Intent.UP):
		_try_board(_top_pad, _bottom_pad, Intent.DOWN)


## Задаёт геометрию в координатах правил. [param descent] — смещение нижней
## площадки от верхней, [param via] — точка перегиба в проёме перекрытия: через
## неё идут и полотно, и сама поездка, поэтому пассажир проходит сквозь дыру,
## а не сквозь плиту.
func setup(descent: Vector2, via: Vector2) -> void:
	var down := WorldSpace.direction_to_scene(descent)
	_via = WorldSpace.direction_to_scene(via)
	_has_via = true
	_bottom_pad.position = down
	# Полотно — два отрезка, каждый своей коробкой: ровное полотно вдоль
	# ломаной, без растяжения тайла, которого в греев-боксе и нет.
	_lay_belt(Vector3.ZERO, _via)
	_lay_belt(_via, down)


## Везёт ли эскалатор кого-нибудь прямо сейчас.
func is_busy() -> bool:
	return _passenger != null


func _try_board(pad: Area3D, target: Area3D, towards: float) -> bool:
	for body: Node3D in pad.get_overlapping_bodies():
		var rider := body as Otto
		if rider == null or not rider.is_grounded():
			continue
		var intent := rider.vertical_intent()
		if absf(intent) < Intent.PRESS or signf(intent) != towards:
			continue

		_passenger = rider
		_path = _route_from(rider.global_position, target)
		_progress = 0.0
		rider.board_escalator()
		return true
	return false


## Путь поездки: от места, где пассажир стоял, через перегиб к дальней площадке.
##
## Перегиб берётся из полотна, поэтому едут ровно там, где выложено. Без
## [method setup] полотна нет — тогда путь прямой, лишь бы не падать по индексу.
func _route_from(start: Vector3, target: Area3D) -> PackedVector3Array:
	if not _has_via:
		return PackedVector3Array([start, target.global_position])
	return PackedVector3Array([start, to_global(_via), target.global_position])


func _carry(delta: float) -> void:
	_progress = minf(_progress + delta / travel_time, 1.0)
	_passenger.global_position = _point_at(_progress)
	if _progress < 1.0:
		return
	_passenger.leave_escalator()
	_passenger = null


## Точка на ломаной по доле пути: длина считается по самим отрезкам, поэтому
## на изломе скорость не прыгает.
func _point_at(ratio: float) -> Vector3:
	var total := 0.0
	for index in _path.size() - 1:
		total += _path[index].distance_to(_path[index + 1])
	if is_zero_approx(total):
		return _path[_path.size() - 1]

	var travelled := total * ratio
	for index in _path.size() - 1:
		var length := _path[index].distance_to(_path[index + 1])
		if travelled <= length or index == _path.size() - 2:
			var part := travelled / length if length > 0.0 else 1.0
			return _path[index].lerp(_path[index + 1], minf(part, 1.0))
		travelled -= length
	return _path[_path.size() - 1]


## Кладёт отрезок полотна коробкой от [param from] до [param to], в своих
## координатах. Коробка стоит серединой на середине отрезка и повёрнута вдоль
## него: так одна и та же коробка годится и на пологий, и на крутой пролёт.
func _lay_belt(from: Vector3, to: Vector3) -> void:
	var span := to - from
	var length := span.length()
	if is_zero_approx(length):
		return

	var belt := GreyboxLook.box(
		Vector3(length, BELT_THICKNESS, BELT_DEPTH), GreyboxLook.surface(GreyboxLook.ESCALATOR)
	)
	belt.position = (from + to) * 0.5 + Vector3(0.0, 0.0, BELT_Z)
	belt.rotation.z = atan2(span.y, span.x)
	_ramp.add_child(belt)
