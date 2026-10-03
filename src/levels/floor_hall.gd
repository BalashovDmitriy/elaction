class_name FloorHall
extends Node3D

## Залы особых этажей за плоскостью игры (ADR-0057, решения 2–5).
##
## На особом этаже вместо задней стены коридора — колонны, стекло или сетка, и
## за ними зал на всю глубину плиты: лобби, ресторан, бассейн, котельная,
## серверная. Роль этажа — по устройству ROM ([FloorRole]); здесь только вид.
## Тел нет, теней нет: примитивы и мебель паков собраны мультимешами
## ([MeshBatch]) — деталей сотни на этаж, вызовов отрисовки десятки на здание.
##
## Зал обходит комнаты за дверями: перед дверью на глубину комнаты
## ([constant DoorRoom.DEPTH]) ничего не стоит — створка открывается в комнату,
## и та встаёт в зале как отгороженный угол. У офиса комнат нет, дверь
## открывается в зал, и свободна только полоса створки.
##
## Ночью на тёмных этажах ROM всё, что светится само, погашено: экраны,
## индикаторы, бутылки бара, окно топки. Пар над котлом живёт и в темноте.
##
## Координаты: x — вдоль этажа, высота — над полом, глубина d — от задней стены
## коридора в зал (0 … [constant WorldSpace.ROOM_DEPTH]).

## Стойки сетки-рабицы и их шаг, м: сетку ставит [BuildingShell].
const MESH_POST := Color(0.34, 0.35, 0.36)
const MESH_POST_STEP: float = 1.5

## Глубина зала, м: до дальней стены, с зазором.
const DEPTH: float = WorldSpace.ROOM_DEPTH - 0.15
## Ближе этого к краю пролёта зал ничего не ставит, м.
const EDGE: float = 0.5
## Полоса створки офисной двери, м: глубже стоять можно.
const LEAF_CLEAR: float = DoorRoom.LEAF_CLEAR

## Свет зала: точечные источники без теней через [constant LIGHT_STEP] м на
## середине глубины. Лампы коридора светят вниз, конусом, и в глубину зала не
## достают; без своего света зал читался бы чёрной дырой. Горят, как лампы,
## только на этажах в кадре ([method light_span]).
const LIGHT_STEP: float = 5.0
const LIGHT_HEIGHT: float = 2.4
const LIGHT_RANGE: float = 5.5
const LIGHT_ENERGY: float = 1.3
## Свой оттенок у зала, где свет особый: вода, серверы, топка, неон бара.
const POOL_LIGHT := Color(0.55, 0.85, 1.0)
const SERVER_LIGHT := Color(0.6, 0.75, 1.0)
const BOILER_LIGHT := Color(1.0, 0.6, 0.35)
const BAR_LIGHT := Color(1.0, 0.55, 0.6)

## Пол зала по роли: мрамор, паркет, плитка, резина, бетон.
const MARBLE := Color(0.78, 0.74, 0.66)
const DARK_STONE := Color(0.16, 0.17, 0.19)
const TERRAZZO := Color(0.55, 0.53, 0.48)
const PARQUET := Color(0.42, 0.25, 0.13)
const POOL_TILE := Color(0.7, 0.78, 0.8)
const RUBBER := Color(0.1, 0.1, 0.11)
const CONCRETE := Color(0.38, 0.38, 0.37)
const RAISED_FLOOR := Color(0.6, 0.62, 0.63)
const LINOLEUM := Color(0.46, 0.44, 0.36)
const CARPET_HALL := Color(0.3, 0.12, 0.14)
const OFFICE_CARPET := Color(0.22, 0.25, 0.3)
const DINER_TILE := Color(0.62, 0.6, 0.55)

## Цвета деталей залов.
const WOOD := Color(0.3, 0.17, 0.1)
const BRASS := Color(0.74, 0.56, 0.28)
const STEEL := Color(0.6, 0.62, 0.64)
const DARK_STEEL := Color(0.2, 0.21, 0.23)
const PAINTED_GREEN := Color(0.22, 0.34, 0.26)
const PAINTED_RED := Color(0.5, 0.12, 0.1)
const PIPE := Color(0.36, 0.33, 0.3)
const INSULATION := Color(0.72, 0.7, 0.64)
const CHALK := Color(0.85, 0.85, 0.82)
const RACK := Color(0.08, 0.085, 0.09)
const SCREEN := Color(0.45, 0.75, 0.95)
const TABLE_GREEN := Color(0.1, 0.32, 0.2)
const LINEN := Color(0.88, 0.87, 0.82)
const CARDBOARD := Color(0.55, 0.42, 0.27)
const FIRE := Color(1.0, 0.45, 0.12)
const CANDLE := Color(1.0, 0.75, 0.4)
const NEON := Color(1.0, 0.3, 0.55)
const BOTTLES: Array[Color] = [
	Color(0.9, 0.55, 0.15), Color(0.3, 0.75, 0.35), Color(0.85, 0.85, 0.7), Color(0.6, 0.2, 0.15)
]

var _rules: BuildingRules = null
var _plan: BuildingPlan = null
var _batch := MeshBatch.new()
## Этаж, который сейчас собирается.
var _index: int = 0
var _surface: float = 0.0
var _lit: bool = true
var _doors: Array[float] = []
var _steam: Array[Vector3] = []
## Свет залов по этажу: [method light_span] гасит невидимые.
var _lights: Dictionary = {}


