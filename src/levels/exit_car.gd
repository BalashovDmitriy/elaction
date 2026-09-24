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
## из кадра. [CarModel] приводит к ней любую машину жребия (ADR-0032, решение 7).
const LENGTH: float = CarModel.LENGTH
const GAP: float = 0.36
const SPEED: float = 9.6
## Машина стоит снаружи здания: за плоскостью игры, но перед стеной, чтобы
## Otto проходил перед ней, а не сквозь.
const Z: float = -0.6

## Куда машина уезжает: -1 влево, +1 вправо. Та же сторона, с которой она стоит.
var towards: float = 1.0

var _leaving: bool = false
var _wheels: Array[Node3D] = []
## Середина каждого колеса в его собственных координатах: вокруг неё оно и
## крутится. Начало узла колеса у пака не на оси, а в нуле машины, и поворот
## вокруг начала носил бы колёса кругом по кузову (авторевью M21).
var _hubs := PackedVector3Array()
## Радиус колеса, м: по нему колёса крутятся в лад с ходом, а не буксуют.
var _wheel_radius: float = 0.3


## Ставит машину у проёма выхода: [param exit_x] — его середина, [param floor_y] —
## пол нижнего этажа в координатах правил.
##
## Место — ближайшее к выходу свободное ([method spot]): на кадрах M20 седан,
## поставленный на фиксированном зазоре, загораживал портал соседней шахты.
## Уезжает от выхода — в ту сторону, где
## стоит: мимо проёма, в который вошёл Otto, она не едет.
##
## [param choice] — какая машина и какого цвета ([method CarModel.choose]).
func park(
	exit_x: float,
	floor_y: float,
	rules: BuildingRules,
	plan: BuildingPlan,
	choice: CarModel.Choice = CarModel.Choice.new()
) -> void:
	name = "ExitCar"
	var x := spot(exit_x, rules, plan)
	towards = -1.0 if x < exit_x else 1.0
	position = WorldSpace.to_scene(Vector2(x, floor_y))
	position.z = Z
	# Модель стоит колёсами в своём нуле, капотом в +X; в другую сторону она
	# разворачивается целиком.
	var model := CarModel.build(choice)
	if towards < 0.0:
		model.rotation.y = PI
	add_child(model)
	_wheels = CarModel.wheels(model)
	_hubs = PackedVector3Array()
	for wheel in _wheels:
		var mesh := wheel as MeshInstance3D
		var box := mesh.mesh.get_aabb() if mesh != null else AABB()
		_hubs.append(box.get_center())
		if mesh != null:
			_wheel_radius = maxf(box.size.y * 0.5, 0.05)


## Где машине встать: середина ближайшего к выходу места на нижнем этаже, где
## она по всей длине с зазором [constant GAP] не задевает ни проём выхода, ни
## шахту, ни внутреннюю стену, ни пролёт эскалатора и не выходит за стены.
## Места нет — вплотную справа от проёма.
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
	# Стена глухая во всю глубину коридора и комнаты, а эскалатор с этажа выше
	# спускается сюда пролётом от проёма до площадки: машина прошла бы сквозь них.
	for wall in plan.walls:
		if wall.floor_index == bottom:
			busy.append(wall.band(rules))
	for escalator in plan.escalators:
		if escalator.floor_index == bottom - 1:
			var landing := escalator.x + escalator.towards * rules.escalator_run
			var gap := escalator.gap(rules)
			busy.append(Vector2(minf(gap.x, landing), maxf(gap.y, landing)))
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
## [param view] — до границы здания машина ползла бы впятеро дольше. Кадр
## уровень даёт по правилам ([method SideCamera.rule_view]), а не сглаженный
## кадр игрока: сдача здания — событие партии и обязана идти от физики.
func advance(delta: float, view: Rect2) -> bool:
	if not _leaving:
		return false
	position.x += towards * SPEED * delta
	# Колёса катятся вокруг своих осей: угол — путь, делённый на радиус. Капот
	# в +X, и колесо, катящееся вперёд, идёт по часовой, если смотреть с +Z, —
	# это минус вокруг +Z. Модель, развёрнутая назад, катит их в своей системе
	# вперёд, поэтому знак один.
	var spin := Basis(Vector3.BACK, -SPEED * delta / _wheel_radius)
	for index in _wheels.size():
		var hub := _hubs[index]
		_wheels[index].transform *= Transform3D(spin, hub - spin * hub)
	var left := position.x - LENGTH * 0.5
	if left + LENGTH < view.position.x or left > view.end.x:
		_leaving = false
		return true
	return false
