class_name Helicopter
extends Node3D

## Вертолёт вступления: привозит Otto на крышу (ADR-0038, решение 1).
##
## Вид, а не тело: коллизий у него нет, в бою он не участвует. Прилетает слева,
## зависает, откатывает сдвижную дверь, сбрасывает бухту троса, по команде
## выбирает трос, задвигает дверь и уходит — нос вниз, с креном, вверх и вбок
## (ADR-0052, решение 6), — а за кадром убирает себя сам. Когда что делать,
## решает [RoofArrival]; вертолёт умеет только лететь, висеть, открывать дверь и
## опускать трос. За остеклением — пилот, на уходе кивает.
##
## Модель с M24i своя (ADR-0049, `tools/build_helicopter.py`): корпус с
## остеклением, полозья, киль, несущий и хвостовой винты отдельными узлами
## `MainRotor` и `TailRotor`, с M24k — дверь узлом `Door`, и пустышки
## огней, прожектора, света кабины, лебёдки и кресла пилота. Нуль узла — под
## осью винта на уровне полозьев, в середине корпуса по глубине: так
## «зависнуть над точкой» — это просто поставить узел в неё.

enum Phase { ARRIVING, HOVERING, LEAVING }

const MODEL := preload("res://assets/models/aircraft/helicopter.glb")
const PILOT_MODEL := preload("res://assets/models/pilot.glb")

## Длина по корпусу от носа до хвоста, м. Лёгкий вертолёт — девять метров с
## небольшим; модель приводится к ней одним масштабом.
const LENGTH: float = 8.6

