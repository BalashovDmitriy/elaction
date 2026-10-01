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

## Выезд на улицу с потоком (ADR-0044, решения 1–2): поднялась по пандусу,
## встала у края мостовой, дождалась просвета, влилась и едет с потоком.
enum Stage { CLIMB, WAIT, MERGE, CRUISE }

## Длина машины, м: по ней она ставится в зазор от проёма и считается уехавшей
## из кадра. [CarModel] приводит к ней любую машину жребия (ADR-0032, решение 7).
const LENGTH: float = CarModel.LENGTH
const GAP: float = 0.36
## Отъезд: трогается с места и разгоняется до [constant SPEED], м/с и м/с².
## С места, а не сразу на полном ходу: машина уезжает, а не исчезает.
const SPEED: float = 9.6
const START_SPEED: float = 1.2
const ACCELERATION: float = 7.2
## У края мостовой машина тормозит, м/с², и встаёт серединой на столько
## левее верха пандуса, м: целиком на улице, носом к полосе.
const BRAKING: float = 8.0
const STOP_PAST_RAMP: float = LENGTH * 0.5 + 0.4
## Съезд в полосу: за сколько метров хода машина переходит с края мостовой на
## середину ближней полосы.
const MERGE_RUN: float = 7.0
## Сколько машина ждёт просвета, прежде чем поток его устроит, решает сам поток
## по своей ситуации ([method StreetTraffic.wait_limit]): выезд не должен
## тянуться дольше, чем держит интерес.
##
## За сколько метров до края мостовой машина смотрит, свободна ли полоса: если
## да — не встаёт, а съезжает с ходу (ADR-0046, решение 3). С этого же места
## мигает поворотник.
const ROLL_IN: float = 3.0
const SIGNAL_AHEAD: float = 6.0
## Как машина качнулась, приняв водителя: наклон, рад, и сколько длится, с.
const ROCK_ANGLE: float = 0.025
const ROCK_TIME: float = 0.5
## Фары и стоп-сигналы: насколько светятся заглушённые и заведённые.
const LIGHTS_OFF: float = 0.15
const LIGHTS_ON: float = 5.0
## Высота фар от земли, м, и их лучи (ADR-0043, решение 5): дальность, м, угол,
## градусы, и насколько луч опущен к дороге, градусы. Лучи светят далеко вперёд
## и ложатся на пандус и улицу до самого затемнения; фар две, по бортам.
const BEAM_HEIGHT: float = 0.5
const BEAM_RANGE: float = 22.0
const BEAM_ANGLE: float = 20.0
const BEAM_DIP: float = 7.0
const BEAM_ENERGY: float = 12.0
## Насколько фары разнесены по бортам, м.
const BEAM_SPREAD: float = 0.62
## Ореол у самой фары: мягкое пятно света вокруг стекла, радиус, м, и яркость.
## Луча-конуса в воздухе нет: геометрией он читался треугольником. Виден в
## воздухе луч только там, где есть объёмный туман, — сам, как настоящий.
const HALO_SIZE: float = 0.55
const HALO_ALPHA: float = 0.55
const HAZE_FOG: float = 2.0
const HALO_SHADER := preload("res://src/levels/headlight_halo.gdshader")
## Докуда слышно машину, м: дверцу, стартер и отъезд — они звучат у машины.
const SOUND_REACH: float = 24.0
## Машина стоит снаружи здания: за плоскостью игры, но перед стеной, чтобы
## Otto проходил перед ней, а не сквозь.
const Z: float = -0.6
## Водительская дверца — деталь модели `DriverDoor`: кузов прорезан по её
## проёму, в проёме — салон `CarInterior` (ADR-0046, решение 1). Начало детали —
## на петле у передней стойки; насколько распахнута открытая, градусы.
const DOOR_SWING: float = 62.0
## Плафон салона — под крышей внутри, в точке `DomeLight` модели: зажигается с
## открытой дверцей, как в любой машине, и высвечивает салон и садящегося. Без
## тени; яркость и дальность, м. Слабый и близкий: светит салон, а не костюм.
const DOME := Color(1.0, 0.82, 0.6)
const DOME_ENERGY: float = 0.9
const DOME_RANGE: float = 1.6
## Правый поворотник (ADR-0046, решение 2): машина съезжает в ближнюю полосу
## улицы — от камеры, по ходу это вправо. Мигает, пока ждёт просвета и съезжает,
## с полупериодом [constant BLINK_HALF], с. Фонари — на дальнем борту, и видно
## мигание по вспышке у каждого: свет ложится на асфальт и кузов.
const INDICATOR := Color(1.0, 0.55, 0.08)
const BLINK_HALF: float = 0.36
const BLINK_GLOW: float = 6.0
const BLINK_ENERGY: float = 2.6
const BLINK_RANGE: float = 2.2

