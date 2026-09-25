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
## Отъезд: трогается с места и разгоняется до [constant SPEED], м/с и м/с².
## С места, а не сразу на полном ходу: машина уезжает, а не исчезает.
const SPEED: float = 9.6
const START_SPEED: float = 1.2
const ACCELERATION: float = 7.2
## Водительская дверь — на столько от середины машины к капоту, м: над передним
## сиденьем. У неё Otto садится в машину (ADR-0038, решение 4).
const DOOR_OFFSET: float = LENGTH * 0.08
## Как машина качнулась, приняв водителя: наклон, рад, и сколько длится, с.
const ROCK_ANGLE: float = 0.025
const ROCK_TIME: float = 0.5
## Фары и стоп-сигналы: насколько светятся заглушённые и заведённые.
const LIGHTS_OFF: float = 0.15
const LIGHTS_ON: float = 5.0
## Высота фар от земли, м, и их луч: дальность, м, и угол, градусы.
const BEAM_HEIGHT: float = 0.5
const BEAM_RANGE: float = 9.0
const BEAM_ANGLE: float = 28.0
const BEAM_ENERGY: float = 4.0
## Докуда слышно машину, м: дверцу, стартер и отъезд — они звучат у машины.
const SOUND_REACH: float = 24.0
## Машина стоит снаружи здания: за плоскостью игры, но перед стеной, чтобы
## Otto проходил перед ней, а не сквозь.
const Z: float = -0.6
## Водительская дверца. У моделей пака дверь не отдельной деталью, поэтому на
## посадку поверх кузова распахивается своя створка — тонкая панель в краске
## кузова со стеклом, на петлях у передней стойки. Видна, пока открыта: закрытую
## рисует сама модель. Длина — доля длины машины; низ панели, линия окна и верх
## стекла — доли высоты кузова.
const DOOR_LENGTH: float = LENGTH * 0.26
const DOOR_SILL: float = 0.24
const DOOR_BELT: float = 0.6
const DOOR_TOP: float = 0.9
const DOOR_THICKNESS: float = 0.04
## Насколько распахнута открытая дверца, градусы.
const DOOR_SWING: float = 62.0
const DOOR_GLASS := Color(0.08, 0.1, 0.13)
## Плафон салона: зажигается с открытой дверцей, как в любой машине, и
## высвечивает садящегося и дверцу — у ворот темно. Без тени; яркость и
## дальность, м.
const DOME := Color(1.0, 0.82, 0.6)
const DOME_ENERGY: float = 1.6
const DOME_RANGE: float = 2.6

## Куда машина уезжает: -1 влево, +1 вправо. С M24b всегда влево — в ворота.
var towards: float = 1.0

var _leaving: bool = false
## Скорость отъезда прямо сейчас, м/с.
var _speed: float = 0.0
## Сколько ещё качается машина, принявшая водителя, с.
var _rocking: float = 0.0
## Свои копии материалов фар и стоп-сигналов: общие из кэша [GreyboxLook] у
## машин всех зданий одни, и заведённая машина зажгла бы фары и следующей.
var _lamps: Array[StandardMaterial3D] = []
var _lamp_glow: Array[float] = []
var _beam: SpotLight3D = null
var _wheels: Array[Node3D] = []
## Середина каждого колеса в его собственных координатах: вокруг неё оно и
## крутится. Начало узла колеса у пака не на оси, а в нуле машины, и поворот
## вокруг начала носил бы колёса кругом по кузову (авторевью M21).
var _hubs := PackedVector3Array()
## Радиус колеса, м: по нему колёса крутятся в лад с ходом, а не буксуют.
var _wheel_radius: float = 0.3
## Пандус за воротами ([GarageGate]): где начинается подъём, в плоскости правил,
## его длина и высота, м. По нему машина уезжает наверх, а не сквозь землю.
var _ramp_start: float = 0.0
var _ramp_run: float = 0.0
var _ramp_rise: float = 0.0
## Пол, на котором машина стоит, в плоскости правил.
var _floor_y: float = 0.0
## Петля водительской дверцы и насколько дверца открыта: 0 — закрыта.
var _door_hinge: Node3D = null
var _door_open: float = 0.0
var _dome: OmniLight3D = null
## Ближний к камере борт кузова, Z в системе машины: к нему Otto шагает на посадке.
var _near_side: float = 0.0


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
	_floor_y = floor_y
	_ramp_start = rules.floor_span(rules.floors - 1).x - GarageGate.RAMP_APRON
	_ramp_run = GarageGate.RAMP_RUN
	_ramp_rise = rules.floor_height
	position = WorldSpace.to_scene(Vector2(x, floor_y))
	position.z = Z
	# Модель стоит колёсами в своём нуле, капотом в +X; в другую сторону она
	# разворачивается целиком.
	var model := CarModel.build(choice)
	if towards < 0.0:
		model.rotation.y = PI
	add_child(model)
	_hang_the_door(model, CarModel.PAINTS[choice.paint])
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


