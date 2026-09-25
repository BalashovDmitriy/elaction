class_name BuildingShafts
extends Node3D

## Одежда шахт здания: стальной лист, направляющие, распорки, порталы этажей с
## табло кабины и кнопками вызова, упоры и машинное отделение.
##
## Своим узлом, а не прямыми детьми уровня. Частей выходит за полсотни на здание,
## а по детям уровня ходят и агенты, и кабины, и половина тестов — каждый такой
## обход перебирал бы ещё и стойки со створками. Ровно по этой причине из уровня
## в своё время вынесли задний план.
##
## Тел здесь нет ни у чего: по направляющим не ходят, они только видны. Ездит
## кабина, а проём в перекрытии режет само перекрытие.
##
## С M21b шахта стальная (ADR-0033, решение 6): у задней стены во всю высоту —
## металлический лист с болтами, по перекрытиям — распорки, у портала —
## хромированный наличник и порог из рифлёной стали. Над порталом — табло с
## этажом, где кабина сейчас, и стрелкой хода; сбоку — кнопки вызова, горит та,
## в сторону которой кабина едет к этому этажу (решение 7, только вид).

## Ширина направляющей шахты, м. Стойка идёт по краю проёма во всю его высоту.
const RAIL_WIDTH: float = 0.18

## Доля тона шахты палитры раунда в направляющих (ADR-0031, решение 5).
const SHAFT_TONE: float = 0.25

## Портал шахты на этаже (ADR-0031, решение 1): доля ширины под каждую
## раскрытую створку, наличник, перемычка и порог, м; цвета металла.
const PORTAL_LEAF_SHARE: float = 0.22
const PORTAL_JAMB: float = 0.07
const PORTAL_HEAD: float = 0.1
const PORTAL_SILL: float = 0.03
const PORTAL_RECESS := Color(0.07, 0.08, 0.1)
const PORTAL_LEAF := Color(0.5, 0.5, 0.48)
## Хром наличника: светлый металл, ловит блик лампы коридора.
const PORTAL_TRIM := Color(0.78, 0.8, 0.83)
## Насколько проём и створки портала не доходят до пола и перемычки, м: доля
## пикселя, но грани разных материалов больше не в одной плоскости.
const PORTAL_EPSILON: float = 0.004

## Лист во всю высоту шахты: насколько шире проёма и толщина, м.
const PLATE_MARGIN: float = 0.05
const PLATE_THICKNESS: float = 0.02

## Распорка между направляющими на уровне перекрытия: высота, м.
const BRACE_HEIGHT: float = 0.12

## Табло кабины над порталом: размер, зазор над перемычкой, м; цвет цифр —
## холодный светодиод, как у табло M19 (не красный: красный огонёк на высоте
## вывески двери — знак двери с документом, авторевью M19).
const BOARD := Vector3(0.7, 0.26, 0.05)
const BOARD_GAP: float = 0.06
const BOARD_DIGITS := Color(0.55, 0.82, 1.0)
## Стрелки хода на табло.
const ARROW_UP := "\u25B2"
const ARROW_DOWN := "\u25BC"

## Панель кнопок сбоку портала: размер, высота середины, отступ от наличника,
## кнопка; цвет горящей и тёмной кнопки.
const CALL_PANEL := Vector3(0.12, 0.26, 0.02)
const CALL_RISE: float = 1.15
const CALL_GAP: float = 0.14
const CALL_BUTTON := Vector3(0.055, 0.055, 0.02)
const CALL_LIT := Color(0.92, 0.96, 1.0)
const CALL_DARK := Color(0.2, 0.21, 0.23)

## Табло и панель висят перед пилястрами, как табличка этажа
## ([constant FloorSigns.STANDOFF]): у края простенка пилястра стоит вплотную
## к порталу, выступает из стены на [constant BuildingRibs.PILASTER_DEPTH], и
## панель на самой стене тонула в ней целиком (авторевью M21b).
const MOUNT_Z: float = WorldSpace.BACK_WALL_Z + BuildingRibs.PILASTER_DEPTH + 0.01

## Что показывает табло, пока кабина на крыше: этажа с таким номером нет.
const ROOF_LABEL := "R"

## Высота упора в конце полосы шахты, м.
const BUFFER_HEIGHT: float = 0.24

## Насколько упор уже и мельче направляющих, м (ADR-0037, решение 2). Упор
## стоит между стойками и не доходит до их граней: грани разных материалов в
## одной плоскости мерцали на ходу камеры — глубина у них одна, и какая из двух
## ближе, решал случай.
const BUFFER_INSET: float = 0.01

## Надстройка машинного отделения на крыше, м.
const MACHINE_ROOM_SIZE := Vector2(2.16, 1.32)

## Глубина стоек и упоров и куда они утоплены: за кабину, но перед стеной.
## Кабина идёт в плоскости игры и закрывает их собой, проходя мимо.
const RAIL_DEPTH: float = 0.3
const RAIL_Z: float = -0.45

## Толщина створок шахты и машинного отделения. Створки висят на задней стене,
## как и двери этажей; домик стоит на крыше у той же стены.
##
## Домик не доходит до плоскости игры: его передняя грань кончается за спиной
## Otto (тело толщиной [constant WorldSpace.BODY_DEPTH] вокруг нуля), иначе он
## проходил бы сквозь стену домика, а не перед ней (авторевью M15).
##
## И на 4 см глубже направляющих: при 0.7 м его фасад вставал в одну плоскость
## с передней гранью стоек, и верх шахты на крыше мерцал (ADR-0037, решение 2).
const PANEL_THICKNESS: float = 0.08
const MACHINE_ROOM_DEPTH: float = 0.74

## Столб света в шахте: радиус, яркость, цвет и вынос перед направляющими, м.
##
## Долг с M12 ([ADR-0017](../../../docs/adr/0017-spectrum-palette-and-shafts.md),
## решение 3), закрытый в M18b
## ([ADR-0025](../../../docs/adr/0025-shafts-escalators-and-riders.md), решение 3).
## Источник настоящий, а не свечение материала: свет обязан лечь на направляющие,
## створки и пол перед проёмом, иначе на погашенном этаже шахта висит светящейся
## полосой в черноте и «здесь путь вниз» читается хуже, чем сбитой лампой.
##
## Холодный против тёплых ламп (ADR-0023, решение 3): шахта — металл, и свет
## в ней не домашний. Теней не кладёт — их в шахте некуда ронять, а стоят они
## дороже всего остального.
## Радиус — чуть шире самой шахты (1.2 м), и это не скупость. На 4.2 м столбы
## пяти шахт стилобата заливали этаж целиком, и погашенный этаж переставал быть
## погашенным: темнота M17 отменялась светом, который к ней отношения не имеет.
## Столб обязан светить в шахте, а не вместо ламп.
const GLOW_RANGE: float = 1.8
const GLOW_ENERGY: float = 1.1
const GLOW_COLOR := Color(0.74, 0.84, 1.0)
const GLOW_Z: float = -0.35

var _rules: BuildingRules
var _plan: BuildingPlan
## Источники столба: этаж → те, что на нём стоят. Гаснут вне кадра, как лампы.
var _glow: Dictionary = {}
## Табло и кнопки порталов: x шахты → этаж → [ShaftBoard]. В одном столбце
## бывает несколько шахт — этажи у них не пересекаются, поэтому ключ «x и этаж»
## однозначен, но обновлять табло надо по этажам своей шахты, а не по столбцу.
var _boards: Dictionary = {}
## Кабины, за которыми следят табло: кабина → её шахта.
var _watched: Dictionary = {}
## Что табло уже показывают: кабина → [этаж, направление]. Надписи меняются
## только при смене, а не каждый кадр.
var _shown: Dictionary = {}
## Табло и кнопки — своим узлом: по прямым детям шахт тесты ищут их части
## (направляющие, упоры, трос спуска), и панель кнопок в 12 см шириной
## сходила бы за трос.
var _board_host: Node3D = null


## Табло и кнопки одного портала.
class ShaftBoard:
	extends RefCounted
	var floor_index: int = 0
	var digits: Label3D = null
	var up_button: MeshInstance3D = null
	var down_button: MeshInstance3D = null
	## Какая кнопка горит: [constant Intent.UP], [constant Intent.DOWN] или 0.
	var lit: float = 0.0


## Одевает все шахты здания разом.
func dress(rules: BuildingRules, plan: BuildingPlan) -> void:
	_rules = rules
	_plan = plan
	set_physics_process(false)
	_board_host = Node3D.new()
	_board_host.name = "Boards"
	add_child(_board_host)
	for shaft in plan.shafts:
		_dress_shaft(shaft)
	_spawn_machine_room()
	add_to_group(Graphics.GROUP)
	apply_graphics()


## Столбы света шахт в объёмном тумане — по уровню качества (ADR-0034,
## решение 1): на «Ультра» в шахте виден луч.
func apply_graphics() -> void:
	for index: int in _glow:
		for light: OmniLight3D in _glow[index]:
			light.light_volumetric_fog_energy = Graphics.light_in_fog()


## Зажигает столбы света на видимых этажах и гасит остальные.
##
## Тем же правилом, что и лампы (ADR-0010, пункт 8): в здании до дюжины шахт и
## по источнику на каждый их этаж, а в кадр влезает два с половиной этажа.
## Гаснет источник, но не сам столб: погашенный этаж от невидимого отличается
## тем, что его видно.
func light_span(span: Vector2i) -> void:
	for index: int in _glow:
		var lit := VisibleFloors.covers(span, index)
		for light: OmniLight3D in _glow[index]:
			light.visible = lit


## Верх шахты: докуда идут её стойки и упор.
##
## У шахты, доходящей до крыши, потолка нет — над ней небо, и [method
## BuildingRules.story_top] отдаёт верх мира. Стойка и упор ушли бы в открытое
## небо над крышей; кончается такая шахта внутри машинного отделения, оно и
## есть её верх.
func top_of(shaft: BuildingPlan.ShaftSpot) -> float:
	if shaft.top > BuildingRules.ROOF:
		return _rules.story_top(shaft.top)
	return _rules.floor_surface(BuildingRules.ROOF) - MACHINE_ROOM_SIZE.y * 0.5


## Одевает шахту: направляющие во всю её высоту и створки на каждом её этаже.
##
## До M12 шахта была дырой в перекрытии — в кадре её почти не было, хотя спуск
## по зданию и есть игра (ADR-0017, решение 3). Направляющие дают ей края,
## створки — отметку этажа: по ним видно, где кабина встаёт.
func _dress_shaft(shaft: BuildingPlan.ShaftSpot) -> void:
	_mark_shaft_ends(shaft)
	var top := top_of(shaft)
	var bottom := _rules.floor_surface(shaft.bottom)
	var half := _rules.shaft_width * 0.5
	# Шахта — металл (ADR-0023, решение 5): направляющие ловят блик ламп.
	var rail := GreyboxLook.metal(GreyboxLook.SHAFT.lerp(_rules.palette.shaft, SHAFT_TONE))

	for side: float in [-1.0, 1.0]:
		var x := shaft.x + half * side
		var left := x if side < 0.0 else x - RAIL_WIDTH
		_add_part(Rect2(left, top, RAIL_WIDTH, bottom - top), rail, RAIL_Z, RAIL_DEPTH)

	# Лист с болтами во всю высоту шахты, у задней стены: шахта — стальной
	# столб сквозь здание, а не продолжение обоев коридора.
	var plate_half := half + PORTAL_JAMB + PLATE_MARGIN
	_add_part(
		# На миллиметры ниже дна: низ листа не в плоскости низа проёма.
		Rect2(shaft.x - plate_half, top, plate_half * 2.0, bottom - top + PORTAL_EPSILON),
		BuildingFinish.shaft_plates(),
		WorldSpace.BACK_WALL_Z + PLATE_THICKNESS * 0.5 + 0.002,
		PLATE_THICKNESS
	)

	for index: int in range(shaft.top, shaft.bottom + 1):
		var surface := _rules.floor_surface(index)
		if index > BuildingRules.ROOF:
			_build_portal(shaft.x, surface)
			_build_board(shaft.x, index, surface)
		if index > shaft.top:
			# Распорка на уровне перекрытия над этажом: там кабина не встаёт.
			var slab := _rules.story_top(index)
			_add_part(
				Rect2(shaft.x - half, slab, half * 2.0, BRACE_HEIGHT), rail, RAIL_Z, RAIL_DEPTH
			)
		_light_the_shaft(shaft.x, index, surface)


## Портал шахты на этаже, как на референсе: тёмный проём, раскрытые створки по
## бокам, наличник, перемычка и порог (ADR-0031, решение 1). Всё у задней стены
## и без тел: кабина ходит перед ним, и её видно целиком.
func _build_portal(x: float, surface: float) -> void:
	var half := _rules.shaft_width * 0.5
	var height := Proportions.DOOR.y
	var back_z := WorldSpace.BACK_WALL_Z + PANEL_THICKNESS * 0.5 + 0.01
	var recess := GreyboxLook.metal(PORTAL_RECESS)
	var leaf := GreyboxLook.metal(PORTAL_LEAF)
	var trim := GreyboxLook.metal(PORTAL_TRIM)

	# Створки и порог чуть не доходят до пола и перемычки: низ проёма, створок
	# и порога ложился в одну плоскость (ADR-0037, решение 2). Проём — во всю
	# высоту двери: по ней его узнают тесты одежды.
	_add_part(
		Rect2(x - half, surface - height, half * 2.0, height), recess, back_z, PANEL_THICKNESS
	)
	var leaf_width := half * 2.0 * PORTAL_LEAF_SHARE
	for side: float in [-1.0, 1.0]:
		var from := x - half if side < 0.0 else x + half - leaf_width
		_add_part(
			Rect2(
				from, surface - height + PORTAL_EPSILON, leaf_width, height - PORTAL_EPSILON * 3.0
			),
			leaf,
			back_z + 0.03,
			PANEL_THICKNESS
		)
		var jamb_from := x - half - PORTAL_JAMB if side < 0.0 else x + half
		_add_part(
			Rect2(jamb_from, surface - height, PORTAL_JAMB, height),
			trim,
			back_z + 0.05,
			PANEL_THICKNESS
		)
	var head := Rect2(
		x - half - PORTAL_JAMB,
		surface - height - PORTAL_HEAD,
		(half + PORTAL_JAMB) * 2.0,
		PORTAL_HEAD
	)
	_add_part(head, trim, back_z + 0.05, PANEL_THICKNESS)
	_add_part(
		Rect2(x - half, surface - PORTAL_SILL, half * 2.0, PORTAL_SILL - PORTAL_EPSILON),
		BuildingFinish.tread_plate(),
		back_z + 0.12,
		0.2
	)


## Табло над порталом и кнопки сбоку. Цифры — этаж, где кабина сейчас; пока
## табло кабину не видело, горит свой этаж.
func _build_board(x: float, index: int, surface: float) -> void:
	var board := ShaftBoard.new()
	board.floor_index = index
	var head_top := surface - Proportions.DOOR.y - PORTAL_HEAD
	var frame := GreyboxLook.box(BOARD, GreyboxLook.metal(PORTAL_RECESS))
	frame.position = WorldSpace.to_scene(Vector2(x, head_top - BOARD_GAP - BOARD.y * 0.5))
	frame.position.z = WorldSpace.BACK_WALL_Z + PANEL_THICKNESS + 0.06
	_board_host.add_child(frame)
	board.digits = Label3D.new()
	board.digits.font = NeonStyle.font(700)
	board.digits.font_size = 64
	board.digits.pixel_size = 0.0034
	board.digits.modulate = BOARD_DIGITS
	board.digits.outline_size = 0
	board.digits.position = frame.position + Vector3(0.0, 0.0, BOARD.z * 0.5 + 0.003)
	_board_host.add_child(board.digits)

	var side := call_side(_rules, _plan, x, index)
	if side != 0.0:
		var panel_x := x + side * (_rules.shaft_width * 0.5 + PORTAL_JAMB + CALL_GAP)
		var panel := GreyboxLook.box(CALL_PANEL, GreyboxLook.metal(PORTAL_TRIM))
		panel.position = WorldSpace.to_scene(Vector2(panel_x, surface - CALL_RISE))
		panel.position.z = MOUNT_Z + CALL_PANEL.z * 0.5
		_board_host.add_child(panel)
		for up: bool in [true, false]:
			var button := GreyboxLook.box(CALL_BUTTON, GreyboxLook.metal(CALL_DARK))
			var lift := CALL_PANEL.y * 0.22 * (1.0 if up else -1.0)
			button.position = panel.position + Vector3(0.0, lift, CALL_PANEL.z * 0.5 + 0.005)
			_board_host.add_child(button)
			if up:
				board.up_button = button
			else:
				board.down_button = button

	if not _boards.has(x):
		_boards[x] = {}
	(_boards[x] as Dictionary)[index] = board
	_show(board, floor_label(_rules, index), 0.0, 0.0)


## Что пишет табло про этаж [param index]: подпись таблички этажа — номер, у
## паркинга «P» ([method FloorSigns.label_of]), — а на крыше
## [constant ROOF_LABEL]. Номер крыши по формуле вышел бы на единицу больше
## верхнего этажа — этажа, которого в здании нет.
static func floor_label(rules: BuildingRules, index: int) -> String:
	if index <= BuildingRules.ROOF:
		return ROOF_LABEL
	return FloorSigns.label_of(rules, index)


## Сколько панель кнопок занимает у шахты [param x] на этаже [param index]:
## пара «левый край, правый край», или нулевая пара, если панели нет. Мебель
## перед ней не встаёт ([method BuildingDressing.blocked_zones]).
static func call_panel_span(
	rules: BuildingRules, plan: BuildingPlan, x: float, index: int
) -> Vector2:
	var side := call_side(rules, plan, x, index)
	if side == 0.0:
		return Vector2.ZERO
	var near := x + side * (rules.shaft_width * 0.5 + PORTAL_JAMB + CALL_GAP - CALL_PANEL.x * 0.5)
	var far := near + side * CALL_PANEL.x
	return Vector2(minf(near, far), maxf(near, far))


## С какой стороны портала панели кнопок место: там, где до двери
## хватает стены и панель не уходит в боковую стену здания. Справа, если
## свободны обе; 0 — если заняты обе.
##
## Дверь считается с наличником, а слева от шахты — ещё и с табличкой номера,
## которая висит справа от двери ([BuildingProps]): по середине двери панель
## вставала на наличник двери соседнего места и на её табличку.
static func call_side(rules: BuildingRules, plan: BuildingPlan, x: float, index: int) -> float:
	var reach := rules.shaft_width * 0.5 + PORTAL_JAMB + CALL_GAP + CALL_PANEL.x
	var bounds := rules.floor_span(index)
	var right := x + reach < bounds.y - BuildingShell.WALL_WIDTH
	var left := x - reach > bounds.x + BuildingShell.WALL_WIDTH
	var door_half := Door.LEAF_SIZE.x * 0.5 + Door.FRAME_WIDTH
	var plate_reach := Door.LEAF_SIZE.x * 0.5 + BuildingProps.PLATE_GAP + BuildingProps.PLATE.x
	var openings: Array[Vector2] = []
	for door in plan.doors:
		if door.floor_index == index:
			openings.append(Vector2(door.x - door_half, door.x + maxf(door_half, plate_reach)))
	for opening in openings:
		if opening.x > x and opening.x < x + reach:
			right = false
		if opening.y < x and opening.y > x - reach:
			left = false
	if right:
		return 1.0
	return -1.0 if left else 0.0


## Табло шахты [param shaft] следят за кабиной [param car]: этаж и направление
## хода. У двухэтажной — за ведущим ярусом.
func watch(car: ElevatorCar, shaft: BuildingPlan.ShaftSpot) -> void:
	_watched[car] = shaft
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	for car: ElevatorCar in _watched:
		if not is_instance_valid(car):
			continue
		refresh(car)


## Показывает на табло шахты кабины [param car] её этаж и ход — если что-то
## изменилось с прошлого раза.
func refresh(car: ElevatorCar) -> void:
	# Нижний ярус двухэтажной кабины табло не ведёт: этаж показывает ведущий.
	if not _watched.has(car):
		return
	var shaft := _watched[car] as BuildingPlan.ShaftSpot
	var index := _nearest_floor(car)
	var heading := heading_of(car.speed_now())
	var last: Array = _shown.get(car, [])
	if not last.is_empty() and last[0] == index and last[1] == heading:
		return
	_shown[car] = [index, heading]
	var label := floor_label(_rules, index)
	# Только этажи своей шахты: в том же столбце бывает другая, со своей кабиной,
	# и табло столбца целиком показывали бы то одну кабину, то другую.
	var column := _boards.get(shaft.x, {}) as Dictionary
	for floor_index in range(shaft.top, shaft.bottom + 1):
		var board := column.get(floor_index) as ShaftBoard
		if board != null:
			_show(board, label, heading, coming(heading, index, floor_index))


## Ход кабины по её скорости: [constant Intent.UP], [constant Intent.DOWN] или
## 0. Скорость — в плоскости правил, где y растёт вниз: едущая вниз кабина
## отчитывается положительной скоростью, как и в [method ElevatorCar.speed_now].
static func heading_of(speed: float) -> float:
	if is_zero_approx(speed):
		return 0.0
	return Intent.DOWN if speed > 0.0 else Intent.UP


## Едет ли кабина к этажу табло: вниз — к этажам под ней, вверх — к этажам над
## ней. Направления — [Intent]; индексы этажей растут вниз, нулевой — верхний.
static func coming(heading: float, car_floor: int, board_floor: int) -> float:
	if heading == Intent.DOWN and board_floor > car_floor:
		return Intent.DOWN
	if heading == Intent.UP and board_floor < car_floor:
		return Intent.UP
	return 0.0


## Ближайший к полу кабины этаж её шахты.
func _nearest_floor(car: ElevatorCar) -> int:
	var index := _rules.floor_index_near(WorldSpace.to_plane(car.global_position).y)
	var shaft := _watched.get(car) as BuildingPlan.ShaftSpot
	return clampi(index, shaft.top, shaft.bottom) if shaft != null else index


## Пишет на табло этаж и стрелку хода кабины [param heading] и зажигает кнопку
## [param call] — ту, в сторону которой кабина идёт к этому этажу.
func _show(board: ShaftBoard, label: String, heading: float, call: float) -> void:
	var arrow := ""
	if heading == Intent.UP:
		arrow = ARROW_UP
	elif heading == Intent.DOWN:
		arrow = ARROW_DOWN
	board.digits.text = label if arrow.is_empty() else "%s %s" % [arrow, label]
	board.lit = call if board.up_button != null else 0.0
	if board.up_button != null:
		# Погасшая кнопка возвращается к тёмному металлу: без материала коробка
		# рисовалась бы белым материалом движка по умолчанию.
		var lit := GreyboxLook.light(CALL_LIT)
		var dark := GreyboxLook.metal(CALL_DARK)
		board.up_button.material_override = lit if call == Intent.UP else dark
		board.down_button.material_override = lit if call == Intent.DOWN else dark


## Следят ли табло за этой кабиной.
func watches(car: ElevatorCar) -> bool:
	return _watched.has(car)


## Что показывает табло портала шахты [param x] на этаже [param index].
func board_text(x: float, index: int) -> String:
	var board := (_boards.get(x, {}) as Dictionary).get(index) as ShaftBoard
	return board.digits.text if board != null else ""


## Какая кнопка горит на этом портале: [constant Intent.UP], [constant
## Intent.DOWN] или 0 — ни одна (или панели нет).
func lit_button(x: float, index: int) -> float:
	var board := (_boards.get(x, {}) as Dictionary).get(index) as ShaftBoard
	return board.lit if board != null else 0.0


## Источник столба на одном этаже шахты: посреди пролёта, перед направляющими.
##
## По источнику на этаж, а не один на всю шахту: полоса бывает в четырнадцать
## этажей, и один источник с таким радиусом освещал бы её середину и оставлял
## тёмными оба конца — а кабина ходит по всей полосе.
func _light_the_shaft(x: float, index: int, surface: float) -> void:
	var light := OmniLight3D.new()
	light.omni_range = GLOW_RANGE
	light.light_energy = GLOW_ENERGY
	light.light_color = GLOW_COLOR
	light.shadow_enabled = false
	light.position = WorldSpace.to_scene(Vector2(x, surface - _rules.floor_height * 0.5))
	light.position.z = GLOW_Z
	add_child(light)

	if not _glow.has(index):
		_glow[index] = [] as Array[OmniLight3D]
	(_glow[index] as Array[OmniLight3D]).append(light)


## Упоры в концах полосы: дальше кабина не идёт, и это видно.
##
## Отзыв после игры: «лифт не слушается команд и стоит, а сошёл — уехал». Это
## и был конец полосы — кабина слышала команду, но идти дальше ей некуда, а
## пустая она тут же уезжала по своему расписанию. Упор объясняет предел без
## единого слова; второй указатель — стрелки в самой кабине.
##
## Нижний упор лежит на дне шахты, то есть над полом нижнего её этажа, а не
## в толще плиты, где его не видно вовсе.
##
## Упор — между стойками, уже и мельче их на [constant BUFFER_INSET]: во всю
## ширину шахты его грани ложились на грани стоек (ADR-0037, решение 2).
func _mark_shaft_ends(shaft: BuildingPlan.ShaftSpot) -> void:
	var inner := _rules.shaft_width * 0.5 - RAIL_WIDTH - BUFFER_INSET
	var top := top_of(shaft)
	var bottom := _rules.floor_surface(shaft.bottom) - BUFFER_HEIGHT
	var buffer := GreyboxLook.marker(GreyboxLook.DOOR)
	var depth := RAIL_DEPTH - BUFFER_INSET * 2.0

	for from: float in [top, bottom]:
		_add_part(Rect2(shaft.x - inner, from, inner * 2.0, BUFFER_HEIGHT), buffer, RAIL_Z, depth)


## Кусок одежды шахты: коробка без тела на месте прямоугольника правил.
func _add_part(rect: Rect2, material: StandardMaterial3D, z: float, depth: float) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var part := GreyboxLook.box(Vector3(rect.size.x, rect.size.y, depth), material)
	part.position = WorldSpace.to_scene(rect.get_center())
	part.position.z = z
	add_child(part)


## Надстройка машинного отделения над верхней шахтой.
##
## Тела у неё нет намеренно: под ней проём той самой шахты, с которой начинается
## спуск, и сплошная надстройка заперла бы Otto на крыше. Стоит она у задней
## стены, и он проходит перед ней.
func _spawn_machine_room() -> void:
	var shaft := _plan.roof_shaft()
	if shaft == null:
		return

	var surface := _rules.floor_surface(BuildingRules.ROOF)
	var rect := Rect2(
		Vector2(shaft.x - MACHINE_ROOM_SIZE.x * 0.5, surface - MACHINE_ROOM_SIZE.y),
		MACHINE_ROOM_SIZE
	)
	var z := WorldSpace.BACK_WALL_Z + MACHINE_ROOM_DEPTH * 0.5
	_add_part(rect, BuildingFinish.shaft_concrete(GreyboxLook.WALL), z, MACHINE_ROOM_DEPTH)
