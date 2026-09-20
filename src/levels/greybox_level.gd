class_name GreyboxLevel
extends Node3D

## Здание, собранное по [BuildingPlan].
##
## Где что стоит, решает раскладка по правилам и сиду; уровень только расставляет
## узлы и связывает их между собой. Геометрия — серые коробки (ADR-0021): модели,
## материалы и настоящий свет придут вехами M16–M19, каждая на своё место.
##
## Раскладка считает в плоскости правил, где Y растёт вниз. Всё, что уровень
## ставит в сцену, проходит через [WorldSpace] — и только через него: разворот
## Y в одном месте (ADR-0021, решение 2).

## Otto вышел из здания, собрав все документы.
signal building_cleared

## Ширина троса, по которому Otto съезжает на крышу, м.
const ROPE_WIDTH: float = 0.12

## Сколько Otto висит над крышей в начале здания и как быстро съезжает.
##
## Выше собственного прыжка (2.4 м): он должен прийти сверху, а не подпрыгнуть.
## Спуск занимает меньше секунды — это кадр вступления, а не механика
## (ADR-0017, решение 4).
const ROPE_DROP: float = 2.64
const ROPE_SPEED: float = 4.2

const CAR_SCENE := preload("res://src/systems/elevators/elevator_car.tscn")
const EXIT_CAR_MODEL := preload("res://assets/models/car.glb")
const ESCALATOR_SCENE := preload("res://src/systems/escalators/escalator.tscn")
const DOOR_SCENE := preload("res://src/systems/doors/door.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const LAMP_SCENE := preload("res://src/systems/lighting/lamp.tscn")

const WALL_WIDTH: float = 0.48

## Дно шахты: сюда падает тот, кто шагнул в пустой проём.
const PIT_HEIGHT: float = 0.6

## На сколько выше пола висит середина лампы, м.
const LAMP_HANG_HEIGHT: float = 1.8

## Выход из здания — на нижнем этаже.
const EXIT_WIDTH: float = 1.92
const EXIT_HEIGHT: float = 1.2

## Машина у выхода: ею оригинал заканчивает здание (ADR-0011, пункт 14).
## Стоит рядом с проёмом и уезжает, увозя Otto; следующее здание собирается
## после отъезда, а не в тот же кадр.
##
## Длина модели `car.glb`, м: по ней машина ставится в зазор от проёма и
## считается уехавшей из кадра. `tools/build_actors.py` строит кузов ровно такой
## длины; высота и ширина у модели свои, и здесь они никому не нужны.
const CAR_LENGTH: float = 2.4
const CAR_GAP: float = 0.36
const CAR_SPEED: float = 9.6
## Машина стоит снаружи здания: за плоскостью игры, но перед стеной, чтобы
## Otto проходил перед ней, а не сквозь.
const CAR_Z: float = -0.6

## Толщина стен, которые только видны: задней стены коридора, дальней стены
## комнаты и перемычек над дверями. Тел у них нет — по Z никто не ходит.
const PANEL_THICKNESS: float = 0.1

## Свет греев-бокса (ADR-0021, решение 4): общий тон, при котором погашенный
## этаж виден, но тёмен, и одна лампа над крышей — у крыши ламп нет, а гаснуть
## она не должна никогда: ей светит город.
const AMBIENT_ENERGY: float = 0.35
const SKY := Color(0.03, 0.04, 0.07)
const ROOF_LIGHT_COLOR := Color(0.72, 0.78, 0.95)
const ROOF_LIGHT_ENERGY: float = 0.9
const ROOF_LIGHT_RANGE: float = 12.0
const ROOF_LIGHT_HEIGHT: float = 4.0

## Насколько злее агенты и насколько хуже слушается кабина по тревоге.
const ALARM_MENACE: float = 1.5
const ALARM_CAR_DELAY: float = 0.6

## На сколько этажей дальше видимой полосы дверь ещё выпускает агентов.
##
## Запас нужен, чтобы агент не появлялся на глазах у игрока в середине кадра:
## дверь отдаёт его за кромкой, и в кадр он уже входит своим ходом.
const AGENT_SPAWN_MARGIN: int = 1

## Ближе этого дверь агента не выпускает, м.
##
## Иначе агент появляется прямо на Otto: двери стоят на местах этажа, и стоящий
## у двери получал выходящего в упор, — а с такого расстояния не помогают ни
## уклонение, ни выстрел первым. Дверь просто ждёт, пока игрок отойдёт.
const AGENT_SAFE_RELEASE: float = 2.88

## На сколько дальше того же запаса агент живёт, прежде чем его уберут.
##
## Больше запаса на выпуск нарочно: совпади они, агент у самой кромки то
## появлялся бы, то исчезал на дрожании камеры.
const AGENT_KEEP_MARGIN: int = 3

## Сколько Otto лежит, прежде чем вернуться в игру, с.
const OTTO_RESPAWN_DELAY: float = 1.2


## Пост у агентской двери: сама дверь, её этаж и тот, кого она уже выпустила.
##
## Этаж считается один раз на здание: двери не ходят, а [method _tend_agents]
## перебирает их каждый кадр — выводить этаж из координаты по шестьдесят раз
## в секунду для полусотни дверей незачем.
class AgentPost:
	extends RefCounted

	var door: Door = null
	var floor_index: int = 0
	## Кто стоит за дверью прямо сейчас. Пусто — дверь свободна.
	var agent: Enemy = null
	## Створка уже идёт под следующего агента, но сам он ещё не показался.
	##
	## Дверь в этом состоянии считается занятой и место под потолком живых
	## занимает: иначе за время телеграфа успело бы открыться сколько угодно
	## дверей, и агенты вывалились бы разом сверх потолка (ADR-0020).
	var opening: bool = false
	## Сколько двери ещё ждать, прежде чем выпустить следующего, с.
	var wait: float = 0.0


## Правила здания. Пустые — значит берутся по умолчанию.
@export var rules: BuildingRules

## Сид здания. Им служит номер здания: раскладка меняется от здания к зданию.
@export var building_seed: int = 1

## Выпускать ли агентов из дверей. Выключается в тестах проходимости: они
## проверяют, что здание проходится, а не что бой выигрывается.
@export var spawn_agents: bool = true

var _plan: BuildingPlan
var _doors: Array[Door] = []
var _cars: Array[ElevatorCar] = []
## Одежда шахт отдельным узлом: полсотни частей на здание не должны попадать
## под каждый обход детей уровня. Стены комнаты — там же и по той же причине.
var _shafts: BuildingShafts = null
var _walls: Node3D = null
var _lighting := FloorLighting.new()
## Какие этажи горели в прошлом кадре: пересчитывать их каждый кадр незачем.
## Пустой полосой служит (0, -1): у неё конец раньше начала, а (-1, -1) теперь
## означает «горит крыша» — это настоящий уровень, и совпадение молчало бы.
var _lit_span := Vector2i(0, -1)
## Лампы здания: их свет гасится за пределами кадра. Упавшие лампы убирают себя
## сами, поэтому перед обращением проверяется живость.
var _lamps: Array[Lamp] = []
## Посты у агентских дверей, по одному на дверь. Двери здания не выпускают всех
## разом — только те, чей этаж рядом с игроком (ADR-0014, пункт 4).
var _posts: Array[AgentPost] = []
## Здание сдано. Событие однократное: по нему main собирает следующее здание.
var _cleared: bool = false
## Машина у выхода и её отъезд: пока она едет, здание ещё не сдано.
var _car: Node3D = null
var _car_leaving: bool = false
## Куда машина уезжает: -1 влево, +1 вправо. Та же сторона, с которой она стоит.
var _car_towards: float = 1.0
var _exit_position := Vector2.ZERO
## Трос вступления и докуда по нему ехать, в плоскости правил. Пока едет —
## Otto не слушается ввода.
var _rope: MeshInstance3D = null
var _sliding: bool = false
var _rope_target: float = 0.0

@onready var otto: Otto = $Otto


func _ready() -> void:
	if rules == null:
		rules = BuildingRules.new()
	_plan = BuildingPlan.generate(rules, building_seed)

	_walls = Node3D.new()
	_walls.name = "Walls"
	add_child(_walls)
	_build_geometry()
	_build_room()
	_spawn_shafts()
	_spawn_escalators()
	_spawn_doors()
	_spawn_lamps()
	_spawn_exit()
	_light_building()

	# Otto начинает с крыши, как в оригинале, и там, где нет проёмов. Крыша —
	# свой уровень над зданием, а не нулевой этаж: ADR-0014, пункт 1.
	# Спускается он туда по тросу — как в порте (ADR-0017, решение 4).
	var roof := BuildingRules.ROOF
	var landing := Vector2(_plan.safe_x(rules, roof), rules.floor_surface(roof))
	otto.global_position = WorldSpace.to_scene(landing - Vector2(0.0, ROPE_DROP))
	_start_the_slide(landing)
	otto.died.connect(_on_otto_died)
	GameState.instance().alarm_raised.connect(_on_alarm_raised)
	if GameState.instance().alarm.raised:
		# Здание заведено уже при включённой сирене — редкость, но бывает.
		_on_alarm_raised()
	otto.apply_camera_bounds(Rect2(0.0, 0.0, rules.width, rules.total_height()))


## Гасит всё, что уехало из кадра. Ламп в здании тридцать, а в кадр влезает
## два с половиной этажа — ADR-0010, пункт 8.
func _process(delta: float) -> void:
	var view := otto.camera_view()
	if _car_leaving:
		_move_car(delta, view)

	var span := VisibleFloors.around(rules, view)
	_shroud_agents()
	# Агенты пересчитываются каждый кадр, а не только на смене полосы: дверь ждёт
	# своей паузы, и пропустив кадр смены, она не выпустила бы никого до следующей.
	if spawn_agents:
		_tend_agents(span, delta)

	if span == _lit_span:
		return

	_lit_span = span
	# Свет лампы кладёт тени, то есть стоит дорого, и горит только в кадре.
	for lamp: Lamp in _lamps:
		if not is_instance_valid(lamp):
			continue
		lamp.set_light_visible(VisibleFloors.covers(span, lamp.floor_index))


## Раскладка, по которой собрано здание.
func plan() -> BuildingPlan:
	return _plan


## Двери здания: по ним видно, какие красные ещё не собраны.
func doors() -> Array[Door]:
	return _doors


## Двери, из которых выходят агенты.
##
## Не то же самое, что обычные двери здания: красная попадает сюда, когда из неё
## забрали документ (ADR-0020, решение 6). Считается по постам, а не по списку
## дверей, потому что пост — это и есть «дверь на довольствии».
func agent_doors() -> Array[Door]:
	var serving: Array[Door] = []
	for post: AgentPost in _posts:
		serving.append(post.door)
	return serving


## Где стоит выход из здания, в плоскости правил.
func exit_position() -> Vector2:
	return _exit_position


## Погашен ли этаж целиком — все его зоны. Гаснут они навсегда: сбитая лампа
## обратно не загорается.
func is_dark(floor_index: int) -> bool:
	return _lighting.is_dark(floor_index)


## Темно ли в точке этажа: погашена ли зона ближайшей к ней лампы (ADR-0023).
func is_dark_at(floor_index: int, x: float) -> bool:
	return _lighting.is_dark_at(floor_index, x)


## Режет перекрытие на куски между проёмами.
##
## Сам разрез — в [method BuildingPlan.spans_between]: по тем же кускам строится
## граф достижимости, и второй такой же счёт рано или поздно разъехался бы с этим.
## Проёмы принимаются в любом порядке.
##
## Статический, чтобы проверяться тестами без сцены.
## [param bounds] — левый и правый края перекрытия ([method BuildingRules.slab_span]):
## здание расширяется книзу, и перекрытие лежит не во всю ширину здания, а от стены
## до стены — своего этажа или нижнего, смотря какой шире.
static func slab_segments(
	surface: float, gaps: Array[Vector2], bounds: Vector2, thickness: float
) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for span in BuildingPlan.spans_between(gaps, bounds):
		rects.append(Rect2(span.x, surface, span.y - span.x, thickness))
	return rects


func _build_geometry() -> void:
	var slab := GreyboxLook.surface(GreyboxLook.SLAB)
	var wall := GreyboxLook.surface(GreyboxLook.WALL)

	for index: int in rules.levels():
		var surface := rules.floor_surface(index)
		var bounds := rules.floor_span(index)
		var gaps := _plan.gaps_on(rules, index)
		# Перекрытие шире собственных стен там, где силуэт делает ступень: оно же
		# потолок нижнего этажа, а тот шире своего верхнего соседа.
		for rect in slab_segments(surface, gaps, rules.slab_span(index), rules.slab_height):
			_build_solid(rect, slab)
		_build_side_walls(index, surface, bounds, wall)


## Боковые стены уровня. Идут ступенями вслед за силуэтом, а не сплошными
## столбцами во всю высоту: здание расширяется книзу (ADR-0014, пункт 3).
##
## У крыши стена доходит до верха мира: это парапет, и он же не даёт шагнуть
## с крыши мимо здания. Прыжок берёт 2.4 м, и низкий бортик Otto перемахнул бы.
func _build_side_walls(
	index: int, surface: float, bounds: Vector2, material: StandardMaterial3D
) -> void:
	var top := rules.story_top(index)
	var height := surface + rules.slab_height - top
	if height <= 0.0:
		return

	_build_solid(Rect2(bounds.x, top, WALL_WIDTH, height), material)
	_build_solid(Rect2(bounds.y - WALL_WIDTH, top, WALL_WIDTH, height), material)


## Комната за коридором: задняя стена с проёмами дверей и дальняя стена.
##
## Это и есть глубина кадра по ADR-0021, решение 1: игра идёт в плоскости, а
## объём — за задней стеной, и виден он в проёмы. Проёмы режутся тем же
## [method BuildingPlan.spans_between], что и перекрытия: дверь занимает в стене
## ровно свою ширину, над ней — перемычка до потолка.
##
## Крыша стены не получает: над ней небо, а дальняя стена там — небоскрёб напротив,
## и он придёт задним планом в M19.
func _build_room() -> void:
	var back := GreyboxLook.surface(GreyboxLook.BACK_WALL)
	var far := GreyboxLook.surface(GreyboxLook.SKY_WALL)
	var back_z := WorldSpace.BACK_WALL_Z - PANEL_THICKNESS * 0.5
	var far_z := WorldSpace.BACK_WALL_Z - WorldSpace.ROOM_DEPTH

	for index: int in rules.levels():
		if index == BuildingRules.ROOF:
			continue
		var surface := rules.floor_surface(index)
		var top := rules.story_top(index)
		var bounds := rules.floor_span(index)
		var inner := Vector2(bounds.x + WALL_WIDTH, bounds.y - WALL_WIDTH)

		var openings := _openings_on(index)
		var lintel_top := surface - Door.LEAF_SIZE.y
		for span in BuildingPlan.spans_between(openings, inner):
			_build_panel(Rect2(span.x, top, span.y - span.x, surface - top), back, back_z)
		for opening in openings:
			_build_panel(
				Rect2(opening.x, top, opening.y - opening.x, lintel_top - top), back, back_z
			)

		_build_panel(Rect2(inner.x, top, inner.y - inner.x, surface - top), far, far_z)


## Проёмы в задней стене этажа: двери и, на нижнем, выход.
func _openings_on(index: int) -> Array[Vector2]:
	var openings: Array[Vector2] = []
	var half := Door.LEAF_SIZE.x * 0.5
	for spot in _plan.doors:
		if spot.floor_index == index:
			openings.append(Vector2(spot.x - half, spot.x + half))
	if index == rules.floors - 1:
		openings.append(Vector2(_plan.exit_x - EXIT_WIDTH * 0.5, _plan.exit_x + EXIT_WIDTH * 0.5))
	return openings


func _spawn_shafts() -> void:
	_shafts = BuildingShafts.new()
	add_child(_shafts)
	_shafts.dress(rules, _plan)
	for shaft in _plan.shafts:
		var stops := PackedFloat32Array()
		for index in range(shaft.top, shaft.bottom + 1):
			stops.append(rules.floor_surface(index))

		var car := CAR_SCENE.instantiate() as ElevatorCar
		car.position.x = shaft.x
		add_child(car)
		car.setup(stops)
		_cars.append(car)
		_spawn_shaft_pit(shaft)


## Вступление: Otto съезжает по тросу на крышу.
##
## Пока едет, он «на эскалаторе» — ввод не действует, физика молчит, и коорди-
## натой распоряжается уровень. Тот же приём, что у двери и эскалатора: своего
## состояния ради одного кадра вступления заводить незачем.
func _start_the_slide(landing: Vector2) -> void:
	_rope_target = landing.y
	_sliding = true
	otto.board_escalator()
	# Вступление длится полсекунды, а здание — минуты: держать ради него обход
	# физики на всё здание незачем, [method _finish_the_slide] его и снимет.
	set_physics_process(true)

	_rope = GreyboxLook.box(
		Vector3(ROPE_WIDTH, landing.y, ROPE_WIDTH), GreyboxLook.surface(GreyboxLook.WALL)
	)
	_rope.position = WorldSpace.to_scene(Vector2(landing.x, landing.y * 0.5))
	_rope.position.z = -0.3
	add_child(_rope)


## Довозит Otto по тросу и убирает трос: он часть вступления, а не здания.
##
## Трос ведёт Otto, только пока тот выше крыши. Переставили ниже — вступление
## кончилось само: так инструменты съёмки и тесты ставят его куда им надо,
## не зная про трос вовсе.
func _physics_process(delta: float) -> void:
	if not _sliding:
		return

	var at := WorldSpace.to_plane(otto.global_position)
	if at.y < _rope_target:
		at.y = minf(at.y + ROPE_SPEED * delta, _rope_target)
		otto.global_position = WorldSpace.to_scene(at)
	if at.y >= _rope_target:
		_finish_the_slide()


## Отдаёт управление игроку и убирает трос.
func _finish_the_slide() -> void:
	_sliding = false
	set_physics_process(false)
	otto.leave_escalator()
	if _rope != null:
		_rope.queue_free()
		_rope = null


## Дно шахты: упавший сюда разбивается, вошедший ногами с этажа — нет.
func _spawn_shaft_pit(shaft: BuildingPlan.ShaftSpot) -> void:
	var surface := rules.floor_surface(shaft.bottom)
	var pit := _zone(
		Rect2(
			shaft.x - rules.shaft_width * 0.5, surface - PIT_HEIGHT, rules.shaft_width, PIT_HEIGHT
		)
	)
	pit.body_entered.connect(_on_pit_entered)
	add_child(pit)


func _spawn_escalators() -> void:
	for spot in _plan.escalators:
		var escalator := ESCALATOR_SCENE.instantiate() as Escalator
		escalator.position = WorldSpace.to_scene(
			Vector2(spot.x, rules.floor_surface(spot.floor_index))
		)
		add_child(escalator)

		var descent := Vector2(spot.towards * rules.escalator_run, rules.floor_height)
		# Перегиб — в самом проёме: через него идут и полотно, и поездка, поэтому
		# пассажир проходит сквозь дыру, а не сквозь плиту.
		var gap := spot.gap(rules)
		var bend := Vector2((gap.x + gap.y) * 0.5 - spot.x, rules.slab_height + 0.04)
		escalator.setup(descent, bend)


func _spawn_doors() -> void:
	# Счёт уровень не трогает: он копится от здания к зданию, обнуляет его тот,
	# кто начинает партию. Здесь объявляется только, сколько здесь документов.
	var game := GameState.instance()
	var documents := 0
	for spot in _plan.doors:
		var door := DOOR_SCENE.instantiate() as Door
		door.position = WorldSpace.to_scene(Vector2(spot.x, rules.floor_surface(spot.floor_index)))
		door.has_document = spot.has_document
		add_child(door)
		_doors.append(door)

		if not door.is_pending():
			_enlist_door(door)
			continue
		documents += 1
		door.document_taken.connect(game.collect_document)
		# Опустевшая дверь становится обычной и начинает выпускать агентов:
		# она и выглядит обычной (ADR-0020, решение 6). Раньше красная дверь
		# оставалась вечным укрытием на всё здание.
		door.document_taken.connect(_enlist_door.bind(door))
	game.start_building(documents)


func _spawn_lamps() -> void:
	for spot in _plan.lamps:
		var lamp := LAMP_SCENE.instantiate() as Lamp
		var hang := rules.floor_surface(spot.floor_index) - LAMP_HANG_HEIGHT
		lamp.position = WorldSpace.to_scene(Vector2(spot.x, hang))
		# Этаж лампы известен здесь, и обратно из координаты его не выводят: она
		# висит ровно на середине пролёта, где округление решает случай.
		lamp.floor_index = spot.floor_index
		# Зона лампы считается от того, что висит: правило темноты узнаёт о
		# лампе здесь же, где она вешается.
		_lighting.hang(spot.floor_index, spot.x)
		lamp.crushed.connect(_on_lamp_crushed)
		lamp.fell.connect(_on_lamp_fell.bind(lamp.floor_index, spot.x))
		add_child(lamp)
		lamp.hang(LAMP_HANG_HEIGHT, rules.floor_height - rules.slab_height)
		_lamps.append(lamp)


## Выход из здания. Не запирается: без всех документов он отправляет обратно
## наверх, к несобранной двери (ADR-0005, пункт 5).
##
## Сам проём вырезан в задней стене ([method _build_room]); здесь — зона, порог
## и машина. Порог светится: выход — цель, и читаться он обязан на погашенном
## этаже (ADR-0019, решение 5).
func _spawn_exit() -> void:
	var bottom := rules.floors - 1
	var surface := rules.floor_surface(bottom)
	var centre := _plan.exit_x
	var area := Rect2(centre - EXIT_WIDTH * 0.5, surface - EXIT_HEIGHT, EXIT_WIDTH, EXIT_HEIGHT)

	var zone := _zone(area)
	zone.body_entered.connect(_on_exit_entered)
	add_child(zone)
	_exit_position = area.get_center()

	var threshold := GreyboxLook.box(
		Vector3(EXIT_WIDTH, 0.05, PANEL_THICKNESS), GreyboxLook.marker(GreyboxLook.DOOR)
	)
	threshold.position = WorldSpace.to_scene(Vector2(centre, surface - 0.025))
	threshold.position.z = WorldSpace.BACK_WALL_Z + PANEL_THICKNESS
	add_child(threshold)
	_spawn_car(area)


## Машина у выхода. Стоит на полу нижнего этажа рядом с проёмом, за плоскостью
## игры: она снаружи здания, и заходить на неё Otto не может — это вид, не тело.
func _spawn_car(exit_area: Rect2) -> void:
	_car = EXIT_CAR_MODEL.instantiate() as Node3D
	_car.name = "ExitCar"
	# Уезжает в ближнюю сторону: там же и стоит. В дальнюю машина ехала бы через
	# всё здание, и «уехал» растянулось бы на пять секунд вместо одной.
	_car_towards = -1.0 if exit_area.get_center().x < rules.width * 0.5 else 1.0
	var x := (
		exit_area.get_center().x + _car_towards * (EXIT_WIDTH * 0.5 + CAR_GAP + CAR_LENGTH * 0.5)
	)
	# Модель стоит колёсами в своём нуле, капотом в +X; в другую сторону она
	# разворачивается целиком.
	_car.position = WorldSpace.to_scene(Vector2(x, exit_area.end.y))
	_car.position.z = CAR_Z
	if _car_towards < 0.0:
		_car.rotation.y = PI
	add_child(_car)


## Otto сел в машину: она уезжает, и только по её отъезду здание считается
## сданным (ADR-0011, пункт 14). Otto на это время прячется, как за дверью.
func _drive_away(runner: Otto) -> void:
	_car_leaving = true
	runner.enter_door()
	Sounds.play(Sounds.CAR_AWAY)


func _move_car(delta: float, view: Rect2) -> void:
	_car.position.x += _car_towards * CAR_SPEED * delta

	# Уехала — значит уехала из кадра, а не за границу здания: кадр и есть то,
	# что видит игрок, а до границы машина ползла бы впятеро дольше.
	var left := _car.position.x - CAR_LENGTH * 0.5
	var gone := left + CAR_LENGTH < view.position.x or left > view.end.x
	if gone:
		_car_leaving = false
		building_cleared.emit()


func _on_exit_entered(body: Node3D) -> void:
	var runner := body as Otto
	if runner == null:
		return
	if GameState.instance().all_documents_collected():
		if not _cleared:
			_cleared = true
			_drive_away(runner)
		return

	# Перенос отложен: сигнал приходит посреди разбора перекрытий, и двигать
	# тело прямо здесь движок просит не делать.
	_send_back_for_documents.call_deferred(runner)


## Возвращает Otto к самой верхней несобранной двери.
func _send_back_for_documents(runner: Otto) -> void:
	var pending := PackedVector2Array()
	for door in _doors:
		if door.is_pending():
			pending.append(door.mat_position())

	var index := DocumentRoute.door_to_return_to(pending)
	if index < 0:
		return
	runner.global_position = WorldSpace.to_scene(pending[index])


## Лампа накрыла агента по дороге вниз — самый дорогой способ убийства.
func _on_lamp_crushed(agent: Enemy) -> void:
	if agent.is_dead():
		return
	agent.kill(true)
	var points := GameState.kill_score(GameState.LAMP_SCORE, agent.is_in_the_dark())
	GameState.instance().add_score(points)


## Лампа долетела до пола: её зона гаснет и обратно уже не загорается.
##
## Гасить нечего: свет лампы ушёл вместе с ней. Здесь остаётся правило —
## запомнить темноту; кто в ней стоит, пересчитает [method _shroud_agents].
func _on_lamp_fell(index: int, x: float) -> void:
	_lighting.darken(index, x)
	_shroud_agents()


## Раздаёт агентам темноту: свою — за неё дороже убийство — и тень Otto, от
## которой зависит, видят ли они его вовсе (ADR-0023, решение 8).
##
## Каждый кадр, а не по событию: агенты ходят по этажу, и зона под ними
## меняется на ходу. Живых в здании не больше восьми, счёт дешёвый.
func _shroud_agents() -> void:
	var here := _floor_of(otto)
	var otto_in_the_dark := _lighting.is_dark_at(here, otto.global_position.x)
	for agent in agents():
		if agent.is_dead():
			continue
		agent.set_in_the_dark(_lighting.is_dark_at(_floor_of(agent), agent.global_position.x))
		agent.set_target_in_the_dark(otto_in_the_dark)


## Все агенты здания: они лежат прямо в уровне, рядом с геометрией.
##
## Публичный: бот и прогон снаружи ищут ровно то же самое, и три копии одного
## перебора детей разъехались бы при первой же правке дерева уровня.
func agents() -> Array[Enemy]:
	var found: Array[Enemy] = []
	for child in get_children():
		var agent := child as Enemy
		if agent != null:
			found.append(agent)
	return found


func _agents_on(index: int) -> Array[Enemy]:
	var found: Array[Enemy] = []
	for agent in agents():
		if _floor_of(agent) == index:
			found.append(agent)
	return found


## Этаж, на котором стоит узел. Единственное место, где высота сцены снова
## становится высотой правил.
func _floor_of(node: Node3D) -> int:
	return rules.floor_index_near(WorldSpace.to_plane(node.global_position).y)


## Держит в здании ровно тех агентов, до которых игроку есть дело: выпускает
## их у дверей рядом с кадром и убирает тех, кто остался далеко позади.
##
## Раньше все 55 выходили разом в [method _ready] и жили до конца здания. Это
## и не давало играть — двое стояли на крыше в зоне огня от точки старта, — и
## держало полсотни тел с физикой и ИИ на каждом кадре (ADR-0014, пункт 4).
##
## Живых не больше, чем разрешают правила, и выпускается за кадр один — тот, чья
## дверь ближе к игроку. Полоса выпуска шире кадра, и внизу здания на каждом её
## этаже по две двери: без потолка живых набиралось до восемнадцати, и нижние
## этажи выходили тиром (ADR-0016, пункт 6).
##
## Один за кадр — не бережливость, а та же мера: двери и так ждут свою паузу,
## а вываливать пятерых разом на смене полосы незачем.
func _tend_agents(span: Vector2i, delta: float) -> void:
	var here := _floor_of(otto)
	var live := 0
	var nearest: AgentPost = null
	var nearest_gap := 0

	for post: AgentPost in _posts:
		# Живость проверяется прямо по полю: свой агент у двери один, а чужого
		# сюда положить некому.
		if is_instance_valid(post.agent) and not post.agent.is_dead():
			if not _within(span, post.floor_index, AGENT_KEEP_MARGIN):
				post.agent.queue_free()
				post.agent = null
				post.door.dismiss_agent()
				continue
			live += 1
			# Створка идёт обратно, как только агент освободил проём: открытая
			# дверь в кадре значит «оттуда сейчас полезут», и держать её
			# открытой при живом агенте — размывать знак (ADR-0020, решение 4).
			if not post.agent.is_emerging():
				post.door.dismiss_agent()
			continue

		# Створка уже идёт: ждём, пока откроется, и только тогда выпускаем.
		# Место под потолком живых агент занимает уже сейчас.
		if post.opening:
			if not _within(span, post.floor_index, AGENT_SPAWN_MARGIN):
				post.door.dismiss_agent()
				post.opening = false
				continue
			live += 1
			if post.door.agent_may_step_out():
				post.agent = _release_agent(post)
				post.opening = false
			continue

		# Проём свободен: агента убили или он уехал из полосы. Створка идёт
		# обратно и отсюда тоже — убитый ровно в тот кадр, когда перестал быть
		# неуязвимым, до ветки живых не доживает, и дверь, которой об этом не
		# сказали, осталась бы стоять открытой навсегда: занятую [method
		# Door.summon_agent] больше не откроет. Вызов у закрытой — пустышка.
		post.door.dismiss_agent()

		# Дверь, чей агент умер или уехал, ждёт свою паузу и только потом
		# выпускает следующего. Пауза идёт игровым временем, а не настенными
		# часами: на паузе здание замирает целиком, и смена агента не должна
		# приходить, пока игра стоит, — а под [member Engine.time_scale] она
		# должна ускоряться вместе со всем остальным, иначе прогон ботом видит
		# вчетверо более редких агентов, чем игрок.
		post.agent = null
		post.wait = maxf(post.wait - delta, 0.0)
		if post.wait > 0.0 or not _within(span, post.floor_index, AGENT_SPAWN_MARGIN):
			continue
		if _too_close_to_otto(post, here):
			continue
		# Створка ещё идёт за прошлым агентом — дверь не в счёт. Иначе она,
		# будучи ближайшей, забирала бы кадр себе и не выпускала никого: за
		# кадр выпускается один, и берётся он у ближайшей двери.
		if not post.door.can_summon():
			continue

		var gap := absi(post.floor_index - here)
		if nearest == null or gap < nearest_gap:
			nearest = post
			nearest_gap = gap

	if nearest != null and live < rules.agents_at_once:
		# Не агент, а просьба открыться: сам он покажется, когда створка дойдёт.
		nearest.opening = nearest.door.summon_agent()


## Ставит дверь на довольствие: с этой минуты она выпускает агентов.
##
## Агента при этом никто не выпускает: дверь отдаёт своего, когда её этаж
## подходит к игроку. Раньше на сборке здания выходили все 55 разом, и двое из
## них стояли на крыше в зоне огня от точки старта — ADR-0014, пункт 4.
##
## Этаж считается один раз: двери не ходят, а [method _tend_agents] перебирает
## их каждый кадр.
func _enlist_door(door: Door) -> void:
	var post := AgentPost.new()
	post.door = door
	post.floor_index = rules.floor_index_near(door.mat_position().y)
	_posts.append(post)


## Стоит ли Otto вплотную к двери. Считается по горизонтали: дверь и Otto на
## разных этажах друг другу не мешают, а этаж двери уже проверен полосой.
##
## Этаж Otto ([param here]) приходит снаружи: дверей в здании полсотни, и выводить
## его из координаты заново для каждой — полсотни одинаковых счётов за кадр.
func _too_close_to_otto(post: AgentPost, here: int) -> bool:
	if post.floor_index != here:
		return false
	return absf(post.door.mat_position().x - otto.global_position.x) < AGENT_SAFE_RELEASE


## Попадает ли уровень в полосу [param span], растянутую на [param margin] этажей.
static func _within(span: Vector2i, index: int, margin: int) -> bool:
	return index >= span.x - margin and index <= span.y + margin


## Ставит агента в открытый проём и отдаёт его: дверь помнит своего, чтобы не
## выпустить второго, пока первый жив.
##
## Зовётся только тогда, когда створка уже открыта: до этого в двери нет проёма,
## из которого можно выйти.
func _release_agent(post: AgentPost) -> Enemy:
	var mat := post.door.mat_position()
	var agent := ENEMY_SCENE.instantiate() as Enemy
	# Правила отдаются до дерева: так агент входит в него уже настроенным, и
	# заводить себе значения по умолчанию ему не приходится.
	agent.apply_rules(rules)
	add_child(agent)
	agent.global_position = WorldSpace.to_scene(mat)
	agent.setup(otto, signf(otto.global_position.x - mat.x))
	agent.set_in_the_dark(_lighting.is_dark_at(post.floor_index, mat.x))
	# Тень Otto отдаётся сразу, не дожидаясь кадра: иначе первый шаг агент делал
	# бы, видя Otto там, где его не видно.
	agent.set_target_in_the_dark(_lighting.is_dark_at(_floor_of(otto), otto.global_position.x))
	agent.set_menace(_menace())
	agent.died.connect(_on_agent_died.bind(post))
	return agent


## Насколько злее агенты этого здания прямо сейчас: к росту от здания к зданию
## добавляется тревога, если она уже включилась. Сам счёт — в [BuildingRules],
## там же общий на обе надбавки потолок.
func _menace() -> float:
	var alarmed := GameState.instance().alarm.raised
	return rules.menace_with(ALARM_MENACE if alarmed else 1.0)


## Сирена: агенты злеют, кабины начинают отвечать с задержкой.
func _on_alarm_raised() -> void:
	# Сирена работает с M5b, а звучать ей было нечем: теперь вместо темы здания
	# идёт мотив тревоги, и снять его можно только новым зданием.
	Sounds.play_music(Sounds.ALARM_THEME)
	for car in _cars:
		car.set_response_delay(ALARM_CAR_DELAY)
	for agent in agents():
		agent.set_menace(_menace())


func _on_agent_died(_agent: Enemy, post: AgentPost) -> void:
	# Смена не по таймеру, а отсчётом у самой двери: выпуском теперь заведует
	# [method _tend_agents], и он же решает, подошёл ли этаж к игроку. Таймер
	# выпустил бы агента у двери на другом конце здания, до которой нет дела.
	post.wait = rules.agent_respawn_delay / _menace()


func _on_otto_died() -> void:
	# Жизнь снимается сразу, чтобы счётчик не врал, пока тело лежит.
	if not GameState.instance().lose_life():
		return
	# Как и смена агента, возвращение в игру не идёт на паузе.
	var timer := get_tree().create_timer(OTTO_RESPAWN_DELAY, false)
	timer.timeout.connect(_respawn_otto)


## Возвращает Otto в игру на том же этаже, но подальше от тех, кто его там убил.
##
## Место выбирается по живым агентам, а не по порядку мест: агент, убивший Otto,
## никуда не делся, и возвращение на то же место — это смерть в петле. На пустом
## этаже выбор вырождается в первое свободное место, как было раньше.
func _respawn_otto() -> void:
	var index := _floor_of(otto)
	var surface := rules.floor_surface(index)
	otto.global_position = WorldSpace.to_scene(Vector2(_safest_x(index), surface))
	otto.revive()


func _safest_x(index: int) -> float:
	var spots := _plan.safe_spots(rules, index)
	if spots.is_empty():
		return _plan.safe_x(rules, index)

	var agents := _agents_on(index)
	var best := spots[0]
	var best_gap := -1.0
	for x: float in spots:
		var gap := INF
		for agent in agents:
			if agent.is_dead():
				continue
			gap = minf(gap, absf(agent.global_position.x - x))
		if gap > best_gap:
			best_gap = gap
			best = x
	return best


func _on_pit_entered(body: Node3D) -> void:
	var victim := body as Otto
	if victim == null:
		return
	var deadly := ShaftHazards.is_deadly_fall(
		victim.is_grounded(), victim.is_riding(), victim.fall_height(), victim.jump_height()
	)
	if deadly:
		victim.kill()


## Твёрдая коробка на месте прямоугольника правил: тело и вид.
##
## Глубиной на коридор и комнату вместе: перекрытие — пол не только коридора,
## но и комнаты за стеной, иначе в проём двери было бы видно пустоту под ногами.
## Передняя грань приходится на переднюю грань коридора, а не на плоскость игры.
func _build_solid(rect: Rect2, material: StandardMaterial3D) -> void:
	var depth := WorldSpace.CORRIDOR_DEPTH + WorldSpace.ROOM_DEPTH
	var size := Vector3(rect.size.x, rect.size.y, depth)
	var centre := WorldSpace.to_scene(rect.get_center())
	centre.z = WorldSpace.CORRIDOR_DEPTH * 0.5 - depth * 0.5

	var body := StaticBody3D.new()
	body.position = centre

	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	body.add_child(GreyboxLook.box(size, material))

	add_child(body)


## Стена, которая только видна: без тела, толщиной [constant PANEL_THICKNESS],
## серединой на [param z].
func _build_panel(rect: Rect2, material: StandardMaterial3D, z: float) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var panel := GreyboxLook.box(Vector3(rect.size.x, rect.size.y, PANEL_THICKNESS), material)
	panel.position = WorldSpace.to_scene(rect.get_center())
	panel.position.z = z
	_walls.add_child(panel)


## Зона на месте прямоугольника правил, ловящая Otto. Толщиной в тело: она
## лежит в плоскости игры, как и всё, с чем он взаимодействует.
func _zone(rect: Rect2) -> Area3D:
	var zone := Area3D.new()
	zone.collision_layer = 0
	zone.collision_mask = 2
	zone.position = WorldSpace.to_scene(rect.get_center())

	var shape := BoxShape3D.new()
	shape.size = Vector3(rect.size.x, rect.size.y, WorldSpace.BODY_DEPTH)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	zone.add_child(collision)
	return zone


## Зажигает здание: общий тон и лампа над крышей.
##
## Светлым этаж делает собственный источник — лампа, — а не отсутствие темноты:
## на этом держится правило темноты (ADR-0010, пункт 3). Общий тон низкий и
## нужен только затем, чтобы погашенный этаж был тёмен, а не чёрен: агенты в
## темноте продолжают стрелять, и игрок обязан видеть, во что стрелять в ответ.
##
## Крыша ламп не имеет и не гаснет никогда: ей светит город. Пока города нет
## (M19), его заменяет один источник над крышей.
func _light_building() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = rules.palette.dark
	environment.ambient_light_energy = AMBIENT_ENERGY
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var roof_span := rules.floor_span(BuildingRules.ROOF)
	var over_roof := Vector2(
		(roof_span.x + roof_span.y) * 0.5,
		rules.floor_surface(BuildingRules.ROOF) - ROOF_LIGHT_HEIGHT
	)
	var sky_light := OmniLight3D.new()
	sky_light.light_color = ROOF_LIGHT_COLOR
	sky_light.light_energy = ROOF_LIGHT_ENERGY
	sky_light.omni_range = ROOF_LIGHT_RANGE
	sky_light.position = WorldSpace.to_scene(over_roof)
	add_child(sky_light)
