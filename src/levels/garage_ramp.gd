class_name GarageRamp
extends Node3D

## Выезд из паркинга за воротами: пандус наверх и то, что вокруг него
## (ADR-0038, решение 3).
##
## До M24b пандус лежал за краем кадра — камера здания туда не заходила, — и
## хватало голой плиты. С выезда кадр раздвигается влево за торец
## ([method ExitBoarding.exit_frame]), и машина уезжает у всех на виду: голая
## плита в тёмной пустоте читалась недостроем. Поэтому выезд собран разрезом,
## как само здание: грунт под пандусом и под улицей, подпорная стена за
## пандусом с парапетом, улица наверху с бордюром, фонарь над въездом и
## нижние этажи соседнего дома за улицей — он закрывает пустоту между улицей
## и городом на заднике.
##
## Вид, без тел: Otto сюда не выходит, машина — вид без тела — проезжает.

## Грунт: сколько его под полом подвала, м, — до низа любого кадра, — и сколько
## улицы левее верха пандуса, м, — до края самого широкого кадра.
const SOIL_DEPTH: float = 6.0
const STREET: float = 16.0
## Подпорная стена за пандусом: толщина и насколько парапет выше улицы, м.
const WALL_THICKNESS: float = 0.24
const PARAPET: float = 0.9
## Асфальт улицы и бордюр у разреза: толщина асфальта, сечение бордюра, м.
const ASPHALT: float = 0.1
const CURB := Vector2(0.18, 0.16)
## Фонарь над въездом: высота столба над улицей, вылет консоли, м, и свет —
## натриевый, как свет за шторой ворот ([constant GarageGate.OUTSIDE]). Без
## тени: источник один на здание и только в кадре выезда.
const LAMP_HEIGHT: float = 2.4
const LAMP_ARM: float = 1.4
const LAMP_RANGE: float = 8.0
const LAMP_ENERGY: float = 4.0
## Подпорная стена: шаг деформационных швов, м, и светильники-«бочонки» на
## ней вдоль подъёма — эмиссия, не источники: высота над проездом и шаг, м.
const JOINT_STEP: float = 3.0
const BULKHEAD := Vector3(0.34, 0.16, 0.08)
const BULKHEAD_RISE: float = 1.9
const BULKHEAD_STEP: float = 4.0
## Соседний дом за улицей: насколько он за плоскостью игры, м, высота фасада
## над улицей, м, шаг витрин, м, витрина, окно второго этажа и вывеска над
## витриной, м. Свет в окнах — тусклый, тёплый: дом живёт, но не спорит с
## выездом.
const NEIGHBOUR_Z: float = -4.2
const NEIGHBOUR_HEIGHT: float = 5.6
const SHOP_STEP: float = 3.4
const SHOP := Vector2(2.3, 1.9)
const WINDOW := Vector2(0.9, 1.1)
const SHOP_SIGN := Vector2(1.5, 0.26)
## Цоколь витрины и маркиза над ней, м.
const RISER: float = 0.45
const AWNING := Vector3(2.6, 0.12, 0.7)
const CORNICE_RISE: float = 2.75
const FRAME: float = 0.07

const SOIL := Color(0.085, 0.075, 0.068)
const SOIL_CUT := Color(0.16, 0.13, 0.11)
const ASPHALT_TONE := Color(0.07, 0.07, 0.08)
const KERB := Color(0.5, 0.5, 0.48)
const BRICK := Color(0.14, 0.095, 0.09)
const STONE := Color(0.32, 0.3, 0.28)
const WINDOW_FRAME := Color(0.04, 0.04, 0.05)
const WINDOW_DARK := Color(0.05, 0.06, 0.08)
const WINDOW_LIT := Color(0.36, 0.23, 0.12)
const AWNING_TONE := Color(0.32, 0.07, 0.07)
const BULKHEAD_GLOW := Color(1.0, 0.8, 0.55)
const SHUTTER := Color(0.26, 0.27, 0.29)
const NEON_SIGNS: Array[Color] = [Color(0.1, 0.7, 0.65), Color(0.85, 0.2, 0.3)]
const POLE := Color(0.16, 0.17, 0.19)