## Окраска. Корпус — тёмный металлик, который ловит неон и огни города;
## остекление светится изнутри приборами — так кабину видно в темноте, и
## вертолёт читается машиной с людьми, а не силуэтом; проём двери — тёплым
## светом кабины.
const HULL_COLOR := Color(0.34, 0.37, 0.44)
const GLASS_COLOR := Color(0.05, 0.07, 0.09)
const GLASS_GLOW := Color(0.3, 0.46, 0.52)
const GLASS_GLOW_ENERGY: float = 0.08
## Остекление прозрачно: за ним видно пилота (ADR-0052, решение 6).
const GLASS_ALPHA: float = 0.42
const CABIN_GLOW := Color(1.0, 0.72, 0.42)
const ROTOR_COLOR := Color(0.5, 0.5, 0.52)
const CABIN_GLOW_ENERGY: float = 0.25
## Диск размытия под лопастями: винт на оборотах — не четыре палки, а круг, по
## которому бегут лопасти. Доля непрозрачности у кончиков и у оси.
const BLUR_ALPHA: float = 0.22
const BLUR_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color;
uniform float blades = 4.0;
void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float streak = 0.55 + 0.45 * cos(atan(p.y, p.x) * blades);
	float ring = smoothstep(0.12, 0.3, r) * (1.0 - smoothstep(0.92, 1.0, r));
	ALBEDO = tint.rgb;
	ALPHA = tint.a * ring * streak * (0.4 + 0.6 * r);
}
"""
## Хвостовой винт крутится быстрее несущего, как у настоящего.
const TAIL_ROTOR_SPEED: float = 48.0
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

## Трос: толщина, цвет и с какой скоростью лебёдка его выбирает, м/с. Отдаёт
## его не лебёдка: бухту сбрасывают, и трос разматывается падением.
const ROPE_RADIUS: float = 0.022
const ROPE_COLOR := Color(0.36, 0.34, 0.3)
const ROPE_SPEED: float = 3.2
## Сброшенная бухта падает с ускорением чуть меньше свободного — трос тянет
## её назад, — и не быстрее предела, м/с², м/с.
const ROPE_DROP_PULL: float = 7.5
const ROPE_DROP_TOP: float = 9.0
## Качание троса маятником в плоскости игры: толчок на сбросе, рад, и как
## быстро гаснет, 1/с; поток от винта качает его и дальше — на столько, рад.
const ROPE_KICK: float = 0.16
const ROPE_DAMPING: float = 1.1
const ROPE_DRAFT: float = 0.018
const ROPE_DRAFT_RATE: float = 1.3

## Сдвижная дверь: за сколько секунд откатывается и насколько отходит от
## борта, прежде чем поехать назад, м.
const DOOR_TIME: float = 0.85
const DOOR_POP: float = 0.05
## Насколько короче своей длины дверь откатывается: край остаётся у проёма.
const DOOR_KEEP: float = 0.12

## Уход (ADR-0052, решение 6): крен в повороте, рад, и насколько вертолёт
## уходит вбок, в глубину кадра, на метр пути вправо; рысканье носом туда же.
const BANK_MAX: float = 0.3
const LEAVE_AWAY: float = 0.28
const LEAVE_YAW: float = 0.32
## Сколько висит с закрытой дверью перед уходом, с: пилот кивает.
const NOD_TIME: float = 0.55

## Пилот сидит в кресле: насколько ступни ниже подушки и впереди неё, м.
const PILOT_FEET := Vector3(0.36, -0.36, 0.0)

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

## Звук: петля висения звучит всю сценку, громче всего в висении и тише на
## ходу; пролёт — второй слой, он слышен на ходу и молкнет в висении. Оба на
## самом вертолёте — позиционно, слышно на [constant ENGINE_REACH] метров.
const ENGINE_REACH: float = 50.0
## Громкость петли висения на месте и на полном ходу, дБ; тон на полном ходу.
const HOVER_DB: float = 0.0
const HOVER_DB_MOVING: float = -7.0
const HOVER_PITCH_MOVING: float = 1.06
## С какой скорости пролёт звучит в полную силу, м/с, и его громкость, дБ.
const PASS_FULL_SPEED: float = 9.0
const PASS_DB: float = -2.0
## Ниже этого слой считается замолкшим, дБ.
const SILENT_DB: float = -60.0
## Как быстро громкость идёт за скоростью, 1/с: без сглаживания рывок
## торможения был бы слышен щелчком.
const VOLUME_EASE: float = 4.0

## Ободок — один на все вертолёты: шейдер компилируется раз за запуск, а не на
## каждое здание, когда вертолёт влетает в кадр.
static var _rim_material: ShaderMaterial = null
## Шейдер диска размытия винтов, тоже один за запуск ([method _blur_shader]).
static var _blur_code: Shader = null

## Утром и днём прожектор не горит (ADR-0052): ставится до [method fly_in].
var daytime: bool = false

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
var _rotor: Node3D = null
var _tail_rotor: Node3D = null
## Точки модели: огни, прожектор, свет кабины, лебёдка — в координатах узла.
var _marks: Dictionary = {}
var _hook := Vector3.ZERO
var _rope: MeshInstance3D = null
var _rope_length: float = 0.0
var _rope_wanted: float = 0.0
## Бухта летит вниз: трос отдаётся падением, а не лебёдкой.
var _dropping: bool = false
var _drop_speed: float = 0.0
## Угол троса от отвеса в плоскости игры, рад, и его скорость.
var _swing: float = 0.0
var _swing_speed: float = 0.0
var _door: Node3D = null
var _door_closed := Vector3.ZERO
var _door_slide: float = 0.0
## Доля открытия двери, 0–1, и куда она идёт.
var _door_share: float = 0.0
var _door_wanted: float = 0.0
var _door_voice: AudioStreamPlayer3D = null
var _winch_voice: AudioStreamPlayer3D = null
var _pilot: FigureRig = null
## Сколько ещё кивает пилот, с.
var _nod: float = 0.0
## Шаги ухода: выбрать трос, задвинуть дверь, кивнуть — и только потом лететь.
var _nodded: bool = false
var _beacons: Array[Node3D] = []
var _strobe: Node3D = null
var _search: SpotLight3D = null
var _cabin: OmniLight3D = null
var _engine: AudioStreamPlayer3D = null
var _pass: AudioStreamPlayer3D = null
var _rope_voice: AudioStreamPlayer3D = null
## Доля хода для громкости слоёв, 0 — висит, 1 — полный ход; сглаженная.
var _motion: float = 1.0
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
##
## [param already_there] — короткое вступление (ADR-0052, решение 6): вертолёт
## с первого кадра висит над точкой с открытой дверью.
func fly_in(hover: Vector3, already_there: bool = false) -> void:
	_hover = safe_hover(hover)
	_from = _hover + Vector3(-ARRIVAL_DISTANCE, ARRIVAL_RISE, 0.0)
	_phase = Phase.ARRIVING
	_time = 0.0
	position = _from
	_velocity = Vector3.ZERO
	_start_engine()
	if already_there:
		position = _hover
		_from = _hover
		_time = ARRIVAL_TIME
		_door_share = 1.0
		_door_wanted = 1.0
		_place_door()
		_motion = 0.0


## Откатывает сдвижную дверь назад — в проёме загорается салон — или задвигает
## её, [param open] = false.
func set_door_open(open: bool) -> void:
	var wanted := 1.0 if open else 0.0
	if not is_equal_approx(_door_wanted, wanted):
		_door_wanted = wanted
		_door_sound()


## Насколько открыта дверь, 0–1: 1 — открыта настежь.
func door_share() -> float:
	return _door_share


## Порог проёма двери в координатах сцены: середина по длине проёма, на полу
## салона, у ближнего борта.
func doorway() -> Vector3:
	return _body.to_global(_marks["Doorway"])


## Сбрасывает бухту троса: трос разматывается падением на [param length]
## метров и качается маятником, пока поток от винта его не успокоит.
func drop_rope(length: float) -> void:
	_rope_wanted = maxf(length, 0.0)
	_dropping = true
	_drop_speed = 0.0
	_swing_speed = ROPE_KICK * 3.0
	_rope_sound(Sounds.ROPE_DROP)


## Точка на тросе в [param along] метрах от крюка — с качанием троса.
func rope_point(along: float) -> Vector3:
	var reach := clampf(along, 0.0, _rope_length)
	return hook() + Vector3(sin(_swing) * reach, -cos(_swing) * reach, 0.0)


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


## Сколько троса отдано сейчас, м.
func rope_length() -> float:
	return _rope_length


## Трос отдан весь.
func rope_is_down() -> bool:
	return _rope_wanted > 0.0 and is_equal_approx(_rope_length, _rope_wanted)


## Выбирает трос, задвигает дверь, пилот кивает — и вертолёт уходит вправо,
## вверх и вбок, через [param delay] секунд висения. Зовётся и посреди
## прилёта: пропущенное вступление вертолёт не доигрывает, а уходит с того
## места и той скоростью, какие у него были.
func leave(delay: float = 0.0) -> void:
	_rope_wanted = 0.0
	_dropping = false
	_leave_in = delay
	_leaving_set = true
	if _rope_length > 0.01:
		_winch(true)
	if _search != null:
		_search.visible = false


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
	_slide_door(delta)
	_pose_pilot(delta)
	_blink()
	_mix_engine(delta)


func _process(delta: float) -> void:
	if _rotor != null:
		_rotor.rotate_object_local(Vector3.UP, ROTOR_SPEED * delta)
	if _tail_rotor != null:
		_tail_rotor.rotate_object_local(Vector3.BACK, TAIL_ROTOR_SPEED * delta)


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
	# Уходит с выбранным тросом и закрытой дверью: болтающийся конец на уходе
	# смотрится обрывом, а открытая дверь — забытой.
	if _leave_in > 0.0 or _rope_length > 0.0:
		return
	if _door_share > 0.0:
		set_door_open(false)
		return
	if not _nodded:
		_nodded = true
		_nod = NOD_TIME
		_leave_in = NOD_TIME
		return
	_start_leaving()


func _start_leaving() -> void:
	_phase = Phase.LEAVING
	_left_from = position
	_time = 0.0


func _fly_off(delta: float) -> void:
	var speed := minf(maxf(_velocity.x, 0.0) + LEAVE_ACCELERATION * delta, LEAVE_SPEED)
	position += Vector3(speed, speed * LEAVE_CLIMB, -speed * LEAVE_AWAY) * delta
	position.y = maxf(position.y, clear_height(position.x))
	# Крен и рысканье в повороте вбок — по набранной скорости.
	var turn := clampf(speed / LEAVE_SPEED, 0.0, 1.0)
	_body.rotation.x = -BANK_MAX * turn
	_body.rotation.y = LEAVE_YAW * turn


## Клонит корпус по ускорению и сопротивлению — носом вниз на разгоне и полном
## ходу, носом вверх на торможении.
func _lean(acceleration: Vector3, delta: float) -> void:
	var push := acceleration.x + DRAG * _velocity.x
	var wanted := clampf(atan2(push, 9.8) * TILT_GAIN, -TILT_MAX, TILT_MAX)
	_tilt = lerpf(_tilt, wanted, 1.0 - exp(-TILT_EASE * delta))
	# Поворот вокруг Z по часовой — нос, смотрящий в +X, уходит вниз.
	_body.rotation.z = -_tilt


func _wind_rope(delta: float) -> void:
	if _dropping and _rope_length < _rope_wanted:
		_drop_speed = minf(_drop_speed + ROPE_DROP_PULL * delta, ROPE_DROP_TOP)
		_rope_length = minf(_rope_length + _drop_speed * delta, _rope_wanted)
	else:
		var was := _rope_length
		_rope_length = move_toward(_rope_length, _rope_wanted, ROPE_SPEED * delta)
		if was > 0.0 and _rope_length <= 0.0:
			_winch(false)
	_swing_rope(delta)
	_rope.visible = _rope_length > 0.01
	# Трос висит с крюка, как бы ни клонился корпус: он на крюке, а не на палке,
	# и качается маятником в плоскости игры.
	var top := hook()
	var tilt := Basis(Vector3.BACK, _swing)
	_rope.global_basis = tilt * Basis.from_scale(Vector3(1.0, maxf(_rope_length, 0.01), 1.0))
	_rope.global_position = top + tilt * Vector3(0.0, -_rope_length * 0.5, 0.0)


## Маятник троса: частота — от длины, затухание — своё, и поток от винта
## толкает его медленной волной.
func _swing_rope(delta: float) -> void:
	if _rope_length <= 0.05:
		_swing = 0.0
		_swing_speed = 0.0
		return
	var rate := 9.8 / maxf(_rope_length, 0.5)
	var draft := sin(_time * ROPE_DRAFT_RATE * TAU) * ROPE_DRAFT
	_swing_speed += (-rate * (_swing - draft) - ROPE_DAMPING * _swing_speed) * delta
	_swing += _swing_speed * delta


## Дверь едет к открытой или закрытой: сначала отходит от борта, потом
## катится назад по направляющим.
func _slide_door(delta: float) -> void:
	if is_equal_approx(_door_share, _door_wanted):
		return
	_door_share = move_toward(_door_share, _door_wanted, delta / DOOR_TIME)
	_place_door()


func _place_door() -> void:
	if _door != null:
		var pop := clampf(_door_share * 5.0, 0.0, 1.0)
		var slide := smoothstep(0.15, 1.0, _door_share)
		_door.position = _door_closed + Vector3(-_door_slide * slide, 0.0, DOOR_POP * pop)
	# Салон горит, пока дверь открыта.
	if _cabin != null:
		_cabin.visible = _door_share > 0.05


## Пилот сидит, на уходе кивает.
func _pose_pilot(delta: float) -> void:
	if _pilot == null:
		return
	_nod = maxf(_nod - delta, 0.0)
	_pilot.show_pose("pilot_nod" if _nod > NOD_TIME * 0.45 else "pilot_sit")


func _blink() -> void:
	var beacon := fmod(_time, BEACON_PERIOD) < FLASH * 1.6
	for light: Node3D in _beacons:
		light.visible = beacon
	var strobe := fmod(_time + 0.4, STROBE_PERIOD)
	_strobe.visible = strobe < FLASH or (strobe > FLASH * 2.5 and strobe < FLASH * 3.5)


## Лязг двери на её месте.
func _door_sound() -> void:
	if _door_voice != null:
		_door_voice.global_position = doorway()
		_door_voice.play()


## Звук троса на крюке: сброс бухты.
func _rope_sound(name: String) -> void:
	if _rope_voice == null:
		return
	var voice := Sounds.source(self, name, ENGINE_REACH)
	voice.top_level = true
	voice.global_position = hook()
	voice.finished.connect(voice.queue_free)
	voice.play()


## Лебёдка выбирает трос — гудит, пока он идёт.
func _winch(on: bool) -> void:
	if _winch_voice == null:
		return
	if on:
		_winch_voice.global_position = hook()
		_winch_voice.play()
	else:
		_winch_voice.stop()


## Звук скольжения Otto по тросу — на крюке, откуда трос идёт. [param on] —
## начать; false — оборвать, если Otto уже внизу или сценку пропустили.
func rope_slide(on: bool) -> void:
	if _rope_voice == null:
		return
	if on:
		_rope_voice.global_position = hook()
		_rope_voice.play()
	else:
		_rope_voice.stop()


## Заводит петлю висения и слой пролёта: оба звучат с прилёта до ухода, а
## громкость между ними делит [method _mix_engine].
func _start_engine() -> void:
	if _engine != null:
		return
	_engine = Sounds.source(self, Sounds.HELICOPTER, ENGINE_REACH)
	_engine.volume_db = HOVER_DB_MOVING
	_engine.play()
	_pass = Sounds.source(self, Sounds.HELICOPTER_PASS, ENGINE_REACH)
	_pass.volume_db = PASS_DB
	_pass.play()
	_rope_voice = Sounds.source(self, Sounds.ROPE_SLIDE, ENGINE_REACH)
	_rope_voice.top_level = true
	_door_voice = Sounds.source(self, Sounds.HELI_DOOR, ENGINE_REACH)
	_door_voice.top_level = true
	_winch_voice = Sounds.source(self, Sounds.WINCH, ENGINE_REACH)
	_winch_voice.top_level = true


## Громкость по ходу: чем быстрее летит, тем тише висение и громче пролёт.
func _mix_engine(delta: float) -> void:
	if _engine == null:
		return
	var wanted := clampf(absf(_velocity.x) / PASS_FULL_SPEED, 0.0, 1.0)
	_motion = lerpf(_motion, wanted, 1.0 - exp(-VOLUME_EASE * delta))
	_engine.volume_db = lerpf(HOVER_DB, HOVER_DB_MOVING, _motion)
	_engine.pitch_scale = lerpf(1.0, HOVER_PITCH_MOVING, _motion)
	_pass.volume_db = maxf(PASS_DB + linear_to_db(maxf(_motion, 0.0001)), SILENT_DB)


## Собирает вид: модель с перекрашенным корпусом, винты с дисками размытия,
## лебёдку с тросом, огни и прожектор по точкам модели.
func _dress() -> void:
	var model := MODEL.instantiate() as Node3D
	_body.add_child(model)
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		_repaint(node as MeshInstance3D)
	_rotor = model.find_child("MainRotor", true, false) as Node3D
	_tail_rotor = model.find_child("TailRotor", true, false) as Node3D
	# Длина — по корпусу: модель собрана в метрах, но переснятая с другой длиной
	# не разойдётся с игрой.
	var hull := _parts_box(model, ["Hull", "Skids"])
	var fit := LENGTH / maxf(hull.size.x, 0.001)
	model.scale = Vector3.ONE * fit
	hull = _parts_box(model, ["Hull", "Skids"])
	for mark: String in [
		"NavGreen",
		"BeaconTop",
		"BeaconBelly",
		"Strobe",
		"Searchlight",
		"CabinLight",
		"Winch",
		"PilotSeat",
	]:
		var anchor := model.find_child(mark, true, false) as Node3D
		_marks[mark] = _chain(_body, anchor).origin if anchor != null else hull.get_center()
	_fit_door(model)
	_seat_pilot()
	_blur(_rotor, 4.0, false)
	_blur(_tail_rotor, 2.0, true)
	_hang_winch(hull)
	_hang_lights()
	_measure(hull, model)


## Дверь модели: закрытая, в своём начале; откатывается на свою длину без
## края у проёма. Порог проёма — низ двери у ближнего борта.
func _fit_door(model: Node3D) -> void:
	_door = model.find_child("Door", true, false) as Node3D
	var door_mesh := _door as MeshInstance3D
	if door_mesh == null:
		_marks["Doorway"] = _marks["CabinLight"]
		return
	_door_closed = _door.position
	var box := door_mesh.mesh.get_aabb()
	_door_slide = maxf(box.size.x - DOOR_KEEP, 0.0)
	var placed := _chain(_body, door_mesh) * box
	_marks["Doorway"] = Vector3(placed.get_center().x, placed.position.y, placed.position.z)


## Пилот в кресле лицом к носу. Риг ставит позу на пол ступнями — его начало
## под ступнями, впереди и ниже подушки кресла.
func _seat_pilot() -> void:
	_pilot = FigureRig.new()
	_pilot.name = "Pilot"
	_pilot.model = PILOT_MODEL
	_pilot.position = _marks["PilotSeat"] + PILOT_FEET
	_body.add_child(_pilot)
	_pilot.face(1.0, true)


## Габарит частей [param names] модели в координатах узла.
func _parts_box(model: Node3D, names: Array[String]) -> AABB:
	var box := AABB()
	var first := true
	for part_name: String in names:
		var part := model.find_child(part_name, true, false) as MeshInstance3D
		if part == null:
			continue
		var placed := _chain(_body, part) * part.mesh.get_aabb()
		box = placed if first else box.merge(placed)
		first = false
	return box


## Габариты для прохода над крышей: корпус со стрелой лебёдки до плоскости игры
## и диск винта — круг радиусом конца лопасти.
func _measure(hull: AABB, model: Node3D) -> void:
	var near := maxf(hull.end.z, -DEPTH_Z)
	_hull_local = AABB(hull.position, Vector3(hull.size.x, hull.size.y, near - hull.position.z))
	var disc := _parts_box(model, ["MainRotor"])
	var centre := _chain(_body, _rotor).origin if _rotor != null else disc.get_center()
	var radius := maxf(disc.size.x, disc.size.z) * 0.5
	_rotor_local = AABB(
		Vector3(centre.x - radius, disc.position.y, centre.z - radius),
		Vector3(radius * 2.0, disc.size.y, radius * 2.0)
	)
	_hull_reach = _tilted(_hull_local)
	_rotor_reach = _tilted(_rotor_local)


## Перекрашивает части модели по имени материала: корпус, стекло, проём кабины.
static func _repaint(mesh: MeshInstance3D) -> void:
	for index: int in mesh.mesh.get_surface_count():
		var source := mesh.mesh.surface_get_material(index)
		var wanted := _paint(source.resource_name if source != null else "")
		if wanted != null:
			mesh.set_surface_override_material(index, wanted)


## Диск размытия под лопастями винта [param rotor]: круг в плоскости вращения,
## крутится вместе с винтом. [param upright] — плоскость вертикальна, вдоль
## корпуса (хвостовой винт), иначе горизонтальна (несущий). Плоскость задана
## явно, а не угадана по габариту: у двухлопастного хвостового винта самая
## тонкая ось габарита — хорда лопасти, а не ось вращения, и диск ложился
## плашмя и кувыркался вокруг оси (авторевью M24i).
func _blur(rotor: Node3D, blades: float, upright: bool) -> void:
	var mesh := rotor as MeshInstance3D
	if mesh == null:
		return
	var box := mesh.mesh.get_aabb()
	var radius := maxf(maxf(box.size.x, box.size.z), box.size.y) * 0.5
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * radius * 2.0
	var look := ShaderMaterial.new()
	look.shader = _blur_shader()
	look.set_shader_parameter(&"tint", Color(ROTOR_COLOR, BLUR_ALPHA))
	look.set_shader_parameter(&"blades", blades)
	quad.material = look
	var disc := MeshInstance3D.new()
	disc.name = "Blur"
	disc.mesh = quad
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Плоскость меша — XZ; хвостовому винту она нужна в XY, лицом по оси +Z.
	if upright:
		disc.rotation.x = PI * 0.5
	rotor.add_child(disc)


## Шейдер диска размытия — один на все вертолёты, как ободок ([method _rim]):
## вертолёт прилетает в каждое здание, и новый шейдер собирался бы на каждом.
static func _blur_shader() -> Shader:
	if _blur_code != null:
		return _blur_code
	_blur_code = Shader.new()
	_blur_code.code = BLUR_SHADER
	return _blur_code


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
	var winch: Vector3 = _marks["Winch"]
	var near_side := minf(winch.z, hull.end.z)
	var reach := -DEPTH_Z - near_side
	var arm := GreyboxLook.box(
		Vector3(0.08, 0.08, reach + 0.1), GreyboxLook.metal(Color(0.3, 0.31, 0.33))
	)
	arm.name = "WinchArm"
	arm.position = Vector3(winch.x, winch.y, near_side + reach * 0.5)
	_body.add_child(arm)
	_hook = Vector3(winch.x, winch.y - 0.06, -DEPTH_Z)

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


func _hang_lights() -> void:
	var green := _light(NAV_GREEN, _marks["NavGreen"])
	green.name = "NavGreen"
	var top := _light(BEACON_RED, _marks["BeaconTop"])
	top.name = "BeaconTop"
	var belly := _light(BEACON_RED, _marks["BeaconBelly"])
	belly.name = "BeaconBelly"
	_beacons = [top, belly]
	_strobe = _light(STROBE_WHITE, _marks["Strobe"])
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
	_search.position = _marks["Searchlight"]
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
	_cabin.position = _marks["CabinLight"]
	_body.add_child(_cabin)
	_show_hover_lights(false)


## Прожектор и свет кабины горят, только пока вертолёт висит с открытой дверью:
## лишний источник в кадре на пару секунд, а не на весь полёт.
func _show_hover_lights(on: bool) -> void:
	if _search != null:
		_search.visible = on and not daytime
	if _cabin != null:
		_cabin.visible = on and _door_share > 0.05


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


## Материал части по имени материала модели: корпус, остекление, проём
## кабины и винт — свои, остальное — как у модели.
static func _paint(material_name: String) -> Material:
	match material_name:
		"Hull":
			var hull := StandardMaterial3D.new()
			hull.albedo_color = HULL_COLOR
			hull.metallic = 0.55
			hull.roughness = 0.32
			hull.next_pass = _rim()
			return hull
		"Glass":
			var glass := StandardMaterial3D.new()
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.albedo_color = Color(GLASS_COLOR, GLASS_ALPHA)
			glass.metallic = 0.2
			glass.roughness = 0.08
			glass.emission_enabled = true
			glass.emission = GLASS_GLOW
			glass.emission_energy_multiplier = GLASS_GLOW_ENERGY
			return glass
		"Cabin":
			var cabin := StandardMaterial3D.new()
			cabin.albedo_color = CABIN_GLOW.darkened(0.5)
			cabin.emission_enabled = true
			cabin.emission = CABIN_GLOW
			cabin.emission_energy_multiplier = CABIN_GLOW_ENERGY
			return cabin
		"Rotor":
			return GreyboxLook.metal(ROTOR_COLOR)
	return null


## Второй проход корпуса — холодный ободок по краям силуэта.
static func _rim() -> ShaderMaterial:
	if _rim_material != null:
		return _rim_material
	var shader := Shader.new()
	shader.code = RIM_SHADER
	_rim_material = ShaderMaterial.new()
	_rim_material.shader = shader
	_rim_material.set_shader_parameter(&"rim_color", RIM_COLOR)
	_rim_material.set_shader_parameter(&"rim_power", RIM_POWER)
	_rim_material.set_shader_parameter(&"rim_strength", RIM_STRENGTH)
	return _rim_material