## Собирает залы всех особых этажей здания.
func build(rules: BuildingRules, plan: BuildingPlan) -> void:
	name = "FloorHall"
	_rules = rules
	_plan = plan
	for index: int in range(0, rules.floors - 1):
		var role := FloorRole.at(rules, index)
		if FloorRole.is_hall(role):
			_floor(index, role)
	_batch.commit(self)
	for at: Vector3 in _steam:
		add_child(HallLook.steam_plume(at))


## Зажигает свет залов на видимых этажах и гасит остальные — тем же
## правилом, что лампы и столбы шахт (ADR-0010, пункт 8).
func light_span(span: Vector2i, strip: Vector2 = Vector2(-INF, INF)) -> void:
	for index: int in _lights:
		var lit := VisibleFloors.covers(span, index)
		for light: OmniLight3D in _lights[index]:
			light.visible = lit and VisibleFloors.in_band(strip, light.global_position.x)


## Источники света залов: тестам.
func lights() -> Array[OmniLight3D]:
	var all: Array[OmniLight3D] = []
	for index: int in _lights:
		all.append_array(_lights[index] as Array[OmniLight3D])
	return all


## Сколько деталей в залах: тестам.
func parts() -> int:
	var total := 0
	for child: Node in get_children():
		var many := child as MultiMeshInstance3D
		if many != null:
			total += many.multimesh.instance_count
	return total


func _floor(index: int, role: FloorRole.Role) -> void:
	_index = index
	_surface = _rules.floor_surface(index)
	_lit = not _rules.is_unlit(index)
	_doors.clear()
	for spot: BuildingPlan.DoorSpot in _plan.doors:
		if spot.floor_index == index:
			_doors.append(spot.x)
	var bounds := _rules.floor_span(index)
	var inner := Vector2(bounds.x + BuildingShell.WALL_WIDTH, bounds.y - BuildingShell.WALL_WIDTH)
	for span: Vector2 in BuildingPlan.spans_between(_plan.blocks_on(_rules, index), inner):
		if span.y - span.x < EDGE * 4.0:
			continue
		_lay(role, Vector2(span.x + EDGE, span.y - EDGE))
		if _lit:
			_light(index, role, span)


## Свет зала на пролёте [param span]: оттенок ламп типа или свой у зала.
func _light(index: int, role: FloorRole.Role, span: Vector2) -> void:
	var colour: Color = BuildingAir.LAMP_LIGHT[_rules.kind]
	match role:
		FloorRole.Role.POOL:
			colour = POOL_LIGHT
		FloorRole.Role.SERVER:
			colour = SERVER_LIGHT
		FloorRole.Role.BOILER:
			colour = BOILER_LIGHT
		FloorRole.Role.BAR:
			colour = BAR_LIGHT
	if not _lights.has(index):
		_lights[index] = [] as Array[OmniLight3D]
	var count := maxi(1, roundi((span.y - span.x) / LIGHT_STEP))
	for step: int in count:
		var x := span.x + (span.y - span.x) * (float(step) + 0.5) / float(count)
		var light := OmniLight3D.new()
		light.name = "HallLight"
		light.light_color = colour
		light.light_energy = LIGHT_ENERGY
		light.omni_range = LIGHT_RANGE
		light.shadow_enabled = false
		light.position = MeshBatch.scene_of(Vector3(x, _surface - LIGHT_HEIGHT, _z(3.8)))
		light.visible = false
		add_child(light)
		(_lights[index] as Array[OmniLight3D]).append(light)


func _lay(role: FloorRole.Role, span: Vector2) -> void:
	match role:
		FloorRole.Role.LOBBY:
			_lobby(span)
		FloorRole.Role.DINING:
			_dining(span)
		FloorRole.Role.BALLROOM:
			_ballroom(span)
		FloorRole.Role.POOL:
			_pool(span)
		FloorRole.Role.BAR:
			_bar(span)
		FloorRole.Role.CONFERENCE:
			_conference(span)
		FloorRole.Role.MEETING:
			_meeting(span)
		FloorRole.Role.GYM:
			_gym(span)
		FloorRole.Role.COMMUNITY:
			_community(span)
		FloorRole.Role.LOCKERS:
			_lockers(span)
		FloorRole.Role.LAUNDRY:
			_laundry(span)
		FloorRole.Role.BOILER:
			_boiler(span)
		FloorRole.Role.MECHANICAL:
			_mechanical(span)
		FloorRole.Role.SERVER:
			_server(span)
		FloorRole.Role.ARCHIVE:
			_archive(span)
		FloorRole.Role.KITCHEN:
			_kitchen(span)
		FloorRole.Role.STORAGE:
			_storage(span)
		FloorRole.Role.WORKSHOP:
			_workshop(span)


# --- Общественные залы ------------------------------------------------------


## Лобби: у отеля — мрамор, стойка регистрации с ключами за ней и диваны; у
## офиса — тёмный камень, пост охраны с мониторами и турникеты; у жилого дома —
## терраццо, почтовые ящики, стол швейцара и скамья.
func _lobby(span: Vector2) -> void:
	match _rules.kind:
		BuildingIdentity.Kind.OFFICE:
			_floor_cover(span, GreyboxLook.polished(DARK_STONE))
			_windows(span)
			var middle := (span.x + span.y) * 0.5
			_desk_row(middle, 2.4, 3.2, STEEL, true)
			for x: float in _along(span, 1.1, 0.0):
				if absf(x - middle) < 2.0:
					continue
				_turnstile(x, 5.0)
			for x: float in _along(span, 4.0, 2.0):
				_prop("bench_cushion", x, 1.4)
				_prop("houseplant_c", x + 1.2, 1.2)
		BuildingIdentity.Kind.RESIDENTIAL:
			_floor_cover(span, GreyboxLook.polished(TERRAZZO))
			_far_wall(span, GreyboxLook.surface(Color(0.5, 0.45, 0.36)))
			for x: float in _along(span, _width_of("mailboxes", 0.05), 0.0):
				_prop("mailboxes", x, DEPTH - 0.2, 0.0, 1.0)
			var middle := (span.x + span.y) * 0.5
			_desk_row(middle, 1.4, 3.6, Color(0.35, 0.24, 0.15), false)
			for x: float in _along(span, 3.5, 1.5):
				if absf(x - middle) < 1.6:
					continue
				_prop("bench_hotel", x, 1.2)
				_prop("radiator", x + 1.2, 0.5)
		_:
			_floor_cover(span, GreyboxLook.polished(MARBLE))
			_far_wall(span, GreyboxLook.surface(Color(0.36, 0.22, 0.14)))
			var middle := (span.x + span.y) * 0.5
			var counter := minf(span.y - span.x - 2.0, 6.0)
			_on(GreyboxLook.surface(WOOD), Vector3(counter, 1.1, 0.7), middle, 0.0, 4.6)
			_on(GreyboxLook.metal(BRASS), Vector3(counter + 0.1, 0.05, 0.8), middle, 1.1, 4.6)
			_key_rack(middle, counter)
			for x: float in _along(span, 3.2, 1.0):
				if not _free(x, 1.2, 2.2):
					continue
				_prop("lounge_sofa", x, 2.0)
				_prop("coffee_table", x, 1.1)
				_prop("floor_lamp_round", x + 1.3, 2.0)
			for x: float in [span.x + 0.4, span.y - 0.4]:
				_prop("houseplant_c", x, 5.5)


## Ресторан отеля — столы со скатертями и свечами, окна на город; столовая
## офиса — длинные столы, линия раздачи у дальней стены.
func _dining(span: Vector2) -> void:
	if _rules.kind == BuildingIdentity.Kind.OFFICE:
		_floor_cover(span, GreyboxLook.polished(DINER_TILE))
		_far_wall(span, GreyboxLook.surface(Color(0.7, 0.7, 0.68)))
		for x: float in _along(span, _width_of("kitchen_cabinet", 0.0), 0.0):
			_prop("kitchen_cabinet", x, DEPTH - 0.4)
		_on(GreyboxLook.metal(STEEL), Vector3(span.y - span.x, 0.04, 0.3), _mid(span), 0.95, 6.1)
		for row: float in [2.4, 4.4]:
			for x: float in _along(span, 2.6, 0.0):
				if not _free(x, 1.0, row):
					continue
				_prop("long_table", x, row)
				for side: float in [-0.55, 0.55]:
					_prop("desk_chair", x + side, row - 0.6, 180.0)
		return
	_floor_cover(span, GreyboxLook.surface(CARPET_HALL))
	_windows(span)
	for row: float in [2.0, 3.9, 5.6]:
		for x: float in _along(span, 2.2, 0.0 if row != 3.9 else 1.1):
			if not _free(x, 0.8, row):
				continue
			_prop("dining_table", x, row)
			_prop("dining_chair", x - 0.62, row, 90.0)
			_prop("dining_chair", x + 0.62, row, -90.0)
			_glow(CANDLE, 0.05, Vector3(x, 0.82, row))


## Бальный зал: паркет, сцена с роялем и колонками у дальней стены, круглые
## столы по краям танцпола и зеркальный шар.
func _ballroom(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.polished(PARQUET))
	_far_wall(span, GreyboxLook.surface(Color(0.32, 0.08, 0.1)))
	var middle := _mid(span)
	var stage := minf(span.y - span.x - 1.0, 7.0)
	_on(GreyboxLook.surface(Color(0.15, 0.1, 0.08)), Vector3(stage, 0.5, 1.8), middle, 0.0, 6.0)
	_piano(middle - stage * 0.25, 5.9)
	for side: float in [-1.0, 1.0]:
		_prop("speaker", middle + side * (stage * 0.5 - 0.4), 6.2)
	_glow(Color(0.9, 0.9, 1.0), 0.45, Vector3(middle, 2.4, 3.5))
	for x: float in _along(span, 2.4, 0.0):
		if absf(x - middle) < 2.5:
			continue
		for row: float in [1.8, 3.6]:
			if _free(x, 0.8, row):
				_prop("round_table", x, row)
				_prop("dining_chair", x - 0.7, row, 90.0)
				_prop("dining_chair", x + 0.7, row, -90.0)


## Бассейн: светлая плитка, чаша с водой в ряби, бортик, лесенки, шезлонги у
## края и окна на город.
func _pool(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.polished(POOL_TILE))
	_windows(span)
	var length := span.y - span.x - 1.0
	var middle := _mid(span)
	var water := HallLook.water()
	_batch.box(
		water,
		Vector3(length, 0.03, 2.6),
		Vector3(middle, _surface - 0.035, WorldSpace.BACK_WALL_Z - 4.0)
	)
	var rim := GreyboxLook.polished(Color(0.86, 0.88, 0.88))
	for edge: float in [2.6, 5.4]:
		_on(rim, Vector3(length + 0.3, 0.06, 0.15), middle, 0.0, edge)
	for side: float in [-1.0, 1.0]:
		_on(rim, Vector3(0.15, 0.06, 2.95), middle + side * (length * 0.5 + 0.08), 0.0, 4.0)
	var rail := GreyboxLook.metal(STEEL)
	for x: float in [span.x + 1.2, span.y - 1.2]:
		for offset: float in [-0.25, 0.25]:
			_batch.cylinder_on(rail, 0.025, 1.0, _surface, Vector3(x + offset, 0.0, _z(2.65)))
	for x: float in _along(span, 1.6, 0.0):
		if _free(x, 0.5, 1.4):
			_prop("bench_cushion", x, 1.4)
	_glow(Color(1.0, 0.4, 0.2), 0.3, Vector3(span.x + 0.4, 1.4, 6.6))


