class_name CarDetail
extends Node3D

## Одежда кабины лифта: стенки, потолок со светильником, поручень, пульт, а в
## шахте — тросы и противовес (ADR-0031, решение 1).
##
## Только вид: тела кабины — пол, крыша, зона пассажира и давки — остаются в
## [ElevatorCar] и не меняются (ADR-0025). Спереди кабина открыта, как в
## оригинале: игрок видит, кто внутри. Светильник — эмиссия, не источник: бюджет
## ламп кадра кабина не трогает.

## Глубина кабины, м: как у её пола в сцене.
const DEPTH: float = 1.0

## Стенка: толщина и то, насколько задняя отстоит от края пола.
const WALL: float = 0.05

## Стойки по углам открытого фасада.
const POST := Vector2(0.07, 0.07)

## Боковые стенки — только угловые панели у задней: Otto входит в кабину сбоку,
## и стенка во всю глубину выглядела бы стеной, сквозь которую он проходит.
const SIDE_DEPTH: float = 0.3

## Поручень на задней стенке: высота над полом, сечение.
const RAIL_RISE: float = 0.95
const RAIL := Vector2(0.04, 0.06)

## Пульт на задней стенке у правой стойки: размер и сколько кнопок.
const PANEL := Vector3(0.16, 0.42, 0.03)
const PANEL_RISE: float = 1.05
const BUTTONS: int = 5
const BUTTON: float = 0.035

## Светильник под потолком: полоса во всю ширину без краёв.
const LIGHT := Vector3(0.0, 0.05, 0.3)

## Тросы: сколько, толщина, разнос от середины кабины, м.
const CABLES: int = 3
const CABLE: float = 0.025
const CABLE_SPREAD: float = 0.14

## Противовес: габарит и где он ходит — за задней стенкой кабины, у левого края.
const WEIGHT := Vector3(0.3, 1.1, 0.16)
const WEIGHT_Z: float = -DEPTH * 0.5 - 0.14
## Отступ противовеса от края шахты, м: левее он проходил сквозь направляющую
## ([constant BuildingShafts.RAIL_WIDTH], 0.18 м) — по глубине они перекрываются.
const WEIGHT_INSET: float = 0.22

const STEEL := Color(0.42, 0.43, 0.45)
const STEEL_DARK := Color(0.2, 0.21, 0.23)
const BRUSHED := Color(0.55, 0.53, 0.5)
const CABIN_LIGHT := Color(1.0, 0.95, 0.85)
const BUTTON_LIT := Color(1.0, 0.75, 0.35)
const CABLE_COLOR := Color(0.12, 0.12, 0.13)

## Кабина по типу здания (ADR-0057, решение 6). Отель — латунь и дерево,
## тёплый свет, зеркало над поручнем; офис — шлифованная нержавейка и холодный
## свет; жилой дом — грузовая кабина из крашеной стали, отбойный брус, лампа в
## решётке и складная решётка-гармошка спереди. Тела у всех одни (ADR-0025).
const WOOD := Color(0.3, 0.17, 0.1)
const BRASS := Color(0.78, 0.6, 0.3)
const MIRROR := Color(0.2, 0.22, 0.23)
const WARM_LIGHT := Color(1.0, 0.8, 0.55)
const PAINTED := Color(0.34, 0.39, 0.34)
const BUMPER := Color(0.35, 0.25, 0.15)
const GATE := Color(0.1, 0.1, 0.1)
## Зеркало отеля над поручнем: низ и высота, доля ширины задней стенки.
const MIRROR_RISE: float = 1.05
const MIRROR_HEIGHT: float = 0.9
const MIRROR_SHARE: float = 0.6
## Отбойный брус грузовой кабины: высота середины, сечение.
const BUMPER_RISE: float = 0.4
const BUMPER_SIZE := Vector2(0.12, 0.06)

## Решётка грузовой кабины: шаг прутьев, их сечение, доля высоты кабины,
## ширина сложенной гармошки у правой стойки, м, и время складывания, с.
## Закрыта, пока сойти нельзя, и сложена, пока можно — по окну выхода ROM
## ([method ElevatorMotion.can_step_out], @36F2): вид правила, а не новое
## правило. Прутья тонкие и тёмные — Otto за ними читается.
const GATE_STEP: float = 0.13
const GATE_BAR := Vector2(0.014, 0.014)
const GATE_SHARE: float = 0.88
const GATE_FOLDED: float = 0.2
const GATE_TIME: float = 0.35
## Звук решётки: лязг стали, слышно рядом.
const GATE_REACH: float = 12.0
const GATE_DB: float = -6.0

var _width: float = 1.2
## Тип здания кабины ([method dress_as]): по нему материалы и решётка.
var _kind: BuildingIdentity.Kind = BuildingIdentity.Kind.OFFICE
## Решётка грузовой кабины: прутья и верхняя и нижняя тяги; 0 — закрыта, 1 —
## сложена.
var _gate_bars: Array[MeshInstance3D] = []
var _gate_rails: Array[MeshInstance3D] = []
var _gate_open: float = 1.0
var _gate_wanted: bool = true
## Корпус кабины отдельным узлом: его пересобирает [method build], а тросы и
## противовес живут дольше — их заводит [method hang_cables] один раз.
var _body: Node3D = null
var _height: float = 3.0
var _cables: Array[MeshInstance3D] = []
var _weight_cables: Array[MeshInstance3D] = []
var _weight: MeshInstance3D = null
## Докуда в шахте ходит кабина: нижняя и верхняя остановки и верх шахты, по y сцены.
var _low: float = 0.0
var _high: float = 0.0
var _top: float = 0.0


## Одевает кабину по типу здания [param kind]. Звать до [method build]: его
## зовёт [method ElevatorCar.fit_to_story].
func dress_as(kind: BuildingIdentity.Kind) -> void:
	_kind = kind


## Есть ли у кабины решётка: только у грузовой жилого дома.
func has_gate() -> bool:
	return not _gate_bars.is_empty()


## Насколько сложена решётка: 1 — сложена, 0 — закрыта.
func gate_openness() -> float:
	return _gate_open


## Складывает решётку, когда из кабины можно сойти, и раздвигает, когда
## нельзя ([param open]), за [constant GATE_TIME] с; лязг — на смене, если
## [param audible]. Окно выхода открывается на каждом проезжаемом этаже, и
## лязгали бы все пустые кабины дома, — звенящие пустые кабины пользователь
## отверг ещё в M21 (ADR-0052, решение 7): слышно только кабину с Otto.
func tend_gate(open: bool, delta: float, audible: bool = true) -> void:
	if _gate_bars.is_empty():
		return
	if open != _gate_wanted:
		_gate_wanted = open
		if audible:
			Sounds.play_at(self, Sounds.CAB_GATE, global_position, GATE_REACH, GATE_DB)
	var target := 1.0 if open else 0.0
	var moved := move_toward(_gate_open, target, delta / GATE_TIME)
	if moved != _gate_open:
		_gate_open = moved
		_place_gate()


## Собирает одежду под ширину кабины и просвет этажа. Зовётся из
## [method ElevatorCar.fit_to_story] и пересобирает всё заново.
func build(width: float, clear_height: float) -> void:
	if _body != null:
		_body.queue_free()
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_width = width
	_height = clear_height

	var steel := GreyboxLook.metal(STEEL)
	var brushed := GreyboxLook.metal(BRUSHED)
	var lamp := CABIN_LIGHT
	match _kind:
		BuildingIdentity.Kind.HOTEL:
			steel = GreyboxLook.metal(BRASS)
			brushed = GreyboxLook.surface(WOOD)
			lamp = WARM_LIGHT
		BuildingIdentity.Kind.RESIDENTIAL:
			steel = GreyboxLook.metal(STEEL_DARK)
			brushed = GreyboxLook.metal(PAINTED)
	# Пол кабины — в её нуле: плита пола лежит под ним, плита крыши — от
	# просвета без толщины плиты до просвета. Стенки идут от пола до крыши;
	# отсчитанные от верха плиты пола, они висели на 18 см выше него.
	var inner := clear_height - ElevatorCar.SLAB_THICKNESS
	var middle := inner * 0.5
	var back_z := -DEPTH * 0.5 + WALL * 0.5

	# Задняя стенка с двумя швами, боковые — угловые панели у задней.
	_part(Vector3(width - WALL * 2.0, inner, WALL), Vector3(0.0, middle, back_z), brushed)
	for seam: float in [-width / 6.0, width / 6.0]:
		_part(Vector3(0.012, inner, 0.01), Vector3(seam, middle, back_z + WALL * 0.5), steel)
	for side: float in [-1.0, 1.0]:
		var x := side * (width * 0.5 - WALL * 0.5)
		var side_z := -DEPTH * 0.5 + SIDE_DEPTH * 0.5
		_part(Vector3(WALL, inner, SIDE_DEPTH), Vector3(x, middle, side_z), brushed)
		var post_x := side * (width * 0.5 - POST.x * 0.5)
		_part(
			Vector3(POST.x, inner, POST.y),
			Vector3(post_x, middle, DEPTH * 0.5 - POST.y * 0.5),
			steel
		)

	# Светильник, поручень, пульт с кнопками.
	var light_y := clear_height - ElevatorCar.SLAB_THICKNESS - LIGHT.y * 0.5
	_part(
		Vector3(width - WALL * 4.0, LIGHT.y, LIGHT.z),
		Vector3(0.0, light_y, 0.0),
		GreyboxLook.light(lamp)
	)
	_part(
		Vector3(width - WALL * 6.0, RAIL.x, RAIL.y),
		Vector3(0.0, RAIL_RISE, back_z + WALL * 0.5 + RAIL.y * 0.5),
		steel
	)
	_dress_by_kind(width, inner, back_z, light_y)
	var panel_x := width * 0.5 - WALL - PANEL.x * 0.5 - 0.06
	var panel_y := PANEL_RISE
	var panel_z := back_z + WALL * 0.5 + PANEL.z * 0.5
	_part(PANEL, Vector3(panel_x, panel_y, panel_z), GreyboxLook.metal(STEEL_DARK))
	for index in BUTTONS:
		var y := panel_y + PANEL.y * 0.35 - float(index) * (PANEL.y * 0.7 / float(BUTTONS - 1))
		_part(
			Vector3(BUTTON, BUTTON, 0.012),
			Vector3(panel_x, y, panel_z + PANEL.z * 0.5),
			GreyboxLook.light(BUTTON_LIT)
		)


## Своё у типа: зеркало отеля, брус, лампа в решётке и решётка грузовой.
func _dress_by_kind(width: float, inner: float, back_z: float, light_y: float) -> void:
	_gate_bars.clear()
	_gate_rails.clear()
	var face_z := back_z + WALL * 0.5
	match _kind:
		BuildingIdentity.Kind.HOTEL:
			_part(
				Vector3(width * MIRROR_SHARE, MIRROR_HEIGHT, 0.01),
				Vector3(0.0, MIRROR_RISE + MIRROR_HEIGHT * 0.5, face_z + 0.005),
				GreyboxLook.metal(MIRROR)
			)
		BuildingIdentity.Kind.RESIDENTIAL:
			var dark := GreyboxLook.metal(STEEL_DARK)
			# Рифлёный пол грузовой — тот же лист, что порог портала шахты.
			_part(
				Vector3(width - WALL * 2.0, 0.01, DEPTH - WALL),
				Vector3(0.0, 0.005, WALL * 0.5),
				BuildingFinish.tread_plate()
			)
			_part(
				Vector3(width - WALL * 2.0, BUMPER_SIZE.x, BUMPER_SIZE.y),
				Vector3(0.0, BUMPER_RISE, face_z + BUMPER_SIZE.y * 0.5),
				GreyboxLook.surface(BUMPER)
			)
			for bar: int in 3:
				_part(
					Vector3(0.012, LIGHT.y + 0.04, LIGHT.z + 0.04),
					Vector3(-0.3 + bar * 0.3, light_y - 0.02, 0.0),
					dark
				)
			_build_gate(width, inner)


## Решётка-гармошка у переднего края: прутья и две тяги. Ставит их
## [method _place_gate] по тому, насколько она сложена.
func _build_gate(width: float, inner: float) -> void:
	var height := inner * GATE_SHARE
	var iron := GreyboxLook.metal(GATE)
	var count := int((width - POST.x * 2.0) / GATE_STEP) + 1
	for bar: int in count:
		var part := GreyboxLook.box(Vector3(GATE_BAR.x, height, GATE_BAR.y), iron)
		part.position.y = height * 0.5
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_body.add_child(part)
		_gate_bars.append(part)
	for rise: float in [0.08, height - 0.04]:
		var rail := GreyboxLook.box(Vector3(1.0, 0.03, GATE_BAR.y), iron)
		rail.position.y = rise
		rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_body.add_child(rail)
		_gate_rails.append(rail)
	_place_gate()


## Расставляет прутья решётки: раздвинутая — на всю ширину проёма, сложенная —
## пачкой у правой стойки.
func _place_gate() -> void:
	if _gate_bars.is_empty():
		return
	var right := _width * 0.5 - POST.x
	var spread := lerpf(_width - POST.x * 2.0, GATE_FOLDED, _gate_open)
	var z := DEPTH * 0.5 - POST.y - GATE_BAR.y
	var count := _gate_bars.size()
	for bar: int in count:
		var share := float(bar) / float(maxi(count - 1, 1))
		_gate_bars[bar].position.x = right - share * spread
		_gate_bars[bar].position.z = z
	for rail: MeshInstance3D in _gate_rails:
		rail.scale.x = spread
		rail.position.x = right - spread * 0.5
		rail.position.z = z


## Заводит тросы и противовес: кабина ходит между остановками [param low] и
## [param high] (y сцены её низа), шахта кончается на [param top].
func hang_cables(low: float, high: float, top: float) -> void:
	_low = low
	_high = high
	_top = top
	if _weight != null:
		return
	var cable := GreyboxLook.metal(CABLE_COLOR)
	for index in CABLES:
		_cables.append(_loose(cable))
	for index in 2:
		_weight_cables.append(_loose(cable))
	_weight = GreyboxLook.box(WEIGHT, GreyboxLook.metal(STEEL_DARK))
	_weight.top_level = true
	add_child(_weight)


## Переносит верх шахты [param top] (y сцены): докуда идут тросы и выше чего
## противовес не поднимается. [method hang_cables] ставит его над потолком
## верхней остановки, а у шахты на крышу над ней небо — верх там задаёт уровень.
func set_top(top: float) -> void:
	_top = top


## Ставит тросы и противовес под кабину, низ которой сейчас на [param car_y].
## Противовес ходит навстречу: кабина внизу — он наверху.
func follow(car_y: float, car_x: float) -> void:
	if _weight == null:
		return
	var roof := car_y + _height
	for index in _cables.size():
		var x := car_x + (float(index) - float(CABLES - 1) * 0.5) * CABLE_SPREAD
		_stretch(_cables[index], x, roof, _top, -0.1)
	# Выше верха шахты противовес не идёт: у шахты на крышу верх — в машинном
	# отделении, и без упора противовес торчал бы над ним в небо.
	var weight_y := minf(_low + _high - car_y + _height * 0.5, _top - WEIGHT.y * 0.5)
	var weight_x := car_x - _width * 0.5 + WEIGHT_INSET + WEIGHT.x * 0.5
	_weight.global_position = Vector3(weight_x, weight_y, WEIGHT_Z)
	for index in _weight_cables.size():
		var x := weight_x + (float(index) - 0.5) * WEIGHT.x * 0.5
		_stretch(_weight_cables[index], x, weight_y + WEIGHT.y * 0.5, _top, WEIGHT_Z)


func _part(size: Vector3, at: Vector3, material: StandardMaterial3D) -> void:
	var part := GreyboxLook.box(size, material)
	part.position = at
	_body.add_child(part)


## Трос без места: ставит его [method follow] каждый шаг.
func _loose(material: StandardMaterial3D) -> MeshInstance3D:
	var line := GreyboxLook.box(Vector3.ONE, material)
	line.top_level = true
	add_child(line)
	return line


## Растягивает трос по вертикали от [param from] до [param to].
func _stretch(line: MeshInstance3D, x: float, from: float, to: float, z: float) -> void:
	var length := maxf(to - from, 0.01)
	line.scale = Vector3(CABLE, length, CABLE)
	line.global_position = Vector3(x, from + length * 0.5, z)
