class_name GreyboxLevel
extends Node2D

## Здание, собранное по [BuildingPlan].
##
## Где что стоит, решает раскладка по правилам и сиду; уровень только расставляет
## узлы и связывает их между собой. Геометрия — прямоугольники: настоящие ассеты
## приходят в M7, свет — в M6.

## Otto вышел из здания, собрав все документы.
signal building_cleared

## Цвета геометрии заданы ярче, чем нужно на экране: с M6 всё, что рисуется,
## множится на общий тон ([constant AMBIENT]), и прежние цвета ушли бы в чёрное.
const SOLID_COLOR := Color(0.30, 0.32, 0.40)
const EXIT_COLOR := Color(0.30, 0.52, 0.36)

## Общий тон здания — и он же тон погашенного этажа (ADR-0010, пункт 3).
##
## Не чёрный: в темноте агенты продолжают стрелять, у них лишь падает
## дальность, и этаж, на котором врага не видно, был бы смертью ни за что.
## Холодный оттенок отделяет погашенный этаж от горящего вернее яркости.
const AMBIENT := Color(0.50, 0.54, 0.68)

## Заливка горящего этажа: она возвращает ему обычную яркость.
const FLOOR_LIGHT := Color(1.0, 0.95, 0.86)
const FLOOR_ENERGY: float = 1.15

## Столб света в шахте: кабина возит свой свет, и шахта видна как шахта.
## Он не гаснет вместе с этажом — это освещение самой шахты, а не этажа.
const SHAFT_LIGHT := Color(0.78, 0.86, 1.0)
const SHAFT_ENERGY: float = 0.55

## Окна в задней стене: сколько на этаже и какого размера.
const WINDOWS_PER_FLOOR: int = 6
const WINDOW_SIZE := Vector2(72.0, 40.0)
## На сколько ниже потолка начинается окно, px.
const WINDOW_TOP: float = 14.0

## Задняя стена этажа. Светлее геометрии: это дальний план, и сливаться
## с перекрытиями ему нельзя, иначе этаж читается как сплошная плита.
const BACK_WALL := Color(0.15, 0.16, 0.22)

## Город за окнами: силуэт и горящие окна. Само небо — цвет узла Background
## в сцене, там же, где сам узел.
const CITY := Color(0.12, 0.14, 0.24)
const CITY_WINDOW := Color(0.92, 0.83, 0.50)

## Насколько город отстаёт от камеры: 1 — бесконечно далёк и стоит на месте.
## По вертикали больше, чем по горизонтали: здание высокое, и город, бегущий
## вниз наравне со спуском, читался бы как соседняя стена, а не как даль.
const CITY_PARALLAX := Vector2(0.86, 0.94)

## Полоса, в которой стоит город, в координатах его собственного слоя.
const CITY_AREA := Rect2(0.0, 40.0, 1280.0, 500.0)

