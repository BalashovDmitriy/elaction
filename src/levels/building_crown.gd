class_name BuildingCrown
extends Node3D

## Высокая корона над крышей по типу здания (ADR-0058, решение 2).
##
## Отель — ступенчатая корона ар-деко из светлого камня с неоновыми гранями,
## веером лучей и шпилем; офис — стеклянная вершина со срезом и антенной-мачтой;
## жилой дом — деревянный бак на высоких опорах над кирпичной будкой выхода.
##
## Корона стоит за плоскостью игры, у задней стены здания: Otto ходит по
## настилу перед ней, вертолёт висит у коридора ([constant Helicopter.DEPTH_Z])
## и облетает её по общему правилу препятствий ([method
## RoofArrival.roof_obstacles]). Поэтому части — отдельные меши, а не мультимеш:
## мультимеш правило не видит. Тел и источников света нет — неон светится
## эмиссией и днём погашен, как вывеска ([method TimeOfDay.sign_lit]).
##
## Координаты: x — вдоль крыши, высота — над настилом, z — сцены.

## Глубина короны и её задняя грань, м: от задней стены здания вперёд, но не
## ближе [constant FRONT_Z] — дальше размаха винта вертолёта.
const BACK_Z: float = WorldSpace.BACK_WALL_Z - WorldSpace.ROOM_DEPTH + 0.05
const FRONT_Z: float = WorldSpace.BACK_WALL_Z - 5.3
const DEPTH: float = FRONT_Z - BACK_Z

## Отель: доля ширины кровли под основанием, ступени (доля ширины основания,
## высота, м), шпиль.
const HOTEL_SHARE: float = 0.6
const HOTEL_TIERS: Array[Vector2] = [
	Vector2(1.0, 1.7), Vector2(0.78, 1.5), Vector2(0.56, 1.3), Vector2(0.36, 1.1), Vector2(0.2, 0.9)
]
const SPIRE := Vector2(0.18, 3.4)
const STONE := Color(0.64, 0.58, 0.48)
const STONE_SHADE := Color(0.42, 0.37, 0.3)
const BRASS := Color(0.78, 0.6, 0.3)
const NEON_STRIP: float = 0.07
const RAYS: int = 9

## Офис: доля ширины кровли, высота стеклянного объёма и среза, мачта.
const OFFICE_SHARE: float = 0.66
const OFFICE_GLASS_HEIGHT: float = 2.6
const OFFICE_SLOPE: float = 3.2
const MAST := Vector2(0.09, 6.0)
const OFFICE_GLASS := Color(0.08, 0.12, 0.18)
const MULLION := Color(0.55, 0.58, 0.62)
const MULLION_STEP: float = 1.1
const OFFICE_LIGHTS := Color(0.85, 0.9, 1.0)
const BEACON := Color(1.0, 0.15, 0.1)

## Жилой дом: будка выхода, опоры и бак.
const BULKHEAD := Vector3(2.6, 2.3, 1.6)
const BRICK := Color(0.46, 0.24, 0.17)
const LEG_HEIGHT: float = 3.2
const TANK := Vector2(1.35, 2.6)
const TANK_ROOF: float = 1.0
const WOOD := Color(0.42, 0.29, 0.18)
const HOOP := Color(0.16, 0.15, 0.14)
const IRON := Color(0.2, 0.2, 0.21)

var _surface: float = 0.0
var _lit: bool = true
var _neon := Color.WHITE
## Огонь на мачте офиса — мигает, как огонь антенны крыши ([RoofKit]); null у
## других типов.
var _beacon: MeshInstance3D = null
var _clock: float = 0.0


## Ставит корону здания: по типу из [member BuildingRules.kind], по ширине
## кровли и времени суток.
func build(rules: BuildingRules) -> void:
	name = "Crown"
	_surface = rules.floor_surface(BuildingRules.ROOF)
	_lit = TimeOfDay.sign_lit(rules.time_of_day)
	_neon = VerticalSign.neon_of(BuildingIdentity.typed(rules.kind))
	var bounds := rules.floor_span(BuildingRules.ROOF)
	var inner := Vector2(bounds.x + BuildingShell.WALL_WIDTH, bounds.y - BuildingShell.WALL_WIDTH)
	var middle := (inner.x + inner.y) * 0.5
	var width := inner.y - inner.x
	match rules.kind:
		BuildingIdentity.Kind.OFFICE:
			_office(middle, width * OFFICE_SHARE)
		BuildingIdentity.Kind.RESIDENTIAL:
			_residential(middle, width)
		_:
			_hotel(middle, width * HOTEL_SHARE)
	set_process(_beacon != null)


## Мигает огнём мачты тем же ритмом, что огонь антенны крыши. Картинка, а не
## правило: по настенным часам.
func _process(delta: float) -> void:
	_clock = fmod(_clock + delta, RoofKit.BEACON_PERIOD)
	_beacon.visible = _clock < RoofKit.BEACON_PERIOD * RoofKit.BEACON_ON