var _rules: BuildingRules = null
## Пол подвала и улица, в плоскости правил; торец здания; ширина проезда.
var _surface: float = 0.0
var _street: float = 0.0
var _left: float = 0.0
var _width: float = 0.0
var _light: OmniLight3D = null


## Собирает выезд у левого торца нижнего этажа.
func build(rules: BuildingRules) -> void:
	name = "Ramp"
	_rules = rules
	_surface = rules.floor_surface(rules.floors - 1)
	_street = _surface - rules.floor_height
	_left = rules.floor_span(rules.floors - 1).x
	_width = WorldSpace.CORRIDOR_DEPTH + 0.4
	_build_slabs()
	_build_soil()
	_build_street()
	_build_wall()
	_build_lamp()
	_build_neighbour()


## Зажигает или гасит фонарь: источник горит, пока выезд может быть в кадре.
func show_light(on: bool) -> void:
	if _light != null:
		_light.visible = on


## Левый конец подъёма — верх пандуса, в плоскости правил.
func top_x() -> float:
	return _left - GarageGate.RAMP_APRON - GarageGate.RAMP_RUN


## Площадка у проёма и подъём влево на этаж. По подъёму уезжает машина
## ([method ExitCar._climb]).
func _build_slabs() -> void:
	var concrete := BuildingFinish.shaft_concrete(Garage.CONCRETE)
	var thickness := _rules.slab_height
	var apron := GarageGate.RAMP_APRON
	var run := GarageGate.RAMP_RUN
	_box(
		Vector3(apron, thickness, _width),
		concrete,
		_at(_left - apron * 0.5, _surface + thickness * 0.5, 0.0)
	)
	var rise := _rules.floor_height
	var slope := Vector2(run, rise).length()
	var incline := _box(Vector3(slope, thickness, _width), concrete, Vector3.ZERO)
	incline.rotation.z = -atan2(rise, run)
	incline.position = _at(_left - apron - run * 0.5, _surface - rise * 0.5 + thickness * 0.5, 0.0)


## Грунт разрезом: клин под подъёмом и пласт под всем выездом. Лицо разреза —
## вровень с проездом, как у плит здания; кромка разреза светлее.
func _build_soil() -> void:
	var soil := GreyboxLook.surface(SOIL)
	var run := GarageGate.RAMP_RUN
	var rise := _rules.floor_height
	var depth := _width + 1.0
	var z := _width * 0.5 - depth * 0.5
	# Клин: высокая сторона слева, у верха пандуса. Чуть ниже плиты, чтобы грани
	# не легли в одну плоскость.
	var prism := PrismMesh.new()
	prism.size = Vector3(run, rise - _rules.slab_height, depth)
	prism.left_to_right = 0.0
	var wedge := MeshInstance3D.new()
	wedge.name = "Wedge"
	wedge.mesh = prism
	wedge.material_override = soil
	wedge.position = _at(
		_left - GarageGate.RAMP_APRON - run * 0.5,
		_surface - (rise - _rules.slab_height) * 0.5 + _rules.slab_height * 0.5,
		z
	)
	add_child(wedge)
	var span := GarageGate.RAMP_APRON + run + STREET
	_box(
		Vector3(span, SOIL_DEPTH, depth),
		soil,
		_at(_left - span * 0.5, _surface + _rules.slab_height + SOIL_DEPTH * 0.5, z)
	)
	# Кромка разреза под полом подвала: светлая полоса, как торец плиты.
	_box(
		Vector3(span, 0.05, 0.01),
		GreyboxLook.surface(SOIL_CUT),
		_at(_left - span * 0.5, _surface + _rules.slab_height + 0.025, _width * 0.5 + 0.005),
		false
	)


