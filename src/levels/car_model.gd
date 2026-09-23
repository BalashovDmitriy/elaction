class_name CarModel
extends RefCounted

## Седан у выхода, собранный из примитивов (ADR-0031, решение 4).
##
## Раньше машина была коробкой из `car.glb` и на фоне дверей смотрелась нелепо.
## Теперь это кузов с капотом и багажником ниже кабины, стёкла, колёса с
## дисками, бамперы, фары и стоп-сигналы. Фары светятся эмиссией — источников
## машина не добавляет.
##
## Нуль модели — между колёсами на земле, капот смотрит в +X.

## Длина по бамперам, м — та же, по которой [ExitCar] ставит машину у выхода.
const LENGTH: float = Proportions.CAR_LENGTH
## Ширина кузова, м — не как у настоящего седана, а сколько влезает между
## задней стеной и телом Otto: машина стоит на [constant ExitCar.Z], стена в
## 0.4 м за ней, тело Otto — в 0.4 м перед ней. Колёса выступают ещё на 4 см.
## Седан в 1.5 м входил в стену на 35 см и выходил в плоскость игры, и Otto
## проходил сквозь машину — та же находка, что у `car.glb` на авторевью M18c
## (авторевью M20).
const WIDTH: float = 0.7

## Нижний пояс кузова: от клиренса до линии окон.
const CLEARANCE: float = 0.2
const BELT: float = 0.72

## Кабина: высота над поясом и доля длины по крыше и по низу.
const CABIN_HEIGHT: float = 0.46
const CABIN_ROOF: float = 0.36
const CABIN_BASE: float = 0.56
## Кабина сдвинута к корме: капот длиннее багажника.
const CABIN_SHIFT: float = -0.06

const WHEEL_RADIUS: float = 0.3
const WHEEL_WIDTH: float = 0.22
## Где колёса по длине, доли длины от середины.
const AXLE: float = 0.31

const PAINT := Color(0.62, 0.1, 0.1)
const GLASS := Color(0.14, 0.2, 0.28)
const CHROME := Color(0.7, 0.7, 0.72)
const TYRE := Color(0.05, 0.05, 0.05)
const HEADLIGHT := Color(1.0, 0.95, 0.8)
const TAILLIGHT := Color(1.0, 0.1, 0.08)


## Собирает седан узлом без тел.
static func build() -> Node3D:
	var car := Node3D.new()
	car.name = "Sedan"
	var paint := GreyboxLook.polished(PAINT)
	var glass := GreyboxLook.polished(GLASS)
	var chrome := GreyboxLook.metal(CHROME)

	# Нижний пояс кузова во всю длину.
	var body_height := BELT - CLEARANCE
	_box(
		car,
		Vector3(LENGTH, body_height, WIDTH),
		Vector3(0.0, CLEARANCE + body_height * 0.5, 0.0),
		paint
	)

	# Кабина трапецией: призма поверх пояса, стёкла чуть внутри неё.
	var base := LENGTH * CABIN_BASE
	var roof := LENGTH * CABIN_ROOF
	var cabin_x := LENGTH * CABIN_SHIFT
	_trapezoid(car, base, roof, CABIN_HEIGHT, WIDTH * 0.92, Vector3(cabin_x, BELT, 0.0), paint)
	_trapezoid(
		car,
		base - 0.08,
		roof - 0.06,
		CABIN_HEIGHT - 0.06,
		WIDTH * 0.94,
		Vector3(cabin_x, BELT + 0.01, 0.0),
		glass
	)
	# Стойка посередине окна.
	_box(
		car,
		Vector3(0.06, CABIN_HEIGHT - 0.05, WIDTH * 0.95),
		Vector3(cabin_x, BELT + CABIN_HEIGHT * 0.5, 0.0),
		paint
	)

	# Бамперы, фары, стоп-сигналы.
	for end: float in [-1.0, 1.0]:
		var x := end * (LENGTH * 0.5 + 0.03)
		_box(car, Vector3(0.08, 0.1, WIDTH * 1.02), Vector3(x, CLEARANCE + 0.08, 0.0), chrome)
		var lamp := GreyboxLook.light(HEADLIGHT if end > 0.0 else TAILLIGHT)
		for side: float in [-1.0, 1.0]:
			_box(
				car,
				Vector3(0.04, 0.1, 0.24),
				Vector3(end * (LENGTH * 0.5 + 0.005), BELT - 0.14, side * (WIDTH * 0.5 - 0.2)),
				lamp
			)

	# Колёса с дисками.
	var tyre := GreyboxLook.surface(TYRE)
	for axle: float in [-AXLE, AXLE]:
		for side: float in [-1.0, 1.0]:
			var z := side * (WIDTH * 0.5 - WHEEL_WIDTH * 0.35)
			_wheel(car, Vector3(axle * LENGTH, WHEEL_RADIUS, z), tyre, chrome)
	return car


static func _box(host: Node3D, size: Vector3, at: Vector3, material: StandardMaterial3D) -> void:
	var part := GreyboxLook.box(size, material)
	part.position = at
	host.add_child(part)


## Трапеция вдоль X: низ [param bottom], верх [param top], стоит низом на
## [param at]. Восемь вершин, двенадцать треугольников, плоские грани.
static func _trapezoid(
	host: Node3D,
	bottom: float,
	top: float,
	height: float,
	depth: float,
	at: Vector3,
	material: StandardMaterial3D
) -> void:
	var near := depth * 0.5
	var corners: Array[Vector3] = [
		Vector3(-bottom * 0.5, 0.0, near),
		Vector3(bottom * 0.5, 0.0, near),
		Vector3(top * 0.5, height, near),
		Vector3(-top * 0.5, height, near),
		Vector3(-bottom * 0.5, 0.0, -near),
		Vector3(bottom * 0.5, 0.0, -near),
		Vector3(top * 0.5, height, -near),
		Vector3(-top * 0.5, height, -near),
	]
	# Грани по четыре вершины, обход против часовой снаружи.
	var faces: Array[PackedInt32Array] = [
		PackedInt32Array([0, 1, 2, 3]),
		PackedInt32Array([5, 4, 7, 6]),
		PackedInt32Array([3, 2, 6, 7]),
		PackedInt32Array([4, 5, 1, 0]),
		PackedInt32Array([1, 5, 6, 2]),
		PackedInt32Array([4, 0, 3, 7]),
	]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in faces:
		# Обход по часовой — лицевая сторона у Godot; против часовой грань
		# отсекалась бы, и кабина была видна изнанкой.
		for index: int in [0, 2, 1, 0, 3, 2]:
			tool.add_vertex(corners[face[index]])
	tool.generate_normals()
	var part := MeshInstance3D.new()
	part.mesh = tool.commit()
	part.material_override = material
	part.position = at
	host.add_child(part)


static func _wheel(
	host: Node3D, at: Vector3, tyre: StandardMaterial3D, rim: StandardMaterial3D
) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = WHEEL_RADIUS
	cylinder.bottom_radius = WHEEL_RADIUS
	cylinder.height = WHEEL_WIDTH
	var wheel := MeshInstance3D.new()
	wheel.mesh = cylinder
	wheel.material_override = tyre
	wheel.rotation.x = PI * 0.5
	wheel.position = at
	host.add_child(wheel)
	var disc := CylinderMesh.new()
	disc.top_radius = WHEEL_RADIUS * 0.55
	disc.bottom_radius = WHEEL_RADIUS * 0.55
	disc.height = WHEEL_WIDTH + 0.02
	var hub := MeshInstance3D.new()
	hub.mesh = disc
	hub.material_override = rim
	hub.rotation.x = PI * 0.5
	hub.position = at
	host.add_child(hub)