## Бар скай-лобби: стойка с табуретами, за ней полки светящихся бутылок, неон
## и диваны у колонн.
func _bar(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.polished(Color(0.14, 0.08, 0.05)))
	_far_wall(span, GreyboxLook.surface(Color(0.12, 0.08, 0.07)))
	var middle := _mid(span)
	var unit_width := _width_of("bar_counter", 0.0)
	var units := clampi(int((span.y - span.x - 2.0) / unit_width), 3, 10)
	var left := middle - units * unit_width * 0.5
	for unit: int in units:
		_prop("bar_counter", left + unit_width * (unit + 0.5), 4.2)
		if unit % 2 == 0:
			_prop("bar_stool", left + unit_width * (unit + 0.5), 3.4)
	_shelves(middle, units * unit_width + 0.6)
	if _lit:
		_batch.box_on(
			GreyboxLook.light(NEON),
			Vector3(units * 0.3, 0.05, 0.03),
			_surface,
			Vector3(middle, 2.5, _z(DEPTH))
		)
	for x: float in [span.x + 1.0, span.y - 1.0]:
		if _free(x, 1.0, 1.6):
			_prop("lounge_armchair", x, 1.6)


## Конференц-зал: ряды кресел спинкой к камере, трибуна и экран у дальней стены.
func _conference(span: Vector2) -> void:
	var office := _rules.kind == BuildingIdentity.Kind.OFFICE
	_floor_cover(span, GreyboxLook.surface(OFFICE_CARPET if office else CARPET_HALL))
	_far_wall(span, GreyboxLook.surface(Color(0.3, 0.3, 0.32) if office else Color(0.3, 0.2, 0.14)))
	var middle := _mid(span)
	var screen := minf(span.y - span.x - 1.0, 4.0)
	var face := GreyboxLook.light(SCREEN) if _lit else GreyboxLook.surface(RACK)
	_batch.box_on(face, Vector3(screen, 1.8, 0.04), _surface, Vector3(middle, 0.9, _z(DEPTH)))
	_on(GreyboxLook.surface(WOOD), Vector3(0.6, 1.1, 0.5), middle + screen * 0.5 + 0.6, 0.0, 6.2)
	for row: float in [1.6, 2.6, 3.6, 4.6]:
		for x: float in _along(span, 0.7, 0.0):
			if _free(x, 0.3, row):
				_prop("dining_chair" if not office else "desk_chair", x, row, 180.0)


## Переговорные офиса: стеклянные коробки с длинным столом, креслами и
## телевизором на стене.
func _meeting(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.surface(OFFICE_CARPET))
	_windows(span)
	var glass := HallLook.glass()
	var frame := GreyboxLook.metal(STEEL)
	for x: float in _along(span, 4.2, 0.0):
		if not _free(x, 2.0, 2.0):
			continue
		for wall: float in [-2.0, 2.0]:
			_batch.box_on(glass, Vector3(0.03, 2.4, 4.6), _surface, Vector3(x + wall, 0.0, _z(4.0)))
			_on(frame, Vector3(0.06, 2.4, 0.06), x + wall, 0.0, 1.7)
		_batch.box_on(glass, Vector3(4.0, 2.4, 0.03), _surface, Vector3(x, 0.0, _z(1.7)))
		_prop("long_table", x, 4.0)
		for side: float in [-0.9, -0.3, 0.3, 0.9]:
			_prop("desk_chair", x + side, 3.3)
			_prop("desk_chair", x + side, 4.7, 180.0)
		_prop("tv_modern", x, 6.2)


## Спортзал: резиновый пол, беговые дорожки, скамьи для жима со штангой,
## стойка гантелей и зеркало во всю дальнюю стену.
func _gym(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.surface(RUBBER))
	_far_wall(span, GreyboxLook.metal(Color(0.24, 0.27, 0.29)))
	var steel := GreyboxLook.metal(DARK_STEEL)
	var belt := GreyboxLook.surface(Color(0.06, 0.06, 0.06))
	for x: float in _along(span, 1.4, 0.0):
		if not _free(x, 0.5, 3.0):
			continue
		_on(belt, Vector3(0.75, 0.2, 1.7), x, 0.0, 3.4)
		_on(steel, Vector3(0.7, 0.08, 0.08), x, 1.2, 2.6)
		for side: float in [-0.35, 0.35]:
			_on(steel, Vector3(0.05, 1.2, 0.05), x + side, 0.0, 2.6)
		var console := GreyboxLook.light(HallLook.LED_AMBER) if _lit else steel
		_on(console, Vector3(0.4, 0.15, 0.05), x, 1.25, 2.58)
	for x: float in _along(span, 2.8, 1.4):
		_prop("bench_cushion", x, 5.4)
		_batch.pipe_x(steel, 0.02, 1.6, Vector3(x, _surface - 1.1, _z(5.4)))
		for side: float in [-0.7, 0.7]:
			_batch.pipe_x(
				GreyboxLook.surface(RACK), 0.18, 0.06, Vector3(x + side, _surface - 1.1, _z(5.4))
			)
	_on(steel, Vector3(span.y - span.x - 1.0, 0.05, 0.4), _mid(span), 0.8, DEPTH - 0.3)


## Общая комната жилого дома: раскладные столы со стульями, пинг-понг,
## телевизор и диван.
func _community(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.surface(LINOLEUM))
	_far_wall(span, GreyboxLook.surface(Color(0.55, 0.5, 0.38)))
	_windows(span)
	var middle := _mid(span)
	var green := GreyboxLook.surface(TABLE_GREEN)
	_on(green, Vector3(2.7, 0.05, 1.5), middle, 0.74, 4.2)
	_on(GreyboxLook.surface(CHALK), Vector3(0.03, 0.15, 1.5), middle, 0.79, 4.2)
	for side: float in [-1.2, 1.2]:
		_on(GreyboxLook.metal(DARK_STEEL), Vector3(0.05, 0.74, 1.2), middle + side, 0.0, 4.2)
	for x: float in _along(span, 2.4, 1.2):
		if absf(x - middle) < 2.2 or not _free(x, 1.0, 2.0):
			continue
		_prop("long_table", x, 2.0)
		_prop("dining_chair", x - 0.5, 2.6, 180.0)
		_prop("dining_chair", x + 0.5, 2.6, 180.0)
	_prop("tv_modern", span.x + 1.0, 6.4)
	_prop("couch_medium", span.x + 1.0, 5.2, 180.0)


## Кладовые-клетки: ряды отсеков из сетки на стойках, в каждом коробки,
## велосипед или старое кресло.
func _lockers(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.surface(CONCRETE))
	var net := HallLook.chain_link()
	var post := GreyboxLook.metal(MESH_POST)
	var stuff: Array[String] = [
		"box_closed", "bicycle", "cardboard_boxes", "armchair", "box_closed"
	]
	var cell := 1.8
	var turn := 0
	for row: float in [2.4, 5.0]:
		for x: float in _along(span, cell, 0.0):
			if not _free(x, cell * 0.5, row):
				continue
			_batch.box_on(net, Vector3(cell, 2.2, 0.02), _surface, Vector3(x, 0.0, _z(row - 1.0)))
			_batch.box_on(
				net, Vector3(0.02, 2.2, 2.0), _surface, Vector3(x - cell * 0.5, 0.0, _z(row))
			)
			_on(post, Vector3(0.05, 2.2, 0.05), x - cell * 0.5, 0.0, row - 1.0)
			var thing := stuff[turn % stuff.size()]
			turn += 1
			_prop(thing, x, row)
			if thing == "box_closed":
				_prop("box_closed", x + 0.3, row + 0.2)


## Прачечная: ряд стиральных и сушильных машин у дальней стены, стол для
## белья и тележки.
func _laundry(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.polished(DINER_TILE.darkened(0.2)))
	_far_wall(span, GreyboxLook.surface(Color(0.62, 0.64, 0.6)))
	var machines: Array[String] = ["washer", "washer", "dryer", "washer_dryer"]
	var turn := 0
	for x: float in _along(span, _width_of("washer", 0.08), 0.0):
		_prop(machines[turn % machines.size()], x, DEPTH - 0.4)
		turn += 1
	var cart := GreyboxLook.surface(Color(0.5, 0.45, 0.35))
	for x: float in _along(span, 3.0, 0.8):
		if not _free(x, 0.8, 3.4):
			continue
		_prop("long_table", x, 3.4)
		_on(GreyboxLook.surface(LINEN), Vector3(0.6, 0.2, 0.4), x, 0.76, 3.4)
		_on(cart, Vector3(0.8, 0.6, 0.5), x + 1.3, 0.15, 2.3)
		_on(GreyboxLook.surface(LINEN), Vector3(0.7, 0.15, 0.45), x + 1.3, 0.75, 2.3)


# --- Технические этажи ------------------------------------------------------


## Котельная: котлы-бочки на опорах с окошком топки, стояки и трубы под
## потолком, манометры; над котлом пар.
func _boiler(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.surface(CONCRETE.darkened(0.2)))
	_far_wall(span, GreyboxLook.surface(Color(0.3, 0.3, 0.28)))
	var shell := GreyboxLook.metal(
		PAINTED_RED if _rules.kind == BuildingIdentity.Kind.HOTEL else PAINTED_GREEN
	)
	var pipe := GreyboxLook.metal(PIPE)
	var lagging := GreyboxLook.surface(INSULATION)
	for x: float in _along(span, 4.2, 0.0):
		if not _free(x, 1.9, 4.5):
			continue
		_batch.pipe_x(shell, 0.85, 3.2, Vector3(x, _surface - 1.25, _z(4.5)))
		for side: float in [-1.2, 1.2]:
			_on(GreyboxLook.surface(DARK_STEEL), Vector3(0.2, 0.45, 1.4), x + side, 0.0, 4.5)
		var door := GreyboxLook.light(FIRE) if _lit else GreyboxLook.surface(RACK)
		_batch.box_on(door, Vector3(0.35, 0.25, 0.02), _surface, Vector3(x - 1.62, 1.1, _z(4.5)))
		_batch.cylinder_on(pipe, 0.12, 2.0, _surface, Vector3(x + 0.8, 2.0, _z(4.5)))
		_batch.sphere(GreyboxLook.surface(CHALK), 0.16, Vector3(x - 0.6, _surface - 2.15, _z(3.6)))
		_steam.append(
			WorldSpace.to_scene(Vector2(x + 0.8, _surface - 3.0)) + Vector3(0, 0, _z(4.5))
		)
	_overhead(span, pipe, lagging)


## Вентиляция и насосы: короба приточных установок с решётками, вентиляторы,
## насосы на рамах и воздуховоды.
func _mechanical(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.surface(CONCRETE))
	_far_wall(span, GreyboxLook.surface(Color(0.34, 0.35, 0.34)))
	var unit := GreyboxLook.metal(Color(0.58, 0.6, 0.6))
	var grille := GreyboxLook.surface(DARK_STEEL)
	var pump := GreyboxLook.metal(Color(0.15, 0.3, 0.55))
	var pipe := GreyboxLook.metal(PIPE)
	for x: float in _along(span, 3.6, 0.0):
		if _free(x, 1.5, 5.0):
			_on(unit, Vector3(2.8, 1.8, 1.6), x, 0.0, 5.0)
			for grid: int in 4:
				_on(grille, Vector3(0.5, 1.2, 0.02), x - 1.0 + grid * 0.66, 0.3, 4.19)
		if _free(x + 1.8, 0.4, 2.2):
			_on(GreyboxLook.surface(DARK_STEEL), Vector3(0.8, 0.12, 0.5), x + 1.8, 0.0, 2.2)
			_batch.pipe_x(pump, 0.18, 0.5, Vector3(x + 1.7, _surface - 0.35, _z(2.2)))
			_batch.cylinder_on(pump, 0.12, 0.45, _surface, Vector3(x + 2.05, 0.12, _z(2.2)))
	_overhead(span, pipe, GreyboxLook.metal(Color(0.7, 0.72, 0.72)))


## Серверная офиса: фальшпол, два ряда стоек с мигающими индикаторами,
## холодный свет и короб кабельного лотка.
func _server(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.polished(RAISED_FLOOR))
	_far_wall(span, GreyboxLook.surface(Color(0.25, 0.27, 0.3)))
	var body := GreyboxLook.metal(RACK)
	var leds: Material = HallLook.led() if _lit else GreyboxLook.surface(DARK_STEEL)
	for row: float in [2.6, 5.2]:
		for x: float in _along(span, 0.66, 0.0):
			if not _free(x, 0.33, row):
				continue
			_on(body, Vector3(0.6, 2.0, 1.0), x, 0.0, row)
			for slot: int in 8:
				_on(leds, Vector3(0.36, 0.03, 0.01), x, 0.3 + slot * 0.2, row - 0.505)
	var tray := GreyboxLook.metal(Color(0.45, 0.47, 0.5))
	_on(tray, Vector3(span.y - span.x, 0.08, 0.4), _mid(span), 2.3, 2.6)
	_on(tray, Vector3(span.y - span.x, 0.08, 0.4), _mid(span), 2.3, 5.2)


## Архив: ряды стеллажей с коробами дел и шкафы-картотеки.
func _archive(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.surface(LINOLEUM.darkened(0.2)))
	_far_wall(span, GreyboxLook.surface(Color(0.5, 0.5, 0.47)))
	for row: float in [2.2, 4.0, 5.8]:
		for x: float in _along(span, 1.6, 0.0 if row != 4.0 else 0.8):
			if _free(x, 0.8, row):
				_shelf_unit(x, row, CARDBOARD)
	for x: float in _along(span, 3.0, 1.5):
		if _free(x, 0.3, 1.0):
			_prop("file_cabinet", x, 1.0)


## Кухня отеля: линия плит под вытяжками, мойки, холодильники и разделочные
## столы из нержавейки.
func _kitchen(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.polished(Color(0.5, 0.42, 0.36)))
	_far_wall(span, GreyboxLook.polished(Color(0.82, 0.82, 0.78)))
	var line: Array[String] = ["kitchen_stove", "kitchen_stove", "kitchen_sink", "kitchen_cabinet"]
	var turn := 0
	for x: float in _along(span, _width_of("kitchen_cabinet", 0.0), 0.0):
		var item := line[turn % line.size()]
		_prop(item, x, DEPTH - 0.4)
		if item == "kitchen_stove":
			_prop("kitchen_hood", x, DEPTH - 0.3, 0.0, 1.5)
		turn += 1
	var steel := GreyboxLook.metal(STEEL)
	for x: float in _along(span, 3.2, 0.0):
		if _free(x, 1.0, 3.6):
			_on(steel, Vector3(2.0, 0.05, 0.9), x, 0.88, 3.6)
			for side: float in [-0.9, 0.9]:
				_on(steel, Vector3(0.05, 0.88, 0.8), x + side, 0.0, 3.6)
			_on(steel, Vector3(1.9, 0.03, 0.8), x, 0.2, 3.6)
		if _free(x + 1.6, 0.4, 2.0):
			_prop("kitchen_fridge", x + 1.6, 2.0)


## Склад: стеллажи с коробками; у отеля бельевая — стопки белого белья.
func _storage(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.surface(CONCRETE))
	_far_wall(span, GreyboxLook.surface(Color(0.4, 0.4, 0.38)))
	var goods := LINEN if _rules.kind == BuildingIdentity.Kind.HOTEL else CARDBOARD
	for row: float in [2.4, 4.8]:
		for x: float in _along(span, 1.6, 0.0):
			if _free(x, 0.8, row):
				_shelf_unit(x, row, goods)
	for x: float in _along(span, 2.6, 1.3):
		if _free(x, 0.4, 6.4):
			_prop("cardboard_boxes", x, 6.4)


