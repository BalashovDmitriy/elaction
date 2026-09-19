class_name GreyboxLevel
extends Node2D

## Здание, собранное по [BuildingPlan].
##
## Где что стоит, решает раскладка по правилам и сиду; уровень только расставляет
## узлы и связывает их между собой. Геометрия собрана из ассетов окружения
## ([SpriteTextures], ADR-0011), свет к ним пришёл раньше — в M6.

## Otto вышел из здания, собрав все документы.
signal building_cleared

## Сила заливки горящего этажа и столба света в шахте.
##
## Сами цвета живут в [BuildingPalette]: они меняются от раунда к раунду
## (ADR-0017, решение 2), а сила — нет, она подобрана под ассеты.
const FLOOR_ENERGY: float = 1.15
const SHAFT_ENERGY: float = 0.55

## Ширина направляющей шахты, px. Стойка идёт по краю проёма во всю его высоту.
const SHAFT_RAIL_WIDTH: float = 6.0

## Высота створок шахты, px. Совпадает с ассетом `shaft_door`.
const SHAFT_DOOR_HEIGHT: float = 34.0

## Надстройка машинного отделения на крыше, px. Совпадает с ассетом `machine_room`.
const MACHINE_ROOM_SIZE := Vector2(72.0, 44.0)

## Ширина троса, по которому Otto съезжает на крышу, px.
const ROPE_WIDTH: float = 4.0

## Сколько Otto висит над крышей в начале здания и как быстро съезжает.
##
## Выше собственного прыжка (80 px): он должен прийти сверху, а не подпрыгнуть.
## Спуск занимает меньше секунды — это кадр вступления, а не механика
## (ADR-0017, решение 4).
const ROPE_DROP: float = 88.0
const ROPE_SPEED: float = 140.0

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

## На сколько этажей дальше видимой полосы дверь ещё выпускает агентов.
##
## Запас нужен, чтобы агент не появлялся на глазах у игрока в середине кадра:
## дверь отдаёт его за кромкой, и в кадр он уже входит своим ходом.
const AGENT_SPAWN_MARGIN: int = 1

## Ближе этого дверь агента не выпускает, px.
##
## Иначе агент появляется прямо на Otto: двери стоят на местах этажа, и стоящий
## у двери получал выходящего в упор — на четыре пикселя, — а с такого
## расстояния не помогают ни уклонение, ни выстрел первым. Дверь просто ждёт,
## пока игрок отойдёт.
const AGENT_SAFE_RELEASE: float = 96.0

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
## Дальний план: задние стены с окнами и город за ними. Свой узел, потому что
## их под три сотни, и каждый обход детей уровня перебирал бы ещё и их.
var _backdrop: BuildingBackdrop = null
## Лампы здания: их свет тоже гасится за пределами кадра. Упавшие лампы
## убирают себя сами, поэтому перед обращением проверяется живость.
var _lamps: Array[Lamp] = []
## Посты у агентских дверей, по одному на дверь. Двери здания не выпускают всех
## разом — только те, чей этаж рядом с игроком (ADR-0014, пункт 4).
var _posts: Array[AgentPost] = []
## Здание сдано. Событие однократное: по нему main собирает следующее здание.
var _cleared: bool = false
## Машина у выхода и её отъезд: пока она едет, здание ещё не сдано.
var _car: Sprite2D = null
var _car_leaving: bool = false
## Куда машина уезжает: -1 влево, +1 вправо. Та же сторона, с которой она стоит.
var _car_towards: float = 1.0
var _exit_position := Vector2.ZERO
## Трос вступления и докуда по нему ехать. Пока едет — Otto не слушается ввода.
var _rope: TextureRect = null
var _sliding: bool = false
var _rope_target: float = 0.0

@onready var otto: Otto = $Otto
@onready var _background: ColorRect = $Background


func _ready() -> void:
	if rules == null:
		rules = BuildingRules.new()
	_plan = BuildingPlan.generate(rules, building_seed)

	_background.size = Vector2(rules.width, rules.total_height())
	_backdrop = BuildingBackdrop.new()
	add_child(_backdrop)
	_backdrop.build(rules, building_seed, WALL_WIDTH)
	_build_geometry()
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
	otto.global_position = landing - Vector2(0.0, ROPE_DROP)
	_start_the_slide(landing)
	otto.died.connect(_on_otto_died)
	GameState.instance().alarm_raised.connect(_on_alarm_raised)
	if GameState.instance().alarm.raised:
		# Здание заведено уже при включённой сирене — редкость, но бывает.
		_on_alarm_raised()
	# Агенты здесь не выпускаются: дверь отдаёт своего, когда её этаж подходит
	# к игроку. Раньше здесь выходили все 55 разом, и двое из них стояли на
	# крыше в зоне огня от точки старта — ADR-0014, пункт 4.
	for door in _agent_doors:
		var post := AgentPost.new()
		post.door = door
		post.floor_index = rules.floor_index_near(door.mat_position().y)
		_posts.append(post)
	otto.apply_camera_bounds(Rect2(0.0, 0.0, rules.width, rules.total_height()))


## Гасит всё, что уехало из кадра. Источников в здании шестьдесят, а в кадр
## влезает два с половиной этажа — ADR-0010, пункт 8.
func _process(delta: float) -> void:
	var view := otto.camera_view()
	if _car_leaving:
		_move_car(delta, view)

	# Город отстаёт от камеры, оттого и кажется далёким.
	_backdrop.follow(view)

	var span := VisibleFloors.around(rules, view)
	# Агенты пересчитываются каждый кадр, а не только на смене полосы: дверь ждёт
	# своей паузы, и пропустив кадр смены, она не выпустила бы никого до следующей.
	if spawn_agents:
		_tend_agents(span, delta)

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
	# Тайлы берутся один раз на здание: плит и стен в нём под три сотни,
	# а текстур две.
	var side_tile := SpriteTextures.tile("wall_side")
	var slab_tile := SpriteTextures.tile("slab")

	for index: int in rules.levels():
		var surface := rules.floor_surface(index)
		var bounds := rules.floor_span(index)
		var gaps := _plan.gaps_on(rules, index)
		# Перекрытие шире собственных стен там, где силуэт делает ступень: оно же
		# потолок нижнего этажа, а тот шире своего верхнего соседа.
		for rect in slab_segments(surface, gaps, rules.slab_span(index), rules.slab_height):
			# Перекрытия тоном раунда не красятся: белый пол и потолок должны
			# читаться одинаково в любом раунде — это опора, а не фон.
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

	_build_solid(Rect2(bounds.x, top, WALL_WIDTH, height), tile, rules.palette.masonry)
	_build_solid(Rect2(bounds.y - WALL_WIDTH, top, WALL_WIDTH, height), tile, rules.palette.masonry)


func _spawn_shafts() -> void:
	# Тайлы берутся один раз на здание: шахт в нём пять, а этажей у них тридцать.
	var rail_tile := SpriteTextures.tile("shaft_rail")
	var door_tile := SpriteTextures.tile("shaft_door")
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
		_dress_shaft(shaft, rail_tile, door_tile)
		_light_shaft(shaft)
	_spawn_machine_room()


## Одевает шахту: направляющие во всю её высоту и створки на каждом её этаже.
##
## До M12 шахта была дырой в перекрытии со столбом света — в кадре её почти не
## было, хотя спуск по зданию и есть игра (ADR-0017, решение 3). Направляющие
## дают ей края, створки — отметку этажа: по ним видно, где кабина встаёт.
##
## Рисуется позади перекрытий (`z_index` −2): стойка идёт сквозь всю шахту, и
## на каждом этаже её перекрывает плита — ровно так, как она и шла бы внутри
## шахты. Кабина идёт впереди и закрывает их собой, когда проходит мимо.
func _dress_shaft(
	shaft: BuildingPlan.ShaftSpot, rail_tile: CanvasTexture, door_tile: CanvasTexture
) -> void:
	var top := rules.story_top(shaft.top)
	if shaft.top <= BuildingRules.ROOF:
		# Над крышей потолка нет, и стойки ушли бы в небо. Верхняя шахта
		# кончается внутри машинного отделения: оно и есть её верх.
		top = rules.floor_surface(BuildingRules.ROOF) - MACHINE_ROOM_SIZE.y * 0.5
	var bottom := rules.floor_surface(shaft.bottom)
	var half := rules.shaft_width * 0.5
	var tint := rules.palette.shaft

	for side: float in [-1.0, 1.0]:
		var x := shaft.x + half * side
		var left := x if side < 0.0 else x - SHAFT_RAIL_WIDTH
		_add_shaft_part(Rect2(left, top, SHAFT_RAIL_WIDTH, bottom - top), rail_tile, tint)

	for index: int in range(shaft.top, shaft.bottom + 1):
		var surface := rules.floor_surface(index)
		var door := Rect2(
			shaft.x - half, surface - SHAFT_DOOR_HEIGHT, rules.shaft_width, SHAFT_DOOR_HEIGHT
		)
		_add_shaft_part(door, door_tile, tint, true)


## Кусок одежды шахты. Без тела: по направляющим не ходят, они только видны.
##
## [param whole] — ассет кладётся целиком, а не плиткой. Стойка тайлится: она
## идёт на сотни пикселей, а тайл у неё в шестнадцать. Створки — одна картинка
## шириной в шахту, и замостить её значило бы порезать их пополам, стоит
## [member BuildingRules.shaft_width] разойтись с ассетом.
func _add_shaft_part(rect: Rect2, tile: CanvasTexture, tint: Color, whole: bool = false) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var part := (
		TiledRect.stretched(rect.size, rect.position, tile, tint)
		if whole
		else TiledRect.make(rect.size, rect.position, tile, tint)
	)
	part.z_index = -2
	add_child(part)


## Надстройка машинного отделения над верхней шахтой.
##
## Тела у неё нет намеренно: под ней проём той самой шахты, с которой начинается
## спуск, и сплошная надстройка заперла бы Otto на крыше. Стоит она позади него
## (`z_index` −2), и он проходит перед ней.
func _spawn_machine_room() -> void:
	var shaft := _plan.roof_shaft()
	if shaft == null:
		return

	var surface := rules.floor_surface(BuildingRules.ROOF)
	var rect := Rect2(
		Vector2(shaft.x - MACHINE_ROOM_SIZE.x * 0.5, surface - MACHINE_ROOM_SIZE.y),
		MACHINE_ROOM_SIZE
	)
	# Не плиткой, а целиком: у домика рисунок цельный, и замостить его значило
	# бы порезать крышу на четверти.
	var room := TiledRect.stretched(
		rect.size, rect.position, SpriteTextures.tile("machine_room"), rules.palette.masonry
	)
	room.z_index = -2
	add_child(room)


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

	_rope = TiledRect.make(
		Vector2(ROPE_WIDTH, landing.y),
		Vector2(landing.x - ROPE_WIDTH * 0.5, 0.0),
		SpriteTextures.tile("rope")
	)
	_rope.z_index = -2
	add_child(_rope)


## Довозит Otto по тросу и убирает трос: он часть вступления, а не здания.
##
## Трос ведёт Otto, только пока тот выше крыши. Переставили ниже — вступление
## кончилось само: так инструменты съёмки и тесты ставят его куда им надо,
## не зная про трос вовсе.
func _physics_process(delta: float) -> void:
	if not _sliding:
		return

	if otto.global_position.y < _rope_target:
		otto.global_position.y = minf(otto.global_position.y + ROPE_SPEED * delta, _rope_target)
	if otto.global_position.y >= _rope_target:
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
	# Вывеска — одна картинка на весь проём, а не тайл: замощённая, она повторилась
	# бы половинкой, стоит проёму разойтись с ассетом.
	zone.add_child(
		TiledRect.stretched(area.size, -area.size * 0.5, SpriteTextures.tile("exit_way"))
	)

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
		if rules.floor_index_near(agent.global_position.y) == index:
			found.append(agent)
	return found


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
	var here := rules.floor_index_near(otto.global_position.y)
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
				continue
			live += 1
			continue

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

		var gap := absi(post.floor_index - here)
		if nearest == null or gap < nearest_gap:
			nearest = post
			nearest_gap = gap

	if nearest != null and live < rules.agents_at_once:
		nearest.agent = _release_agent(nearest)


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


## Выпускает агента из двери и отдаёт его: дверь помнит своего, чтобы не
## выпустить второго, пока первый жив.
func _release_agent(post: AgentPost) -> Enemy:
	var mat := post.door.mat_position()
	var agent := ENEMY_SCENE.instantiate() as Enemy
	# Правила отдаются до дерева: так агент входит в него уже настроенным, и
	# заводить себе значения по умолчанию ему не приходится.
	agent.apply_rules(rules)
	add_child(agent)
	agent.global_position = mat
	agent.setup(otto, signf(otto.global_position.x - mat.x))
	agent.set_in_the_dark(_lighting.is_dark(post.floor_index))
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


func _build_solid(rect: Rect2, tile: CanvasTexture, tint := Color.WHITE) -> void:
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
	body.add_child(TiledRect.make(rect.size, -rect.size * 0.5, tile, tint))
	body.add_child(_occluder(rect.size))

	add_child(body)


## Столб света в шахте на всю её высоту.
##
## Шахта — единственное, что светится в погашенном здании само: она соединяет
## этажи, и свет в ней показывает, куда идти, когда лампы сбиты. Гасить её вместе
## с этажом нельзя — этажей у шахты много, а столб один.
func _light_shaft(shaft: BuildingPlan.ShaftSpot) -> void:
	var top := rules.story_top(shaft.top)
	var bottom := rules.floor_surface(shaft.bottom)
	var area := Rect2(shaft.x - rules.shaft_width * 0.5, top, rules.shaft_width, bottom - top)
	var light := AreaLight.column(area, rules.palette.shaft_light, SHAFT_ENERGY)
	add_child(light)
	_shaft_lights.append(light)


## Зажигает здание: общий тон и заливка на каждом этаже.
##
## Светлым этаж делает собственный источник, а не отсутствие темноты — вся
## конструкция вехи держится на этом (ADR-0010, пункт 3).
func _light_building() -> void:
	var ambient := CanvasModulate.new()
	ambient.color = rules.palette.dark
	add_child(ambient)

	for index: int in rules.levels():
		var light := AreaLight.covering(_story_area(index), rules.palette.lit, FLOOR_ENERGY)
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
