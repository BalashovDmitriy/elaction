class_name GreyboxLevel
extends Node2D

## Здание, собранное по [BuildingPlan].
##
## Где что стоит, решает раскладка по правилам и сиду; уровень только расставляет
## узлы и связывает их между собой. Геометрия собрана из ассетов окружения
## ([SpriteTextures], ADR-0011), свет к ним пришёл раньше — в M6.

## Otto вышел из здания, собрав все документы.
signal building_cleared

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

## Машина у выхода: ею оригинал заканчивает здание (ADR-0011, пункт 14).
## Стоит рядом с проёмом и уезжает, увозя Otto; следующее здание собирается
## после отъезда, а не в тот же кадр.
##
## Габарит нарочно не записан здесь второй раз: его знает сам ассет, а кадр ему
## задаёт `tools/render_actors.py`. Своя копия числа разъехалась бы с кадром при
## первой же правке машины, и та повисла бы над полом или утонула в нём.
const CAR_GAP: float = 12.0
const CAR_SPEED: float = 320.0

## Насколько злее агенты и насколько хуже слушается кабина по тревоге.
const ALARM_MENACE: float = 1.5
const ALARM_CAR_DELAY: float = 0.6

## Сколько дверь ждёт, прежде чем выпустить следующего агента, с.
const AGENT_RESPAWN_DELAY: float = 3.0

## На сколько этажей дальше видимой полосы дверь ещё выпускает агентов.
##
## Запас нужен, чтобы агент не появлялся на глазах у игрока в середине кадра:
## дверь отдаёт его за кромкой, и в кадр он уже входит своим ходом.
const AGENT_SPAWN_MARGIN: int = 1

## На сколько дальше того же запаса агент живёт, прежде чем его уберут.
##
## Больше запаса на выпуск нарочно: совпади они, агент у самой кромки то
## появлялся бы, то исчезал на дрожании камеры.
const AGENT_KEEP_MARGIN: int = 3

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
## Заливка по уровню: ключ — номер уровня, крыша включая. Гаснет, когда на
## этаже падает лампа. Словарь, а не список: уровни считаются от −1.
var _floor_lights: Dictionary = {}
## Столбы света в шахтах, по одному на шахту, в порядке раскладки.
var _shaft_lights: Array[AreaLight] = []
## Какие этажи горели в прошлом кадре: пересчитывать их каждый кадр незачем.
## Пустой полосой служит (0, -1): у неё конец раньше начала, а (-1, -1) теперь
## означает «горит крыша» — это настоящий уровень, и совпадение молчало бы.
var _lit_span := Vector2i(0, -1)
## Дальний план: город за окнами. Двигается медленнее камеры.
var _city: Node2D = null
## Задние стены этажей. Их под три сотни, и держать их прямо в уровне значит
## заставить каждый обход [method _agents] перебирать ещё и их.
var _back_walls: Node2D = null
## Лампы здания: их свет тоже гасится за пределами кадра. Упавшие лампы
## убирают себя сами, поэтому перед обращением проверяется живость.
var _lamps: Array[Lamp] = []
## Кто стоит за каждой агентской дверью: дверь -> живой агент или null.
## Двери здания не выпускают всех разом — только те, чей этаж рядом с игроком
## (ADR-0014, пункт 4). Пустое значение значит «дверь свободна».
var _behind_door: Dictionary = {}
## Когда двери снова можно выпускать агента: дверь -> время по [method Time.get_ticks_msec].
var _door_ready_at: Dictionary = {}
## Здание сдано. Событие однократное: по нему main собирает следующее здание.
var _cleared: bool = false
## Машина у выхода и её отъезд: пока она едет, здание ещё не сдано.
var _car: Sprite2D = null
var _car_leaving: bool = false
## Куда машина уезжает: -1 влево, +1 вправо. Та же сторона, с которой она стоит.
var _car_towards: float = 1.0
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

	# Otto начинает с крыши, как в оригинале, и там, где нет проёмов. Крыша —
	# свой уровень над зданием, а не нулевой этаж: ADR-0014, пункт 1.
	var roof := BuildingRules.ROOF
	otto.global_position = Vector2(_plan.safe_x(rules, roof), rules.floor_surface(roof))
	otto.died.connect(_on_otto_died)
	GameState.instance().alarm_raised.connect(_on_alarm_raised)
	if GameState.instance().alarm.raised:
		# Здание заведено уже при включённой сирене — редкость, но бывает.
		_on_alarm_raised()
	# Агенты здесь не выпускаются: дверь отдаёт своего, когда её этаж подходит
	# к игроку. Раньше здесь выходили все 55 разом, и двое из них стояли на
	# крыше в зоне огня от точки старта — ADR-0014, пункт 4.
	for door in _agent_doors:
		_behind_door[door] = null
		_door_ready_at[door] = 0
	otto.apply_camera_bounds(Rect2(0.0, 0.0, rules.width, rules.total_height()))