## Мастерская жилого дома: верстак, щит с инструментом на стене, шкафы и
## стремянка.
func _workshop(span: Vector2) -> void:
	_floor_cover(span, GreyboxLook.surface(CONCRETE.darkened(0.1)))
	_far_wall(span, GreyboxLook.surface(Color(0.42, 0.38, 0.3)))
	var board := GreyboxLook.surface(Color(0.55, 0.42, 0.25))
	var tool := GreyboxLook.metal(DARK_STEEL)
	for x: float in _along(span, 3.0, 0.0):
		if not _free(x, 1.2, 5.6):
			continue
		_on(GreyboxLook.surface(WOOD.lightened(0.15)), Vector3(2.2, 0.08, 0.8), x, 0.86, 5.8)
		for side: float in [-1.0, 1.0]:
			_on(GreyboxLook.surface(WOOD), Vector3(0.08, 0.86, 0.7), x + side, 0.0, 5.8)
		_batch.box_on(board, Vector3(2.0, 1.0, 0.03), _surface, Vector3(x, 1.25, _z(DEPTH - 0.02)))
		for peg: int in 6:
			_batch.box_on(
				tool,
				Vector3(0.05, 0.35, 0.03),
				_surface,
				Vector3(x - 0.8 + peg * 0.32, 1.5, _z(DEPTH - 0.05))
			)
		_prop("cabinet", x + 1.5, 3.0)
	var ladder := GreyboxLook.metal(STEEL)
	for side: float in [-0.25, 0.25]:
		_on(ladder, Vector3(0.04, 2.0, 0.04), span.x + 0.6 + side, 0.0, 2.5)
	for rung: int in 6:
		_on(ladder, Vector3(0.5, 0.03, 0.04), span.x + 0.6, 0.3 + rung * 0.3, 2.5)


# --- Детали -----------------------------------------------------------------


## Пол зала поверх плиты: на всю глубину зала по пролёту.
func _floor_cover(span: Vector2, material: Material) -> void:
	_batch.box(
		material,
		Vector3(span.y - span.x + EDGE * 2.0, 0.02, WorldSpace.ROOM_DEPTH),
		Vector3(_mid(span), _surface - 0.01, WorldSpace.BACK_WALL_Z - WorldSpace.ROOM_DEPTH * 0.5)
	)


## Дальняя стена зала своим цветом: поверх общей стены [BuildingShell].
func _far_wall(span: Vector2, material: Material) -> void:
	var height := _surface - _rules.story_top(_index)
	_batch.box(
		material,
		Vector3(span.y - span.x + EDGE * 2.0, height, 0.04),
		Vector3(_mid(span), _surface - height * 0.5, _z(WorldSpace.ROOM_DEPTH - 0.04))
	)


## Окна на город у дальней стены — общественным залам.
func _windows(span: Vector2) -> void:
	OpenSpace.ribbon_windows(
		_batch,
		TimeOfDay.window_look(_rules.time_of_day, OpenSpace.NIGHT_GLASS),
		GreyboxLook.metal(OpenSpace.FRAME),
		Vector2(span.x - EDGE, span.y + EDGE),
		_surface,
		WorldSpace.BACK_WALL_Z - WorldSpace.ROOM_DEPTH + 0.05
	)


## Трубы под потолком технического этажа: две магистрали вдоль и отводы вниз.
func _overhead(span: Vector2, pipe: Material, lagging: Material) -> void:
	var length := span.y - span.x + EDGE * 2.0
	var middle := _mid(span)
	_batch.pipe_x(lagging, 0.16, length, Vector3(middle, _surface - 2.75, _z(6.4)))
	_batch.pipe_x(pipe, 0.09, length, Vector3(middle, _surface - 2.55, _z(5.9)))
	for x: float in _along(span, 2.2, 1.1):
		_batch.cylinder_on(pipe, 0.06, 2.6, _surface, Vector3(x, 0.0, _z(6.6)))


## Стол во всю длину: стойка поста охраны или швейцара, с мониторами.
func _desk_row(x: float, length: float, d: float, colour: Color, screens: bool) -> void:
	_on(GreyboxLook.metal(colour), Vector3(length, 1.05, 0.7), x, 0.0, d)
	if not screens:
		_prop("desk_chair", x, d + 0.7, 180.0)
		return
	for side: float in [-0.5, 0.0, 0.5]:
		_on(GreyboxLook.surface(RACK), Vector3(0.45, 0.32, 0.05), x + side, 1.1, d + 0.15)
		var face := GreyboxLook.light(SCREEN) if _lit else GreyboxLook.surface(RACK)
		_on(face, Vector3(0.39, 0.26, 0.01), x + side, 1.13, d + 0.12)


## Турникет: тумба со стеклянной створкой.
func _turnstile(x: float, d: float) -> void:
	_on(GreyboxLook.metal(STEEL), Vector3(0.18, 1.0, 1.0), x, 0.0, d)
	_batch.box_on(
		HallLook.glass(), Vector3(0.7, 0.6, 0.02), _surface, Vector3(x + 0.45, 0.4, _z(d))
	)
	var lamp := GreyboxLook.light(HallLook.LED_GREEN) if _lit else GreyboxLook.surface(RACK)
	_on(lamp, Vector3(0.1, 0.02, 0.1), x, 1.0, d - 0.3)


