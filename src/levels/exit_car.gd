class_name ExitCar
extends Node3D

## Машина у выхода: ею оригинал заканчивает здание (ADR-0011, пункт 14).
##
## Стоит рядом с проёмом выхода на полу нижнего этажа, за плоскостью игры: она
## снаружи здания, и заходить на неё Otto не может — это вид, не тело. Уезжает,
## увозя Otto; следующее здание собирается после отъезда, а не в тот же кадр.
##
## Своим узлом с M18d: уровень перерос предел строк, а у машины своё состояние —
## куда стоит и едет ли, — которое уровню знать незачем.

## Длина машины, м: по ней она ставится в зазор от проёма и считается уехавшей
## из кадра. Седан собирает [CarModel] ровно такой длины (ADR-0031, решение 4).
const LENGTH: float = CarModel.LENGTH
const GAP: float = 0.36
const SPEED: float = 9.6
## Машина стоит снаружи здания: за плоскостью игры, но перед стеной, чтобы
## Otto проходил перед ней, а не сквозь.
const Z: float = -0.6

## Куда машина уезжает: -1 влево, +1 вправо. Та же сторона, с которой она стоит.
var towards: float = 1.0

var _leaving: bool = false


## Ставит машину у проёма выхода: [param exit_x] — его середина, [param floor_y] —
## пол нижнего этажа в координатах правил, [param width] — ширина здания.
##
## Уезжает в ближнюю сторону: там же и стоит. В дальнюю машина ехала бы через
## всё здание, и «уехал» растянулось бы на пять секунд вместо одной.
func park(exit_x: float, floor_y: float, width: float) -> void:
	name = "ExitCar"
	towards = -1.0 if exit_x < width * 0.5 else 1.0
	var x := exit_x + towards * (BuildingShell.EXIT_WIDTH * 0.5 + GAP + LENGTH * 0.5)
	position = WorldSpace.to_scene(Vector2(x, floor_y))
	position.z = Z
	# Модель стоит колёсами в своём нуле, капотом в +X; в другую сторону она
	# разворачивается целиком.
	var model := CarModel.build()
	if towards < 0.0:
		model.rotation.y = PI
	add_child(model)


## Otto сел в машину: она трогается.
func drive_away() -> void:
	_leaving = true
	Sounds.play(Sounds.CAR_AWAY)


## Везёт машину. Возвращает true в тот кадр, когда она уехала из кадра
## [param view] — кадр и есть то, что видит игрок, а до границы здания машина
## ползла бы впятеро дольше.
func advance(delta: float, view: Rect2) -> bool:
	if not _leaving:
		return false
	position.x += towards * SPEED * delta
	var left := position.x - LENGTH * 0.5
	if left + LENGTH < view.position.x or left > view.end.x:
		_leaving = false
		return true
	return false