## Гасит всё, что уехало из кадра. Источников в здании шестьдесят, а в кадр
## влезает два с половиной этажа — ADR-0010, пункт 8.
func _process(delta: float) -> void:
	var view := otto.camera_view()
	if _car_leaving:
		_move_car(delta, view)

	# Город отстаёт от камеры, оттого и кажется далёким.
	_city.position = view.position * CITY_PARALLAX

	var span := VisibleFloors.around(rules, view)
	# Агенты пересчитываются каждый кадр, а не только на смене полосы: дверь ждёт
	# своей паузы, и пропустив кадр смены, она не выпустила бы никого до следующей.
	if spawn_agents:
		_tend_agents(span)

	if span == _lit_span:
		return

	_lit_span = span
	for index: int in _floor_lights:
		var light: AreaLight = _floor_lights[index]
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
## [param bounds] — левый и правый края уровня: здание расширяется книзу, и
## перекрытие лежит не во всю ширину здания, а от стены до стены своего этажа.
static func slab_segments(
	surface: float, gaps: Array[Vector2], bounds: Vector2, thickness: float
) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for span in BuildingPlan.spans_between(gaps, bounds):
		rects.append(Rect2(span.x, surface, span.y - span.x, thickness))
	return rects


func _build_geometry() -> void:
	# Тайлы берутся один раз на здание: плит и стен в нём под три сотни,
	# а текстур две.
	var side_tile := SpriteTextures.tile("wall_side")
	var slab_tile := SpriteTextures.tile("slab")

	for index: int in rules.levels():
		var surface := rules.floor_surface(index)
		var bounds := rules.floor_span(index)
		var gaps := _plan.gaps_on(rules, index)
		for rect in slab_segments(surface, gaps, bounds, rules.slab_height):
			_build_solid(rect, slab_tile)
		_build_side_walls(index, surface, bounds, side_tile)


## Боковые стены уровня. Идут ступенями вслед за силуэтом, а не сплошными
## столбцами во всю высоту: здание расширяется книзу (ADR-0014, пункт 3).
##
## У крыши стена доходит до верха мира: это парапет, и он же не даёт шагнуть
## с крыши мимо здания. Прыжок берёт 80 px, и низкий бортик Otto перемахнул бы.
func _build_side_walls(index: int, surface: float, bounds: Vector2, tile: CanvasTexture) -> void:
	var top := rules.story_top(index)
	var height := surface + rules.slab_height - top
	if height <= 0.0:
		return

	_build_solid(Rect2(bounds.x, top, WALL_WIDTH, height), tile)
	_build_solid(Rect2(bounds.y - WALL_WIDTH, top, WALL_WIDTH, height), tile)


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
	zone.add_child(_tiled(area.size, -area.size * 0.5, SpriteTextures.tile("exit_way")))

	zone.body_entered.connect(_on_exit_entered)
	add_child(zone)
	_exit_position = zone.global_position
	_spawn_car(area)