## Куда машина уезжает: -1 влево, +1 вправо. С M24b всегда влево — в ворота.
var towards: float = 1.0
## Поток улицы, в который машина вливается. Нет его — уезжает, как до M24h,
## по пустой улице не останавливаясь.
var traffic: StreetTraffic = null
var stage: Stage = Stage.CLIMB
## Сколько машина уже ждёт просвета, с.
var waited: float = 0.0

var _leaving: bool = false
## Скорость отъезда прямо сейчас, м/с.
var _speed: float = 0.0
## Сколько ещё качается машина, принявшая водителя, с.
var _rocking: float = 0.0
## Свои копии материалов фар и стоп-сигналов: общие из кэша [GreyboxLook] у
## машин всех зданий одни, и заведённая машина зажгла бы фары и следующей.
var _lamps: Array[StandardMaterial3D] = []
var _lamp_glow: Array[float] = []
var _beam: Node3D = null
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
## Водительская дверца модели и насколько она открыта: 0 — закрыта.
var _door: Node3D = null
var _door_open: float = 0.0
## Середина дверцы от середины машины к капоту, м: у неё Otto садится.
var _door_offset: float = LENGTH * 0.08
var _dome: OmniLight3D = null
## Правый поворотник: свой материал фонарей, их вспышки и ход мигания, с.
var _indicator: StandardMaterial3D = null
var _flashes: Array[OmniLight3D] = []
var _blink: float = 0.0
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
	_fit_the_cabin(model)
	_wheels = CarModel.wheels(model)
	_hubs = CarModel.hubs(_wheels)
	_wheel_radius = CarModel.wheel_radius(_wheels, _wheel_radius)


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
			var landing := escalator.landing(rules)
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
	return position.x + towards * _door_offset


## Открывает водительскую дверцу: 0 — закрыта, 1 — распахнута.
func set_door(openness: float) -> void:
	var was := _door_open
	_door_open = clampf(openness, 0.0, 1.0)
	# Дверцу открывают — щелчок ручки и замка (ADR-0052, решение 7).
	if was <= 0.0 and _door_open > 0.0 and is_inside_tree():
		_say(Sounds.CAR_DOOR_OPEN)
	var eased := ease(_door_open, -2.0)
	if _door != null:
		# Дверца лежит от петли к багажнику (-X модели) у борта -Z модели и
		# распахивается наружу: поворот вокруг +Y с минусом уводит её край в -Z.
		_door.rotation.y = -deg_to_rad(DOOR_SWING) * eased
	if _dome != null:
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
## светит двумя лучами вперёд. Лучи без тени, и только на отъезде.
func set_lights(on: bool) -> void:
	if _lamps.is_empty():
		_own_the_lamps()
	for index in _lamps.size():
		var glow := LIGHTS_ON if on else LIGHTS_OFF
		_lamps[index].emission_energy_multiplier = _lamp_glow[index] * glow
	if on and _beam == null:
		_beam = Node3D.new()
		_beam.name = "Beam"
		# Лучи вдоль капота, чуть к дороге: прожектор светит по своей -Z, капот
		# смотрит в towards.
		_beam.position = Vector3(towards * LENGTH * 0.5, BEAM_HEIGHT, 0.0)
		_beam.rotation.y = PI * 0.5 if towards < 0.0 else -PI * 0.5
		add_child(_beam)
		for side: float in [-1.0, 1.0]:
			_beam.add_child(_headlight(side))
	if _beam != null:
		_beam.visible = on


