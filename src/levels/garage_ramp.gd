class_name GarageRamp
extends Node3D

## Выезд из паркинга за воротами: тоннель, пандус наверх и улица (ADR-0038,
## решение 3).
##
## С посадки кадр раздвигается влево за торец ([method ExitBoarding.exit_frame])
## и едет за машиной вверх по пандусу до улицы. Первый вариант — голая
## подпорная стена на полкадра, три лампы и плоские дома — был на кадрах ниже
## всей игры. Теперь выезд собран, как само здание, разрезом:
##
## - за воротами — **тоннель**: низкий потолок с люминесцентными светильниками,
##   пятна их света на пандусе и на стене, кабельный лоток, спринклерная труба,
##   отбойник в жёлто-чёрную полосу и стрелка EXIT краской на стене;
## - дальше пандус выходит в **открытую рампу**: подпорная стена литого бетона
##   (щиты, стяжки, потёки — [code]street_concrete.gdshader[/code]), поверху
##   ограждение, светильники-«бочонки» и водосток;
## - наверху — **улица** ([ExitStreet]): мостовая, фонарь над въездом и ряд
##   домов через дорогу; тротуар идёт над тоннелем;
## - под всем — грунт разрезом, с пластами.
##
## Свет: фонарь над въездом — один источник без тени, и горит он, только пока
## выезд в кадре ([method show_light]); остальное — эмиссия и пятна.
##
## Вид, без тел: Otto сюда не выходит, машина — вид без тела — проезжает.

## Грунт под полом подвала, м, — до низа любого кадра.
const SOIL_DEPTH: float = 6.0
## Тоннель: сколько пандуса от ворот накрыто потолком, м. Дальше потолок
## задевал бы крышу машины: пол пандуса поднимается, а потолок — нет.
const TUNNEL: float = 5.0
## Подпорная стена: толщина, м.
const WALL_THICKNESS: float = 0.24
## Тротуар над тоннелем и вдоль рампы: насколько выше мостовой, м.
const KERB: float = 0.15
## Ограждение рампы: высота над тротуаром, шаг стоек, м.
const RAIL_HEIGHT: float = 1.0
const RAIL_STEP: float = 1.25
## Фонарь над въездом: высота столба над тротуаром, вынос консоли, м, и свет —
## натриевый, как свет за шторой ворот ([constant GarageGate.OUTSIDE]).
const LAMP_HEIGHT: float = 4.6
const LAMP_ARM: float = 1.0
const LAMP_RANGE: float = 11.0
const LAMP_ENERGY: float = 9.0
## Где стоит фонарь — левее торца, м: в кадре и на въезде, и на улице.
const LAMP_FROM_WALL: float = 7.0
## Светильники тоннеля: шаг от ворот, длина трубки, м, и пятна их света.
const TUBE_STEP: float = 1.6
const TUBE := Vector3(1.1, 0.04, 0.1)
const WASH := Vector2(2.0, 2.2)
const WASH_ENERGY: float = 0.18
const POOL_ENERGY: float = 0.24
## Светильники-«бочонки» на стене рампы: размер, высота над проездом и шаг, м.
const BULKHEAD := Vector3(0.34, 0.16, 0.08)
const BULKHEAD_RISE: float = 1.5
const BULKHEAD_STEP: float = 3.0
## Отбойник у стены: высота и глубина, м.
const BUMPER := Vector2(0.14, 0.14)

const SOIL := Color(0.12, 0.105, 0.095)
const SOIL_CUT := Color(0.16, 0.13, 0.11)
const WALL_TONE := Color(0.5, 0.5, 0.49)
const PAVEMENT := Color(0.22, 0.22, 0.23)
const KERB_TONE := Color(0.42, 0.42, 0.4)
const RAIL := Color(0.36, 0.37, 0.39)
const TRAY := Color(0.4, 0.41, 0.43)
const CABLE := Color(0.03, 0.03, 0.035)
const BULKHEAD_GLOW := Color(1.0, 0.8, 0.55)
const POLE := Color(0.16, 0.17, 0.19)
const WALL_PAINT := Color(0.78, 0.78, 0.74)

var _rules: BuildingRules = null
## Пол подвала и улица, в плоскости правил; торец здания; ширина проезда.
var _surface: float = 0.0
var _street: float = 0.0
var _left: float = 0.0
var _width: float = 0.0
var _weather: Weather.Kind = Weather.Kind.CLEAR
var _light: OmniLight3D = null
var _street_node: ExitStreet = null