## Машина у выхода. Стоит на полу нижнего этажа рядом с проёмом, за геометрией:
## она снаружи здания, и заходить на неё Otto не может — это картинка, не тело.
func _spawn_car(exit_area: Rect2) -> void:
	var texture := SpriteTextures.actor("car", "parked")
	var size := texture.get_size()
	_car = Sprite2D.new()
	_car.texture = texture
	_car.centered = false
	_car.z_index = -2
	# Уезжает в ближнюю сторону: там же и стоит. В дальнюю машина ехала бы через
	# всё здание, и «уехал» растянулось бы на пять секунд вместо одной.
	_car_towards = -1.0 if exit_area.get_center().x < rules.width * 0.5 else 1.0
	var x := exit_area.get_center().x + _car_towards * (EXIT_WIDTH * 0.5 + CAR_GAP)
	_car.position = Vector2(x - size.x * 0.5, exit_area.end.y - size.y)
	_car.flip_h = _car_towards < 0.0
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
	var width := _car.texture.get_width()
	var gone := _car.position.x + width < view.position.x or _car.position.x > view.end.x
	if gone:
		_car_leaving = false
		building_cleared.emit()


func _on_exit_entered(body: Node2D) -> void:
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
	runner.global_position = pending[index]


## Лампа накрыла агента по дороге вниз — самый дорогой способ убийства.
func _on_lamp_crushed(agent: Enemy) -> void:
	if agent.is_dead():
		return
	agent.kill(true)
	var points := GameState.kill_score(GameState.LAMP_SCORE, agent.is_in_the_dark())
	GameState.instance().add_score(points)


## Лампа долетела до пола: этаж гаснет и обратно уже не загорается.
func _on_lamp_fell(index: int) -> void:
	if not _lighting.darken(index):
		return
	# Этаж падает до общего тона здания: света на нём больше нет.
	if _floor_lights.has(index):
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


## Держит в здании ровно тех агентов, до которых игроку есть дело: выпускает
## их у дверей рядом с кадром и убирает тех, кто остался далеко позади.
##
## Раньше все 55 выходили разом в [method _ready] и жили до конца здания. Это
## и не давало играть — двое стояли на крыше в зоне огня от точки старта, — и
## держало полсотни тел с физикой и ИИ на каждом кадре (ADR-0014, пункт 4).
func _tend_agents(span: Vector2i) -> void:
	var now := Time.get_ticks_msec()
	for door: Door in _agent_doors:
		var index := rules.floor_index_near(door.mat_position().y)
		var agent: Enemy = _behind_door[door]
		var alive := is_instance_valid(agent) and not agent.is_dead()

		if alive:
			if not _within(span, index, AGENT_KEEP_MARGIN):
				agent.queue_free()
				_behind_door[door] = null
			continue

		# Дверь, чей агент умер или уехал, ждёт свою паузу и только потом
		# выпускает следующего.
		_behind_door[door] = null
		if _within(span, index, AGENT_SPAWN_MARGIN) and now >= int(_door_ready_at[door]):
			_behind_door[door] = _release_agent(door)


## Попадает ли уровень в полосу [param span], растянутую на [param margin] этажей.
static func _within(span: Vector2i, index: int, margin: int) -> bool:
	return index >= span.x - margin and index <= span.y + margin


## Выпускает агента из двери и отдаёт его: дверь помнит своего, чтобы не
## выпустить второго, пока первый жив.
func _release_agent(door: Door) -> Enemy:
	var mat := door.mat_position()
	var agent := ENEMY_SCENE.instantiate() as Enemy
	add_child(agent)
	agent.global_position = mat
	agent.setup(otto, signf(otto.global_position.x - mat.x))
	agent.set_in_the_dark(_lighting.is_dark(rules.floor_index_near(mat.y)))
	agent.set_menace(_menace())
	agent.died.connect(_on_agent_died.bind(door))
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
	for agent in _agents():
		agent.set_menace(_menace())


func _on_agent_died(_agent: Enemy, door: Door) -> void:
	# Смена не по таймеру, а по отметке времени: выпуском теперь заведует
	# [method _tend_agents], и он же решает, подошёл ли этаж к игроку. Таймер
	# выпустил бы агента у двери на другом конце здания, до которой нет дела.
	var wait := AGENT_RESPAWN_DELAY / _menace()
	_door_ready_at[door] = Time.get_ticks_msec() + int(wait * 1000.0)


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
	var index := rules.floor_index_near(otto.global_position.y)
	var surface := rules.floor_surface(index)
	otto.global_position = Vector2(_safest_x(index), surface)
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


func _on_pit_entered(body: Node2D) -> void:
	var victim := body as Otto
	if victim == null:
		return
	var deadly := ShaftHazards.is_deadly_fall(
		victim.is_grounded(), victim.is_riding(), victim.fall_height(), victim.jump_height()
	)
	if deadly:
		victim.kill()


func _build_solid(rect: Rect2, tile: CanvasTexture) -> void:
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
	body.add_child(_tiled(rect.size, -rect.size * 0.5, tile))
	body.add_child(_occluder(rect.size))

	add_child(body)


## Окна этажа: равные проёмы в задней стене, через которые виден город.
##
## Статический, чтобы проверяться без сцены, — как и [method slab_segments].
## [param bounds] — внутренние края стены, между которыми раскладываются окна.
static func window_gaps(bounds: Vector2, count: int, window_width: float) -> Array[Vector2]:
	var gaps: Array[Vector2] = []
	var width := bounds.y - bounds.x
	if count <= 0 or window_width <= 0.0 or width <= 0.0:
		return gaps

	var pitch := width / float(count)
	for number: int in count:
		# Окно стоит посередине своей доли стены: так они разнесены поровну
		# и у стен здания остаётся полполосы, а не обрезанное окно.
		var centre := bounds.x + pitch * (float(number) + 0.5)
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

	# Тайлы берутся один раз на здание: полос и рам под три сотни, а текстур две.
	var wall_tile := SpriteTextures.tile("wall")
	var frame_tile := SpriteTextures.tile("window_frame")
	# Этажи, крыши среди них нет: она снаружи, комнаты за ней не бывает, и стена
	# вышла бы полосой в небе над тем местом, где Otto начинает.
	for index: int in rules.floors:
		var top := rules.story_top(index)
		var surface := rules.floor_surface(index)
		if surface - top <= 0.0:
			continue

		# Окна режутся по ширине своего этажа: на узких этажах стена короче,
		# и окна, разложенные по ширине здания, уехали бы за неё на улицу.
		var bounds := rules.floor_span(index)
		var inner := Vector2(bounds.x + WALL_WIDTH, bounds.y - WALL_WIDTH)
		var gaps := window_gaps(inner, WINDOWS_PER_FLOOR, WINDOW_SIZE.x)

		var window_top := minf(top + WINDOW_TOP, surface)
		var window_bottom := minf(window_top + WINDOW_SIZE.y, surface)
		var width := inner.y - inner.x
		_add_back_wall(Rect2(inner.x, top, width, window_top - top), wall_tile)
		_add_back_wall(Rect2(inner.x, window_bottom, width, surface - window_bottom), wall_tile)

		for span: Vector2 in BuildingPlan.spans_between(gaps, inner):
			var strip := Rect2(span.x, window_top, span.y - span.x, window_bottom - window_top)
			_add_back_wall(strip, wall_tile)

		for gap: Vector2 in gaps:
			var opening := Rect2(gap.x, window_top, gap.y - gap.x, window_bottom - window_top)
			_add_window_frame(opening, frame_tile)