## Доска с ключами за стойкой регистрации: ячейки с латунными бирками.
func _key_rack(x: float, width: float) -> void:
	var board := GreyboxLook.surface(WOOD.darkened(0.3))
	_batch.box_on(board, Vector3(width, 1.2, 0.05), _surface, Vector3(x, 1.0, _z(DEPTH - 0.05)))
	var tag := GreyboxLook.metal(BRASS)
	var columns := int(width / 0.25)
	for column: int in columns:
		for row: int in 4:
			_batch.box_on(
				tag,
				Vector3(0.05, 0.08, 0.02),
				_surface,
				Vector3(
					x - width * 0.5 + 0.125 + column * 0.25, 1.15 + row * 0.27, _z(DEPTH - 0.09)
				)
			)


## Рояль: корпус, поднятая крышка и ножки.
func _piano(x: float, d: float) -> void:
	var black := GreyboxLook.polished(Color(0.02, 0.02, 0.025))
	_on(black, Vector3(1.6, 0.3, 1.2), x, 1.15, d)
	_batch.box(black, Vector3(1.5, 0.02, 1.1), Vector3(x, _surface - 1.75, _z(d - 0.1)))
	for side: float in [-0.65, 0.65]:
		_on(black, Vector3(0.08, 0.65, 0.08), x + side, 0.5, d)
	_on(GreyboxLook.surface(CHALK), Vector3(1.2, 0.03, 0.15), x, 1.2, d - 0.55)


## Полки бара у дальней стены: три яруса бутылок, светятся при свете.
func _shelves(x: float, width: float) -> void:
	var wood := GreyboxLook.surface(WOOD.darkened(0.2))
	_batch.box_on(wood, Vector3(width, 1.6, 0.3), _surface, Vector3(x, 0.9, _z(DEPTH - 0.15)))
	var count := int(width / 0.14)
	for tier: int in 3:
		for bottle: int in count:
			var colour := BOTTLES[(bottle * 7 + tier * 3) % BOTTLES.size()]
			var look := (
				GreyboxLook.light(colour) if _lit else GreyboxLook.surface(colour.darkened(0.6))
			)
			_batch.box_on(
				look,
				Vector3(0.06, 0.26, 0.06),
				_surface,
				Vector3(
					x - width * 0.5 + 0.07 + bottle * 0.14, 1.05 + tier * 0.48, _z(DEPTH - 0.33)
				)
			)


## Стеллаж: стойки, четыре полки и груз на них.
func _shelf_unit(x: float, d: float, goods: Color) -> void:
	var steel := GreyboxLook.metal(Color(0.42, 0.44, 0.46))
	var load := GreyboxLook.surface(goods)
	for side: float in [-0.7, 0.7]:
		_on(steel, Vector3(0.05, 2.2, 0.6), x + side, 0.0, d)
	for tier: int in 4:
		_on(steel, Vector3(1.45, 0.03, 0.6), x, 0.15 + tier * 0.55, d)
		for box: int in 3:
			if (box + tier) % 4 == 3:
				continue
			_on(load, Vector3(0.38, 0.3, 0.45), x - 0.45 + box * 0.45, 0.18 + tier * 0.55, d)


## Светящаяся точка: свеча, зеркальный шар, табло. Погашена — на тёмном этаже.
func _glow(colour: Color, size: float, at: Vector3) -> void:
	if not _lit:
		return
	_batch.sphere(GreyboxLook.light(colour), size, Vector3(at.x, _surface - at.y, _z(at.z)))


## Коробка на полу: [param h] — высота низа, [param d] — глубина середины.
func _on(material: Material, size: Vector3, x: float, h: float, d: float) -> void:
	_batch.box_on(material, size, _surface, Vector3(x, h, _z(d)))


## Предмет пака серединой на (x, d), низом на [param h] над полом, повёрнутый
## на [param turn] градусов вокруг вертикали.
func _prop(prop_name: String, x: float, d: float, turn: float = 0.0, h: float = 0.0) -> void:
	var parts := HallLook.template(prop_name, _rules.kind)
	if parts.is_empty():
		return
	var place := Transform3D(
		Basis(Vector3.UP, deg_to_rad(turn)), MeshBatch.scene_of(Vector3(x, _surface - h, _z(d)))
	)
	for part: Array in parts:
		_batch.mesh(part[0] as Mesh, place * (part[1] as Transform3D))


func _free(x: float, half: float, d: float) -> bool:
	var office := _rules.kind == BuildingIdentity.Kind.OFFICE
	var reach := LEAF_CLEAR if office else DoorRoom.DEPTH + 0.3
	if d - 0.5 > reach:
		return true
	var clear := (
		Door.LEAF_SIZE.x if office else DoorRoom.WIDTH * 0.5 + DoorRoom.SHIFT + DoorRoom.WALL
	)
	for door: float in _doors:
		if absf(x - door) < clear + half:
			return false
	return true


## Места вдоль пролёта с шагом [param step] от края со сдвигом [param offset].
func _along(span: Vector2, step: float, offset: float) -> Array[float]:
	var places: Array[float] = []
	var length := span.y - span.x
	var count := int((length - offset) / step)
	if count <= 0:
		return places
	var start := span.x + offset + (length - offset - (count - 1) * step) * 0.5
	for place: int in count:
		places.append(start + place * step)
	return places


## Ширина предмета пака в его росте по каталогу и зазор [param gap]: шаг
## ряда машин, шкафов, стоек бара.
func _width_of(prop_name: String, gap: float) -> float:
	return PropCatalog.footprint(prop_name).x + gap


func _mid(span: Vector2) -> float:
	return (span.x + span.y) * 0.5


## Z сцены по глубине зала.
func _z(d: float) -> float:
	return WorldSpace.BACK_WALL_Z - d