## Собирает выезд у левого торца нижнего этажа.
func build(rules: BuildingRules, building_seed: int = 1) -> void:
	name = "Ramp"
	_rules = rules
	_surface = rules.floor_surface(rules.floors - 1)
	_street = _surface - rules.floor_height
	_left = rules.floor_span(rules.floors - 1).x
	_width = WorldSpace.CORRIDOR_DEPTH + 0.4
	_weather = Weather.of_seed(building_seed)
	_street_node = ExitStreet.new()
	add_child(_street_node)
	_street_node.build(_left, _street, building_seed, _weather)
	_build_slabs()
	_build_soil()
	_build_street_edge()
	_build_tunnel()
	_build_open_ramp()
	_build_lamp()


## Зажигает или гасит свет выезда: горит, пока выезд в кадре.
func show_light(on: bool) -> void:
	if _light != null:
		_light.visible = on
	if _street_node != null:
		_street_node.show_light(on)


## Настоящие источники выезда — для тестов бюджета.
func lights() -> Array[Light3D]:
	var found: Array[Light3D] = []
	if _light != null:
		found.append(_light)
	if _street_node != null:
		found.append_array(_street_node.lights())
	return found


## Левый конец подъёма — верх пандуса, в плоскости правил.
func top_x() -> float:
	return _left - GarageGate.RAMP_APRON - GarageGate.RAMP_RUN


## Высота проезда над полом подвала в [param x], м: площадка у ворот, подъём,
## улица.
static func climb_at(rules: BuildingRules, x: float) -> float:
	var start := rules.floor_span(rules.floors - 1).x - GarageGate.RAMP_APRON
	return rules.floor_height * clampf((start - x) / GarageGate.RAMP_RUN, 0.0, 1.0)


## Где кончается потолок тоннеля, в плоскости правил.
func mouth_x() -> float:
	return _left - TUNNEL


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
	var incline := _slope(Vector3(0.0, thickness, _width), concrete, 0.0, thickness * 0.5)
	incline.name = "Incline"
	# Отбойник у стены: жёлтый, с чёрными торцами на площадке.
	var yellow := GreyboxLook.surface(Garage.PAINT_YELLOW)
	var black := GreyboxLook.surface(Garage.PAINT_BLACK)
	var bumper_z := -_width * 0.5 + BUMPER.y * 0.5
	var x := _left - 0.25
	var index := 0
	while x > _left - apron + 0.2:
		_box(
			Vector3(0.5, BUMPER.x, BUMPER.y),
			yellow if index % 2 == 0 else black,
			_at(x, _surface - BUMPER.x * 0.5, bumper_z),
			false
		)
		x -= 0.5
		index += 1
	_slope(Vector3(0.0, BUMPER.x, BUMPER.y), yellow, bumper_z, -BUMPER.x * 0.5)


## Наклонная коробка вдоль подъёма: во всю его длину, [param size] — толщина и
## глубина (x не в счёт), [param z] — середина по глубине, [param lift] —
## насколько середина ниже (+) или выше (−) поверхности пандуса.
func _slope(size: Vector3, material: Material, z: float, lift: float) -> MeshInstance3D:
	var run := GarageGate.RAMP_RUN
	var rise := _rules.floor_height
	var part := _box(
		Vector3(Vector2(run, rise).length(), size.y, size.z), material, Vector3.ZERO, false
	)
	var angle := atan2(rise, run)
	part.rotation.z = -angle
	var middle := _left - GarageGate.RAMP_APRON - run * 0.5
	# Сдвиг от поверхности — по нормали к подъёму, а не по вертикали.
	var normal := Vector2(sin(angle), cos(angle))
	var centre := Vector2(middle, _surface - rise * 0.5) + normal * lift * Vector2(-1.0, 1.0)
	part.position = _at(centre.x, centre.y, z)
	return part


## Грунт разрезом: клин под подъёмом и пласт под всем выездом. Лицо разреза —
## вровень с проездом, как у плит здания; кромка разреза светлее.
func _build_soil() -> void:
	var soil := _soil()
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
	wedge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wedge.position = _at(
		_left - GarageGate.RAMP_APRON - run * 0.5,
		_surface - (rise - _rules.slab_height) * 0.5 + _rules.slab_height * 0.5,
		z
	)
	add_child(wedge)
	var span := ExitStreet.FROM
	_box(
		Vector3(span, SOIL_DEPTH, depth),
		soil,
		_at(_left - span * 0.5, _surface + _rules.slab_height + SOIL_DEPTH * 0.5, z)
	)
	# Под улицей левее пандуса — грунт до асфальта.
	var street_span := span - GarageGate.RAMP_APRON - run
	var fill := _surface + _rules.slab_height - _street - ExitStreet.ASPHALT
	_box(
		Vector3(street_span, fill, depth),
		soil,
		_at(top_x() - street_span * 0.5, _street + ExitStreet.ASPHALT + fill * 0.5, z)
	)
	# Кромка разреза под полом подвала: светлая полоса, как торец плиты.
	_box(
		Vector3(span, 0.05, 0.01),
		GreyboxLook.surface(SOIL_CUT),
		_at(_left - span * 0.5, _surface + _rules.slab_height + 0.025, _width * 0.5 + 0.005),
		false
	)


## Край улицы у выезда: асфальт левее верха пандуса — на него машина выезжает,
## — и тротуар над тоннелем и вдоль рампы.
func _build_street_edge() -> void:
	var from := _left - ExitStreet.FROM
	var right := top_x()
	var near := _width * 0.5
	var depth := near - ExitStreet.NEAR_Z
	_box(
		Vector3(right - from, ExitStreet.ASPHALT, depth),
		_street_node.road(),
		_at((from + right) * 0.5, _street + ExitStreet.ASPHALT * 0.5, near - depth * 0.5)
	)
	# Кромка разреза по асфальту — светлая черта, как торец плиты здания.
	_box(
		Vector3(right - from, 0.03, 0.01),
		GreyboxLook.surface(KERB_TONE),
		_at((from + right) * 0.5, _street + 0.015, near + 0.005)
	)
	var walk := GreyboxLook.surface(PAVEMENT)
	var back := -_width * 0.5 - WALL_THICKNESS
	# Вдоль рампы тротуар — за стеной, от ограждения до мостовой.
	var strip := back - ExitStreet.NEAR_Z
	_box(
		Vector3(_left - right, KERB, strip),
		walk,
		_at((right + _left) * 0.5, _street - KERB * 0.5, back - strip * 0.5)
	)
	# Над тоннелем — во всю глубину проезда.
	_box(
		Vector3(TUNNEL, KERB, near - back),
		walk,
		_at(_left - TUNNEL * 0.5, _street - KERB * 0.5, (near + back) * 0.5)
	)
	# Бордюр у мостовой, на сантиметр выше тротуара.
	_box(
		Vector3(_left - right, KERB + 0.01, 0.16),
		GreyboxLook.surface(KERB_TONE),
		_at((right + _left) * 0.5, _street - (KERB + 0.01) * 0.5, ExitStreet.NEAR_Z - 0.08)
	)


## Тоннель: стена за проездом, потолок, светильники и то, что на стене.
func _build_tunnel() -> void:
	var back := -_width * 0.5 - WALL_THICKNESS
	var ceiling := _street + _rules.slab_height
	var mouth := mouth_x()
	var depth := _surface + _rules.slab_height - ceiling
	_box(
		Vector3(TUNNEL, depth, WALL_THICKNESS),
		_wall(ceiling, _surface),
		_at(_left - TUNNEL * 0.5, ceiling + depth * 0.5, back + WALL_THICKNESS * 0.5)
	)
	var concrete := BuildingFinish.shaft_concrete(Garage.CONCRETE.darkened(0.15))
	var near := _width * 0.5
	_box(
		Vector3(TUNNEL, _rules.slab_height, near - back),
		concrete,
		_at(_left - TUNNEL * 0.5, _street + _rules.slab_height * 0.5, (near + back) * 0.5)
	)
	# Полосы габарита на торце потолка у выхода из тоннеля.
	var yellow := GreyboxLook.surface(Garage.PAINT_YELLOW)
	var black := GreyboxLook.surface(Garage.PAINT_BLACK)
	for index in 6:
		_box(
			Vector3(0.2, _rules.slab_height - 0.1, 0.008),
			yellow if index % 2 == 0 else black,
			_at(mouth + 0.1 + 0.2 * index, _street + _rules.slab_height * 0.5, near + 0.004),
			false
		)
	var face := -_width * 0.5
	var steel := GreyboxLook.metal(TRAY)
	# Кабельный лоток и кабели в нём, под потолком.
	_box(
		Vector3(TUNNEL - 0.4, 0.08, 0.24),
		steel,
		_at(_left - TUNNEL * 0.5 - 0.1, ceiling + 0.4, face + 0.12),
		false
	)
	_box(
		Vector3(TUNNEL - 0.5, 0.05, 0.18),
		GreyboxLook.surface(CABLE),
		_at(_left - TUNNEL * 0.5 - 0.1, ceiling + 0.335, face + 0.12),
		false
	)
	# Спринклерная труба — красная, вдоль потолка.
	var pipe := _pipe(TUNNEL - 0.2, 0.035, GreyboxLook.metal(Garage.PIPE_RED))
	pipe.rotation.z = PI * 0.5
	pipe.position = _at(_left - TUNNEL * 0.5, ceiling + 0.14, face + 0.42)
	# Светильники: трубки у стены под потолком, пятна на стене и на пандусе.
	var x := _left - TUBE_STEP * 0.5
	while x > mouth + TUBE.x * 0.5:
		_box(
			Vector3(TUBE.x + 0.08, 0.07, TUBE.z + 0.06),
			GreyboxLook.metal(Garage.FIXTURE_BODY),
			_at(x, ceiling + 0.035, face + 0.4),
			false
		)
		_box(TUBE, GreyboxLook.light(Garage.TUBE), _at(x, ceiling + 0.09, face + 0.4), false)
		var wash := _glow(WASH, Garage.TUBE, WASH_ENERGY, true)
		wash.position = _at(x, ceiling + WASH.y * 0.5 - 0.1, face + 0.006)
		add_child(wash)
		var pool := _glow(Vector2(2.2, 2.2), Garage.TUBE, POOL_ENERGY, false)
		var ground := climb_at(_rules, x)
		pool.position = _at(x, _surface - ground - 0.012, 0.0)
		if ground > 0.0:
			pool.rotation.z = -atan2(_rules.floor_height, GarageGate.RAMP_RUN)
		add_child(pool)
		x -= TUBE_STEP
	# Стрелка EXIT краской на стене — по ней выезжают.
	var words := Garage.label("◀ EXIT", 800, 0.42, WALL_PAINT)
	words.position = _at(_left - 1.9, _surface - 1.45, face + 0.004)
	add_child(words)
	var bar := GreyboxLook.surface(Garage.PAINT_YELLOW)
	_box(Vector3(2.1, 0.06, 0.004), bar, _at(_left - 1.9, _surface - 1.1, face + 0.002), false)


## Открытая рампа за тоннелем: подпорная стена, водосток, «бочонки» и
## ограждение поверху.
func _build_open_ramp() -> void:
	var back := -_width * 0.5 - WALL_THICKNESS
	var right := mouth_x()
	var left := top_x()
	var top := _street - KERB
	var height := _surface + _rules.slab_height - top
	_box(
		Vector3(right - left, height, WALL_THICKNESS),
		_wall(top, _surface, 0.7 if Weather.is_raining(_weather) else 0.0),
		_at((left + right) * 0.5, top + height * 0.5, back + WALL_THICKNESS * 0.5)
	)
	# Отлив парапета — светлая полоса по верху.
	_box(
		Vector3(right - left, 0.05, WALL_THICKNESS + 0.06),
		GreyboxLook.surface(KERB_TONE),
		_at((left + right) * 0.5, top - 0.025, back + WALL_THICKNESS * 0.5),
		false
	)
	var face := -_width * 0.5
	# Водосток — от отлива вниз к проезду, у выхода из тоннеля.
	var drain_x := right - 0.35
	var drain_ground := _surface - climb_at(_rules, drain_x)
	var drain := _pipe(drain_ground - top, 0.05, GreyboxLook.metal(Garage.PIPE_GREY))
	drain.position = _at(drain_x, (drain_ground + top) * 0.5, face + 0.07)
	# Светильники над проездом идут вдоль подъёма: каждый на своей высоте над
	# ним, пока помещается под отливом.
	var x := right - 1.2
	while x > left + 0.5:
		var ground := _surface - climb_at(_rules, x)
		var lamp_y := ground - BULKHEAD_RISE
		if lamp_y - BULKHEAD.y < top + 0.2:
			break
		_box(
			BULKHEAD,
			GreyboxLook.light(BULKHEAD_GLOW),
			_at(x, lamp_y, face + BULKHEAD.z * 0.5),
			false
		)
		x -= BULKHEAD_STEP
	# Ограждение: стойки на отливе и два прута поверху.
	var metal := GreyboxLook.metal(RAIL)
	var rail_z := back + WALL_THICKNESS * 0.5
	var coping := top - 0.05
	var post := right - 0.3
	while post > left + 0.1:
		_box(
			Vector3(0.05, RAIL_HEIGHT, 0.05),
			metal,
			_at(post, coping - RAIL_HEIGHT * 0.5, rail_z),
			false
		)
		post -= RAIL_STEP
	for rise: float in [RAIL_HEIGHT - 0.03, RAIL_HEIGHT * 0.5]:
		_box(
			Vector3(right - left - 0.2, 0.04, 0.04),
			metal,
			_at((left + right) * 0.5, coping - rise, rail_z + 0.005),
			false
		)