## Улица левее верха пандуса: грунт до пола подвала, асфальт и бордюр.
func _build_street() -> void:
	var soil := GreyboxLook.surface(SOIL)
	var right := top_x()
	var depth := _width + 1.0
	var z := _width * 0.5 - depth * 0.5
	var fill := _surface + _rules.slab_height - _street
	_box(
		Vector3(STREET, fill - ASPHALT, depth),
		soil,
		_at(right - STREET * 0.5, _street + ASPHALT + (fill - ASPHALT) * 0.5, z)
	)
	_box(
		Vector3(STREET, ASPHALT, depth),
		GreyboxLook.polished(ASPHALT_TONE),
		_at(right - STREET * 0.5, _street + ASPHALT * 0.5, z)
	)
	_box(
		Vector3(STREET, CURB.y, CURB.x),
		GreyboxLook.surface(KERB),
		_at(right - STREET * 0.5, _street - CURB.y * 0.5 + 0.02, _width * 0.5 - CURB.x * 0.5)
	)
	# Кромка разреза под асфальтом.
	_box(
		Vector3(STREET, 0.05, 0.01),
		GreyboxLook.surface(SOIL_CUT),
		_at(right - STREET * 0.5, _street + ASPHALT + 0.025, _width * 0.5 + 0.005),
		false
	)


## Подпорная стена за пандусом: от пола подвала до парапета над улицей.
func _build_wall() -> void:
	var concrete := BuildingFinish.shaft_concrete(Garage.CONCRETE.darkened(0.25))
	var right := _left
	var left := top_x()
	var top := _street - PARAPET
	var height := _surface - top
	_box(
		Vector3(right - left, height, WALL_THICKNESS),
		concrete,
		_at((left + right) * 0.5, top + height * 0.5, -_width * 0.5 - WALL_THICKNESS * 0.5)
	)
	# Отлив парапета — светлая полоса по верху.
	_box(
		Vector3(right - left, 0.06, WALL_THICKNESS + 0.08),
		GreyboxLook.surface(KERB),
		_at((left + right) * 0.5, top - 0.03, -_width * 0.5 - WALL_THICKNESS * 0.5),
		false
	)
	var face := -_width * 0.5 + 0.005
	var joint := GreyboxLook.surface(Garage.CONCRETE.darkened(0.7))
	var x := right - JOINT_STEP
	while x > left:
		_box(Vector3(0.03, height, 0.01), joint, _at(x, top + height * 0.5, face), false)
		x -= JOINT_STEP
	# Светильники над проездом идут вдоль подъёма: каждый на своей высоте над ним.
	var start := _left - GarageGate.RAMP_APRON
	x = _left - 1.2
	while x > left + 0.5:
		var along := clampf((start - x) / GarageGate.RAMP_RUN, 0.0, 1.0)
		var ground := _surface - _rules.floor_height * along
		_box(
			BULKHEAD,
			GreyboxLook.light(BULKHEAD_GLOW),
			_at(x, ground - BULKHEAD_RISE, face + BULKHEAD.z * 0.5),
			false
		)
		x -= BULKHEAD_STEP


## Фонарь над подъёмом: столб на парапете подпорной стены, консоль над
## проездом. Там, где машина идёт в гору, — светлее всего.
func _build_lamp() -> void:
	var pole_x := _left - GarageGate.RAMP_APRON - GarageGate.RAMP_RUN * 0.3
	var pole_z := -_width * 0.5 - WALL_THICKNESS * 0.5
	var base := _street - PARAPET
	var metal := GreyboxLook.metal(POLE)
	_box(Vector3(0.12, LAMP_HEIGHT, 0.12), metal, _at(pole_x, base - LAMP_HEIGHT * 0.5, pole_z))
	_box(
		Vector3(0.08, 0.08, LAMP_ARM),
		metal,
		_at(pole_x, base - LAMP_HEIGHT, pole_z + LAMP_ARM * 0.5)
	)
	var head_z := pole_z + LAMP_ARM
	_box(
		Vector3(0.3, 0.12, 0.5),
		GreyboxLook.light(GarageGate.OUTSIDE),
		_at(pole_x, base - LAMP_HEIGHT + 0.08, head_z),
		false
	)
	_light = OmniLight3D.new()
	_light.name = "StreetLight"
	_light.light_color = GarageGate.OUTSIDE
	_light.light_energy = LAMP_ENERGY
	_light.omni_range = LAMP_RANGE
	_light.shadow_enabled = false
	_light.position = _at(pole_x, base - LAMP_HEIGHT + 0.3, head_z)
	add_child(_light)


