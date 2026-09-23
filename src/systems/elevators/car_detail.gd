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

const STEEL := Color(0.42, 0.43, 0.45)
const STEEL_DARK := Color(0.2, 0.21, 0.23)
const BRUSHED := Color(0.55, 0.53, 0.5)
const CABIN_LIGHT := Color(1.0, 0.95, 0.85)
const BUTTON_LIT := Color(1.0, 0.75, 0.35)
const CABLE_COLOR := Color(0.12, 0.12, 0.13)

var _width: float = 1.2
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
	var inner := clear_height - ElevatorCar.SLAB_THICKNESS * 2.0
	var middle := ElevatorCar.SLAB_THICKNESS + inner * 0.5
	var back_z := -DEPTH * 0.5 + WALL * 0.5

	# Задняя стенка с двумя швами, боковые — узкие, во всю глубину.
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
		GreyboxLook.light(CABIN_LIGHT)
	)
	_part(
		Vector3(width - WALL * 6.0, RAIL.x, RAIL.y),
		Vector3(0.0, ElevatorCar.SLAB_THICKNESS + RAIL_RISE, back_z + WALL * 0.5 + RAIL.y * 0.5),
		steel
	)
	var panel_x := width * 0.5 - WALL - PANEL.x * 0.5 - 0.06
	var panel_y := ElevatorCar.SLAB_THICKNESS + PANEL_RISE
	var panel_z := back_z + WALL * 0.5 + PANEL.z * 0.5
	_part(PANEL, Vector3(panel_x, panel_y, panel_z), GreyboxLook.metal(STEEL_DARK))
	for index in BUTTONS:
		var y := panel_y + PANEL.y * 0.35 - float(index) * (PANEL.y * 0.7 / float(BUTTONS - 1))
		_part(
			Vector3(BUTTON, BUTTON, 0.012),
			Vector3(panel_x, y, panel_z + PANEL.z * 0.5),
			GreyboxLook.light(BUTTON_LIT)
		)


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


## Ставит тросы и противовес под кабину, низ которой сейчас на [param car_y].
## Противовес ходит навстречу: кабина внизу — он наверху.
func follow(car_y: float, car_x: float) -> void:
	if _weight == null:
		return
	var roof := car_y + _height
	for index in _cables.size():
		var x := car_x + (float(index) - float(CABLES - 1) * 0.5) * CABLE_SPREAD
		_stretch(_cables[index], x, roof, _top, -0.1)
	var weight_y := _low + _high - car_y + _height * 0.5
	var weight_x := car_x - _width * 0.5 + WEIGHT.x * 0.5 + 0.06
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