## Фонарь над въездом: столб на тротуаре за ограждением, консоль над рампой.
func _build_lamp() -> void:
	var pole_x := _left - LAMP_FROM_WALL
	var pole_z := ExitStreet.NEAR_Z + 0.35
	var base := _street - KERB
	var metal := GreyboxLook.metal(POLE)
	_box(Vector3(0.12, LAMP_HEIGHT, 0.12), metal, _at(pole_x, base - LAMP_HEIGHT * 0.5, pole_z))
	_box(
		Vector3(0.08, 0.08, LAMP_ARM),
		metal,
		_at(pole_x, base - LAMP_HEIGHT, pole_z + LAMP_ARM * 0.5),
		false
	)
	var head_z := pole_z + LAMP_ARM
	_box(Vector3(0.34, 0.1, 0.5), metal, _at(pole_x, base - LAMP_HEIGHT + 0.02, head_z), false)
	_box(
		Vector3(0.28, 0.04, 0.42),
		GreyboxLook.light(GarageGate.OUTSIDE),
		_at(pole_x, base - LAMP_HEIGHT + 0.09, head_z),
		false
	)
	_light = OmniLight3D.new()
	_light.name = "StreetLight"
	_light.light_color = GarageGate.OUTSIDE
	_light.light_energy = LAMP_ENERGY
	_light.omni_range = LAMP_RANGE
	_light.omni_attenuation = 0.7
	_light.shadow_enabled = false
	_light.position = _at(pole_x, base - LAMP_HEIGHT + 0.3, head_z)
	_light.visible = false
	add_child(_light)
	if Weather.is_raining(_weather):
		add_child(
			RainLook.halo(
				_light.position + Vector3(0.0, 0.0, -1.4),
				GarageGate.OUTSIDE,
				0.22,
				Vector2(5.5, 5.0)
			)
		)


## Материал стены: литой бетон с высотой верха и низа, от которых потёки и
## сырость.
func _wall(top: float, bottom: float, wetness: float = 0.0) -> ShaderMaterial:
	var grain := BuildingFinish.shaft_concrete(WALL_TONE)
	var look := ShaderMaterial.new()
	look.shader = preload("res://src/levels/street_concrete.gdshader")
	look.set_shader_parameter("tone", WALL_TONE)
	look.set_shader_parameter("grain", grain.albedo_texture)
	look.set_shader_parameter("grain_normal", grain.normal_texture)
	look.set_shader_parameter("top_y", WorldSpace.height_to_scene(top))
	look.set_shader_parameter("bottom_y", WorldSpace.height_to_scene(bottom))
	look.set_shader_parameter("wetness", wetness)
	return look


## Материал грунта: пласты от уровня улицы.
func _soil() -> ShaderMaterial:
	var look := ShaderMaterial.new()
	look.shader = preload("res://src/levels/street_soil.gdshader")
	look.set_shader_parameter("tone", SOIL)
	look.set_shader_parameter("street_y", WorldSpace.height_to_scene(_street))
	return look


## Труба длиной [param length] и радиусом [param radius], стоя по Y.
func _pipe(length: float, radius: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	return part


## Пятно света — плоскость с градиентом, складывается с тем, на чём лежит.
## [param upright] — на стене, светлее сверху, у светильника; иначе — на полу,
## круглое.
static func _glow(size: Vector2, tone: Color, energy: float, upright: bool) -> MeshInstance3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(tone, energy))
	gradient.set_color(1, Color(tone, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.0) if upright else Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 1.0) if upright else Vector2(0.5, 0.0)
	texture.width = 64
	texture.height = 64
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_texture = texture
	material.disable_receive_shadows = true
	var part := MeshInstance3D.new()
	part.name = "Glow"
	if upright:
		var quad := QuadMesh.new()
		quad.size = size
		part.mesh = quad
	else:
		var plane := PlaneMesh.new()
		plane.size = size
		part.mesh = plane
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return part


func _at(x: float, y: float, z: float) -> Vector3:
	return Garage.scene_point(x, y, z)


## Коробка выезда. Теней выезд не кладёт: его источники — без теней.
func _box(
	size: Vector3, material: Material, centre: Vector3, shadow: bool = false
) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.material_override = material
	part.position = centre
	if not shadow:
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	return part