## Одна фара: прожектор без тени, опущенный к дороге, и ореол у стекла.
func _headlight(side: float) -> Node3D:
	var lamp := Node3D.new()
	lamp.position = Vector3(side * BEAM_SPREAD * 0.5, 0.0, 0.0)
	lamp.rotation.x = -deg_to_rad(BEAM_DIP)
	var spot := SpotLight3D.new()
	spot.light_color = CarModel.HEADLIGHT
	spot.light_energy = BEAM_ENERGY
	spot.spot_range = BEAM_RANGE
	spot.spot_angle = BEAM_ANGLE
	# Край луча мягкий: пятно на дороге расплывается, а не обрезано конусом.
	spot.spot_attenuation = 1.2
	spot.spot_angle_attenuation = 0.4
	spot.shadow_enabled = false
	spot.light_volumetric_fog_energy = HAZE_FOG
	lamp.add_child(spot)
	lamp.add_child(halo())
	return lamp


## Ореол у стекла фары: плоское пятно, всегда повёрнутое к камере, ярче к
## середине и мягко сходящее на нет к краю.
static func halo() -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(HALO_SIZE, HALO_SIZE)
	var look := ShaderMaterial.new()
	look.shader = HALO_SHADER
	look.set_shader_parameter(&"tint", Color(CarModel.HEADLIGHT, HALO_ALPHA))
	quad.material = look
	var halo := MeshInstance3D.new()
	halo.name = "Halo"
	halo.mesh = quad
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return halo


## Горят ли фары прямо сейчас.
func lights_on() -> bool:
	return _beam != null and _beam.visible


## Машина тронулась, увозя Otto: мотор, фары и разгон с места.
func drive_away() -> void:
	_leaving = true
	if traffic != null:
		traffic.keep_running()
	_speed = START_SPEED
	set_lights(true)
	_say(Sounds.CAR_AWAY)


## Едет ли машина.
func is_leaving() -> bool:
	return _leaving


## Скорость машины прямо сейчас, м/с.
func speed_now() -> float:
	return _speed


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
	_speed = _speed_now(delta)
	_signal(delta)
	position.x += towards * _speed * delta
	_climb()
	_merge()
	# Колёса катятся вокруг своих осей ([method CarModel.roll]).
	CarModel.roll(_wheels, _hubs, _speed * delta, _wheel_radius)
	var left := position.x - LENGTH * 0.5
	if left + LENGTH < view.position.x or left > view.end.x:
		_leaving = false
		return true
	return false


## Скорость на этот шаг: разгон по пандусу, торможение к краю мостовой,
## стоянка до просвета и ход полосы после.
func _speed_now(delta: float) -> float:
	if traffic == null:
		return minf(_speed + ACCELERATION * delta, SPEED)
	match stage:
		Stage.CLIMB:
			return _climb_speed(delta)
		Stage.WAIT:
			waited += delta
			traffic.hold_back(waited >= traffic.wait_limit())
			if not traffic.is_clear_for(position.x):
				return 0.0
			traffic.hold_back(false)
			traffic.join(self)
			stage = Stage.MERGE
			return minf(START_SPEED, traffic.near_speed())
	return minf(_speed + ACCELERATION * delta, traffic.near_speed())


## Скорость на подъезде к краю мостовой: просвет есть — съезжает с ходу, нет —
## тормозит и встаёт у края.
func _climb_speed(delta: float) -> float:
	var left := _to_the_kerb()
	if left <= ROLL_IN and traffic.is_clear_for(stop_x()):
		# Просвет есть: не вставая, съезжает в полосу с ходу.
		traffic.join(self)
		stage = Stage.MERGE
		return minf(_speed + ACCELERATION * delta, traffic.near_speed())
	if left <= 0.01:
		position.x = stop_x()
		stage = Stage.WAIT
		return 0.0
	var braked := sqrt(2.0 * BRAKING * left)
	return minf(minf(_speed + ACCELERATION * delta, SPEED), braked)


## Сколько машине осталось до края мостовой, м; за ним — меньше нуля.
func _to_the_kerb() -> float:
	return (position.x - stop_x()) * -towards


## Где машина ждёт просвета, по X середины: у края мостовой за верхом пандуса.
## Уезжает она с M24b всегда влево, и верх пандуса левее его начала.
func stop_x() -> float:
	return _ramp_start - _ramp_run - STOP_PAST_RAMP


