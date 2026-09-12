class_name GreyboxLevel
extends Node2D

## Здание, собранное по [BuildingPlan].
##
## Где что стоит, решает раскладка по правилам и сиду; уровень только расставляет
## узлы и связывает их между собой. Геометрия — прямоугольники: настоящие ассеты
## приходят в M7, свет — в M6.

## Otto вышел из здания, собрав все документы.
signal building_cleared

const SOLID_COLOR := Color(0.22, 0.24, 0.30)
const EXIT_COLOR := Color(0.30, 0.52, 0.36)

## Чем накрывается погашенный этаж до настоящего света в M6.
const DARKNESS_COLOR := Color(0.02, 0.02, 0.05, 0.72)
const DARKNESS_Z: int = 20

const CAR_SCENE := preload("res://src/systems/elevators/elevator_car.tscn")
const ESCALATOR_SCENE := preload("res://src/systems/escalators/escalator.tscn")
const DOOR_SCENE := preload("res://src/systems/doors/door.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const LAMP_SCENE := preload("res://src/systems/lighting/lamp.tscn")

const WALL_WIDTH: float = 16.0

## Проём шахты равен ширине кабины, чтобы по краям не оставалось щелей.
const SHAFT_WIDTH: float = 40.0

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

## Сид здания. В M5b им станет номер здания.
@export var building_seed: int = 1

var _plan: BuildingPlan
var _doors: Array[Door] = []
## Обычные двери: из них выходят агенты. Красные документов не стерегут.
var _agent_doors: Array[Door] = []
var _cars: Array[ElevatorCar] = []
var _lighting := FloorLighting.new()
## Здание сдано. Событие однократное: в M5b к нему прицепится переход дальше.
var _cleared: bool = false

@onready var otto: Otto = $Otto
@onready var _background: ColorRect = $Background


func _ready() -> void:
	if rules == null:
		rules = BuildingRules.new()
	_plan = BuildingPlan.generate(rules, building_seed)

	_background.size = Vector2(rules.width, rules.total_height())
	_build_geometry()
	_spawn_shafts()
	_spawn_escalators()
	_spawn_doors()
	_spawn_lamps()
	_spawn_exit()

	# Otto начинает с крыши, как в оригинале, и там, где нет проёмов.
	otto.global_position = Vector2(_plan.safe_x(rules, 0), rules.floor_surface(0))
	otto.died.connect(_on_otto_died)
	GameState.instance().alarm_raised.connect(_on_alarm_raised)
	if GameState.instance().alarm.raised:
		# Здание заведено уже при включённой сирене — редкость, но бывает.
		_on_alarm_raised()
	for door in _agent_doors:
		_release_agent(door)
	otto.apply_camera_bounds(Rect2(0.0, 0.0, rules.width, rules.total_height()))


## Режет перекрытие на куски между проёмами.
##
## Проёмы принимаются в любом порядке и сортируются здесь же. Порядок важен:
## по несортированному списку куски накладываются друг на друга и перекрытие
## выходит сплошным — проёма как не бывало.
##
## Статический, чтобы проверяться тестами без сцены.
static func slab_segments(
	surface: float, gaps: Array[Vector2], width: float, thickness: float
) -> Array[Rect2]:
	var ordered := gaps.duplicate()
	ordered.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

	var rects: Array[Rect2] = []
	var cursor := 0.0
	for gap in ordered:
		if gap.x > cursor:
			rects.append(Rect2(cursor, surface, gap.x - cursor, thickness))
		# maxf, чтобы вложенный проём не отматывал курсор назад.
		cursor = maxf(cursor, gap.y)
	if cursor < width:
		rects.append(Rect2(cursor, surface, width - cursor, thickness))
	return rects


func _build_geometry() -> void:
	var height := rules.total_height()
	_build_solid(Rect2(0.0, 0.0, WALL_WIDTH, height))
	_build_solid(Rect2(rules.width - WALL_WIDTH, 0.0, WALL_WIDTH, height))

	for index in rules.floors:
		var surface := rules.floor_surface(index)
		for rect in slab_segments(surface, _gaps_for(index), rules.width, rules.slab_height):
			_build_solid(rect)


## Проёмы в перекрытии этажа: пары «левый край, правый край».
func _gaps_for(index: int) -> Array[Vector2]:
	var gaps: Array[Vector2] = []

	for shaft in _plan.shafts:
		# Кабина проходит сквозь перекрытия своей полосы, кроме нижнего: там она
		# встаёт на пол, и он же служит дном шахты.
		if index >= shaft.top and index < shaft.bottom:
			gaps.append(Vector2(shaft.x - SHAFT_WIDTH * 0.5, shaft.x + SHAFT_WIDTH * 0.5))

	for escalator in _plan.escalators:
		if index == escalator.floor_index:
			gaps.append(escalator.gap(rules))

	return gaps


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


## Дно шахты: упавший сюда разбивается, вошедший ногами с этажа — нет.
func _spawn_shaft_pit(shaft: BuildingPlan.ShaftSpot) -> void:
	var surface := rules.floor_surface(shaft.bottom)
	var pit := Area2D.new()
	pit.collision_layer = 0
	pit.collision_mask = 2
	pit.position = Vector2(shaft.x, surface - PIT_HEIGHT * 0.5)

	var shape := RectangleShape2D.new()
	shape.size = Vector2(SHAFT_WIDTH, PIT_HEIGHT)
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
	_cover_with_darkness(index)
	for agent in _agents_on(index):
		agent.set_in_the_dark(true)


func _cover_with_darkness(index: int) -> void:
	var top := rules.story_top(index)
	var size := Vector2(rules.width, rules.floor_surface(index) + rules.slab_height - top)
	var shade := _panel(size, Vector2(0.0, top), DARKNESS_COLOR)
	shade.z_index = DARKNESS_Z
	add_child(shade)


func _agents_on(index: int) -> Array[Enemy]:
	var found: Array[Enemy] = []
	for child in get_children():
		var agent := child as Enemy
		if agent == null:
			continue
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
## добавляется тревога, если она уже включилась.
func _menace() -> float:
	var alarmed := GameState.instance().alarm.raised
	return rules.agent_menace * (ALARM_MENACE if alarmed else 1.0)


## Сирена: агенты злеют, кабины начинают отвечать с задержкой.
func _on_alarm_raised() -> void:
	for car in _cars:
		car.set_response_delay(ALARM_CAR_DELAY)
	for child in get_children():
		var agent := child as Enemy
		if agent != null:
			agent.set_menace(_menace())


func _on_agent_died(_agent: Enemy, door: Door) -> void:
	var timer := get_tree().create_timer(AGENT_RESPAWN_DELAY / _menace())
	timer.timeout.connect(_release_agent.bind(door))


func _on_otto_died() -> void:
	# Жизнь снимается сразу, чтобы счётчик не врал, пока тело лежит.
	if not GameState.instance().lose_life():
		return
	var timer := get_tree().create_timer(OTTO_RESPAWN_DELAY)
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


func _build_solid(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.position = rect.position + rect.size * 0.5
	# Тела добавляются в дерево после Otto, то есть рисовались бы поверх него.
	# Геометрия всегда за актёрами, но перед фоном (у фона z_index = -10).
	body.z_index = -1

	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	body.add_child(_panel(rect.size, -rect.size * 0.5, SOLID_COLOR))

	add_child(body)


## Цветной прямоугольник — временная замена спрайтам до M7.
func _panel(size: Vector2, offset: Vector2, color: Color) -> ColorRect:
	var panel := ColorRect.new()
	panel.color = color
	panel.size = size
	panel.position = offset
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel
