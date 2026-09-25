class_name Helicopter
extends Node3D

## Вертолёт вступления: привозит Otto на крышу (ADR-0038, решение 1).
##
## Вид, а не тело: коллизий у него нет, в бою он не участвует. Прилетает слева,
## зависает, спускает трос с лебёдки над дверью, по команде выбирает трос и
## уходит вправо и вверх, а за кадром убирает себя сам. Когда что делать, решает
## [RoofArrival]; вертолёт умеет только лететь, висеть и опускать трос.
##
## Модель — Helicopter, kazuma, CC0 (poly.pizza): один меш из четырёх
## поверхностей, и четвёртая — несущий винт. Он вынимается в свой меш и крутится
## кодом. Нуль узла — под осью винта на уровне полозьев, в середине корпуса по
## глубине: так «зависнуть над точкой» — это просто поставить узел в неё.

enum Phase { ARRIVING, HOVERING, LEAVING }

const MODEL := preload("res://assets/models/aircraft/helicopter.glb")

## Длина по корпусу от носа до хвоста, м. Лёгкий вертолёт — девять метров с
## небольшим; модель приводится к ней одним масштабом.
const LENGTH: float = 8.6

## Какая поверхность меша — несущий винт и куда у модели смотрит нос: в сторону
## +Y меша — 1, в сторону −Y — −1 (модель экспортирована осью Z вверх, и длина
## идёт по Y меша).
const ROTOR_SURFACE: int = 3
const NOSE_MESH_Y: float = -1.0

## Окраска. У модели корпус почти чёрный, и ночью над крышей от вертолёта
## оставались одни огни: корпус перекрашен в тёмный металлик, который ловит
## неон и огни города. Остекление светится изнутри приборами — так кабину видно
## в темноте, и вертолёт читается машиной с людьми, а не силуэтом.
const HULL_SURFACE: int = 0
const GLASS_SURFACE: int = 2
const HULL_COLOR := Color(0.34, 0.37, 0.44)
const GLASS_COLOR := Color(0.05, 0.07, 0.09)
const GLASS_GLOW := Color(0.45, 0.7, 0.75)
const GLASS_GLOW_ENERGY: float = 0.3
const ROTOR_COLOR := Color(0.5, 0.5, 0.52)

## Насколько винт в кадре шире модели. У модели он короче корпуса вдвое, а у
## настоящего лёгкого вертолёта диск почти в длину фюзеляжа: так силуэт читается
## вертолётом, а не игрушкой.
const ROTOR_SPREAD: float = 1.45

## Обороты винта, рад/с. Не настоящие — на них винт стоял бы строботом на
## частоте кадра, — а такие, чтобы лопасти читались движением.
const ROTOR_SPEED: float = 21.0

## Корпус стоит за плоскостью игры: ближний борт с дверью — у самой плоскости,
## а стрела лебёдки выносит трос ровно в неё, туда, где висит Otto.
const DEPTH_Z: float = -1.15

## Полёт: откуда прилетает — столько метров левее и выше точки зависания — и за
## сколько секунд. Кривая хода без рывка на входе: влетает он на крейсерской
## скорости и гасит её к точке ([method _arrival_progress]).
const ARRIVAL_DISTANCE: float = 22.0
const ARRIVAL_RISE: float = 1.8
const ARRIVAL_TIME: float = 2.3

## Как вертолёт уходит: разгон, предел скорости и набор высоты на метр пути, м/с².
const LEAVE_ACCELERATION: float = 7.0
const LEAVE_SPEED: float = 17.0
const LEAVE_CLIMB: float = 0.45
## Сколько метров пути до того, как он убирает себя: кадр в ширину 23.5 м, и
## вертолёт уходит за его край с запасом при любом месте зависания.
const GONE_AFTER: float = 38.0

## Наклон по ускорению, как у настоящего: разгон — носом вниз, торможение —
## носом вверх. [constant DRAG] — сопротивление на крейсерской скорости: без него
## летящий ровно не клонился бы вовсе.
const DRAG: float = 0.35
const TILT_GAIN: float = 0.75
## Предел наклона — 10°, в радианах: функции в константу GDScript не пускает.
## На нём же держится запас над техникой крыши ([method clear_height]): хвост
## наклонённого корпуса опускается на 0.9 м, и при 14° запас рос бы вдвое.
const TILT_MAX: float = 0.1745
const TILT_EASE: float = 5.0

## Запас над техникой крыши, м, и крутизна подъёма к ней: путь не прыгает вверх
## над башней, а заранее набирает высоту — метр на полтора пройденных.
const CLEARANCE: float = 0.4
const CLEAR_SLOPE: float = 0.65

## Ободок корпуса: холодный отсвет по краям силуэта. Хвостовая балка ночью
## иначе пропадает — на неё не падает ни свет кабины, ни прожектор. Это второй
## проход меша, а не источник: ни теней, ни света в бюджете кадра.
const RIM_COLOR := Color(0.5, 0.62, 0.85)
const RIM_POWER: float = 2.2
const RIM_STRENGTH: float = 0.55
const RIM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled;

uniform vec4 rim_color : source_color;
uniform float rim_power = 2.0;
uniform float rim_strength = 0.5;

void fragment() {
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	ALBEDO = rim_color.rgb * edge * rim_strength;
}
"""

## Висение не бывает неподвижным: вертолёт чуть ходит вверх-вниз.
const BOB_HEIGHT: float = 0.06
const BOB_RATE: float = 1.7

## Трос: толщина, цвет и с какой скоростью лебёдка его отдаёт и выбирает, м/с.
const ROPE_RADIUS: float = 0.022
const ROPE_COLOR := Color(0.36, 0.34, 0.3)
const ROPE_SPEED: float = 11.0

## Огни: зелёный бортовой — на ближнем борту (нос смотрит вправо, к камере —
## правый борт), красный маячок сверху и снизу, белая вспышка на хвосте.
const NAV_GREEN := Color(0.25, 1.0, 0.45)
const BEACON_RED := Color(1.0, 0.12, 0.08)
const STROBE_WHITE := Color(1.0, 1.0, 1.0)
const LIGHT_SIZE: float = 0.07
## Маячок мигает раз в секунду, вспышка — двойная раз в полторы.
const BEACON_PERIOD: float = 1.0
const STROBE_PERIOD: float = 1.5
const FLASH: float = 0.07

## Прожектор под носом: пятно на крыше, пока вертолёт висит. Без теней — он
## горит пару секунд, и платить за тень незачем.
const SEARCH_ENERGY: float = 10.0
const SEARCH_RANGE: float = 11.0
const SEARCH_ANGLE: float = 20.0
const SEARCH_COLOR := Color(0.92, 0.95, 1.0)

## Свет кабины из открытой двери: тёплый, неяркий, на пару метров.
const CABIN_COLOR := Color(1.0, 0.78, 0.5)
const CABIN_ENERGY: float = 1.6
const CABIN_RANGE: float = 3.4

## Гул слышен на столько метров. Файла звука пока нет — звук подбирается, и
## вертолёт молчит, пока его нет ([method _start_engine]).
const ENGINE_REACH: float = 45.0

var _phase: Phase = Phase.ARRIVING
var _time: float = 0.0
var _hover := Vector3.ZERO
var _from := Vector3.ZERO
## Скорость, которую видно по ходу, м/с: по ней клонится корпус и с неё
## начинается уход — оборванный посреди прилёта не останавливается рывком.
var _velocity := Vector3.ZERO
var _tilt: float = 0.0
var _left_from := Vector3.ZERO
var _leave_in: float = 0.0
var _leaving_set: bool = false

var _body: Node3D = null
var _rotor: MeshInstance3D = null
var _hook := Vector3.ZERO
var _rope: MeshInstance3D = null
var _rope_length: float = 0.0
var _rope_wanted: float = 0.0
var _beacons: Array[Node3D] = []
var _strobe: Node3D = null
var _search: SpotLight3D = null
var _cabin: OmniLight3D = null
var _engine: AudioStreamPlayer3D = null
## Габарит корпуса со стрелой лебёдки и габарит диска винта в координатах узла,
## при нулевом наклоне; и они же со всеми наклонами до [constant TILT_MAX].
var _hull_local := AABB()
var _rotor_local := AABB()
var _hull_reach := AABB()
var _rotor_reach := AABB()
## Техника крыши, над которой надо пройти: габариты в координатах сцены.
var _obstacles: Array[AABB] = []


func _init() -> void:
	name = "Helicopter"
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_dress()


## Начинает прилёт: вертолёт появляется за левым краем и идёт к [param hover] —
## точке под осью винта на уровне полозьев, в координатах сцены.
##
## Точка поднимается над техникой крыши, если та выше ([method safe_hover]).
func fly_in(hover: Vector3) -> void:
	_hover = safe_hover(hover)
	_from = _hover + Vector3(-ARRIVAL_DISTANCE, ARRIVAL_RISE, 0.0)
	_phase = Phase.ARRIVING
	_time = 0.0
	position = _from
	_velocity = Vector3.ZERO
	_start_engine()


## Что на крыше мешает полёту: габариты в координатах сцены. Путь прилёта,
## висение и уход идут над ними с запасом [constant CLEARANCE].
func avoid(obstacles: Array[AABB]) -> void:
	_obstacles = obstacles


## Точка висения над [param hover], поднятая над техникой крыши, если нужно.
func safe_hover(hover: Vector3) -> Vector3:
	return Vector3(hover.x, maxf(hover.y, clear_height(hover.x)), DEPTH_Z)


## Ниже какой высоты полозьям нельзя опускаться, когда ось винта над
## [param x], — по всей технике крыши, при любом наклоне корпуса и с запасом.
## Над соседями высота спадает склоном [constant CLEAR_SLOPE]: путь набирает
## её заранее. Мешать нечему — минус бесконечность.
func clear_height(x: float) -> float:
	var lowest := -INF
	for obstacle: AABB in _obstacles:
		for reach: AABB in [_hull_reach, _rotor_reach]:
			var near := DEPTH_Z + reach.position.z - CLEARANCE
			var far := DEPTH_Z + reach.end.z + CLEARANCE
			if obstacle.end.z < near or obstacle.position.z > far:
				continue
			var left := x + reach.position.x - CLEARANCE
			var right := x + reach.end.x + CLEARANCE
			var gap := maxf(maxf(obstacle.position.x - right, left - obstacle.end.x), 0.0)
			var needed := obstacle.end.y + CLEARANCE - reach.position.y - gap * CLEAR_SLOPE
			lowest = maxf(lowest, needed)
	return lowest


## Насколько верх вертолёта с винтом выше полозьев при любом наклоне, м.
func top_above_skids() -> float:
	return maxf(_hull_reach.end.y, _rotor_reach.end.y)


## Габарит корпуса со стрелой лебёдки сейчас, в координатах сцены.
func hull_box() -> AABB:
	return _body.global_transform * _hull_local


## Габарит диска винта сейчас, в координатах сцены: винт крутится, и габарит
## берётся по всему диску, а не по лопастям в этот миг.
func rotor_box() -> AABB:
	return _body.global_transform * _rotor_local


## Висит ли над точкой — прилетел и ещё не ушёл.
func is_hovering() -> bool:
	return _phase == Phase.HOVERING and not _leaving_set


## Ушёл ли — улетает или уже решил улетать.
func is_leaving() -> bool:
	return _phase == Phase.LEAVING or _leaving_set


## Где трос выходит из лебёдки, в координатах сцены: стрела выносит его в
## плоскость игры.
func hook() -> Vector3:
	return _body.to_global(_hook)


## Где висел бы крюк над точкой зависания: по нему уровень ставит Otto заранее,
## пока вертолёт ещё летит.
func hook_at_hover(hover: Vector3) -> Vector3:
	return Vector3(hover.x, hover.y, DEPTH_Z) + _hook


## Отдаёт трос на [param length] метров. Лебёдка идёт с [constant ROPE_SPEED].
func lower_rope(length: float) -> void:
	_rope_wanted = maxf(length, 0.0)


## Сколько троса отдано сейчас, м.
func rope_length() -> float:
	return _rope_length


## Трос отдан весь.
func rope_is_down() -> bool:
	return _rope_wanted > 0.0 and is_equal_approx(_rope_length, _rope_wanted)


## Выбирает трос и уходит вправо и вверх — через [param delay] секунд висения.
## Зовётся и посреди прилёта: пропущенное вступление вертолёт не доигрывает,
## а уходит с того места и той скоростью, какие у него были.
func leave(delay: float = 0.0) -> void:
	_rope_wanted = 0.0
	_leave_in = delay
	_leaving_set = true
	_show_hover_lights(false)


func _physics_process(delta: float) -> void:
	_time += delta
	var before := position
	match _phase:
		Phase.ARRIVING:
			_arrive()
		Phase.HOVERING:
			_hang()
		Phase.LEAVING:
			_fly_off(delta)
			if position.distance_to(_left_from) > GONE_AFTER:
				queue_free()
				return

	var seen := (position - before) / maxf(delta, 0.0001)
	var acceleration := (seen - _velocity) / maxf(delta, 0.0001)
	_velocity = seen
	_lean(acceleration, delta)
	_wind_rope(delta)
	_blink()


func _process(delta: float) -> void:
	if _rotor != null:
		_rotor.rotate_object_local(Vector3.FORWARD, ROTOR_SPEED * delta)


## Прилёт по кривой [method _arrival_progress]: на входе скорость крейсерская,
## к точке сходит на нет.
func _arrive() -> void:
	var u := clampf(_time / ARRIVAL_TIME, 0.0, 1.0)
	position = _from.lerp(_hover, _arrival_progress(u))
	position.y = maxf(position.y, clear_height(position.x))
	if u >= 1.0:
		_phase = Phase.HOVERING
		_time = 0.0
		if not _leaving_set:
			_show_hover_lights(true)
	elif _leaving_set:
		_start_leaving()


## Доля пути к точке зависания: кубика с начальной скоростью полтора пути за
## время прилёта, без ускорения на входе и с нулевой скоростью в конце.
static func _arrival_progress(u: float) -> float:
	return 1.5 * u - 0.5 * u * u * u


func _hang() -> void:
	position = _hover + Vector3(0.0, sin(_time * BOB_RATE * TAU) * BOB_HEIGHT, 0.0)
	if not _leaving_set:
		return
	_leave_in -= get_physics_process_delta_time()
	# Уходит с выбранным тросом: болтающийся конец на уходе смотрится обрывом.
	if _leave_in <= 0.0 and _rope_length <= 0.0:
		_start_leaving()


func _start_leaving() -> void:
	_phase = Phase.LEAVING
	_left_from = position
	_time = 0.0


func _fly_off(delta: float) -> void:
	var speed := minf(maxf(_velocity.x, 0.0) + LEAVE_ACCELERATION * delta, LEAVE_SPEED)
	position += Vector3(speed, speed * LEAVE_CLIMB, 0.0) * delta
	position.y = maxf(position.y, clear_height(position.x))


## Клонит корпус по ускорению и сопротивлению — носом вниз на разгоне и полном
## ходу, носом вверх на торможении.
func _lean(acceleration: Vector3, delta: float) -> void:
	var push := acceleration.x + DRAG * _velocity.x
	var wanted := clampf(atan2(push, 9.8) * TILT_GAIN, -TILT_MAX, TILT_MAX)
	_tilt = lerpf(_tilt, wanted, 1.0 - exp(-TILT_EASE * delta))
	# Поворот вокруг Z по часовой — нос, смотрящий в +X, уходит вниз.
	_body.rotation.z = -_tilt


func _wind_rope(delta: float) -> void:
	_rope_length = move_toward(_rope_length, _rope_wanted, ROPE_SPEED * delta)
	_rope.visible = _rope_length > 0.01
	# Трос висит отвесно, как бы ни клонился корпус: он на крюке, а не на палке.
	var top := hook()
	_rope.global_basis = Basis.from_scale(Vector3(1.0, maxf(_rope_length, 0.01), 1.0))
	_rope.global_position = top - Vector3(0.0, _rope_length * 0.5, 0.0)


func _blink() -> void:
	var beacon := fmod(_time, BEACON_PERIOD) < FLASH * 1.6
	for light: Node3D in _beacons:
		light.visible = beacon
	var strobe := fmod(_time + 0.4, STROBE_PERIOD)
	_strobe.visible = strobe < FLASH or (strobe > FLASH * 2.5 and strobe < FLASH * 3.5)


## Гул мотора — позиционной петлёй, если звук уже есть. Нет — вертолёт молчит:
## звук подбирается, и имя [constant Sounds.HELICOPTER] ждёт свой файл.
func _start_engine() -> void:
	if _engine != null or Sounds.variant_paths(Sounds.HELICOPTER).is_empty():
		return
	_engine = Sounds.source(self, Sounds.HELICOPTER, ENGINE_REACH)
	_engine.play()


## Собирает вид: корпус, винт отдельным мешем, лебёдку с тросом, огни и прожектор.
func _dress() -> void:
	var model := MODEL.instantiate() as Node3D
	_body.add_child(model)
	var hull := model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var source := hull.mesh
	# Ось винта — середина его вершин, а не габарита: лопастей три, и габарит
	# у них несимметричный — вокруг его середины винт ходил бы восьмёркой.
	var rotor_box := _surface_box(source, ROTOR_SURFACE)
	var middle := _surface_middle(source, ROTOR_SURFACE)
	var hub := Vector3(middle.x, middle.y, rotor_box.position.z)

	var body_mesh := ArrayMesh.new()
	for index: int in source.get_surface_count():
		if index != ROTOR_SURFACE:
			_copy_surface(source, index, body_mesh, Vector3.ZERO, _paint(index, source))
	hull.mesh = body_mesh

	var rotor_mesh := ArrayMesh.new()
	_copy_surface(source, ROTOR_SURFACE, rotor_mesh, hub, _paint(ROTOR_SURFACE, source))
	_rotor = MeshInstance3D.new()
	_rotor.name = "Rotor"
	_rotor.mesh = rotor_mesh
	_rotor.position = hub
	_rotor.scale = Vector3(ROTOR_SPREAD, ROTOR_SPREAD, 1.0)
	hull.add_child(_rotor)

	# Масштаб и место — по габариту корпуса без винта: нос в +X, ось винта над
	# нулём, полозья на нуле, середина по глубине на нуле.
	var to_model := _chain(model, hull)
	var box := to_model * _surface_box(source, 0)
	var turn := Basis(Vector3.UP, -PI * 0.5 * NOSE_MESH_Y)
	var length := maxf(box.size.x, box.size.z)
	var fit := LENGTH / maxf(length, 0.001)
	model.basis = turn.scaled(Vector3.ONE * fit)
	var placed := _chain(_body, hull)
	var hull_box := placed * _surface_box(source, 0)
	var hub_at := placed * hub
	model.position = -Vector3(hub_at.x, hull_box.position.y, hull_box.get_center().z)
	placed = _chain(_body, hull)
	hull_box = placed * _surface_box(source, 0)
	_hang_winch(hull_box)
	_hang_lights(hull_box)
	_measure(hull_box, placed, source, hub)


## Габариты для прохода над крышей: корпус со стрелой лебёдки до плоскости игры
## и диск винта — круг радиусом самой дальней вершины лопасти.
func _measure(hull: AABB, placed: Transform3D, source: Mesh, hub: Vector3) -> void:
	var near := maxf(hull.end.z, -DEPTH_Z)
	_hull_local = AABB(hull.position, Vector3(hull.size.x, hull.size.y, near - hull.position.z))
	var to_rotor := placed * _rotor.transform
	var centre := placed * hub
	var radius := 0.0
	var low := INF
	var high := -INF
	var vertices := (
		source.surface_get_arrays(ROTOR_SURFACE)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	)
	for vertex: Vector3 in vertices:
		var at := to_rotor * (vertex - hub)
		radius = maxf(radius, Vector2(at.x - centre.x, at.z - centre.z).length())
		low = minf(low, at.y)
		high = maxf(high, at.y)
	_rotor_local = AABB(
		Vector3(centre.x - radius, low, centre.z - radius),
		Vector3(radius * 2.0, high - low, radius * 2.0)
	)
	_hull_reach = _tilted(_hull_local)
	_rotor_reach = _tilted(_rotor_local)


## Габарит [param box] при всех наклонах до [constant TILT_MAX]: при малых углах
## крайние точки — на краях диапазона и в нуле.
static func _tilted(box: AABB) -> AABB:
	var reach := box
	for angle: float in [-TILT_MAX, TILT_MAX]:
		reach = reach.merge(Transform3D(Basis(Vector3.BACK, angle), Vector3.ZERO) * box)
	return reach


## Стрела лебёдки над дверью: от ближнего борта в плоскость игры. Трос висит с её
## конца, и Otto на нём — в плоскости игры, как везде.
func _hang_winch(hull: AABB) -> void:
	var door_top := hull.position.y + hull.size.y * 0.62
	var near_side := hull.end.z
	var reach := -DEPTH_Z - near_side
	var arm := GreyboxLook.box(
		Vector3(0.08, 0.08, reach + 0.1), GreyboxLook.metal(Color(0.3, 0.31, 0.33))
	)
	arm.name = "WinchArm"
	arm.position = Vector3(0.0, door_top, near_side + reach * 0.5)
	_body.add_child(arm)
	_hook = Vector3(0.0, door_top - 0.06, -DEPTH_Z)

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = ROPE_RADIUS
	cylinder.bottom_radius = ROPE_RADIUS
	cylinder.height = 1.0
	cylinder.radial_segments = 6
	cylinder.rings = 1
	cylinder.material = GreyboxLook.surface(ROPE_COLOR)
	_rope = MeshInstance3D.new()
	_rope.name = "Rope"
	_rope.mesh = cylinder
	_rope.visible = false
	_rope.top_level = true
	add_child(_rope)


func _hang_lights(hull: AABB) -> void:
	var nose := hull.end.x
	var tail := hull.position.x
	var roof := hull.position.y + hull.size.y * 0.66
	var near_side := hull.end.z
	var green := _light(
		NAV_GREEN, Vector3(nose * 0.55, hull.position.y + hull.size.y * 0.45, near_side)
	)
	green.name = "NavGreen"
	var top := _light(BEACON_RED, Vector3(-1.0, roof, 0.0))
	top.name = "BeaconTop"
	var belly := _light(BEACON_RED, Vector3(0.3, hull.position.y + hull.size.y * 0.3, 0.0))
	belly.name = "BeaconBelly"
	_beacons = [top, belly]
	_strobe = _light(STROBE_WHITE, Vector3(tail + 0.15, hull.position.y + hull.size.y * 0.6, 0.0))
	_strobe.name = "Strobe"

	_search = SpotLight3D.new()
	_search.name = "Searchlight"
	_search.light_color = SEARCH_COLOR
	_search.light_energy = SEARCH_ENERGY
	_search.spot_range = SEARCH_RANGE
	_search.spot_angle = SEARCH_ANGLE
	_search.shadow_enabled = false
	# Конус виден в дымке над крышей ([RoofRain]), где она есть.
	_search.light_volumetric_fog_energy = Graphics.light_in_fog() * 2.0
	_search.position = Vector3(nose * 0.6, hull.position.y + hull.size.y * 0.25, -DEPTH_Z * 0.5)
	# Смотрит вниз и чуть вперёд: пятно ложится туда, куда спускается Otto.
	_search.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	_search.rotate_z(deg_to_rad(12.0))
	_body.add_child(_search)

	# Свет кабины из открытой двери: ложится на Otto, пока он выходит на трос,
	# и на борт у двери — без него корпус ночью только силуэт.
	_cabin = OmniLight3D.new()
	_cabin.name = "CabinLight"
	_cabin.light_color = CABIN_COLOR
	_cabin.light_energy = CABIN_ENERGY
	_cabin.omni_range = CABIN_RANGE
	_cabin.shadow_enabled = false
	_cabin.position = Vector3(0.0, hull.position.y + hull.size.y * 0.45, near_side + 0.35)
	_body.add_child(_cabin)
	_show_hover_lights(false)


## Прожектор и свет кабины горят, только пока вертолёт висит с открытой дверью:
## лишний источник в кадре на пару секунд, а не на весь полёт.
func _show_hover_lights(on: bool) -> void:
	if _search != null:
		_search.visible = on
	if _cabin != null:
		_cabin.visible = on


func _light(color: Color, at: Vector3) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = LIGHT_SIZE
	sphere.height = LIGHT_SIZE * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.material = GreyboxLook.light(color)
	var light := MeshInstance3D.new()
	light.mesh = sphere
	light.position = at
	light.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(light)
	return light


## Преобразование из пространства меша [param leaf] в пространство [param root]:
## узлы ещё не в дереве, и глобальных координат у них нет.
static func _chain(root: Node3D, leaf: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var node: Node = leaf
	while node != null and node != root:
		var spatial := node as Node3D
		if spatial != null:
			xf = spatial.transform * xf
		node = node.get_parent()
	return xf


static func _surface_box(mesh: Mesh, index: int) -> AABB:
	var vertices := mesh.surface_get_arrays(index)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var box := AABB(vertices[0], Vector3.ZERO)
	for vertex: Vector3 in vertices:
		box = box.expand(vertex)
	return box


## Материал поверхности: корпус, остекление и винт — свои, полоса — как у модели.
static func _paint(index: int, source: Mesh) -> Material:
	match index:
		HULL_SURFACE:
			var hull := StandardMaterial3D.new()
			hull.albedo_color = HULL_COLOR
			hull.metallic = 0.55
			hull.roughness = 0.32
			hull.next_pass = _rim()
			return hull
		GLASS_SURFACE:
			var glass := StandardMaterial3D.new()
			glass.albedo_color = GLASS_COLOR
			glass.metallic = 0.2
			glass.roughness = 0.08
			glass.emission_enabled = true
			glass.emission = GLASS_GLOW
			glass.emission_energy_multiplier = GLASS_GLOW_ENERGY
			return glass
		ROTOR_SURFACE:
			return GreyboxLook.metal(ROTOR_COLOR)
	return source.surface_get_material(index)


## Второй проход корпуса — холодный ободок по краям силуэта.
static func _rim() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = RIM_SHADER
	var rim := ShaderMaterial.new()
	rim.shader = shader
	rim.set_shader_parameter(&"rim_color", RIM_COLOR)
	rim.set_shader_parameter(&"rim_power", RIM_POWER)
	rim.set_shader_parameter(&"rim_strength", RIM_STRENGTH)
	return rim


static func _surface_middle(mesh: Mesh, index: int) -> Vector3:
	var vertices := mesh.surface_get_arrays(index)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var sum := Vector3.ZERO
	for vertex: Vector3 in vertices:
		sum += vertex
	return sum / float(maxi(vertices.size(), 1))


## Переносит поверхность [param index] в [param into], сдвинув её на
## [param offset] к нулю: винт крутится вокруг своей оси, а не нуля модели.
static func _copy_surface(
	source: Mesh, index: int, into: ArrayMesh, offset: Vector3, material: Material
) -> void:
	var arrays := source.surface_get_arrays(index)
	if offset != Vector3.ZERO:
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		for at: int in vertices.size():
			vertices[at] -= offset
		arrays[Mesh.ARRAY_VERTEX] = vertices
	into.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	into.surface_set_material(into.get_surface_count() - 1, material)