const CAR_SCENE := preload("res://src/systems/elevators/elevator_car.tscn")
const ESCALATOR_SCENE := preload("res://src/systems/escalators/escalator.tscn")
const DOOR_SCENE := preload("res://src/systems/doors/door.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const LAMP_SCENE := preload("res://src/systems/lighting/lamp.tscn")

const WALL_WIDTH: float = 16.0

## Дно шахты: сюда падает тот, кто шагнул в пустой проём.
const PIT_HEIGHT: float = 20.0

## На сколько выше пола висит середина лампы, px.
const LAMP_HANG_HEIGHT: float = 60.0

## Выход из здания — на нижнем этаже.
const EXIT_WIDTH: float = 64.0
const EXIT_HEIGHT: float = 40.0

## Насколько злее агенты и насколько хуже слушается кабина по тревоге.
const ALARM_MENACE: float = 1.5
const ALARM_CAR_DELAY: float = 0.6

## Сколько дверь ждёт, прежде чем выпустить следующего агента, с.
const AGENT_RESPAWN_DELAY: float = 3.0

## Сколько Otto лежит, прежде чем вернуться в игру, с.
const OTTO_RESPAWN_DELAY: float = 1.2

## Правила здания. Пустые — значит берутся по умолчанию.
@export var rules: BuildingRules

## Сид здания. Им служит номер здания: раскладка меняется от здания к зданию.
@export var building_seed: int = 1

## Выпускать ли агентов из дверей. Выключается в тестах проходимости: они
## проверяют, что здание проходится, а не что бой выигрывается.
@export var spawn_agents: bool = true

var _plan: BuildingPlan
var _doors: Array[Door] = []
## Обычные двери: из них выходят агенты. Красные документов не стерегут.
var _agent_doors: Array[Door] = []
var _cars: Array[ElevatorCar] = []
var _lighting := FloorLighting.new()
## Заливка по этажу. Гаснет, когда на этаже падает лампа.
var _floor_lights: Array[AreaLight] = []
## Столбы света в шахтах, по одному на шахту, в порядке раскладки.
var _shaft_lights: Array[AreaLight] = []
## Какие этажи горели в прошлом кадре: пересчитывать их каждый кадр незачем.
var _lit_span := Vector2i(-1, -1)
## Дальний план: город за окнами. Двигается медленнее камеры.
var _city: Node2D = null
## Задние стены этажей. Их под три сотни, и держать их прямо в уровне значит
## заставить каждый обход [method _agents] перебирать ещё и их.
var _back_walls: Node2D = null
## Лампы здания: их свет тоже гасится за пределами кадра. Упавшие лампы
## убирают себя сами, поэтому перед обращением проверяется живость.
var _lamps: Array[Lamp] = []
## Здание сдано. Событие однократное: по нему main собирает следующее здание.
var _cleared: bool = false
var _exit_position := Vector2.ZERO

@onready var otto: Otto = $Otto
@onready var _background: ColorRect = $Background


func _ready() -> void:
	if rules == null:
		rules = BuildingRules.new()
	_plan = BuildingPlan.generate(rules, building_seed)

	_background.size = Vector2(rules.width, rules.total_height())
	_build_city()
	_build_back_walls()
	_build_geometry()
	_spawn_shafts()
	_spawn_escalators()
	_spawn_doors()
	_spawn_lamps()
	_spawn_exit()
	_light_building()

	# Otto начинает с крыши, как в оригинале, и там, где нет проёмов.
	otto.global_position = Vector2(_plan.safe_x(rules, 0), rules.floor_surface(0))
	otto.died.connect(_on_otto_died)
	GameState.instance().alarm_raised.connect(_on_alarm_raised)
	if GameState.instance().alarm.raised:
		# Здание заведено уже при включённой сирене — редкость, но бывает.
		_on_alarm_raised()
	if spawn_agents:
		for door in _agent_doors:
			_release_agent(door)
	otto.apply_camera_bounds(Rect2(0.0, 0.0, rules.width, rules.total_height()))


## Гасит всё, что уехало из кадра. Источников в здании шестьдесят, а в кадр
## влезает два с половиной этажа — ADR-0010, пункт 8.
func _process(_delta: float) -> void:
	var view := otto.camera_view()
	# Город отстаёт от камеры, оттого и кажется далёким.
	_city.position = view.position * CITY_PARALLAX

	var span := VisibleFloors.around(rules, view)
	if span == _lit_span:
		return

	_lit_span = span
	for index: int in _floor_lights.size():
		var light := _floor_lights[index]
		# Погашенный этаж остаётся погашенным: в кадре он или нет, лампы на нём
		# больше нет. Поэтому видимость решает не только отбор.
		light.visible = VisibleFloors.covers(span, index) and not _lighting.is_dark(index)

	for index: int in _shaft_lights.size():
		# Шахта тянется через много этажей, поэтому горит, если в кадр попал
		# хоть один из них. Без этого в тридцатиэтажке горели бы все шахты разом,
		# и обещанная дюжина источников в кадре перестала бы быть правдой.
		var shaft := _plan.shafts[index]
		_shaft_lights[index].visible = shaft.top <= span.y and shaft.bottom >= span.x

	# У этажа два источника (ADR-0010, пункт 3), и отбор нужен обоим: пятно
	# лампы вдобавок кладёт тени, то есть стоит дороже заливки. Этаж лампы
	# берётся из её же положения — так же, как его берёт tools/light_shot.gd.
	for lamp: Lamp in _lamps:
		if not is_instance_valid(lamp):
			continue
		var floor_index := rules.floor_index_near(lamp.global_position.y)
		lamp.set_light_visible(VisibleFloors.covers(span, floor_index))


## Раскладка, по которой собрано здание.
func plan() -> BuildingPlan:
	return _plan


## Двери здания: по ним видно, какие красные ещё не собраны.
func doors() -> Array[Door]:
	return _doors


## Где стоит выход из здания.
func exit_position() -> Vector2:
	return _exit_position


## Погашен ли этаж. Гаснет он навсегда: сбитая лампа обратно не загорается.
func is_dark(floor_index: int) -> bool:
	return _lighting.is_dark(floor_index)


## Режет перекрытие на куски между проёмами.
##
## Сам разрез — в [method BuildingPlan.spans_between]: по тем же кускам строится
## граф достижимости, и второй такой же счёт рано или поздно разъехался бы с этим.
## Проёмы принимаются в любом порядке.
##
## Статический, чтобы проверяться тестами без сцены.
static func slab_segments(
	surface: float, gaps: Array[Vector2], width: float, thickness: float
) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for span in BuildingPlan.spans_between(gaps, width):
		rects.append(Rect2(span.x, surface, span.y - span.x, thickness))
	return rects


func _build_geometry() -> void:
	var height := rules.total_height()
	_build_solid(Rect2(0.0, 0.0, WALL_WIDTH, height))
	_build_solid(Rect2(rules.width - WALL_WIDTH, 0.0, WALL_WIDTH, height))

	# Тайл берётся один раз на здание: плит в нём под три сотни, а текстура одна.
	var slab_tile := EnvTextures.tile("slab")
	for index in rules.floors:
		var surface := rules.floor_surface(index)
		var gaps := _plan.gaps_on(rules, index)
		for rect in slab_segments(surface, gaps, rules.width, rules.slab_height):
			_build_solid(rect, slab_tile)


func _spawn_shafts() -> void:
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
		_light_shaft(shaft)


## Дно шахты: упавший сюда разбивается, вошедший ногами с этажа — нет.
func _spawn_shaft_pit(shaft: BuildingPlan.ShaftSpot) -> void:
	var surface := rules.floor_surface(shaft.bottom)
	var pit := Area2D.new()
	pit.collision_layer = 0
	pit.collision_mask = 2
	pit.position = Vector2(shaft.x, surface - PIT_HEIGHT * 0.5)

	var shape := RectangleShape2D.new()
	shape.size = Vector2(rules.shaft_width, PIT_HEIGHT)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	pit.add_child(collision)

	pit.body_entered.connect(_on_pit_entered)
	add_child(pit)


func _spawn_escalators() -> void:
	for spot in _plan.escalators:
		var escalator := ESCALATOR_SCENE.instantiate() as Escalator
		escalator.position = Vector2(spot.x, rules.floor_surface(spot.floor_index))
		add_child(escalator)

		var descent := Vector2(spot.towards * rules.escalator_run, rules.floor_height)
		# Перегиб — в самом проёме: через него идут и полотно, и поездка, поэтому
		# пассажир проходит сквозь дыру, а не сквозь плиту.
		var gap := spot.gap(rules)
		var bend := Vector2((gap.x + gap.y) * 0.5 - spot.x, rules.slab_height + 4.0)
		escalator.setup(descent, bend)


func _spawn_doors() -> void:
	# Счёт уровень не трогает: он копится от здания к зданию, обнуляет его тот,
	# кто начинает партию. Здесь объявляется только, сколько здесь документов.
	var game := GameState.instance()
	var documents := 0
	for spot in _plan.doors:
		var door := DOOR_SCENE.instantiate() as Door
		door.position = Vector2(spot.x, rules.floor_surface(spot.floor_index))
		door.has_document = spot.has_document
		add_child(door)
		_doors.append(door)

		if not door.is_pending():
			_agent_doors.append(door)
			continue
		documents += 1
		door.document_taken.connect(game.collect_document)
	game.start_building(documents)


func _spawn_lamps() -> void:
	for spot in _plan.lamps:
		var lamp := LAMP_SCENE.instantiate() as Lamp
		lamp.position = Vector2(spot.x, rules.floor_surface(spot.floor_index) - LAMP_HANG_HEIGHT)
		lamp.crushed.connect(_on_lamp_crushed)
		# Этаж лампы известен здесь, и обратно из координаты его выводить незачем.
		lamp.fell.connect(_on_lamp_fell.bind(spot.floor_index))
		add_child(lamp)
		lamp.hang(LAMP_HANG_HEIGHT)
		_lamps.append(lamp)


## Выход из здания. Не запирается: без всех документов он отправляет обратно
## наверх, к несобранной двери (ADR-0005, пункт 5).
func _spawn_exit() -> void:
	var bottom := rules.floors - 1
	var surface := rules.floor_surface(bottom)
	var centre := _plan.exit_x
	var area := Rect2(centre - EXIT_WIDTH * 0.5, surface - EXIT_HEIGHT, EXIT_WIDTH, EXIT_HEIGHT)

	var zone := Area2D.new()
	zone.collision_layer = 0
	zone.collision_mask = 2
	zone.position = area.position + area.size * 0.5
	zone.z_index = -1

	var shape := RectangleShape2D.new()
	shape.size = area.size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	zone.add_child(collision)
	zone.add_child(_panel(area.size, -area.size * 0.5, EXIT_COLOR))

	zone.body_entered.connect(_on_exit_entered)
	add_child(zone)
	_exit_position = zone.global_position


func _on_exit_entered(body: Node2D) -> void:
	var runner := body as Otto
	if runner == null:
		return
	if GameState.instance().all_documents_collected():
		if not _cleared:
			_cleared = true
			building_cleared.emit()
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
	runner.global_position = pending[index]


## Лампа накрыла агента по дороге вниз — самый дорогой способ убийства.
func _on_lamp_crushed(agent: Enemy) -> void:
	if agent.is_dead():
		return
	agent.kill()
	var points := GameState.kill_score(GameState.LAMP_SCORE, agent.is_in_the_dark())
	GameState.instance().add_score(points)


## Лампа долетела до пола: этаж гаснет и обратно уже не загорается.
func _on_lamp_fell(index: int) -> void:
	if not _lighting.darken(index):
		return
	# Этаж падает до общего тона здания: света на нём больше нет.
	if index < _floor_lights.size():
		_floor_lights[index].visible = false
	for agent in _agents_on(index):
		agent.set_in_the_dark(true)


## Все агенты здания: они лежат прямо в уровне, рядом с геометрией.
func _agents() -> Array[Enemy]:
	var found: Array[Enemy] = []
	for child in get_children():
		var agent := child as Enemy
		if agent != null:
			found.append(agent)
	return found


func _agents_on(index: int) -> Array[Enemy]:
	var found: Array[Enemy] = []
	for agent in _agents():
		if rules.floor_index_near(agent.global_position.y) == index:
			found.append(agent)
	return found


## Выпускает агента из двери.
func _release_agent(door: Door) -> void:
	var mat := door.mat_position()
	var agent := ENEMY_SCENE.instantiate() as Enemy
	add_child(agent)
	agent.global_position = mat
	agent.setup(otto, signf(otto.global_position.x - mat.x))
	agent.set_in_the_dark(_lighting.is_dark(rules.floor_index_near(mat.y)))
	agent.set_menace(_menace())
	agent.died.connect(_on_agent_died.bind(door))


## Насколько злее агенты этого здания прямо сейчас: к росту от здания к зданию
## добавляется тревога, если она уже включилась. Сам счёт — в [BuildingRules],
## там же общий на обе надбавки потолок.
func _menace() -> float:
	var alarmed := GameState.instance().alarm.raised
	return rules.menace_with(ALARM_MENACE if alarmed else 1.0)


## Сирена: агенты злеют, кабины начинают отвечать с задержкой.
func _on_alarm_raised() -> void:
	for car in _cars:
		car.set_response_delay(ALARM_CAR_DELAY)
	for agent in _agents():
		agent.set_menace(_menace())


func _on_agent_died(_agent: Enemy, door: Door) -> void:
	# process_always = false: на паузе здание замирает целиком, и смена агента
	# не должна приходить, пока игра стоит.
	var timer := get_tree().create_timer(AGENT_RESPAWN_DELAY / _menace(), false)
	timer.timeout.connect(_release_agent.bind(door))


func _on_otto_died() -> void:
	# Жизнь снимается сразу, чтобы счётчик не врал, пока тело лежит.
	if not GameState.instance().lose_life():
		return
	# Как и смена агента, возвращение в игру не идёт на паузе.
	var timer := get_tree().create_timer(OTTO_RESPAWN_DELAY, false)
	timer.timeout.connect(_respawn_otto)


func _respawn_otto() -> void:
	var index := rules.floor_index_near(otto.global_position.y)
	otto.global_position = Vector2(_plan.safe_x(rules, index), rules.floor_surface(index))
	otto.revive()


func _on_pit_entered(body: Node2D) -> void:
	var victim := body as Otto
	if victim == null:
		return
	var deadly := ShaftHazards.is_deadly_fall(
		victim.is_grounded(), victim.is_riding(), victim.fall_height(), victim.jump_height()
	)
	if deadly:
		victim.kill()


func _build_solid(rect: Rect2, tile: CanvasTexture = null) -> void:
	var body := StaticBody2D.new()
	body.position = rect.position + rect.size * 0.5
	# Тела добавляются в дерево после Otto, то есть рисовались бы поверх него.
	# Геометрия всегда за актёрами, но перед фоном (у фона z_index = -12).
	body.z_index = -1

	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	if tile == null:
		body.add_child(_panel(rect.size, -rect.size * 0.5, SOLID_COLOR))
	else:
		body.add_child(_tiled(rect.size, -rect.size * 0.5, tile))
	body.add_child(_occluder(rect.size))

	add_child(body)


## Окна этажа: равные проёмы в задней стене, через которые виден город.
##
## Статический, чтобы проверяться без сцены, — как и [method slab_segments].
static func window_gaps(width: float, count: int, window_width: float) -> Array[Vector2]:
	var gaps: Array[Vector2] = []
	if count <= 0 or window_width <= 0.0:
		return gaps

	var pitch := width / float(count)
	for number: int in count:
		# Окно стоит посередине своей доли стены: так они разнесены поровну
		# и у стен здания остаётся полполосы, а не обрезанное окно.
		var centre := pitch * (float(number) + 0.5)
		var half := minf(window_width, pitch) * 0.5
		gaps.append(Vector2(centre - half, centre + half))
	return gaps


## Задняя стена: сплошная, кроме окон. Через окна виден город.
##
## Стена кладётся тремя полосами: над окнами, по окнам и под ними. Резать её
## по горизонтали умеет [method BuildingPlan.spans_between] — та же функция,
## что режет перекрытия проёмами.
func _build_back_walls() -> void:
	_back_walls = Node2D.new()
	_back_walls.z_index = -8
	add_child(_back_walls)

	var gaps := window_gaps(rules.width, WINDOWS_PER_FLOOR, WINDOW_SIZE.x)
	# С первого этажа, а не с нулевого: нулевой — крыша, комнаты за ней нет.
	# [method BuildingRules.story_top] отдаёт для неё верх здания, и стена вышла бы
	# полосой в небе над тем местом, где Otto начинает, с обрезанными окнами.
	for index: int in range(1, rules.floors):
		var top := rules.story_top(index)
		var surface := rules.floor_surface(index)
		if surface - top <= 0.0:
			continue

		var window_top := minf(top + WINDOW_TOP, surface)
		var window_bottom := minf(window_top + WINDOW_SIZE.y, surface)
		_add_back_wall(Rect2(0.0, top, rules.width, window_top - top))
		_add_back_wall(Rect2(0.0, window_bottom, rules.width, surface - window_bottom))

		for span: Vector2 in BuildingPlan.spans_between(gaps, rules.width):
			var strip := Rect2(span.x, window_top, span.y - span.x, window_bottom - window_top)
			_add_back_wall(strip)


func _add_back_wall(rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	_back_walls.add_child(_panel(rect.size, rect.position, BACK_WALL))


## Город за окнами. Свет здания на него не падает: он снаружи и далеко.
func _build_city() -> void:
	_city = Node2D.new()
	_city.z_index = -9
	add_child(_city)

	for tower: Skyline.Tower in Skyline.generate(building_seed, CITY_AREA):
		_add_city_panel(tower.rect, CITY)
		for window: Rect2 in tower.windows:
			_add_city_panel(window, CITY_WINDOW)


## Кусок дальнего плана. Свет здания на него не падает.
##
## Маска гасится на каждой панели, а не на общем узле: [member CanvasItem.light_mask]
## детям не передаётся, и город в окне разгорался вместе с этажом — окно читалось
## как освещённая ниша, а не как улица.
func _add_city_panel(rect: Rect2, color: Color) -> void:
	var panel := _panel(rect.size, rect.position, color)
	panel.light_mask = 0
	_city.add_child(panel)


## Столб света в шахте на всю её высоту.
##
## Шахта — единственное, что светится в погашенном здании само: она соединяет
## этажи, и свет в ней показывает, куда идти, когда лампы сбиты. Гасить её вместе
## с этажом нельзя — этажей у шахты много, а столб один.
func _light_shaft(shaft: BuildingPlan.ShaftSpot) -> void:
	var top := rules.story_top(shaft.top)
	var bottom := rules.floor_surface(shaft.bottom)
	var area := Rect2(shaft.x - rules.shaft_width * 0.5, top, rules.shaft_width, bottom - top)
	var light := AreaLight.column(area, SHAFT_LIGHT, SHAFT_ENERGY)
	add_child(light)
	_shaft_lights.append(light)


## Зажигает здание: общий тон и заливка на каждом этаже.
##
## Светлым этаж делает собственный источник, а не отсутствие темноты — вся
## конструкция вехи держится на этом (ADR-0010, пункт 3).
func _light_building() -> void:
	var ambient := CanvasModulate.new()
	ambient.color = AMBIENT
	add_child(ambient)

	for index: int in rules.floors:
		var light := AreaLight.covering(_story_area(index), FLOOR_LIGHT, FLOOR_ENERGY)
		add_child(light)
		_floor_lights.append(light)


## Пролёт этажа: от потолка до низа настила, на котором стоят.
##
## Настил включён нарочно: кончайся заливка ровно по полу, сам пол и ноги
## стоящего на нём остались бы неосвещёнными.
##
## У крыши потолка нет, и лампы на ней тоже нет — вешать её там не на что.
## Поэтому крыше полоса отмеряется вверх от настила: светит ей город, и
## погасить этот свет нельзя.
func _story_area(index: int) -> Rect2:
	var surface := rules.floor_surface(index)
	var top := surface - rules.floor_height if index <= 0 else rules.story_top(index)
	return Rect2(0.0, top, rules.width, surface + rules.slab_height - top)


## Перекрытия и стены не пропускают свет: иначе лампа светила бы сквозь пол
## на соседние этажи, и погашенный этаж подсвечивался бы снизу.
func _occluder(size: Vector2) -> LightOccluder2D:
	var half := size * 0.5
	var shape := OccluderPolygon2D.new()
	shape.polygon = PackedVector2Array(
		[-half, Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]
	)

	var occluder := LightOccluder2D.new()
	occluder.occluder = shape
	return occluder


## Плитка из ассета: [CanvasTexture] повторяется по площади прямоугольника.
##
## Заменяет [method _panel] там, где генератор уже нарисовал ассет. Вместе с
## цветом приходят нормаль и блик, поэтому свет из M6 ложится на рельеф, а не
## на плоскость (ADR-0011, пункт 7).
func _tiled(size: Vector2, offset: Vector2, tile: CanvasTexture) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = tile
	rect.stretch_mode = TextureRect.STRETCH_TILE
	# Повтор включается на самом узле: по умолчанию холст зажимает текстуру
	# по краям, и плита в тридцать тайлов вышла бы одним растянутым.
	rect.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	rect.size = size
	rect.position = offset
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Цветной прямоугольник — временная замена спрайтам до M7.
func _panel(size: Vector2, offset: Vector2, color: Color) -> ColorRect:
	var panel := ColorRect.new()
	panel.color = color
	panel.size = size
	panel.position = offset
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel
