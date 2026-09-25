class_name Garage
extends Node3D

## Подземный паркинг — нижний этаж здания (ADR-0038, решение 3).
##
## До M24b нижний этаж был коридором с бетонной стеной и полосами на полу. Здесь
## он — паркинг: задней стены нет, за плоскостью игры открывается зал глубиной
## в комнату, в нём — места с чужими машинами носом к дальней стене, колонны по
## передней линии мест, балки, короб вентиляции и люминесцентные светильники,
## разметка, пятна масла, номера на колоннах и знаки. Коридор — проезд: по нему
## и уезжает машина Otto — в ворота в левом торце, за которыми пандус наверх.
##
## Только вид, тел здесь нет: всё стоит за плоскостью игры или над головой.
## Настоящего света паркинг не добавляет — светят лампы этажа, как везде; трубки
## светильников — эмиссия и гаснут вместе с зоной своей лампы ([method darken]).
##
## Раскладка — статическими функциями: где колонны, места и чужие машины, тесты
## проверяют без сцены, на любом сиде.
##
## Ворота в левом торце — [GarageGate], узел [member gate]; поднимает их
## сдача здания через [method open_gate].

## Стенка у ворот: от левой стены до первой колонны зал закрыт — угол, на
## котором висят вывеска и стрелка, м.
const GATE_BAY: float = 0.8
## Колонна: сечение и середина по глубине — сразу за линией бывшей задней
## стены, передняя грань за спиной Otto с запасом.
const COLUMN: float = 0.5
const COLUMN_Z: float = WorldSpace.BACK_WALL_Z - 0.35
## Шаг колонн — два места по полтора шага сетки; колонна не встаёт ближе
## этого к ядру шахты или стене, м.
const COLUMN_PITCH: float = Proportions.SLOT * 3.0
const COLUMN_CLEARANCE: float = 0.15
## Место: не уже этого, м. Между колоннами выходит два места по 2.45.
const BAY_MIN: float = 2.4
## Места по глубине: от передней линии до колёсного упора, м.
const BAY_FRONT_Z: float = WorldSpace.BACK_WALL_Z - 0.25
const BAY_BACK_Z: float = -5.6
## Дальняя стена зала: середина и толщина, м.
const FAR_Z: float = -7.2
const FAR_THICKNESS: float = 0.2

## Машина на месте: ширина, до которой раздаётся модель пака (у пака она сжата
## до зазора между стеной и Otto, [CarModel]), и середина по глубине.
const CAR_WIDTH: float = 1.62
const CAR_Z: float = -3.35
## Доля занятых мест.
const PARKED_SHARE: float = 0.65

## Балка: ширина, насколько опущена под перекрытие, м.
const BEAM := Vector2(0.4, 0.4)
## Балка через проезд не идёт ближе этого к лампе: шнур лампы прошёл бы сквозь.
const BEAM_LAMP_CLEARANCE: float = 0.7
## Под потолком всё видно только ниже полосы, которую закрывает кромка
## перекрытия ([method FloorSigns.hidden_band]), и полоса эта тем шире, чем
## глубже вещь. Поэтому ряды идут не по высоте, а по отступу от кромки на
## экране: светильники — у передней линии, сразу под кромкой; трубы — за ними
## чуть ниже; короб вентиляции — в глубине ещё ниже. Поставь их всех «сразу
## под кромкой своей глубины» — и на экране они легли бы в одну линию, а
## передний закрыл бы остальные (первый кадр вехи: трубка светильника целиком
## за красной трубой).
##
## Светильник: корпус, рассеиватель, глубина ряда, м.
const FIXTURE := Vector3(1.3, 0.07, 0.16)
const DIFFUSER := Vector3(1.22, 0.05, 0.1)
const FIXTURE_Z: float = WorldSpace.BACK_WALL_Z + 0.06
## Светильник не встаёт перед лампой этажа ближе этого, м: абажур закрыл бы его.
const FIXTURE_LAMP_CLEARANCE: float = 1.0
## Пятно света от трубки на полу места: ширина и глубина, м, и яркость.
const POOL := Vector2(2.3, 2.6)
const POOL_ENERGY: float = 0.22
## Свет трубки: конус вниз и в зал, на машину места. Только над занятым
## местом — светить в пустое место незачем, а источников в кадре и так много
## (бюджет — ADR-0010, пункт 1). Без тени — теней в здании кладут только лампы
## (ADR-0023, решение 3), — слабый и короткий: до перекрытия сверху он не
## достаёт. Гаснет с зоной своей лампы и вне кадра, как лампы. Без него зал за
## проездом оставался синей чернотой, и машины в нём не читались.
const TUBE_LIGHT_ENERGY: float = 1.6
const TUBE_LIGHT_RANGE: float = 4.6
const TUBE_LIGHT_ANGLE: float = 62.0
## Наклон конуса от вертикали в глубину зала, градусы.
const TUBE_LIGHT_TILT: float = 38.0
## Над машиной Otto у ворот светильник светит не в зал, а на проезд: машина
## стоит перед ним, и в темноте у торца её было не разглядеть.
const EXIT_CAR_TILT: float = -24.0
## Трубы вдоль зала: радиус, середина по глубине и отступ от кромки на
## экране, м. Идут сквозь колонны — там их закрывает бетон.
const PIPE_RADIUS: float = 0.06
const PIPE_Z: float = COLUMN_Z + 0.1
const PIPE_DROP: float = 0.12
## Короб вентиляции: сечение, середина по глубине, отступ от кромки, м.
const DUCT := Vector2(0.5, 0.28)
const DUCT_Z: float = -2.4
const DUCT_DROP: float = 0.14

## Ядро шахты — бетонная стена вокруг портала и кнопок, м сверх них.
const CORE_MARGIN: float = 0.15
## Простенок под табличкой этажа: насколько шире таблички влево, м.
const PIER_MARGIN: float = 0.35

## Цвета: бетон, краска разметки, упоры, пятна, светильники.
const CONCRETE := Color(0.72, 0.72, 0.7)
const PAINT_WHITE := Color(0.72, 0.72, 0.68)
const PAINT_YELLOW := Color(0.82, 0.62, 0.1)
const PAINT_BLACK := Color(0.05, 0.05, 0.05)
const PAINT_BAND := Color(0.62, 0.46, 0.12)
const SIGN_BLUE := Color(0.08, 0.24, 0.62)
const OIL := Color(0.025, 0.025, 0.03)
const DUCT_METAL := Color(0.6, 0.62, 0.64)
const PIPE_RED := Color(0.55, 0.1, 0.08)
const PIPE_GREY := Color(0.34, 0.35, 0.37)
const TUBE := Color(0.82, 0.93, 1.0)
const TUBE_OFF := Color(0.42, 0.44, 0.46)
const FIXTURE_BODY := Color(0.7, 0.71, 0.72)
const HEADLIGHT_OFF := Color(0.6, 0.6, 0.56)
const TAILLIGHT_OFF := Color(0.32, 0.04, 0.03)

## Надпись уровня паркинга на простенке у таблички этажа.
const LEVEL_MARK := "B1"

## Соль жребия машин: своя, чтобы паркинг не ходил в ногу с раскладкой.
const SALT: int = 0x6A2A_6E00


## Светильник над местом: трубка, пятно на полу и, над занятым местом, свет.
class Fixture:
	extends RefCounted

	var tube: MeshInstance3D = null
	var pool: MeshInstance3D = null
	var light: SpotLight3D = null
	var lit: bool = true


## Чужая машина на месте: где, какая и каким концом к проезду.
class Parked:
	extends RefCounted

	var x: float = 0.0
	var choice: CarModel.Choice = CarModel.Choice.new()
	## Носом к дальней стене — к проезду смотрит багажник.
	var nose_in: bool = true


## Материал пятна света — один на все пятна.
static var _pool: StandardMaterial3D = null

## Ворота в левом торце: штора, короб, вывеска EXIT и пандус за ними.
var gate: GarageGate = null

var _rules: BuildingRules = null
var _plan: BuildingPlan = null
var _bottom: int = 0
var _surface: float = 0.0
var _top: float = 0.0
var _inner := Vector2.ZERO
var _concrete: StandardMaterial3D = null
## Светильники по лампам этажа: x лампы → [Fixture] её зоны.
var _tubes: Dictionary = {}
## Все светильники — для [method tube_lit_at] и отбора света по кадру.
var _fixtures: Array[Fixture] = []
## В кадре ли этаж: свет трубок горит только тогда ([method show_lights]).
var _in_view: bool = true
var _lamp_xs := PackedFloat64Array()


## Середина ворот по горизонтали: в толще левой стены нижнего этажа.
static func gate_x(rules: BuildingRules) -> float:
	return rules.floor_span(rules.floors - 1).x + BuildingShell.WALL_WIDTH * 0.5


## Внутренний пролёт нижнего этажа — от стены до стены.
static func inner_span(rules: BuildingRules) -> Vector2:
	var bounds := rules.floor_span(rules.floors - 1)
	return Vector2(bounds.x + BuildingShell.WALL_WIDTH, bounds.y - BuildingShell.WALL_WIDTH)


## Ядра шахт, спускающихся в подвал: портал с наличником и панель кнопок.
static func cores(rules: BuildingRules, plan: BuildingPlan) -> Array[Vector2]:
	var bottom := rules.floors - 1
	var found: Array[Vector2] = []
	var reach := (
		rules.shaft_width * 0.5
		+ BuildingShafts.PORTAL_JAMB
		+ BuildingShafts.CALL_GAP
		+ BuildingShafts.CALL_PANEL.x
		+ CORE_MARGIN
	)
	for shaft in plan.shafts:
		if shaft.top <= bottom and bottom <= shaft.bottom:
			found.append(Vector2(shaft.x - reach, shaft.x + reach))
	return found


## Простенок под табличкой этажа: она висит у задней стены, и в открытом зале
## ей нужна стена позади.
static func pier(rules: BuildingRules) -> Vector2:
	var sign_x := FloorSigns.centre_on(rules, rules.floors - 1).x
	var left := sign_x - Proportions.FLOOR_SIGN.x * 0.5 - PIER_MARGIN
	return Vector2(left, inner_span(rules).y)


## Всё, что закрывает зал с передней линии: стенка у ворот, ядра шахт,
## простенок таблички, внутренние стены и пролёты эскалаторов. Колонн и мест
## здесь нет.
static func busy_spans(rules: BuildingRules, plan: BuildingPlan) -> Array[Vector2]:
	var bottom := rules.floors - 1
	var inner := inner_span(rules)
	var busy: Array[Vector2] = [Vector2(inner.x, inner.x + GATE_BAY), pier(rules)]
	busy.append_array(cores(rules, plan))
	for wall in plan.walls:
		if wall.floor_index == bottom:
			busy.append(wall.band(rules))
	for escalator in plan.escalators:
		if escalator.floor_index == bottom - 1 or escalator.floor_index == bottom:
			var gap := escalator.gap(rules)
			busy.append(Vector2(gap.x - 1.0, gap.y + 1.0))
	return busy


## Колонны передней линии: по сетке с шагом [constant COLUMN_PITCH], кроме
## тех, что встали бы в ядро шахты, в стену или у ворот.
static func column_xs(rules: BuildingRules, plan: BuildingPlan) -> PackedFloat64Array:
	var inner := inner_span(rules)
	var busy := busy_spans(rules, plan)
	var reach := COLUMN * 0.5 + COLUMN_CLEARANCE
	var found := PackedFloat64Array()
	var x := rules.slot_x(0) - Proportions.SLOT * 0.5
	while x + reach <= inner.y:
		var free := x - reach >= inner.x
		for span in busy:
			if x + reach > span.x and x - reach < span.y:
				free = false
		if free:
			found.append(x)
		x += COLUMN_PITCH
	return found


## Места паркинга: пары «левый край, правый край» между колоннами и стенами,
## не уже [constant BAY_MIN].
static func bays(rules: BuildingRules, plan: BuildingPlan) -> Array[Vector2]:
	var blocks := busy_spans(rules, plan)
	for x in column_xs(rules, plan):
		blocks.append(Vector2(x - COLUMN * 0.5, x + COLUMN * 0.5))
	var found: Array[Vector2] = []
	for span in BuildingPlan.spans_between(blocks, inner_span(rules)):
		var count := floori((span.y - span.x) / BAY_MIN)
		if count <= 0:
			continue
		var width := (span.y - span.x) / float(count)
		for index in count:
			found.append(Vector2(span.x + width * index, span.x + width * (index + 1)))
	return found


## Куда чужой машине нельзя: к выходу и к машине Otto — к её месту
## ([method ExitCar.spot]) и полосе у ворот ([method ExitCar.parked_span]), с
## зазором. Машина Otto стоит в проезде, чужие — в зале, но в кадре они одна
## над другой, и место Otto должно читаться свободным.
static func keep_out(rules: BuildingRules, plan: BuildingPlan) -> Array[Vector2]:
	var exit_half := Proportions.EXIT_WIDTH * 0.5
	var spot := ExitCar.spot(plan.exit_x, rules, plan)
	var car_half := CarModel.LENGTH * 0.5 + ExitCar.GAP
	var at_gate := ExitCar.parked_span(rules)
	return (
		[
			Vector2(plan.exit_x - exit_half, plan.exit_x + exit_half),
			Vector2(spot - car_half, spot + car_half),
			Vector2(at_gate.x - ExitCar.GAP, at_gate.y + ExitCar.GAP),
		]
		as Array[Vector2]
	)


## Чужие машины здания: жребий по сиду, на местах [method bays], мимо
## [method keep_out].
static func parked(rules: BuildingRules, plan: BuildingPlan, building_seed: int) -> Array[Parked]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, SALT])
	var banned := keep_out(rules, plan)
	var found: Array[Parked] = []
	for bay in bays(rules, plan):
		# Жребий тянется на каждое место, занятое или нет: иначе правка
		# запретной зоны переставила бы машины по всему паркингу.
		var roll := rng.randf()
		var model := rng.randi_range(0, CarModel.MODELS.size() - 1)
		# Красная — машина Otto в первом здании: чужие её не повторяют.
		var paint := rng.randi_range(1, CarModel.PAINTS.size() - 1)
		var nose_in := rng.randf() < 0.75
		if roll > PARKED_SHARE or bay.y - bay.x < CAR_WIDTH + 0.4:
			continue
		var free := true
		for span in banned:
			if bay.y > span.x and bay.x < span.y:
				free = false
		if not free:
			continue
		var car := Parked.new()
		car.x = (bay.x + bay.y) * 0.5
		car.choice.model = model
		car.choice.paint = paint
		car.nose_in = nose_in
		found.append(car)
	return found


## Собирает паркинг на нижнем этаже.
func build(rules: BuildingRules, plan: BuildingPlan, building_seed: int) -> void:
	_rules = rules
	_plan = plan
	_bottom = rules.floors - 1
	_surface = rules.floor_surface(_bottom)
	_top = rules.story_top(_bottom)
	_inner = inner_span(rules)
	_concrete = BuildingFinish.shaft_concrete(CONCRETE)
	for lamp in plan.lamps:
		if lamp.floor_index == _bottom:
			_lamp_xs.append(lamp.x)

	_build_walls()
	_build_columns()
	_build_ceiling()
	_build_fixtures(building_seed)
	_mark_the_floor(building_seed)
	_park_cars(building_seed)
	gate = GarageGate.new()
	gate.name = "Gate"
	add_child(gate)
	gate.build(rules)
	_hang_signs()
	if rules.is_unlit(_bottom):
		for lamp_x in _lamp_xs:
			darken(lamp_x)


## Гасит трубки в зоне лампы, ближайшей к [param x] — туда, где она висела.
## Зовёт уровень, когда лампа нижнего этажа упала: зона темна, и светильник
## над ней гореть не должен.
func darken(x: float) -> void:
	var nearest := _nearest_lamp(x)
	if is_nan(nearest):
		return
	for fixture: Fixture in _tubes.get(nearest, []):
		fixture.lit = false
		fixture.tube.material_override = GreyboxLook.surface(TUBE_OFF)
		fixture.pool.visible = false
		if fixture.light != null:
			fixture.light.visible = false


## Горит ли трубка светильника над [param x]; false — светильника там нет.
func tube_lit_at(x: float) -> bool:
	for fixture in _fixtures:
		if absf(fixture.tube.position.x - x) <= FIXTURE.x * 0.5:
			return fixture.lit
	return false


## Свет трубок горит, только пока нижний этаж в кадре — тем же правилом, что
## лампы ([VisibleFloors]); зовёт уровень.
func show_lights(in_view: bool) -> void:
	if in_view == _in_view:
		return
	_in_view = in_view
	for fixture in _fixtures:
		if fixture.light != null:
			fixture.light.visible = in_view and fixture.lit


## Сколько светильников светят по-настоящему — для тестов бюджета.
func lights() -> Array[SpotLight3D]:
	var found: Array[SpotLight3D] = []
	for fixture in _fixtures:
		if fixture.light != null:
			found.append(fixture.light)
	return found


## Поднимает штору ворот за [param duration] секунд под мотор ворот — см.
## [method GarageGate.open]. Звук ворот играет здесь, сдача здания его не
## повторяет.
func open_gate(duration: float = GarageGate.OPEN_TIME) -> Tween:
	return gate.open(duration)


## Открыты ли ворота целиком.
func is_gate_open() -> bool:
	return gate.is_open()


func _nearest_lamp(x: float) -> float:
	var best := NAN
	for lamp_x in _lamp_xs:
		if is_nan(best) or absf(lamp_x - x) < absf(best - x):
			best = lamp_x
	return best


## Дальняя стена, ядра шахт, стенка у ворот и простенок таблички.
func _build_walls() -> void:
	var height := _surface - _top
	var far_front := FAR_Z + FAR_THICKNESS * 0.5
	_box(
		Vector3(_inner.y - _inner.x, height, FAR_THICKNESS),
		_concrete,
		_at((_inner.x + _inner.y) * 0.5, _top + height * 0.5, FAR_Z)
	)
	# Полоса краски по дальней стене и номера мест над ней — у пола: верх
	# стены в глубине закрывает кромка перекрытия.
	var band := GreyboxLook.surface(PAINT_BAND)
	for span in BuildingPlan.spans_between(cores(_rules, _plan), _inner):
		_box(
			Vector3(span.y - span.x, 0.5, 0.01),
			band,
			_at((span.x + span.y) * 0.5, _surface - 0.55, far_front + 0.005),
			false
		)
	var number := 0
	for bay in bays(_rules, _plan):
		number += 1
		var digits := label("%02d" % number, 800, 0.34, PAINT_WHITE)
		digits.position = _at((bay.x + bay.y) * 0.5, _surface - 1.1, far_front + 0.004)
		add_child(digits)

	# Ядро шахты — бетон от передней линии до дальней стены: портал, лист и
	# кнопки шахты висят на его передней грани, как висели на задней стене.
	var core_depth := WorldSpace.BACK_WALL_Z - far_front
	for core in cores(_rules, _plan):
		_box(
			Vector3(core.y - core.x, height, core_depth),
			_concrete,
			_at(
				(core.x + core.y) * 0.5,
				_top + height * 0.5,
				WorldSpace.BACK_WALL_Z - core_depth * 0.5
			)
		)
	var wall_depth := 0.5
	var walls: Array[Vector2] = [Vector2(_inner.x, _inner.x + GATE_BAY), pier(_rules)]
	for wall in walls:
		# Простенок таблички чуть выступает: табличка висит перед задней
		# стеной на [constant FloorSigns.STANDOFF], и без опоры она парила бы.
		var front := WorldSpace.BACK_WALL_Z
		if wall == walls[1]:
			front = WorldSpace.BACK_WALL_Z + FloorSigns.STANDOFF - 0.03
		_box(
			Vector3(wall.y - wall.x, height, wall_depth),
			_concrete,
			_at((wall.x + wall.y) * 0.5, _top + height * 0.5, front - wall_depth * 0.5)
		)
	var mark := label(LEVEL_MARK, 700, 0.62, PAINT_YELLOW)
	var pier_span := pier(_rules)
	mark.position = _at(
		(pier_span.x + pier_span.y) * 0.5,
		_surface - 1.25,
		WorldSpace.BACK_WALL_Z + FloorSigns.STANDOFF - 0.03 + 0.004
	)
	add_child(mark)


## Колонны передней линии: бетон, полосы краски понизу, номер и знак «P».
func _build_columns() -> void:
	var height := _surface - _top
	var yellow := GreyboxLook.surface(PAINT_YELLOW)
	var black := GreyboxLook.surface(PAINT_BLACK)
	var white := GreyboxLook.surface(PAINT_WHITE)
	var blue := GreyboxLook.surface(SIGN_BLUE)
	var front := COLUMN_Z + COLUMN * 0.5
	var number := 0
	for x in column_xs(_rules, _plan):
		number += 1
		_box(Vector3(COLUMN, height, COLUMN), _concrete, _at(x, _top + height * 0.5, COLUMN_Z))
		# Краска обёрткой чуть шире колонны и чуть выше пола — ни одна грань
		# не в плоскости бетона.
		_box(
			Vector3(COLUMN + 0.02, 0.9, COLUMN + 0.02),
			yellow,
			_at(x, _surface - 0.005 - 0.45, COLUMN_Z),
			false
		)
		for rise: float in [0.25, 0.6]:
			_box(
				Vector3(COLUMN + 0.03, 0.12, COLUMN + 0.03),
				black,
				_at(x, _surface - rise, COLUMN_Z),
				false
			)
		_box(Vector3(0.36, 0.26, 0.006), white, _at(x, _surface - 1.55, front + 0.005), false)
		var code := label("%s·%02d" % [LEVEL_MARK, number], 700, 0.1, PAINT_BLACK)
		code.position = _at(x, _surface - 1.55, front + 0.01)
		add_child(code)
		if number % 2 == 1:
			_box(Vector3(0.34, 0.34, 0.02), blue, _at(x, _surface - 2.1, front + 0.012), false)
			var letter := label("P", 800, 0.26, Color(0.95, 0.96, 1.0))
			letter.position = _at(x, _surface - 2.1, front + 0.025)
			add_child(letter)


## Балки поперёк зала над колоннами, короб вентиляции и трубы.
func _build_ceiling() -> void:
	var far_front := FAR_Z + FAR_THICKNESS * 0.5
	# Торцы балок — зубцами под кромкой перекрытия: через проезд, над
	# колонной. Над лампой балка начинается за передней линией.
	for x in column_xs(_rules, _plan):
		var front := WorldSpace.CORRIDOR_DEPTH * 0.5 - 0.02
		for lamp_x in _lamp_xs:
			if absf(lamp_x - x) < BEAM_LAMP_CLEARANCE:
				front = COLUMN_Z - COLUMN * 0.5
		var depth := front - far_front
		_box(
			Vector3(BEAM.x, BEAM.y, depth),
			_concrete,
			_at(x, _top + BEAM.y * 0.5, front - depth * 0.5)
		)

	# Оцинковка шершавая, а не зеркальная: зеркало отражало бы синеву зала.
	var duct := GreyboxLook.surface(DUCT_METAL)
	var duct_front := DUCT_Z + DUCT.x * 0.5
	var duct_top := _top + FloorSigns.hidden_band(duct_front) + DUCT_DROP
	for span in BuildingPlan.spans_between(cores(_rules, _plan), _inner):
		if span.y - span.x < 1.0:
			continue
		_box(
			Vector3(span.y - span.x, DUCT.y, DUCT.x),
			duct,
			_at((span.x + span.y) * 0.5, duct_top + DUCT.y * 0.5, DUCT_Z)
		)
		# Фланцы стыков: коробка чуть больше сечения через каждые 1.5 м.
		var flange_x := span.x + 0.75
		while flange_x < span.y - 0.3:
			_box(
				Vector3(0.05, DUCT.y + 0.04, DUCT.x + 0.04),
				duct,
				_at(flange_x, duct_top + DUCT.y * 0.5, DUCT_Z),
				false
			)
			flange_x += 1.5

	# Трубы вдоль зала: красная спринклерная и серая под ней. Разрывы — у
	# ядер шахт и простенка таблички: трубы уходят в бетон.
	var cuts: Array[Vector2] = [pier(_rules)]
	cuts.append_array(cores(_rules, _plan))
	var pipe_top := _top + FloorSigns.hidden_band(PIPE_Z + PIPE_RADIUS) + PIPE_DROP
	var pipes: Array[Array] = [
		[GreyboxLook.metal(PIPE_RED), pipe_top + PIPE_RADIUS, PIPE_RADIUS],
		[GreyboxLook.metal(PIPE_GREY), pipe_top + PIPE_RADIUS * 2.0 + 0.06, PIPE_RADIUS * 0.7],
	]
	for span in BuildingPlan.spans_between(cuts, _inner):
		if span.y - span.x < 0.4:
			continue
		for pipe in pipes:
			var mesh := CylinderMesh.new()
			mesh.top_radius = pipe[2]
			mesh.bottom_radius = pipe[2]
			mesh.height = span.y - span.x
			mesh.radial_segments = 12
			mesh.rings = 1
			var part := MeshInstance3D.new()
			part.mesh = mesh
			part.material_override = pipe[0]
			part.rotation.z = PI * 0.5
			part.position = _at((span.x + span.y) * 0.5, pipe[1], PIPE_Z)
			add_child(part)


## Люминесцентные светильники над местами: корпус на подвесах, трубка —
## эмиссия, под ней на полу — пятно света, над занятым местом — слабый свет
## без тени. Всё это гаснет вместе с зоной ближайшей лампы.
func _build_fixtures(building_seed: int) -> void:
	var taken := PackedFloat64Array()
	for car in parked(_rules, _plan, building_seed):
		taken.append(car.x)
	var at_gate := ExitCar.parked_span(_rules)
	var body := GreyboxLook.metal(FIXTURE_BODY)
	var tube := GreyboxLook.light(TUBE)
	var front := FIXTURE_Z + FIXTURE.z * 0.5
	var fixture_top := _top + FloorSigns.hidden_band(front) + 0.03
	var reach := (FIXTURE.x - 0.1) * 0.5
	for bay in bays(_rules, _plan):
		var x := _fixture_x(bay)
		if is_nan(x):
			continue
		_box(FIXTURE, body, _at(x, fixture_top + FIXTURE.y * 0.5, FIXTURE_Z), false)
		for side: float in [-1.0, 1.0]:
			_box(
				Vector3(0.015, fixture_top - _top, 0.015),
				body,
				_at(x + side * reach * 0.8, (_top + fixture_top) * 0.5, FIXTURE_Z),
				false
			)
		var glow := _box(
			DIFFUSER,
			tube,
			_at(x, fixture_top + FIXTURE.y + DIFFUSER.y * 0.5 - 0.015, FIXTURE_Z + 0.01),
			false
		)
		var fixture := Fixture.new()
		fixture.tube = glow
		fixture.pool = _light_pool()
		fixture.pool.position = _at(x, _surface - 0.012, FIXTURE_Z - POOL.y * 0.5 + 0.2)
		add_child(fixture.pool)
		var over_car := bay.y > at_gate.x and bay.x < at_gate.y
		if taken.has((bay.x + bay.y) * 0.5) or over_car:
			fixture.light = _tube_light(EXIT_CAR_TILT if over_car else TUBE_LIGHT_TILT)
			fixture.light.position = _at(x, fixture_top + FIXTURE.y + DIFFUSER.y, FIXTURE_Z)
			add_child(fixture.light)
		_fixtures.append(fixture)
		var owner := _nearest_lamp(x)
		if is_nan(owner):
			continue
		var list: Array = _tubes.get(owner, [])
		list.append(fixture)
		_tubes[owner] = list


## Свет трубки над занятым местом или машиной Otto: конус без тени вниз,
## наклонённый на [param tilt] градусов.
static func _tube_light(tilt: float) -> SpotLight3D:
	var light := SpotLight3D.new()
	light.light_color = TUBE
	light.light_energy = TUBE_LIGHT_ENERGY
	light.spot_range = TUBE_LIGHT_RANGE
	light.spot_angle = TUBE_LIGHT_ANGLE
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = 0.0
	# Конус светит вдоль своей -Z: поворот вокруг X опускает его вниз и
	# наклоняет — плюс в глубину зала, минус к проезду.
	light.rotation.x = deg_to_rad(tilt - 90.0)
	return light


## Где в месте [param bay] висит светильник: посередине или сдвинутым от
## лампы этажа. NAN — места нет: абажур лампы закрыл бы его.
func _fixture_x(bay: Vector2) -> float:
	var middle := (bay.x + bay.y) * 0.5
	var x := middle
	var slack := maxf((bay.y - bay.x - FIXTURE.x) * 0.5 - 0.05, 0.0)
	for lamp_x in _lamp_xs:
		var gap := x - lamp_x
		if absf(gap) >= FIXTURE_LAMP_CLEARANCE:
			continue
		x = lamp_x + (1.0 if gap >= 0.0 else -1.0) * FIXTURE_LAMP_CLEARANCE
		if absf(x - middle) > slack:
			return NAN
	return x


## Пятно света на полу: плоскость с круглым градиентом, складывается с полом.
## Не источник — картинка света, как у огоньков читаемости.
static func _light_pool() -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = POOL
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = _pool_material()
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return part


static func _pool_material() -> StandardMaterial3D:
	if _pool != null:
		return _pool
	var gradient := Gradient.new()
	gradient.set_color(0, Color(TUBE, POOL_ENERGY))
	gradient.set_color(1, Color(TUBE, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 64
	texture.height = 64
	_pool = StandardMaterial3D.new()
	_pool.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pool.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pool.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_pool.albedo_texture = texture
	_pool.disable_receive_shadows = true
	return _pool


## Разметка: полосы мест, упоры, край проезда, стрелки к воротам, пятна масла.
func _mark_the_floor(building_seed: int) -> void:
	var white := GreyboxLook.surface(PAINT_WHITE)
	var yellow := GreyboxLook.surface(PAINT_YELLOW)
	var stop := GreyboxLook.surface(PAINT_YELLOW.darkened(0.3))
	var oil := GreyboxLook.polished(OIL)
	var depth := BAY_FRONT_Z - BAY_BACK_Z
	var edges := PackedFloat64Array()
	for bay in bays(_rules, _plan):
		for edge: float in [bay.x, bay.y]:
			if not edges.has(edge):
				edges.append(edge)
		_box(
			Vector3(minf(1.2, bay.y - bay.x - 0.6), 0.1, 0.15),
			stop,
			_at((bay.x + bay.y) * 0.5, _surface - 0.05, BAY_BACK_Z + 0.2)
		)
	# Краска — на два миллиметра над полом: полоса уходит под колонну и
	# стену, и низ её иначе лёг бы в одну плоскость с их низом.
	for edge in edges:
		_box(
			Vector3(0.1, 0.005, depth),
			white,
			_at(edge, _surface - 0.0045, BAY_FRONT_Z - depth * 0.5),
			false
		)

	# Край проезда — жёлтая линия вдоль передней линии мест.
	for span in BuildingPlan.spans_between(busy_spans(_rules, _plan), _inner):
		_box(
			Vector3(span.y - span.x, 0.005, 0.1),
			yellow,
			_at((span.x + span.y) * 0.5, _surface - 0.0045, WorldSpace.BACK_WALL_Z + 0.1),
			false
		)

	# Стрелки к воротам по проезду: одна у ворот, дальше — через пролёт.
	# Первая — сразу за машиной Otto у ворот: под ней стрелку не видно.
	var arrow_x := ExitCar.parked_span(_rules).y + 1.2
	while arrow_x < _inner.y - 1.0:
		_paint_arrow(arrow_x, white)
		arrow_x += COLUMN_PITCH * 2.0

	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, SALT, "oil"])
	for bay in bays(_rules, _plan):
		for _stain in rng.randi_range(0, 2):
			var x := rng.randf_range(bay.x + 0.4, bay.y - 0.4)
			var z := rng.randf_range(BAY_BACK_Z + 0.8, BAY_FRONT_Z - 1.2)
			_stain_at(x, z, rng.randf_range(0.18, 0.42), oil)
	for _stain in 4:
		var x := rng.randf_range(_inner.x + 1.0, _inner.y - 1.0)
		_stain_at(x, rng.randf_range(-0.8, 0.8), rng.randf_range(0.12, 0.3), oil)


## Стрелка на полу проезда остриём к воротам: древко и наконечник.
func _paint_arrow(x: float, paint: StandardMaterial3D) -> void:
	var z := WorldSpace.CORRIDOR_DEPTH * 0.25
	_box(Vector3(0.9, 0.005, 0.16), paint, _at(x + 0.35, _surface - 0.0045, z), false)
	var head := PrismMesh.new()
	head.size = Vector3(0.5, 0.45, 0.006)
	var part := MeshInstance3D.new()
	part.mesh = head
	part.material_override = paint
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Треугольник призмы — в плоскости XY остриём вверх; лечь на пол остриём
	# влево — поворот вокруг X на пол, затем вокруг Y.
	part.basis = Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, -PI * 0.5)
	part.position = _at(x - 0.3, _surface - 0.0045, z)
	add_child(part)


## Пятно масла: тёмный блестящий овал на полу.
func _stain_at(x: float, z: float, radius: float, material: StandardMaterial3D) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.004
	mesh.radial_segments = 16
	mesh.rings = 1
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.scale = Vector3(1.0, 1.0, 0.6)
	part.position = _at(x, _surface - 0.002, z)
	add_child(part)


## Чужие машины: модели паков, раздвинутые до настоящей ширины и повёрнутые
## носом в зал или к проезду. Фары и стоп-сигналы не горят: машины стоят.
func _park_cars(building_seed: int) -> void:
	var cars := Node3D.new()
	cars.name = "ParkedCars"
	add_child(cars)
	for spot in parked(_rules, _plan, building_seed):
		var model := CarModel.build(spot.choice)
		model.name = "Parked"
		model.scale = Vector3(1.0, 1.0, CAR_WIDTH / _depth_of(model))
		# Капот модели — в +X; поворот на четверть вокруг Y уводит его в -Z.
		model.rotation.y = PI * 0.5 if spot.nose_in else -PI * 0.5
		model.position = _at(spot.x, _surface, CAR_Z)
		_switch_lights_off(model)
		cars.add_child(model)


## Глубина модели пака по её мешам, м.
static func _depth_of(model: Node3D) -> float:
	var low := INF
	var high := -INF
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box := mesh.transform * mesh.mesh.get_aabb()
		low = minf(low, box.position.z)
		high = maxf(high, box.end.z)
	return maxf(high - low, 0.1)


static func _switch_lights_off(model: Node3D) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface)
			var name := material.resource_name if material != null else ""
			if name == "Headlights":
				mesh.set_surface_override_material(surface, GreyboxLook.polished(HEADLIGHT_OFF))
			elif name == "TailLights":
				mesh.set_surface_override_material(surface, GreyboxLook.polished(TAILLIGHT_OFF))


## Стрелка к воротам и полосы опасности на стенке у ворот.
func _hang_signs() -> void:
	var inner_x := _inner.x
	var arrow := label("◀", 800, 0.5, PAINT_WHITE)
	arrow.position = _at(inner_x + GATE_BAY * 0.5, _surface - 1.2, WorldSpace.BACK_WALL_Z + 0.004)
	add_child(arrow)
	# Полосы опасности по низу стенки у ворот — угол, о который бьются бамперы.
	var yellow := GreyboxLook.surface(PAINT_YELLOW)
	var black := GreyboxLook.surface(PAINT_BLACK)
	for index in 4:
		_box(
			Vector3(GATE_BAY, 0.15, 0.008),
			yellow if index % 2 == 0 else black,
			_at(
				inner_x + GATE_BAY * 0.5,
				_surface - 0.003 - 0.075 - 0.15 * index,
				WorldSpace.BACK_WALL_Z + 0.004
			),
			false
		)


## Надпись краской или светом шрифтом игры.
## Статическая: ею же подписаны ворота ([GarageGate]).
static func label(text: String, weight: int, height: float, color: Color) -> Label3D:
	var painted := Label3D.new()
	painted.text = text
	painted.font = NeonStyle.font(weight)
	painted.font_size = 64
	painted.pixel_size = height / 64.0
	painted.modulate = color
	painted.outline_size = 0
	painted.shaded = true
	painted.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return painted


## Точка сцены: x и высота в координатах правил, глубина — как есть.
static func scene_point(x: float, y: float, z: float) -> Vector3:
	var point := WorldSpace.to_scene(Vector2(x, y))
	point.z = z
	return point


static func _at(x: float, y: float, z: float) -> Vector3:
	return scene_point(x, y, z)


## Коробка без тела в точке [param centre]. Мелочь — разметка, краска, таблички —
## теней не кладёт: теней в кадре она не прибавляет, а проходов теней стоит.
func _box(
	size: Vector3,
	material: StandardMaterial3D,
	centre: Vector3,
	shadow: bool = true,
	parent: Node = null
) -> MeshInstance3D:
	var part := GreyboxLook.box(size, material)
	part.position = centre
	if not shadow:
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else self).add_child(part)
	return part