## Где водительская дверь, по горизонтали в плоскости правил: там Otto садится.
func door_x() -> float:
	return position.x + towards * DOOR_OFFSET


## Открывает водительскую дверцу: 0 — закрыта (и не видна), 1 — распахнута.
func set_door(openness: float) -> void:
	_door_open = clampf(openness, 0.0, 1.0)
	if _door_hinge == null:
		return
	_door_hinge.visible = _door_open > 0.0
	# Свободный край дверцы — к багажнику, и распахивается она к камере (+Z):
	# поворот вокруг +Y уводит +X в -Z, поэтому знак — по [member towards].
	var eased := ease(_door_open, -2.0)
	_door_hinge.rotation.y = towards * deg_to_rad(DOOR_SWING) * eased
	_dome.visible = _door_open > 0.0
	_dome.light_energy = DOME_ENERGY * eased


## Насколько открыта водительская дверца.
func door_openness() -> float:
	return _door_open


## Где садящийся встаёт в глубину, Z сцены: у ближнего борта, в проёме дверцы.
func seat_z() -> float:
	return global_position.z + _near_side - 0.18


## Otto сел: машина качнулась под ним и хлопнула дверцей.
func take_the_driver() -> void:
	_rocking = ROCK_TIME
	_say(Sounds.CAR_DOOR)


## Стартер заводит мотор, и загораются фары.
func start_engine() -> void:
	set_lights(true)
	_say(Sounds.CAR_START)


## Горят ли фары: заглушённая машина стоит с тёмными, заведённая зажигает их и
## светит лучом вперёд. Луч — один источник без тени, и только на отъезде.
func set_lights(on: bool) -> void:
	if _lamps.is_empty():
		_own_the_lamps()
	for index in _lamps.size():
		var glow := LIGHTS_ON if on else LIGHTS_OFF
		_lamps[index].emission_energy_multiplier = _lamp_glow[index] * glow
	if on and _beam == null:
		_beam = SpotLight3D.new()
		_beam.name = "Beam"
		_beam.light_color = CarModel.HEADLIGHT
		_beam.light_energy = BEAM_ENERGY
		_beam.spot_range = BEAM_RANGE
		_beam.spot_angle = BEAM_ANGLE
		_beam.shadow_enabled = false
		# Луч вдоль капота: прожектор светит по своей -Z, капот смотрит в towards.
		_beam.position = Vector3(towards * LENGTH * 0.5, BEAM_HEIGHT, 0.0)
		_beam.rotation.y = PI * 0.5 if towards < 0.0 else -PI * 0.5
		add_child(_beam)
	if _beam != null:
		_beam.visible = on


## Горят ли фары прямо сейчас.
func lights_on() -> bool:
	return _beam != null and _beam.visible


## Машина тронулась, увозя Otto: мотор, фары и разгон с места.
func drive_away() -> void:
	_leaving = true
	_speed = START_SPEED
	set_lights(true)
	_say(Sounds.CAR_AWAY)


## Едет ли машина.
func is_leaving() -> bool:
	return _leaving


## Качает машину, принявшую водителя: затухающий наклон вдоль кузова.
func settle(delta: float) -> void:
	if _rocking <= 0.0:
		return
	_rocking = maxf(_rocking - delta, 0.0)
	var left := _rocking / ROCK_TIME
	rotation.z = sin((1.0 - left) * TAU * 2.0) * ROCK_ANGLE * left


## Везёт машину. Возвращает true в тот кадр, когда она уехала из кадра
## [param view] — до границы здания машина ползла бы впятеро дольше. Кадр
## уровень даёт по правилам ([method SideCamera.rule_view]), а не сглаженный
## кадр игрока: сдача здания — событие партии и обязана идти от физики.
func advance(delta: float, view: Rect2) -> bool:
	if not _leaving:
		return false
	_speed = minf(_speed + ACCELERATION * delta, SPEED)
	position.x += towards * _speed * delta
	_climb()
	# Колёса катятся вокруг своих осей: угол — путь, делённый на радиус. Капот
	# в +X, и колесо, катящееся вперёд, идёт по часовой, если смотреть с +Z, —
	# это минус вокруг +Z. Модель, развёрнутая назад, катит их в своей системе
	# вперёд, поэтому знак один.
	var spin := Basis(Vector3.BACK, -_speed * delta / _wheel_radius)
	for index in _wheels.size():
		var hub := _hubs[index]
		_wheels[index].transform *= Transform3D(spin, hub - spin * hub)
	var left := position.x - LENGTH * 0.5
	if left + LENGTH < view.position.x or left > view.end.x:
		_leaving = false
		return true
	return false


## Вешает водительскую дверцу на петлю у передней стойки: панель в краске
## [param paint] и стекло над ней. Размеры — по габариту модели [param model].
func _hang_the_door(model: Node3D, paint: Color) -> void:
	var box := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var part := (model.transform * _to_model(model, mesh)) * mesh.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	_near_side = box.end.z
	var height := box.size.y
	_door_hinge = Node3D.new()
	_door_hinge.name = "DoorHinge"
	# Петля — у передней стойки: от середины дверцы к капоту на половину её длины.
	var front := towards * (DOOR_OFFSET + DOOR_LENGTH * 0.5)
	_door_hinge.position = Vector3(front, 0.0, _near_side + DOOR_THICKNESS * 0.5 + 0.01)
	add_child(_door_hinge)
	var reach := -towards * DOOR_LENGTH * 0.5
	var panel_h := height * (DOOR_BELT - DOOR_SILL)
	var panel := GreyboxLook.box(
		Vector3(DOOR_LENGTH, panel_h, DOOR_THICKNESS), GreyboxLook.polished(paint)
	)
	panel.name = "DoorPanel"
	panel.position = Vector3(reach, height * DOOR_SILL + panel_h * 0.5, 0.0)
	_door_hinge.add_child(panel)
	var glass_h := height * (DOOR_TOP - DOOR_BELT)
	var glass := GreyboxLook.box(
		Vector3(DOOR_LENGTH * 0.86, glass_h, DOOR_THICKNESS * 0.5), GreyboxLook.polished(DOOR_GLASS)
	)
	glass.name = "DoorGlass"
	glass.position = Vector3(reach * 1.1, height * DOOR_BELT + glass_h * 0.5, 0.0)
	_door_hinge.add_child(glass)
	_dome = OmniLight3D.new()
	_dome.name = "Dome"
	_dome.light_color = DOME
	_dome.omni_range = DOME_RANGE
	_dome.shadow_enabled = false
	_dome.position = Vector3(towards * DOOR_OFFSET, height * 0.8, _near_side + 0.3)
	add_child(_dome)
	set_door(0.0)


## Трансформ меша [param mesh] в системе модели [param model].
static func _to_model(model: Node3D, mesh: Node3D) -> Transform3D:
	var chain := Transform3D.IDENTITY
	var node: Node = mesh
	while node != null and node != model:
		var spatial := node as Node3D
		if spatial != null:
			chain = spatial.transform * chain
		node = node.get_parent()
	return chain


## Ставит машину на пандус за воротами: высота по середине машины, наклон — по
## подъёму. Пандус идёт влево от площадки у ворот, выше него — улица, ровно.
func _climb() -> void:
	if _ramp_run <= 0.0:
		return
	var along := clampf((_ramp_start - position.x) / _ramp_run, 0.0, 1.0)
	var at := WorldSpace.to_plane(position)
	at.y = _floor_y - _ramp_rise * along
	var z := position.z
	position = WorldSpace.to_scene(at)
	position.z = z
	# Капот смотрит влево, и нос на подъёме задирается: поворот вокруг +Z по
	# часовой, если смотреть с камеры, — минус.
	var slope := atan2(_ramp_rise, _ramp_run)
	rotation.z = -slope if along > 0.0 and along < 1.0 else 0.0


## Звук на месте машины: позиционный источник, который уезжает вместе с ней.
func _say(sound: String) -> void:
	var player := Sounds.source(self, sound, SOUND_REACH)
	player.finished.connect(player.queue_free)
	player.play()


## Заводит свои копии материалов фар и стоп-сигналов вместо общих из кэша.
func _own_the_lamps() -> void:
	var shared: Array[StandardMaterial3D] = [
		GreyboxLook.light(CarModel.HEADLIGHT), GreyboxLook.light(CarModel.TAILLIGHT)
	]
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in mesh.get_surface_override_material_count():
			var material := mesh.get_surface_override_material(surface) as StandardMaterial3D
			if material == null or not shared.has(material):
				continue
			var own := material.duplicate() as StandardMaterial3D
			mesh.set_surface_override_material(surface, own)
			_lamps.append(own)
			_lamp_glow.append(material.emission_energy_multiplier)