func _add_back_wall(rect: Rect2, tile: CanvasTexture) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	_back_walls.add_child(_tiled(rect.size, rect.position, tile))


## Рама вокруг проёма, в котором виден город.
##
## Кладётся девятикусочно и наполовину заходит на стену: так проём получает
## откос, на котором играет свет этажа, а город в нём остаётся городом —
## середина рамы пустая, а не застеклённая.
func _add_window_frame(opening: Rect2, tile: CanvasTexture) -> void:
	if opening.size.x <= 0.0 or opening.size.y <= 0.0:
		return

	var overlap := SpriteTextures.FRAME_MARGIN * 0.5
	var frame := NinePatchRect.new()
	frame.texture = tile
	frame.draw_center = false
	frame.patch_margin_left = int(SpriteTextures.FRAME_MARGIN)
	frame.patch_margin_top = int(SpriteTextures.FRAME_MARGIN)
	frame.patch_margin_right = int(SpriteTextures.FRAME_MARGIN)
	frame.patch_margin_bottom = int(SpriteTextures.FRAME_MARGIN)
	frame.position = opening.position - Vector2(overlap, overlap)
	frame.size = opening.size + Vector2(overlap, overlap) * 2.0
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_walls.add_child(frame)


## Город за окнами. Свет здания на него не падает: он снаружи и далеко.
func _build_city() -> void:
	_city = Node2D.new()
	_city.z_index = -9
	add_child(_city)

	var stone := SpriteTextures.tile("city_wall")
	for tower: Skyline.Tower in Skyline.generate(building_seed, CITY_AREA):
		_add_city_panel(tower.rect, CITY, stone)
		for window: Rect2 in tower.windows:
			# Окно города — источник, а не поверхность: рельеф ему ни к чему.
			_add_city_panel(window, CITY_WINDOW, null)


## Кусок дальнего плана. Свет здания на него не падает.
##
## Маска гасится на каждой панели, а не на общем узле: [member CanvasItem.light_mask]
## детям не передаётся, и город в окне разгорался вместе с этажом — окно читалось
## как освещённая ниша, а не как улица.
## Кусок дальнего плана: башня с текстурой или окно, которое рисуется заливкой.
## Окну рельеф ни к чему — оно источник, а не поверхность, поэтому [param tile]
## у него пустой. Это единственное место, где заливка осталась намеренно.
func _add_city_panel(rect: Rect2, color: Color, tile: CanvasTexture = null) -> void:
	var panel: Control = (
		_panel(rect.size, rect.position, color)
		if tile == null
		else _tiled(rect.size, rect.position, tile)
	)
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

	for index: int in rules.levels():
		var light := AreaLight.covering(_story_area(index), FLOOR_LIGHT, FLOOR_ENERGY)
		add_child(light)
		_floor_lights[index] = light


## Пролёт уровня: от потолка до низа настила, на котором стоят.
##
## Настил включён нарочно: кончайся заливка ровно по полу, сам пол и ноги
## стоящего на нём остались бы неосвещёнными.
##
## У крыши потолка нет — над ней небо, и [method BuildingRules.story_top] отдаёт
## верх мира. Ламп на крыше тоже нет, поэтому погасить её свет нечем: светит ей
## город, и это единственный уровень, который не гаснет никогда.
func _story_area(index: int) -> Rect2:
	var surface := rules.floor_surface(index)
	var top := rules.story_top(index)
	var bounds := rules.floor_span(index)
	return Rect2(bounds.x, top, bounds.y - bounds.x, surface + rules.slab_height - top)


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
	# Размер задаёт место, а не тайл. По умолчанию [TextureRect] объявляет
	# минимальным размером размер текстуры, и [Control] поднимал до него всё,
	# что меньше: полоса стены над окном (14 px при тайле 32 px) растягивалась
	# до 32 px и закрывала город в верхней трети проёма.
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
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