## Высота верха короны над настилом, м: тестам и кадру вступления.
func top() -> float:
	var highest := 0.0
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box := mesh.transform * mesh.mesh.get_aabb()
		highest = maxf(highest, box.end.y - WorldSpace.to_scene(Vector2(0.0, _surface)).y)
	return highest


## Ступени ар-деко: каждая уже предыдущей, по краям — неоновые грани, на
## второй — веер лучей, наверху шпиль.
func _hotel(middle: float, base: float) -> void:
	var stone := GreyboxLook.surface(STONE)
	var shade := GreyboxLook.surface(STONE_SHADE)
	var neon := _neon_look()
	var rise := 0.0
	for tier: int in HOTEL_TIERS.size():
		var width := base * HOTEL_TIERS[tier].x
		var height := HOTEL_TIERS[tier].y
		_box(stone, Vector3(width, height, DEPTH), middle, rise, BACK_Z + DEPTH * 0.5)
		# Карниз ступени — тёмная полоса, чтобы ступени читались и днём.
		_box(
			shade,
			Vector3(width + 0.12, 0.12, DEPTH + 0.1),
			middle,
			rise + height,
			BACK_Z + DEPTH * 0.5
		)
		for side: float in [-1.0, 1.0]:
			_box(
				neon,
				Vector3(NEON_STRIP, height * 0.9, NEON_STRIP),
				middle + side * (width * 0.5 - NEON_STRIP),
				rise + height * 0.05,
				FRONT_Z + NEON_STRIP * 0.5
			)
		if tier == 1:
			_rays(middle, rise + height, width * 0.42, neon)
		rise += height + 0.12
	var spire := CylinderMesh.new()
	spire.top_radius = 0.01
	spire.bottom_radius = SPIRE.x
	spire.height = SPIRE.y
	spire.radial_segments = 8
	_mesh(spire, GreyboxLook.metal(BRASS), middle, rise, BACK_Z + DEPTH * 0.5)


## Веер лучей над ступенью: тонкие планки из одной точки, как солнце ар-деко.
func _rays(middle: float, bottom: float, reach: float, look: Material) -> void:
	for ray: int in RAYS:
		var angle := lerpf(-PI * 0.42, PI * 0.42, float(ray) / float(RAYS - 1))
		var length := reach * (0.75 if ray % 2 == 1 else 1.0)
		var part := GreyboxLook.box(Vector3(0.05, length, 0.04), look as StandardMaterial3D)
		part.rotation.z = -angle
		var direction := Vector3(sin(angle), cos(angle), 0.0)
		var base := _at(middle, bottom - 1.2, FRONT_Z + 0.03)
		part.position = base + direction * length * 0.5
		_add(part)


## Стеклянная вершина офиса: объём в стекле с переплётом и полосами света,
## над ним — срез клином, на высоком краю мачта с огнём.
func _office(middle: float, width: float) -> void:
	var glass := GreyboxLook.polished(OFFICE_GLASS)
	var frame := GreyboxLook.metal(MULLION)
	var z := BACK_Z + DEPTH * 0.5
	_box(glass, Vector3(width, OFFICE_GLASS_HEIGHT, DEPTH), middle, 0.0, z)
	var count := int(width / MULLION_STEP)
	for step: int in count + 1:
		var x := middle - width * 0.5 + width * float(step) / float(maxi(count, 1))
		_box(frame, Vector3(0.05, OFFICE_GLASS_HEIGHT, 0.05), x, 0.0, FRONT_Z + 0.03)
	for row: float in [0.8, 1.7]:
		var band := GreyboxLook.light(OFFICE_LIGHTS) if _lit else frame
		_box(band, Vector3(width - 0.2, 0.08, 0.02), middle, row, FRONT_Z + 0.04)
	var wedge := PrismMesh.new()
	wedge.left_to_right = 1.0
	wedge.size = Vector3(width, OFFICE_SLOPE, DEPTH)
	_mesh(wedge, glass, middle, OFFICE_GLASS_HEIGHT, z)
	# Кромка среза — светлая планка вдоль ската: силуэт читается и ночью.
	var edge := GreyboxLook.box(
		Vector3(Vector2(width, OFFICE_SLOPE).length(), 0.06, 0.06), _neon_look()
	)
	edge.rotation.z = atan2(OFFICE_SLOPE, width)
	edge.position = _at(middle, OFFICE_GLASS_HEIGHT + OFFICE_SLOPE * 0.5, FRONT_Z + 0.05)
	_add(edge)
	var mast_x := middle + width * 0.5 - 0.4
	var mast := CylinderMesh.new()
	mast.top_radius = MAST.x * 0.5
	mast.bottom_radius = MAST.x
	mast.height = MAST.y
	mast.radial_segments = 6
	var mast_base := OFFICE_GLASS_HEIGHT + OFFICE_SLOPE - 0.3
	_mesh(mast, GreyboxLook.metal(MULLION), mast_x, mast_base, z)
	for bar: int in 3:
		_box(frame, Vector3(0.9 - bar * 0.25, 0.04, 0.04), mast_x, mast_base + 1.4 + bar * 1.3, z)
	var tip := SphereMesh.new()
	tip.radius = 0.14
	tip.height = 0.28
	_beacon = _mesh(tip, GreyboxLook.light(BEACON), mast_x, mast_base + MAST.y, z)