## Съезд с края мостовой на середину ближней полосы плавной кривой: капот
## поворачивается по ходу, в полосе выпрямляется.
func _merge() -> void:
	if traffic == null or (stage != Stage.MERGE and stage != Stage.CRUISE):
		return
	var run := (stop_x() - position.x) * -towards
	var share := clampf(run / MERGE_RUN, 0.0, 1.0)
	var lane := traffic.near_lane_z()
	position.z = lerpf(Z, lane, smoothstep(0.0, 1.0, share))
	# Наклон кривой — производная smoothstep: 6u(1 - u) на длину съезда.
	var slope := (lane - Z) * 6.0 * share * (1.0 - share) / MERGE_RUN
	rotation.y = atan(slope)
	if share >= 1.0:
		stage = Stage.CRUISE


## Находит в модели [param model] дверцу, плафон и поворотник и меряет борт:
## к ближнему садящийся шагает. Модели без салона — дверцы нет, и Otto садится
## у середины, как раньше.
func _fit_the_cabin(model: Node3D) -> void:
	var box := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var part := (model.transform * _to_model(model, mesh)) * mesh.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	_near_side = box.end.z
	_door = model.find_child("DriverDoor", true, false) as Node3D
	if _door != null:
		var door_mesh := _door as MeshInstance3D
		var span := door_mesh.mesh.get_aabb() if door_mesh != null else AABB()
		# Середина дверцы в системе модели: петля плюс половина её длины к багажнику.
		_door_offset = _door.position.x + span.get_center().x
	_dome = OmniLight3D.new()
	_dome.name = "Dome"
	_dome.light_color = DOME
	_dome.omni_range = DOME_RANGE
	_dome.shadow_enabled = false
	var anchor := model.find_child("DomeLight", true, false) as Node3D
	if anchor != null:
		anchor.add_child(_dome)
	else:
		_dome.position = Vector3(towards * _door_offset, box.end.y - 0.1, 0.0)
		add_child(_dome)
	_hook_the_indicator(model)
	set_door(0.0)


## Правый поворотник модели: свой материал вместо общего из кэша и по вспышке у
## каждого фонаря — по краям его сетки вдоль машины.
func _hook_the_indicator(model: Node3D) -> void:
	var lamps := model.find_child("IndicatorRight", true, false) as MeshInstance3D
	if lamps == null:
		return
	_indicator = GreyboxLook.light(INDICATOR).duplicate() as StandardMaterial3D
	_indicator.emission_energy_multiplier = 0.0
	lamps.material_override = _indicator
	var span := lamps.mesh.get_aabb()
	for x: float in [span.position.x, span.end.x]:
		var flash := OmniLight3D.new()
		flash.light_color = INDICATOR
		flash.omni_range = BLINK_RANGE
		flash.shadow_enabled = false
		flash.visible = false
		flash.position = Vector3(x, span.get_center().y, span.get_center().z)
		lamps.add_child(flash)
		_flashes.append(flash)


## Мигает ли правый поворотник: на подъезде к краю мостовой, пока машина ждёт
## просвета и пока съезжает в полосу.
func is_signalling() -> bool:
	if not _leaving or traffic == null:
		return false
	if stage == Stage.CLIMB:
		return _to_the_kerb() <= SIGNAL_AHEAD
	return stage == Stage.WAIT or stage == Stage.MERGE


## Горит ли фонарь поворотника в этот миг мигания.
func indicator_lit() -> bool:
	return not _flashes.is_empty() and _flashes[0].visible


## Ход мигания: горит первую половину периода, гаснет вторую.
func _signal(delta: float) -> void:
	if _indicator == null:
		return
	var on := false
	if is_signalling():
		_blink += delta
		on = fmod(_blink, BLINK_HALF * 2.0) < BLINK_HALF
		# Реле поворотника щёлкает на каждой вспышке.
		if on and not indicator_lit() and is_inside_tree():
			_say(Sounds.TURN_SIGNAL)
	else:
		_blink = 0.0
	_indicator.emission_energy_multiplier = BLINK_GLOW if on else 0.0
	for flash: OmniLight3D in _flashes:
		flash.visible = on
		flash.light_energy = BLINK_ENERGY


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
	at.y = _floor_y - _ramp_rise * GarageRamp.rise_share(along)
	var z := position.z
	position = WorldSpace.to_scene(at)
	position.z = z
	# Капот смотрит влево, и нос на подъёме задирается: поворот вокруг +Z по
	# часовой, если смотреть с камеры, — минус. Наклон — по касательной к кривой
	# подъёма: на её концах он сходит к нулю плавно, без перелома.
	rotation.z = -atan(_ramp_rise / _ramp_run * GarageRamp.rise_slope(along))


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
