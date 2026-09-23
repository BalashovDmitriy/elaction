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
## пол нижнего этажа в координатах правил.
##
## Место — ближайшее к выходу, где машина по всей длине не заходит ни на проём
## выхода, ни на шахту: на кадрах M20 седан, поставленный на фиксированном зазоре,
## загораживал портал соседней шахты. Уезжает в ближнюю к себе сторону здания —
## в дальнюю ехала бы через всё здание.
func park(exit_x: float, floor_y: float, rules: BuildingRules, plan: BuildingPlan) -> void:
	name = "ExitCar"
	var x := spot(exit_x, rules, plan)
	towards = -1.0 if x < exit_x else 1.0
	position = WorldSpace.to_scene(Vector2(x, floor_y))
	position.z = Z
	# Модель стоит колёсами в своём нуле, капотом в +X; в другую сторону она
	# разворачивается целиком.
	var model := CarModel.build()
	if towards < 0.0:
		model.rotation.y = PI
	add_child(model)


## Где машине встать: середина ближайшего к выходу места на нижнем этаже, где
## она по всей длине с зазором [constant GAP] не задевает ни проём выхода, ни
## шахту и не выходит за стены. Места нет — у проёма, как было до M20.
static func spot(exit_x: float, rules: BuildingRules, plan: BuildingPlan) -> float:
	var bottom := rules.floors - 1
	var bounds := rules.floor_span(bottom)
	var busy: Array[Vector2] = [
		Vector2(exit_x - BuildingShell.EXIT_WIDTH * 0.5, exit_x + BuildingShell.EXIT_WIDTH * 0.5)
	]
	var half_shaft := rules.shaft_width * 0.5 + BuildingShafts.PORTAL_JAMB
	for shaft in plan.shafts:
		if shaft.top <= bottom and bottom <= shaft.bottom:
			busy.append(Vector2(shaft.x - half_shaft, shaft.x + half_shaft))
	var half := LENGTH * 0.5 + GAP
	# Кандидаты — вплотную к краю каждого занятого места с обеих сторон: ближе
	# к выходу свободного места быть не может.
	var candidates: Array[float] = []
	for zone in busy:
		candidates.append(zone.x - half)
		candidates.append(zone.y + half)
	candidates.sort_custom(
		func(a: float, b: float) -> bool: return absf(a - exit_x) < absf(b - exit_x)
	)
	for x: float in candidates:
		if x - half < bounds.x + BuildingShell.WALL_WIDTH - 0.001:
			continue
		if x + half > bounds.y - BuildingShell.WALL_WIDTH + 0.001:
			continue
		var clear := true
		for zone in busy:
			if x + half > zone.x + 0.001 and x - half < zone.y - 0.001:
				clear = false
				break
		if clear:
			return x
	return exit_x + BuildingShell.EXIT_WIDTH * 0.5 + half


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