## Жилой дом: кирпичная будка выхода на крышу, рядом бак на опорах с обручами
## и конусной крышей, лесенка.
func _residential(middle: float, width: float) -> void:
	var brick := GreyboxLook.surface(BRICK)
	var iron := GreyboxLook.metal(IRON)
	var wood := GreyboxLook.surface(WOOD)
	var z := BACK_Z + DEPTH * 0.5
	var head_x := middle - width * 0.22
	_box(brick, Vector3(BULKHEAD.x, BULKHEAD.y, DEPTH), head_x, 0.0, z)
	_box(
		GreyboxLook.surface(BRICK.darkened(0.3)),
		Vector3(BULKHEAD.x + 0.15, 0.15, DEPTH + 0.1),
		head_x,
		BULKHEAD.y,
		z
	)
	var tank_x := middle + width * 0.12
	var spread := TANK.x * 0.8
	# Бак шире глубины короны: его середина отодвинута назад, чтобы передний
	# край не вышел к винту ([constant FRONT_Z]); задний уходит за здание.
	var tank_z := FRONT_Z - TANK.x * 1.12
	for side: float in [-1.0, 1.0]:
		var leg := CylinderMesh.new()
		leg.top_radius = 0.07
		leg.bottom_radius = 0.07
		leg.height = LEG_HEIGHT
		leg.radial_segments = 6
		_mesh(leg, iron, tank_x + side * spread, 0.0, tank_z)
	for brace: float in [0.9, 2.1]:
		_box(iron, Vector3(spread * 2.0, 0.06, 0.06), tank_x, brace, z)
	_box(iron, Vector3(TANK.x * 2.3, 0.12, DEPTH * 0.9), tank_x, LEG_HEIGHT, z)
	var barrel := CylinderMesh.new()
	barrel.top_radius = TANK.x
	barrel.bottom_radius = TANK.x * 1.04
	barrel.height = TANK.y
	barrel.radial_segments = 16
	_mesh(barrel, wood, tank_x, LEG_HEIGHT + 0.12, tank_z)
	for hoop: int in 4:
		var ring := CylinderMesh.new()
		ring.top_radius = TANK.x + 0.04
		ring.bottom_radius = TANK.x + 0.04
		ring.height = 0.07
		ring.radial_segments = 16
		_mesh(ring, GreyboxLook.metal(HOOP), tank_x, LEG_HEIGHT + 0.4 + hoop * 0.6, tank_z)
	var cap := CylinderMesh.new()
	cap.top_radius = 0.05
	cap.bottom_radius = TANK.x * 1.1
	cap.height = TANK_ROOF
	cap.radial_segments = 16
	_mesh(cap, GreyboxLook.surface(WOOD.darkened(0.35)), tank_x, LEG_HEIGHT + 0.12 + TANK.y, tank_z)
	for rung: int in 9:
		_box(iron, Vector3(0.4, 0.03, 0.03), tank_x - TANK.x - 0.3, 0.3 + rung * 0.35, FRONT_Z)
	for side: float in [-0.2, 0.2]:
		_box(iron, Vector3(0.03, LEG_HEIGHT, 0.03), tank_x - TANK.x - 0.3 + side, 0.0, FRONT_Z)


## Неон короны: светится ночью и в сумерках, днём — погашенная трубка.
func _neon_look() -> StandardMaterial3D:
	if _lit:
		return GreyboxLook.light(_neon)
	return GreyboxLook.surface(VerticalSign.unlit_tube(_neon))


## Коробка размером [param size] низом на высоте [param rise] над настилом.
func _box(material: Material, size: Vector3, x: float, rise: float, z: float) -> void:
	var part := GreyboxLook.box(size, material as StandardMaterial3D)
	part.position = _at(x, rise + size.y * 0.5, z)
	_add(part)


## Меш низом на высоте [param rise]: у цилиндров, конусов и клиньев нуль — в
## середине, и он поднимается на половину высоты.
func _mesh(
	mesh: PrimitiveMesh, material: Material, x: float, rise: float, z: float
) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	var half := mesh.get_aabb().size.y * 0.5
	part.position = _at(x, rise + half, z)
	_add(part)
	return part


func _at(x: float, rise: float, z: float) -> Vector3:
	var place := WorldSpace.to_scene(Vector2(x, _surface - rise))
	place.z = z
	return place


func _add(part: MeshInstance3D) -> void:
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.layers = PropCatalog.RENDER_LAYER
	add_child(part)
