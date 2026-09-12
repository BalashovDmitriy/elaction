class_name GreyboxLevel
extends Node2D

## Временный «серый ящик»: три этажа, шахта лифта, эскалатор.
##
## Геометрия описывается прямоугольниками и собирается в рантайме. Настоящие
## уровни на данных появятся в M5; до тех пор этого хватает, чтобы проверить
## движение, лифт, эскалатор и падение в шахту.

## Otto вышел из здания, собрав все документы.
signal building_cleared

const SOLID_COLOR := Color(0.22, 0.24, 0.30)
const EXIT_COLOR := Color(0.30, 0.52, 0.36)
const CAR_SCENE := preload("res://src/systems/elevators/elevator_car.tscn")
const ESCALATOR_SCENE := preload("res://src/systems/escalators/escalator.tscn")
const DOOR_SCENE := preload("res://src/systems/doors/door.tscn")

## Поверхности этажей сверху вниз. По ним же кабина выбирает остановки.
const FLOOR_SURFACES: Array[float] = [100.0, 220.0, 340.0]
const SLAB_HEIGHT: float = 20.0
const LEVEL_WIDTH: float = 1280.0
const LEVEL_HEIGHT: float = 360.0
const WALL_WIDTH: float = 16.0

## Проём шахты. Ширина совпадает с кабиной, чтобы по краям не оставалось щелей,
## сквозь которые можно просочиться мимо неё.
const SHAFT_LEFT: float = 560.0
const SHAFT_WIDTH: float = 40.0

## Дно шахты: сюда падает тот, кто шагнул в пустой проём.
const PIT_HEIGHT: float = 20.0

## Эскалатор ведёт со среднего этажа на нижний сквозь проём в перекрытии.
## Спускается влево, поэтому верхняя площадка справа от проёма: сойдя с неё,
## Otto идёт к шахте, а не обратно в проём.
const ESCALATOR_FLOOR: int = 1
const ESCALATOR_GAP_LEFT: float = 380.0
const ESCALATOR_GAP_WIDTH: float = 60.0
const ESCALATOR_TOP_X: float = 448.0
const ESCALATOR_BOTTOM_X: float = 372.0

## Двери этажей: номер этажа, x и есть ли за ней документ.
const DOORS: Array[Dictionary] = [
	{"floor": 0, "x": 200.0, "document": true},
	{"floor": 1, "x": 700.0, "document": false},
	{"floor": 1, "x": 980.0, "document": true},
	{"floor": 2, "x": 160.0, "document": true},
]

## Выход из здания — на нижнем этаже справа.
const EXIT_LEFT: float = 1180.0
const EXIT_WIDTH: float = 64.0
const EXIT_HEIGHT: float = 40.0

@export var camera_bounds := Rect2(0, 0, LEVEL_WIDTH, LEVEL_HEIGHT)

var _doors: Array[Door] = []
## Здание сдано. Otto может зайти в зону выхода снова, но событие однократное:
## в M5 к нему прицепится переход к следующему зданию.
var _cleared: bool = false

@onready var otto: Otto = $Otto


func _ready() -> void:
	for rect in _building_solids():
		_build_solid(rect)
	_spawn_car()
	_spawn_shaft_pit()
	_spawn_escalator()
	_spawn_doors()
	_spawn_exit()
	otto.apply_camera_bounds(camera_bounds)


## Геометрия здания: перекрытия с проёмами и стены по краям уровня.
func _building_solids() -> Array[Rect2]:
	var rects: Array[Rect2] = [
		Rect2(0.0, 0.0, WALL_WIDTH, LEVEL_HEIGHT),
		Rect2(LEVEL_WIDTH - WALL_WIDTH, 0.0, WALL_WIDTH, LEVEL_HEIGHT),
	]
	for index: int in FLOOR_SURFACES.size():
		rects.append_array(slab_segments(FLOOR_SURFACES[index], _gaps_for(index)))
	return rects


## Проёмы в перекрытии этажа: пары «левый край, правый край», по возрастанию x.
func _gaps_for(index: int) -> Array[Vector2]:
	# Нижний этаж сплошной: это дно шахты, падать дальше некуда.
	if index == FLOOR_SURFACES.size() - 1:
		return []

	var gaps: Array[Vector2] = [Vector2(SHAFT_LEFT, SHAFT_LEFT + SHAFT_WIDTH)]
	if index == ESCALATOR_FLOOR:
		gaps.append(Vector2(ESCALATOR_GAP_LEFT, ESCALATOR_GAP_LEFT + ESCALATOR_GAP_WIDTH))
	return gaps