## Нижние этажи дома за улицей: кирпич, карниз, витрины у тротуара — одни
## горят, другие закрыты шторами, — вывески и окна второго этажа.
func _build_neighbour() -> void:
	var right := _left
	var left := top_x() - STREET
	_box(
		Vector3(right - left, NEIGHBOUR_HEIGHT, 0.3),
		GreyboxLook.surface(BRICK),
		_at((left + right) * 0.5, _street - NEIGHBOUR_HEIGHT * 0.5, NEIGHBOUR_Z - 0.15)
	)
	for rise: float in [CORNICE_RISE, NEIGHBOUR_HEIGHT - 0.12]:
		_box(
			Vector3(right - left, 0.22, 0.14),
			GreyboxLook.surface(STONE),
			_at((left + right) * 0.5, _street - rise, NEIGHBOUR_Z + 0.07)
		)
	var face := NEIGHBOUR_Z + 0.01
	var index := 0
	var x := right - SHOP_STEP * 0.5
	while x > left + SHOP_STEP * 0.5:
		var shop_y := _street - RISER - SHOP.y * 0.5
		var lit := index % 3 != 1
		_pane(Vector2(x, shop_y), SHOP, face, WINDOW_LIT if lit else SHUTTER, lit)
		if index % 2 == 0:
			_box(
				AWNING,
				GreyboxLook.surface(AWNING_TONE),
				_at(x, shop_y - SHOP.y * 0.5 - 0.12, face + AWNING.z * 0.5)
			)
		if lit:
			_box(
				Vector3(0.05, SHOP.y, 0.03),
				GreyboxLook.surface(WINDOW_FRAME),
				_at(x, shop_y, face + 0.03),
				false
			)
			_box(
				Vector3(SHOP_SIGN.x, SHOP_SIGN.y, 0.04),
				GreyboxLook.marker(NEON_SIGNS[index % NEON_SIGNS.size()]),
				_at(x, _street - RISER - SHOP.y - 0.45, face + 0.02),
				false
			)
		for offset: float in [-0.8, 0.8]:
			var upper_lit := (index * 2 + int(offset > 0.0)) % 5 == 2
			_pane(
				Vector2(x + offset, _street - CORNICE_RISE - 0.45 - WINDOW.y * 0.5),
				WINDOW,
				face,
				WINDOW_LIT if upper_lit else WINDOW_DARK,
				upper_lit
			)
		index += 1
		x -= SHOP_STEP


## Окно фасада: тёмная рама и стекло в ней — светится, если [param lit].
func _pane(centre: Vector2, size: Vector2, face: float, tone: Color, lit: bool) -> void:
	_box(
		Vector3(size.x + FRAME * 2.0, size.y + FRAME * 2.0, 0.02),
		GreyboxLook.surface(WINDOW_FRAME),
		_at(centre.x, centre.y, face),
		false
	)
	_box(
		Vector3(size.x, size.y, 0.02),
		GreyboxLook.marker(tone) if lit else GreyboxLook.metal(tone),
		_at(centre.x, centre.y, face + 0.012),
		false
	)


func _at(x: float, y: float, z: float) -> Vector3:
	return Garage.scene_point(x, y, z)


func _box(
	size: Vector3, material: StandardMaterial3D, centre: Vector3, shadow: bool = true
) -> MeshInstance3D:
	return Garage.put_box(self, size, material, centre, shadow)
