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
const ESCALATOR_SCENE := preload("res://src/systems/escalators/escalator.tscn")
const DOOR_SCENE := preload("res://src/systems/doors/door.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const LAMP_SCENE := preload("res://src/systems/lighting/lamp.tscn")

## Дно шахты: сюда падает тот, кто шагнул в пустой проём.
const PIT_HEIGHT: float = 0.6

## На сколько ниже потолка висит середина лампы, м.
##
## Под потолком, как в оригинале: при просвете 3.0 м низ лампы на 2.52 —
## 84% просвета против 82% у оригинала. Два процента — это запас, на котором
## держится «не из прыжка»: Otto упирается головой в потолок, когда ступни
## поднялись на 1.32 м, и его пуля идёт не выше 2.47. Сбивают лампу из кабины,
## как в 1983 (ADR-0026, решение 5).
##
## От потолка, а не от пола: этаж другой высоты — а такие собирают тесты —
## иначе вешал бы лампу в плиту или посреди комнаты.
const LAMP_DROP: float = Proportions.LAMP_CORD + Proportions.LAMP.y * 0.5

## Высота зоны выхода из здания. Ширина — [constant BuildingShell.EXIT_WIDTH]:
## ей же оболочка режет проём в задней стене. Выросла вместе с Otto
## (ADR-0026, решение 7).
const EXIT_HEIGHT: float = Proportions.BODY * 0.95

## Вывеска над выходом: габарит и на сколько выше проёма стены висит её
## середина, м (ADR-0023, решение 6).
const EXIT_SIGN_SIZE := Vector3(1.2, 0.18, 0.06)
const EXIT_SIGN_RISE: float = 0.3

## Насколько хуже слушается кабина по тревоге, с.
const ALARM_CAR_DELAY: float = 0.6

## С какого отрыва по этажам агент уходит в ближайшую дверь: в ROM — 80 px
## экрана, этаж и две трети (@041F).
const AGENT_FAR_FLOORS: int = 2

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
	## Ячейка агента, которого дверь выпускает или выпустила; -1 — никакая.
	var slot: int = -1


## Правила здания. Пустые — значит берутся по умолчанию.
@export var rules: BuildingRules

## Сид здания: номер здания с солью партии ([method GameState.building_seed]).
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
## Оболочка здания: перекрытия, стены и комната за коридором. Ставит их она,
## а уровень населяет готовое — ADR-0024 развёл это по узлам.
var _shell: BuildingShell = null
## Рёбра — торцы плит, плинтус, пилястры — тоже своим узлом (ADR-0023, решение 4).
var _ribs: BuildingRibs = null
var _lighting := FloorLighting.new()
## Какие этажи горели в прошлом кадре: пересчитывать их каждый кадр незачем.
## Пустой полосой служит (0, -1): у неё конец раньше начала, а (-1, -1) теперь
## означает «горит крыша» — это настоящий уровень, и совпадение молчало бы.
var _lit_span := Vector2i(0, -1)
## Лампы здания: их свет гасится за пределами кадра. Упавшие лампы убирают себя
## сами, поэтому перед обращением проверяется живость.
var _lamps: Array[Lamp] = []
## Эскалаторы здания: у каждого свой источник, и гаснет он вне кадра, как лампы.
var _escalators: Array[Escalator] = []
## Посты у агентских дверей, по одному на дверь. Двери здания не выпускают всех
## разом — только те, чей этаж рядом с игроком (ADR-0014, пункт 4).
var _posts: Array[AgentPost] = []
## Жребий выпуска агентов по ROM и сколько ещё длится тревога агентов, с.
var _spawn := AgentSpawn.new()
var _alert_left: float = 0.0
## Здание сдано. Событие однократное: по нему main собирает следующее здание.
var _cleared: bool = false
## Машина у выхода: пока она едет, здание ещё не сдано.
var _car: ExitCar = null
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
	_spawn.rng.seed = building_seed

	_ribs = BuildingRibs.new()
	_ribs.name = "Ribs"
	_ribs.setup(rules, _plan)
	add_child(_ribs)
	_shell = BuildingShell.new()
	_shell.name = "Shell"
	add_child(_shell)
	_shell.build(rules, _plan, _ribs)
	var signs := FloorSigns.new()
	signs.name = "FloorSigns"
	add_child(signs)
	signs.hang(rules)
	_spawn_shafts()
	_spawn_escalators()
	_spawn_doors()
	_spawn_lamps()
	_spawn_exit()
	# Воздух, крыша, обстановка, город и погода — окружение без геймплея (ADR-0029).
	var scenery := BuildingScenery.new()
	scenery.name = "Scenery"
	add_child(scenery)
	scenery.build(rules, _plan, building_seed)

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
##
## Здесь только свет: он часть картинки, и считать его чаще кадра незачем.
func _process(_delta: float) -> void:
	var span := VisibleFloors.around(rules, otto.camera_view())
	if span == _lit_span:
		return

	_lit_span = span
	# Свет лампы кладёт тени, то есть стоит дорого, и горит только в кадре.
	for lamp: Lamp in _lamps:
		if not is_instance_valid(lamp):
			continue
		lamp.set_light_visible(VisibleFloors.covers(span, lamp.floor_index))
	# Столбы шахт — тем же правилом: их в здании втрое больше, чем ламп.
	if _shafts != null:
		_shafts.light_span(span)
	# Эскалатор светит в проём между двумя этажами: горит, пока в кадре хоть
	# один из них.
	for escalator: Escalator in _escalators:
		escalator.set_light_visible(
			(
				VisibleFloors.covers(span, escalator.floor_index)
				or VisibleFloors.covers(span, escalator.floor_index + 1)
			)
		)


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


## Дверь, из которой вышел агент, или null. Не ближайшая к нему: с M18e двери
## стоят через место, и вышедший бывает ближе к соседней (ADR-0028).
func door_of(agent: Enemy) -> Door:
	for post: AgentPost in _posts:
		if post.agent == agent:
			return post.door
	return null


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


func _spawn_shafts() -> void:
	_shafts = BuildingShafts.new()
	add_child(_shafts)
	_shafts.dress(rules, _plan)
	for shaft in _plan.shafts:
		# Верхний ярус пары не спускается на нижний этаж шахты: нижний упёрся бы
		# в дно. Поэтому остановки считаются по ведущему, а не по полосе.
		var lowest := shaft.bottom - 1 if shaft.double_deck else shaft.bottom
		var stops := PackedFloat32Array()
		for index in range(shaft.top, lowest + 1):
			stops.append(rules.floor_surface(index))

		var car := CAR_SCENE.instantiate() as ElevatorCar
		car.position.x = shaft.x
		add_child(car)
		# Кабина занимает просвет этажа целиком, как в оригинале: высоту она
		# берёт из правил, а не из своей сцены (ADR-0025, решение 10).
		car.fit_to_story(rules.floor_height - rules.slab_height, rules.shaft_width)
		car.setup(stops)
		_cars.append(car)
		if shaft.double_deck:
			_spawn_lower_deck(car, shaft)
		_spawn_shaft_pit(shaft)


## Вступление: Otto съезжает по тросу на крышу.
##
## Пока едет, он «на эскалаторе» — ввод не действует, физика молчит, и коорди-
## натой распоряжается уровень. Тот же приём, что у двери и эскалатора: своего
## состояния ради одного кадра вступления заводить незачем.
func _start_the_slide(landing: Vector2) -> void:
	_rope_target = landing.y
	_sliding = true
	otto.ride(true)

	_rope = GreyboxLook.box(
		Vector3(ROPE_WIDTH, landing.y, ROPE_WIDTH), GreyboxLook.surface(GreyboxLook.WALL)
	)
	_rope.position = WorldSpace.to_scene(Vector2(landing.x, landing.y * 0.5))
	_rope.position.z = -0.3
	add_child(_rope)


## Ход здания: вступление, отъезд машины, агенты у дверей.
##
## Всё это — физика, а не кадр, и раньше жило в [method Node._process]. Разница
## не косметическая: кадр идёт по настенным часам, физика — ровным шагом, а бот
## водит Otto шагами физики. Выпуск агентов от delta кадра означал, что на
## быстрой машине их выходит больше за тот же шаг бота, и один и тот же сид
## давал то четыре смерти, то пять. Ровно этот долг тянулся с M18a.
func _physics_process(delta: float) -> void:
	if _sliding:
		_slide_along(delta)
		return

	var view := otto.camera_view()
	if _car != null and _car.advance(delta, view):
		building_cleared.emit()

	_stir_agents(delta)
	_shroud_agents()
	# Агенты пересчитываются каждый шаг, а не только на смене полосы: дверь ждёт
	# своей паузы, и пропустив шаг смены, она не выпустила бы никого до следующей.
	if spawn_agents:
		_tend_agents(VisibleFloors.around(rules, view), delta)


## Довозит Otto по тросу и убирает трос: он часть вступления, а не здания.
##
## Трос ведёт Otto, только пока тот выше крыши. Переставили ниже — вступление
## кончилось само: так инструменты съёмки и тесты ставят его куда им надо,
## не зная про трос вовсе.
func _slide_along(delta: float) -> void:
	var at := WorldSpace.to_plane(otto.global_position)
	if at.y < _rope_target:
		at.y = minf(at.y + ROPE_SPEED * delta, _rope_target)
		otto.global_position = WorldSpace.to_scene(at)
	if at.y >= _rope_target:
		_finish_the_slide()


## Отдаёт управление игроку и убирает трос.
func _finish_the_slide() -> void:
	_sliding = false
	otto.ride(false)
	if _rope != null:
		_rope.queue_free()
		_rope = null


## Нижний ярус двухэтажной пары: этажом ниже ведущего и на его ходу.
##
## Ставится после ведущего, и это не случайность: ярус берёт высоту ведущего
## в том же кадре, а узлы обходятся в порядке дерева.
func _spawn_lower_deck(leader: ElevatorCar, shaft: BuildingPlan.ShaftSpot) -> void:
	var deck := CAR_SCENE.instantiate() as ElevatorCar
	deck.position.x = shaft.x
	add_child(deck)
	deck.fit_to_story(rules.floor_height - rules.slab_height, rules.shaft_width)
	deck.serve_as_deck(leader, rules.floor_height)
	# Ярус идёт в общий список наравне с ведущим: агент садится в тот, что стоит
	# вровень с его этажом, и какой это из двух — не его дело.
	_cars.append(deck)


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
		# Этаж известен здесь, и обратно из координаты его не выводят: по нему
		# уровень гасит источник пролёта вне кадра.
		escalator.floor_index = spot.floor_index
		add_child(escalator)
		_escalators.append(escalator)

		var descent := Vector2(spot.towards * rules.escalator_run, rules.floor_height)
		# Перегиб — в самом проёме: через него идут и полотно, и поездка, поэтому
		# пассажир проходит сквозь дыру, а не сквозь плиту.
		var gap := spot.gap(rules)
		# Проём — в координатах эскалатора: обрамление ставит он сам, а правила
		# о том, где стоит его узел, знать не обязаны.
		var edges := Vector2(gap.x - spot.x, gap.y - spot.x)
		escalator.setup(descent, spot.bend(rules), edges, rules.slab_height)


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


## На сколько выше пола висит середина лампы при этих правилах, м.
static func lamp_height(of_rules: BuildingRules) -> float:
	return of_rules.floor_height - of_rules.slab_height - LAMP_DROP


func _spawn_lamps() -> void:
	for spot in _plan.lamps:
		var lamp := LAMP_SCENE.instantiate() as Lamp
		var hang := rules.floor_surface(spot.floor_index) - lamp_height(rules)
		lamp.position = WorldSpace.to_scene(Vector2(spot.x, hang))
		# Этаж лампы известен здесь, и обратно из координаты его не выводят: под
		# потолком она ближе к полу этажа выше, чем к своему.
		lamp.floor_index = spot.floor_index
		# Зона лампы считается от того, что висит: правило темноты узнаёт о
		# лампе здесь же, где она вешается.
		_lighting.hang(spot.floor_index, spot.x)
		lamp.crushed.connect(_on_lamp_crushed)
		lamp.fell.connect(_on_lamp_fell.bind(lamp.floor_index, spot.x))
		add_child(lamp)
		lamp.hang(lamp_height(rules), rules.floor_height - rules.slab_height)
		lamp.tint(rules.palette.lit, BuildingShell.PALETTE_SHARE)
		_lamps.append(lamp)
	# Тёмные этажи карты ламп не получают, и темнота им объявляется здесь же,
	# где вешаются лампы: иначе этаж без ламп для правила темноты светел (ADR-0028).
	for index in rules.floors:
		if rules.is_unlit(index):
			_lighting.mark_unlit(index)


## Выход из здания. Не запирается: без всех документов он отправляет обратно
## наверх, к несобранной двери (ADR-0005, пункт 5).
##
## Сам проём вырезан в задней стене ([method _build_room]); здесь — зона, порог,
## вывеска и машина. Вывеска горит своим светом: выход — цель, и читаться он
## обязан на погашенном этаже (ADR-0019, решение 5; ADR-0023, решение 6).
func _spawn_exit() -> void:
	var bottom := rules.floors - 1
	var surface := rules.floor_surface(bottom)
	var centre := _plan.exit_x
	var area := Rect2(
		centre - BuildingShell.EXIT_WIDTH * 0.5,
		surface - EXIT_HEIGHT,
		BuildingShell.EXIT_WIDTH,
		EXIT_HEIGHT
	)

	var zone := _zone(area)
	zone.body_entered.connect(_on_exit_entered)
	add_child(zone)
	_exit_position = area.get_center()

	var threshold := GreyboxLook.box(
		Vector3(BuildingShell.EXIT_WIDTH, 0.05, BuildingShell.PANEL_THICKNESS),
		GreyboxLook.metal(GreyboxLook.TRIM)
	)
	threshold.position = WorldSpace.to_scene(Vector2(centre, surface - 0.025))
	threshold.position.z = WorldSpace.BACK_WALL_Z + BuildingShell.PANEL_THICKNESS
	add_child(threshold)

	# Не `sign`: так зовут встроенную функцию, и местная переменная её заслонила бы.
	var board := GreyboxLook.box(EXIT_SIGN_SIZE, GreyboxLook.light(GreyboxLook.SIGN_GREEN))
	board.name = "ExitSign"
	board.position = WorldSpace.to_scene(
		Vector2(centre, surface - Door.LEAF_SIZE.y - EXIT_SIGN_RISE)
	)
	board.position.z = WorldSpace.BACK_WALL_Z + EXIT_SIGN_SIZE.z * 0.5
	add_child(board)
	_spawn_car(area)


## Машина у выхода: ставит её [ExitCar] у проёма, на пол нижнего этажа.
func _spawn_car(exit_area: Rect2) -> void:
	_car = ExitCar.new()
	_car.park(exit_area.get_center().x, exit_area.end.y, rules.width)
	add_child(_car)


func _on_exit_entered(body: Node3D) -> void:
	var runner := body as Otto
	if runner == null:
		return
	if GameState.instance().all_documents_collected():
		if not _cleared:
			_cleared = true
			# Otto на время отъезда прячется, как за дверью, и только по отъезду
			# здание считается сданным (ADR-0011, пункт 14).
			runner.stay_indoors(true)
			_car.drive_away()
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
## меняется на ходу. Живых в здании не больше четырёх, но ищет их [method agents]
## перебором всех детей уровня, а их под три сотни: если кадр когда-нибудь упрётся
## в это, агентов надо держать списком, а не искать заново.
##
## Тем же проходом раздаётся и тревога агентов ([method _stir_agents]).
func _shroud_agents() -> void:
	var here := _floor_of(otto)
	var otto_in_the_dark := _lighting.is_dark_at(here, otto.global_position.x)
	for agent in agents():
		if agent.is_dead():
			continue
		_shroud_agent(agent, _floor_of(agent), agent.global_position.x, here, otto_in_the_dark)
		if _alert_left > 0.0:
			agent.alert_for(_alert_left)


## Что агент знает про Otto и про себя: своя темнота, тень Otto и глухая стена
## между ними.
##
## Одним местом на обоих зовущих: [method _shroud_agents] пересчитывает это
## каждый кадр, а [method _release_agent] — разово, до первого кадра нового
## агента. Разъехаться им нельзя, иначе первый шаг агент делал бы по другим
## правилам, чем все следующие, — на стене это едва не случилось.
##
## Про Otto ([param here], [param target_in_the_dark]) считается снаружи: агентов
## до четырёх, а Otto один, и четыре одинаковых счёта за кадр ни к чему.
## [param where] и [param x] — тоже снаружи: у только что выпущенного агента
## координата ещё коврика двери, а не его тела.
func _shroud_agent(agent: Enemy, where: int, x: float, here: int, target_in_the_dark: bool) -> void:
	agent.set_in_the_dark(_lighting.is_dark_at(where, x))
	agent.set_target_in_the_dark(target_in_the_dark)
	# Стена делит только свой этаж: с другого этажа Otto и так не достать.
	agent.set_target_behind_a_wall(
		where == here and _plan.wall_between(here, x, otto.global_position.x)
	)
	var lift := AgentLifts.offer(_plan, rules, _cars, where, x, here)
	agent.set_lift_at(lift)
	# Далеко отставший агент уходит в ближайшую дверь, а не бродит до конца
	# здания (@041F): его ячейка нужнее там, где игрок. Но только тот, кому
	# не на чем доехать: у кого шахта в сторону Otto под боком, ждёт кабину.
	var stranded := (
		absi(where - here) >= AGENT_FAR_FLOORS
		and is_nan(lift)
		and not AgentLifts.can_ride(_plan, rules, where, x, here)
	)
	agent.set_exit_at(AgentLifts.nearest_door(_plan, rules, _cars, where, x) if stranded else NAN)


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


## Держит в здании ровно тех агентов, до которых игроку есть дело, — по правилам
## выпуска аркадного ROM (ADR-0027, решение 2).
##
## Агентов в здании не больше трёх, а поздно и на высоком навыке — четырёх:
## столько ячеек держит ROM (@594D). Раз в тик логики уровень бросает жребий:
## этаж Otto, выше или ниже, — а с шансом по сложности именно этаж Otto (@5A4C), —
## и случайная свободная синяя дверь на нём. На этаже агентов не больше, чем
## разрешает время в здании; пока Otto не на ногах или тревоги агентов нет — один
## (@5905, @59F4).
##
## Поверх ROM остаются наши правила двери: не выпускать вплотную к Otto и
## телеграф створки (ADR-0020). Агенты, отставшие на несколько этажей за кадр,
## убираются, как раньше: ячейка им нужнее там, где игрок.
func _tend_agents(span: Vector2i, delta: float) -> void:
	var live := 0
	var per_floor: Dictionary = {}
	for post: AgentPost in _posts:
		# Живость проверяется прямо по полю: свой агент у двери один, а чужого
		# сюда положить некому.
		if is_instance_valid(post.agent) and not post.agent.is_dead():
			if not _within(span, post.floor_index, AGENT_KEEP_MARGIN):
				post.agent.queue_free()
				post.agent = null
				post.door.dismiss_agent()
				_free_slot(post)
				continue
			live += 1
			var where := _floor_of(post.agent)
			per_floor[where] = int(per_floor.get(where, 0)) + 1
			# Створка идёт обратно, как только агент освободил проём: открытая
			# дверь в кадре значит «оттуда сейчас полезут», и держать её
			# открытой при живом агенте — размывать знак (ADR-0020, решение 4).
			if not post.agent.is_emerging():
				post.door.dismiss_agent()
			continue

		# Створка уже идёт: ждём, пока откроется, и только тогда выпускаем.
		# Ячейку агент занимает уже сейчас.
		if post.opening:
			if not _within(span, post.floor_index, AGENT_SPAWN_MARGIN):
				post.door.dismiss_agent()
				post.opening = false
				_free_slot(post)
				continue
			live += 1
			per_floor[post.floor_index] = int(per_floor.get(post.floor_index, 0)) + 1
			if post.door.agent_may_step_out():
				post.agent = _release_agent(post)
				post.opening = false
			continue

		# Проём свободен: агента убили или он ушёл. Створка идёт обратно и
		# отсюда тоже — убитый ровно в тот кадр, когда перестал быть неуязвимым,
		# до ветки живых не доживает, и дверь, которой об этом не сказали,
		# осталась бы стоять открытой навсегда. Вызов у закрытой — пустышка.
		post.agent = null
		post.door.dismiss_agent()

	if _spawn.tick(delta):
		_try_to_spawn(span, live, per_floor)


## Один жребий выпуска: ячейка, этаж, дверь (try_to_spawn_an_enemy_5A26).
func _try_to_spawn(span: Vector2i, live: int, per_floor: Dictionary) -> void:
	var time := _building_time()
	var available := rules.agents_at_once(time)
	if live >= available:
		return
	var slot := _spawn.open_slot(available, Door.AGENT_OPEN_TIME)
	if slot < 0:
		return

	var here := _floor_of(otto)
	var floor_index := _spawn.pick_floor(here, _difficulty())
	var cap := Arcade.agents_per_floor(time, otto.is_on_foot(), _alert_left > 0.0)
	if int(per_floor.get(floor_index, 0)) >= cap:
		return

	var free: Array[AgentPost] = []
	for post: AgentPost in _posts:
		if post.floor_index != floor_index or post.opening or is_instance_valid(post.agent):
			continue
		if not _within(span, post.floor_index, AGENT_SPAWN_MARGIN):
			continue
		# Створка ещё идёт за прошлым агентом — дверь не в счёт.
		if _too_close_to_otto(post, here) or not post.door.can_summon():
			continue
		free.append(post)
	if free.is_empty():
		return

	var chosen := free[_spawn.pick(free.size())]
	# Не агент, а просьба открыться: сам он покажется, когда створка дойдёт.
	chosen.opening = chosen.door.summon_agent()
	if chosen.opening:
		chosen.slot = slot
		_spawn.take(slot)


## Освобождает ячейку поста: смена в ней придёт через паузу по сложности.
func _free_slot(post: AgentPost) -> void:
	_spawn.release(post.slot, _difficulty())
	post.slot = -1


## Сколько уже идёт здание, с: от этого растёт сложность (ADR-0027, решение 1).
func _building_time() -> float:
	return GameState.instance().alarm.elapsed()


## Сложность здания прямо сейчас: навык плюс время (compute_difficulty_592F).
func _difficulty() -> int:
	return Arcade.difficulty(rules.skill, _building_time())


## Тревога агентов: пуля Otto в кадре при сложности больше нуля — 90 тиков
## (@59C8). Под ней выпуск идёт по полному пределу этажа, а агенты стреляют,
## не глядя (ADR-0027, решение 5).
##
## Самим агентам её раздаёт [method _shroud_agents] тем же проходом, что и
## темноту: второй перебор трёхсот детей уровня за кадр ради этого ни к чему.
func _stir_agents(delta: float) -> void:
	_alert_left = maxf(_alert_left - delta, 0.0)
	if _difficulty() > 0 and Bullet.any_in_flight(get_tree(), Bullet.FROM_OTTO):
		_alert_left = Arcade.seconds(Arcade.ALERT_TICKS)


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
	# Сеется до [method Enemy.setup]: выход из двери уже тянет из генератора
	# длину первого перехода, и несеянный он дал бы её случайной — прогон бота
	# переставал бы повторяться с первого же агента.
	agent.seed_decisions(_spawn.rng.randi())
	add_child(agent)
	agent.global_position = WorldSpace.to_scene(mat)
	agent.setup(otto, signf(otto.global_position.x - mat.x))
	# Тень Otto и стена отдаются сразу, не дожидаясь кадра: иначе первый шаг агент
	# делал бы, видя Otto там, где его не видно.
	var here := _floor_of(otto)
	_shroud_agent(
		agent, post.floor_index, mat.x, here, _lighting.is_dark_at(here, otto.global_position.x)
	)
	agent.set_threat(_difficulty(), rules.skill, GameState.instance().alarm.raised)
	agent.set_late(post.slot >= 2)
	if _alert_left > 0.0:
		agent.alert_for(_alert_left)
	agent.died.connect(_on_agent_died.bind(post))
	agent.left_building.connect(_on_agent_left.bind(post))
	return agent


## Сирена: агенты злеют, кабины начинают отвечать с задержкой.
func _on_alarm_raised() -> void:
	# Сирена работает с M5b, а звучать ей было нечем: теперь вместо темы здания
	# идёт мотив тревоги, и снять его можно только новым зданием.
	Sounds.play_music(Sounds.ALARM_THEME)
	for car in _cars:
		car.set_response_delay(ALARM_CAR_DELAY)
	for agent in agents():
		agent.set_alarmed(true)


func _on_agent_died(_agent: Enemy, post: AgentPost) -> void:
	# Ячейка освобождается со сменой по сложности (@3866): следующего выпустит
	# жребий, а не эта же дверь.
	_free_slot(post)


## Агент дошёл до двери и ушёл в неё (@55B0): тело убирается, ячейка свободна.
func _on_agent_left(agent: Enemy, post: AgentPost) -> void:
	agent.queue_free()
	if post.agent == agent:
		post.agent = null
	_free_slot(post)


func _on_otto_died() -> void:
	# Жизнь снимается сразу, чтобы счётчик не врал, пока тело лежит.
	if not GameState.instance().lose_life():
		return
	# Как и смена агента, возвращение в игру не идёт на паузе — и отсчитывается
	# шагами физики, а не кадрами: иначе на быстрой машине Otto возвращается
	# раньше, чем на медленной, и прогон бота перестаёт повторяться.
	var timer := get_tree().create_timer(OTTO_RESPAWN_DELAY, false, true)
	timer.timeout.connect(_respawn_otto)


## Возвращает Otto в игру на том же этаже, но подальше от тех, кто его там убил.
##
## Место выбирается по живым агентам, а не по порядку мест: агент, убивший Otto,
## никуда не делся, и возвращение на то же место — это смерть в петле. На пустом
## этаже выбор вырождается в первое свободное место, как было раньше.
func _respawn_otto() -> void:
	# Таймер висит на дереве, а не на уровне, и переживает его: погибший Otto,
	# уровень которого убрали — выходом в меню или концом теста, — возвращался
	# бы в здание, которого уже нет.
	if not is_inside_tree():
		return
	var index := _floor_of(otto)
	var surface := rules.floor_surface(index)
	otto.global_position = WorldSpace.to_scene(Vector2(_safest_x(index), surface))
	otto.revive()


func _safest_x(index: int) -> float:
	var spots := _plan.safe_spots(rules, index)
	if spots.is_empty():
		return _plan.safe_x(rules, index)
	# Своя сторона этажа, а не та, что за стеной или проёмом.
	var from_x := WorldSpace.to_plane(otto.global_position).x
	spots = _plan.spots_on_the_same_piece(rules, index, from_x, spots)

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