## Режет перекрытие на куски между проёмами.
##
## Проёмы принимаются в любом порядке и сортируются здесь же. Порядок важен:
## по несортированному списку куски накладываются друг на друга и перекрытие
## выходит сплошным — проёма как не бывало.
##
## Статический, чтобы проверяться тестами без сцены.
static func slab_segments(surface: float, gaps: Array[Vector2]) -> Array[Rect2]:
	var ordered := gaps.duplicate()
	ordered.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

	var rects: Array[Rect2] = []
	var cursor := 0.0
	for gap in ordered:
		if gap.x > cursor:
			rects.append(Rect2(cursor, surface, gap.x - cursor, SLAB_HEIGHT))
		# maxf, чтобы вложенный проём не отматывал курсор назад.
		cursor = maxf(cursor, gap.y)
	if cursor < LEVEL_WIDTH:
		rects.append(Rect2(cursor, surface, LEVEL_WIDTH - cursor, SLAB_HEIGHT))
	return rects


func _spawn_car() -> void:
	var car := CAR_SCENE.instantiate() as ElevatorCar
	car.position.x = SHAFT_LEFT + SHAFT_WIDTH * 0.5
	add_child(car)
	# Кабина ждёт на верхнем этаже: оттуда Otto и начинает спуск.
	car.setup(PackedFloat32Array(FLOOR_SURFACES))


## Дно шахты: упавший сюда разбивается, вошедший ногами с этажа — нет.
func _spawn_shaft_pit() -> void:
	var pit := Area2D.new()
	pit.collision_layer = 0
	pit.collision_mask = 2
	pit.position = Vector2(
		SHAFT_LEFT + SHAFT_WIDTH * 0.5, FLOOR_SURFACES[FLOOR_SURFACES.size() - 1] - PIT_HEIGHT * 0.5
	)

	var shape := RectangleShape2D.new()
	shape.size = Vector2(SHAFT_WIDTH, PIT_HEIGHT)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	pit.add_child(collision)

	pit.body_entered.connect(_on_pit_entered)
	add_child(pit)


func _spawn_escalator() -> void:
	var escalator := ESCALATOR_SCENE.instantiate() as Escalator
	var top := FLOOR_SURFACES[ESCALATOR_FLOOR]
	var bottom := FLOOR_SURFACES[ESCALATOR_FLOOR + 1]
	escalator.position = Vector2(ESCALATOR_TOP_X, top)
	add_child(escalator)
	escalator.setup(Vector2(ESCALATOR_BOTTOM_X - ESCALATOR_TOP_X, bottom - top))


func _spawn_doors() -> void:
	# Счёт уровень не трогает: он копится от здания к зданию, обнуляет его тот,
	# кто начинает партию. Здесь объявляется только, сколько здесь документов.
	var game := GameState.instance()
	var documents := 0
	for entry: Dictionary in DOORS:
		var door := DOOR_SCENE.instantiate() as Door
		door.position = Vector2(entry["x"], FLOOR_SURFACES[entry["floor"]])
		door.has_document = entry["document"]
		add_child(door)
		_doors.append(door)
		if not door.is_pending():
			continue
		documents += 1
		door.document_taken.connect(game.collect_document)
	game.start_building(documents)


## Выход из здания. Не запирается: без всех документов он отправляет обратно
## наверх, к несобранной двери (ADR-0005, пункт 5).
func _spawn_exit() -> void:
	var bottom := FLOOR_SURFACES[FLOOR_SURFACES.size() - 1]
	var area := Rect2(EXIT_LEFT, bottom - EXIT_HEIGHT, EXIT_WIDTH, EXIT_HEIGHT)

	var zone := Area2D.new()
	zone.collision_layer = 0
	zone.collision_mask = 2
	zone.position = area.position + area.size * 0.5

	var shape := RectangleShape2D.new()
	shape.size = area.size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	zone.add_child(collision)

	var visual := ColorRect.new()
	visual.color = EXIT_COLOR
	visual.size = area.size
	visual.position = -area.size * 0.5
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone.add_child(visual)

	zone.z_index = -1
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

	var visual := ColorRect.new()
	visual.color = SOLID_COLOR
	visual.size = rect.size
	visual.position = -rect.size * 0.5
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(visual)

	add_child(body)
