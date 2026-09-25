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

## Куда машина уезжает: -1 влево, +1 вправо. С M24b всегда влево — в ворота.
var towards: float = 1.0

var _leaving: bool = false
var _wheels: Array[Node3D] = []
## Середина каждого колеса в его собственных координатах: вокруг неё оно и
## крутится. Начало узла колеса у пака не на оси, а в нуле машины, и поворот
## вокруг начала носил бы колёса кругом по кузову (авторевью M21).
var _hubs := PackedVector3Array()
## Радиус колеса, м: по нему колёса крутятся в лад с ходом, а не буксуют.
var _wheel_radius: float = 0.3


## Ставит машину у ворот паркинга: [param exit_x] — середина выхода, [param
## floor_y] — пол нижнего этажа в координатах правил.
##
## Место — у ворот в левом торце ([method spot]), капотом к ним: машина Otto в
## ROM всегда слева, и уезжает она в ворота (ADR-0038, решение 3).
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
	towards = -1.0
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


## Где машина стоит у ворот: пара «левый край, правый край» по бамперам.
##
## Вплотную к левому торцу нижнего этажа, с зазором [constant GAP] от стены: в
## торце ворота паркинга, и машина уезжает в них (ADR-0038, решение 3). По этой
## полосе раскладка держит шахту в подвал подальше от машины
## ([method clears_shaft]) и ставит выход — место Otto у водительской двери.
static func parked_span(rules: BuildingRules) -> Vector2:
	var bounds := rules.floor_span(rules.floors - 1)
	var left := bounds.x + BuildingShell.WALL_WIDTH + GAP
	return Vector2(left, left + LENGTH)


## Не задевает ли шахта в [param shaft_x] машину у ворот — порталом, с зазором
## [constant GAP].
##
## Раскладка спрашивает до того, как шахте дойти до подвала: машина стоит у
## торца всегда, и уступать место должна шахта, а не она.
static func clears_shaft(rules: BuildingRules, shaft_x: float) -> bool:
	var half_shaft := rules.shaft_width * 0.5 + BuildingShafts.PORTAL_JAMB
	return shaft_x - half_shaft >= parked_span(rules).y + GAP - 0.001


## Где машине встать: у ворот в левом торце ([method parked_span]), если там
## свободно, — раскладка это обещает. Иначе — левее всего, где она по всей длине
## с зазором [constant GAP] не задевает ни шахту, ни внутреннюю стену, ни пролёт
## эскалатора и не выходит за стены. Места нет вовсе — на самом выходе
## [param exit_x].
##
## Проём выхода больше не мешает: выход — это сама машина, Otto садится в неё.
static func spot(exit_x: float, rules: BuildingRules, plan: BuildingPlan) -> float:
	var bottom := rules.floors - 1
	var bounds := rules.floor_span(bottom)
	var busy: Array[Vector2] = []
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
	# Кандидаты — у ворот и вплотную к правому краю каждого занятого места:
	# левее свободного места быть не может.
	var parked := parked_span(rules)
	var candidates: Array[float] = [(parked.x + parked.y) * 0.5]
	for zone in busy:
		candidates.append(zone.y + half)
	candidates.sort()
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
	return exit_x


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
