class_name ExitStreet
extends Node3D

## Улица за выездом из паркинга (M24b): мостовая, тротуар и ряд домов через
## дорогу — витрины, маркизы, неон, пожарная лестница, фонарь.
##
## Машина Otto выезжает из тоннеля на эту улицу, и кадр едет за ней
## ([ExitBoarding]): улица — последний кадр здания. Раньше за пандусом стояли
## плоские рыжие прямоугольники и бирюзовые черты, а над ними светилась дымка
## города на заднике — розовая полоса, читавшаяся ошибкой. Теперь дома через
## дорогу собраны тем же видом, что город на заднике ([CityLook]): пояса,
## простенки, окна с жизнью за стеклом — и они выше любого кадра выезда, так
## что задник над улицей не виден вовсе.
##
## Нижний этаж домов — свой, объёмный: витрины горят, у закрытых — рулонные
## шторы и погасший неон, над витринами маркизы и вывески буквами шрифта игры.
## Свет — эмиссия и пятна на тротуаре; настоящий источник один — отсвет
## вертикальной вывески, и горит он, только пока выезд в кадре. В дождь
## мостовая мокрая и в ней ловятся огни, над улицей идут струи, по лужам —
## круги.
##
## Вид, без тел: Otto сюда не выходит, машина — вид без тела — проезжает.

## Насколько ряд домов тянется левее торца здания, м: до края самого широкого
## кадра выезда, когда кадр доехал за машиной до улицы.
const FROM: float = 36.0
## Мостовая: от тротуара у выезда ([constant NEAR_Z]) до бордюра через дорогу;
## толщина асфальта, м.
const NEAR_Z: float = -2.2
const FAR_KERB_Z: float = -8.0
const ASPHALT: float = 0.1
## Бордюр через дорогу: ширина и высота над мостовой, м; тротуар — вровень с
## ним, но на сантиметр ниже, чтобы грани не легли в одну плоскость.
const KERB := Vector2(0.18, 0.16)
## Лицо домов через дорогу — насколько за плоскостью игры, м, и сколько
## какой-то дом может отступить от линии.
const FACADE_Z: float = -10.0
const SETBACK: float = 0.45
## Дома: ширина и высота над улицей, м. Ниже любого не бывает: верх кадра
## выезда на лице домов — выше улицы на 14 м с лишним.
const WIDTHS := Vector2(6.5, 10.5)
const HEIGHTS := Vector2(16.0, 21.0)
## Нижний этаж с витринами и карниз над ним, м; толщина коробки фасада.
const SHOP_STOREY: float = 4.2
const CORNICE: float = 0.22
const FACADE_DEPTH: float = 1.2
## Тон фасада относительно дальнего города. Фасад — без освещения, как у
## города, а в воздухе здания без освещения он выходил светлее всего кадра:
## темнее города вдвое, и зарево улиц слабее ([constant FACADE_GLOW]).
const FACADE_BOOST: float = 0.38
const FACADE_GLOW: float = 0.012
## Доля горящих окон и их яркость: ближе города, но тусклее витрин.
const LIT_SHARE: float = 0.4
const WINDOW_GLOW: float = 0.42
## Яркость витрин: стекло без освещения, и в полную силу оно выгорало в белое.
const SHOP_GLOW: float = 0.17
## Витрина: цоколь под ней, высота стекла, ширина двери, м.
const RISER: float = 0.55
const GLASS_HEIGHT: float = 2.1
const DOOR_WIDTH: float = 0.95
const DOOR_HEIGHT: float = 2.35
const FRAME: float = 0.06
## Вывеска над витриной: низ, высота щита и букв, м.
const SIGN_BOTTOM: float = 2.95
const SIGN_HEIGHT: float = 0.62
const LETTERS: float = 0.4
## Маркиза: низ ламбрекена, вылет и высота ламбрекена, шаг полос, м.
const AWNING_LOW: float = 2.5
const AWNING_REACH: float = 1.1
const VALANCE: float = 0.26
const STRIPE: float = 0.32
## Рулонная штора закрытой лавки: высота до короба, шаг ламелей, м.
const SHUTTER_HEIGHT: float = 2.6
const SLAT: float = 0.13
## Вертикальная вывеска на кронштейнах: шаг букв и их кегль, вынос от фасада,
## м; отсвет — яркость и радиус.
const BLADE_STEP: float = 0.78
const BLADE_LETTER: float = 0.62
const BLADE_REACH: float = 0.95
const BLADE_ENERGY: float = 3.5
const BLADE_RANGE: float = 6.5
## Пожарная лестница: вылет площадки, ширина, высота перил, м.
const ESCAPE_REACH: float = 0.95
const ESCAPE_WIDTH: float = 2.6
const ESCAPE_RAIL: float = 0.9
## Фонарь через дорогу: высота, вынос консоли, м. Света не даёт — только
## светильник и пятно на тротуаре.
const LAMP_HEIGHT: float = 4.6
const LAMP_ARM: float = 1.2
## Пятна света на тротуаре: перед витриной и под фонарём.
const SPILL_ENERGY: float = 0.32
const POOL_ENERGY: float = 0.4
## Дождь над улицей: сколько струй на «высоком» и кругов на лужах.
const DROPS: int = 1300
const RIPPLES: int = 90

const ASPHALT_DRY := Color(0.055, 0.055, 0.062)
const ASPHALT_WET := Color(0.025, 0.026, 0.032)
const KERB_TONE := Color(0.42, 0.42, 0.4)
const PAVEMENT := Color(0.2, 0.2, 0.21)
const LANE_PAINT := Color(0.55, 0.52, 0.42)
const FRAME_TONE := Color(0.04, 0.04, 0.05)
const PANEL := Color(0.06, 0.06, 0.07)
const SHUTTER_TONE := Color(0.3, 0.31, 0.33)
const IRON := Color(0.07, 0.07, 0.08)
const POLE := Color(0.16, 0.17, 0.19)
## Цоколь нижнего этажа по типу дома ([enum CityPlan.Kind]).
const BASE_TONES: Array[Color] = [
	Color(0.3, 0.3, 0.31), Color(0.34, 0.3, 0.27), Color(0.22, 0.25, 0.3), Color(0.3, 0.17, 0.14)
]
## Типы домов ряда: жилые и кирпичные чаще контор, стеклянных башен нет —
## у стеклянной башни нет витрин.
const KINDS: Array[int] = [
	CityPlan.Kind.HOMES, CityPlan.Kind.BRICK, CityPlan.Kind.OFFICE, CityPlan.Kind.HOMES
]
## Маркизы: густые ночные тона.
const AWNINGS: Array[Color] = [
	Color(0.36, 0.06, 0.08), Color(0.06, 0.22, 0.16), Color(0.1, 0.12, 0.3), Color(0.3, 0.2, 0.06)
]
## Неон вывесок. Не цвета огоньков игры (ADR-0023, решение 6): без зелёного
## выхода и красной двери.
const NEON: Array[Color] = [
	Color(1.0, 0.25, 0.55),
	Color(0.3, 0.9, 0.85),
	Color(1.0, 0.62, 0.18),
	Color(0.68, 0.38, 1.0),
	Color(0.4, 0.62, 1.0),
]
const SHOPS: Array[String] = [
	"BAR", "DINER", "CAFE", "PAWN", "LIQUOR", "NOODLES", "JAZZ", "DELI", "BOOKS", "TAILOR", "RADIO"
]
## Без HOTEL: через дорогу от отеля он спорил бы с вывеской здания.
const BLADES: Array[String] = ["BAR", "JAZZ", "CLUB", "LOUNGE", "DANCE", "GRILL"]
## Натриевый свет фонаря и тёплый — из витрин.
const SODIUM := Color(1.0, 0.62, 0.28)
const WARM := Color(1.0, 0.78, 0.45)
const COLD := Color(0.62, 0.78, 1.0)

const SALT: int = 0x57_4EE7

var _left: float = 0.0
## Улица и верх тротуара через дорогу в плоскости правил: дома стоят на
## тротуаре, а не в нём.
var _street: float = 0.0
var _floor: float = 0.0
var _weather: Weather.Kind = Weather.Kind.CLEAR
var _rng := RandomNumberGenerator.new()
var _road: StandardMaterial3D = null
var _glow: OmniLight3D = null
var _rain: Array[GPUParticles3D] = []
## Коробки фасадов и окна — мультимешами, как у города на заднике.
var _facades: Array[Transform3D] = []
var _facade_tones: Array[Color] = []
var _facade_kinds: Array[Color] = []
var _windows: Array[Array] = [[], []]
## Колода вывесок: лавки на одной улице не повторяются.
var _names: Array[String] = []


## Собирает улицу у левого торца здания: [param left] — торец, [param street]
## — уровень улицы в плоскости правил.
func build(left: float, street: float, building_seed: int, weather: Weather.Kind) -> void:
	name = "Street"
	_left = left
	_street = street
	_floor = street - (KERB.y - 0.01)
	_weather = weather
	_rng.seed = hash([building_seed, SALT])
	_names.assign(SHOPS)
	for index in range(_names.size() - 1, 0, -1):
		var other := _rng.randi_range(0, index)
		var held := _names[index]
		_names[index] = _names[other]
		_names[other] = held
	_road = road_material(weather)
	_build_road()
	_build_row()
	_build_lamp(_left - FROM * 0.55)
	_park_a_car(_left - _rng.randf_range(12.0, 17.0))
	_flush_multimeshes()
	if Weather.is_raining(weather):
		_build_rain()
	add_to_group(Graphics.GROUP)
	apply_graphics()


## Асфальт мостовой: в дождь темнее и почти зеркальный — в нём ловятся огни.
static func road_material(weather: Weather.Kind) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	if Weather.is_raining(weather):
		material.albedo_color = ASPHALT_WET
		material.roughness = 0.07
		material.metallic = 0.25
	else:
		material.albedo_color = ASPHALT_DRY
		material.roughness = 0.62
	return material


## Материал мостовой — им же выезд кладёт асфальт у верха пандуса.
func road() -> StandardMaterial3D:
	return _road


## Настоящий свет улицы: горит, пока выезд в кадре.
func show_light(on: bool) -> void:
	if _glow != null:
		_glow.visible = on


## Настоящие источники улицы — для тестов бюджета.
func lights() -> Array[Light3D]:
	var found: Array[Light3D] = []
	if _glow != null:
		found.append(_glow)
	return found


## Доля струй дождя по уровню качества.
func apply_graphics() -> void:
	for layer in _rain:
		RainLook.scale_amount(layer, Graphics.rain_share())
	if _glow != null:
		_glow.light_volumetric_fog_energy = Graphics.light_in_fog()


## Мостовая с разметкой, бордюр и тротуар через дорогу.
func _build_road() -> void:
	var from := _left - FROM
	var span := _left - from
	var middle := (from + _left) * 0.5
	var depth := NEAR_Z - FAR_KERB_Z
	_box(
		Vector3(span, ASPHALT, depth),
		_road,
		_at(middle, _street + ASPHALT * 0.5, (NEAR_Z + FAR_KERB_Z) * 0.5)
	)
	# Прерывистая осевая: по штриху на шаг, чуть над асфальтом.
	var paint := GreyboxLook.surface(LANE_PAINT)
	var lane_z := (NEAR_Z + FAR_KERB_Z) * 0.5
	var x := _left - 1.5
	while x > from + 1.5:
		_box(Vector3(2.4, 0.01, 0.2), paint, _at(x, _street - 0.005, lane_z), false)
		x -= 5.0
	var kerb_z := FAR_KERB_Z - KERB.x * 0.5
	_box(
		Vector3(span, KERB.y, KERB.x),
		GreyboxLook.surface(KERB_TONE),
		_at(middle, _street - KERB.y * 0.5, kerb_z)
	)
	var walk_depth := FAR_KERB_Z - KERB.x - (FACADE_Z - SETBACK)
	var walk := KERB.y - 0.01
	_box(
		Vector3(span, walk, walk_depth),
		GreyboxLook.surface(PAVEMENT),
		_at(middle, _street - walk * 0.5, FAR_KERB_Z - KERB.x - walk_depth * 0.5)
	)


## Ряд домов через дорогу: от торца здания влево, дом за домом.
func _build_row() -> void:
	var right := _left + 0.5
	var index := 0
	var blade_at := 1 + _rng.randi_range(0, 1)
	var escape_at := 0 if blade_at != 0 else 2
	while right > _left - FROM:
		var width := _rng.randf_range(WIDTHS.x, WIDTHS.y)
		var left := right - width
		var block := CityPlan.Block.new()
		block.kind = KINDS[_rng.randi_range(0, KINDS.size() - 1)] as CityPlan.Kind
		block.mullions = _rng.randi_range(0, 2)
		block.x = left
		block.width = width
		block.height = _rng.randf_range(HEIGHTS.x, HEIGHTS.y)
		var face := FACADE_Z - _rng.randf_range(0.0, SETBACK)
		_build_house(block, Vector2(left, right), face)
		if index == blade_at:
			_hang_blade(right - 1.2, face)
		if index == escape_at:
			_build_escape(block, Vector2(left, right), face)
		right = left
		index += 1


## Дом через дорогу: цоколь с витринами, карниз, фасад с окнами.
func _build_house(block: CityPlan.Block, span: Vector2, face: float) -> void:
	var width := span.y - span.x
	var middle := (span.x + span.y) * 0.5
	var base := BuildingFinish.shaft_concrete(BASE_TONES[block.kind])
	var base_height := SHOP_STOREY - CORNICE - (_street - _floor)
	_box(
		Vector3(width, base_height, 0.5),
		base,
		_at(middle, _floor - base_height * 0.5, face - 0.25),
		false
	)
	_box(
		Vector3(width, CORNICE, 0.66),
		GreyboxLook.surface(BASE_TONES[block.kind].lightened(0.25)),
		_at(middle, _street - SHOP_STOREY + CORNICE * 0.5, face - 0.25 + 0.08),
		false
	)
	var upper := block.height - SHOP_STOREY
	var centre := _at(middle, _street - SHOP_STOREY - upper * 0.5, face - FACADE_DEPTH * 0.5)
	_facades.append(Transform3D(Basis.from_scale(Vector3(width, upper, FACADE_DEPTH)), centre))
	var tone := CityLook.facade_tone(block) * FACADE_BOOST
	_facade_tones.append(Color(tone.r, tone.g, tone.b))
	_facade_kinds.append(CityLook.facade_custom(block))
	_place_windows(block, span, face, upper)
	var shops := 2 if width >= 8.5 else 1
	var share := width / float(shops)
	for shop in shops:
		var shop_middle := span.x + share * (float(shop) + 0.5)
		var shop_width := minf(share - 0.9, 4.2)
		if _rng.randf() < 0.72:
			_build_open_shop(shop_middle, shop_width, face)
		else:
			_build_closed_shop(shop_middle, shop_width, face)


## Окна верхних этажей — по той же сетке, что пояса и простенки шейдера
## фасада ([code]city_facade.gdshader[/code]): окно на высоте шага над низом
## коробки, колонки — по середине фасада.
func _place_windows(block: CityPlan.Block, span: Vector2, face: float, upper: float) -> void:
	var step := CityPlan.WINDOW_STEP
	var width := span.y - span.x
	var columns := maxi(floori(width / step.x) - 1, 1)
	var first := width * 0.5 - float(columns - 1) * step.x * 0.5
	var window_size := CityLook.WINDOW_SIZES[block.kind]
	var bottom := _street - SHOP_STOREY
	var level := 0
	while step.y * float(level + 1) + window_size.y * 0.5 < upper - 1.4:
		for column in columns:
			var cell := Vector2i(column, level)
			var lit := _rng.randf() < LIT_SHARE
			var x := span.x + first + float(column) * step.x
			var y := bottom - step.y * float(level + 1)
			var place := Transform3D(
				Basis.from_scale(CityLook.window_scale(block)), _at(x, y, face + 0.02)
			)
			var tone := WARM if _rng.randf() > 0.3 else COLD
			var glow := WINDOW_GLOW if lit else 1.0
			var colour := (
				Color(tone.r * glow, tone.g * glow, tone.b * glow)
				if lit
				else CityBackdrop.WINDOW_DARK
			)
			(_windows[1 if lit else 0] as Array).append(
				[place, colour, CityLook.window_custom(block, cell, lit)]
			)
		level += 1


## Лавка открыта: горящая витрина в раме, дверь со стеклом, неон над ней,
## иногда маркиза, и пятно света на тротуаре.
func _build_open_shop(middle: float, width: float, face: float) -> void:
	var glass_width := width - DOOR_WIDTH - FRAME * 3.0
	var glass_x := middle - width * 0.5 + FRAME + glass_width * 0.5
	var glass_y := _floor - RISER - GLASS_HEIGHT * 0.5
	var insides: Array[int] = [
		CityLook.Inside.BLINDS, CityLook.Inside.PERSON, CityLook.Inside.CURTAINS
	]
	var inside := insides[_rng.randi_range(0, insides.size() - 1)]
	var tone := (WARM if _rng.randf() < 0.75 else COLD) * SHOP_GLOW
	_add_glass(Vector2(glass_x, glass_y), Vector2(glass_width, GLASS_HEIGHT), face, tone, inside)
	var frame := GreyboxLook.metal(FRAME_TONE)
	var front := face + 0.04
	# Рама витрины: низ, верх, края и средник.
	for y: float in [_floor - RISER, _floor - RISER - GLASS_HEIGHT]:
		_box(Vector3(glass_width + FRAME * 2.0, FRAME, 0.05), frame, _at(glass_x, y, front), false)
	for x: float in [glass_x - glass_width * 0.5, glass_x + glass_width * 0.5, glass_x]:
		_box(Vector3(FRAME, GLASS_HEIGHT, 0.05), frame, _at(x, glass_y, front), false)
	_box(
		Vector3(glass_width, RISER, 0.08),
		GreyboxLook.surface(PANEL.lightened(0.1)),
		_at(glass_x, _floor - RISER * 0.5, face + 0.04),
		false
	)
	# Дверь: полотно и стекло в нём, чуть тусклее витрины.
	var door_x := middle + width * 0.5 - FRAME - DOOR_WIDTH * 0.5
	_box(
		Vector3(DOOR_WIDTH, DOOR_HEIGHT, 0.06),
		GreyboxLook.metal(FRAME_TONE.lightened(0.05)),
		_at(door_x, _floor - DOOR_HEIGHT * 0.5, face + 0.03),
		false
	)
	_add_glass(
		Vector2(door_x, _floor - DOOR_HEIGHT * 0.6),
		Vector2(DOOR_WIDTH * 0.62, DOOR_HEIGHT * 0.5),
		face + 0.045,
		tone * 0.6,
		CityLook.Inside.PLAIN
	)
	var neon := NEON[_rng.randi_range(0, NEON.size() - 1)]
	_hang_sign(middle, width, face, neon, true)
	if _rng.randf() < 0.6:
		_build_awning(middle, width, face)
	_spill(Vector2(middle, width), face, tone)


## Лавка закрыта: рулонная штора с коробом и погасший неон.
func _build_closed_shop(middle: float, width: float, face: float) -> void:
	var metal := GreyboxLook.metal(SHUTTER_TONE)
	var groove := GreyboxLook.metal(SHUTTER_TONE.darkened(0.5))
	_box(
		Vector3(width, SHUTTER_HEIGHT, 0.06),
		metal,
		_at(middle, _floor - SHUTTER_HEIGHT * 0.5, face + 0.03),
		false
	)
	var rise := SLAT
	while rise < SHUTTER_HEIGHT - 0.05:
		_box(
			Vector3(width - 0.04, 0.014, 0.006),
			groove,
			_at(middle, _floor - rise, face + 0.063),
			false
		)
		rise += SLAT
	_box(
		Vector3(width + 0.1, 0.18, 0.26),
		metal,
		_at(middle, _floor - SHUTTER_HEIGHT - 0.09, face + 0.13),
		false
	)
	_hang_sign(middle, width, face, NEON[_rng.randi_range(0, NEON.size() - 1)], false)


## Вывеска над витриной: тёмный щит и буквы неоном. У закрытой лавки неон
## погашен — буквы еле видны.
func _hang_sign(middle: float, width: float, face: float, neon: Color, lit: bool) -> void:
	var board_width := minf(width - 0.2, 3.6)
	var board := _box(
		Vector3(board_width, SIGN_HEIGHT, 0.12),
		GreyboxLook.metal(PANEL),
		_at(middle, _street - SIGN_BOTTOM - SIGN_HEIGHT * 0.5, face + 0.06),
		false
	)
	var words := Label3D.new()
	words.text = _names.pop_back() if not _names.is_empty() else SHOPS[0]
	words.font = NeonStyle.font(700)
	words.font_size = 96
	words.pixel_size = LETTERS / 96.0
	words.shaded = false
	words.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if lit:
		words.modulate = neon
		words.outline_modulate = neon.darkened(0.45)
		words.outline_size = 10
	else:
		words.modulate = neon.darkened(0.82)
		words.outline_size = 0
	words.position = Vector3(0.0, 0.0, 0.065)
	board.add_child(words)


## Маркиза: навес над витриной и полосатый ламбрекен.
func _build_awning(middle: float, width: float, face: float) -> void:
	var cloth := AWNINGS[_rng.randi_range(0, AWNINGS.size() - 1)]
	var top := _street - AWNING_LOW - VALANCE
	_box(
		Vector3(width, 0.06, AWNING_REACH),
		GreyboxLook.surface(cloth),
		_at(middle, top - 0.03, face + AWNING_REACH * 0.5),
		false
	)
	var edge := face + AWNING_REACH
	_box(
		Vector3(width, VALANCE, 0.03),
		GreyboxLook.surface(cloth),
		_at(middle, top + VALANCE * 0.5, edge + 0.015),
		false
	)
	var stripe := GreyboxLook.surface(cloth.lightened(0.55))
	var x := middle - width * 0.5 + STRIPE * 0.5
	while x < middle + width * 0.5 - STRIPE * 0.25:
		_box(
			Vector3(STRIPE * 0.5, VALANCE, 0.006),
			stripe,
			_at(x, top + VALANCE * 0.5, edge + 0.033),
			false
		)
		x += STRIPE


## Вертикальная вывеска на кронштейнах у угла дома: буквы столбиком и
## отсвет — единственный настоящий источник улицы.
func _hang_blade(x: float, face: float) -> void:
	var text := BLADES[_rng.randi_range(0, BLADES.size() - 1)]
	var neon := NEON[_rng.randi_range(0, NEON.size() - 1)]
	var height := float(text.length()) * BLADE_STEP + 0.5
	var bottom := _street - SHOP_STOREY - 0.6
	var z := face + BLADE_REACH
	var panel := _box(
		Vector3(0.9, height, 0.16),
		GreyboxLook.metal(PANEL),
		_at(x, bottom - height * 0.5, z),
		false
	)
	panel.name = "Blade"
	for share: float in [0.15, 0.85]:
		_box(
			Vector3(0.06, 0.06, BLADE_REACH - 0.08),
			GreyboxLook.metal(IRON),
			_at(x, bottom - height * share, face + (BLADE_REACH - 0.08) * 0.5),
			false
		)
	# Щит — лицом к камере, как у вывески здания ([VerticalSign]): буквы
	# столбиком.
	var y := bottom - height + 0.25 + BLADE_STEP * 0.5
	for letter in text:
		var label := Label3D.new()
		label.text = letter
		label.font = NeonStyle.font(700)
		label.font_size = 96
		label.pixel_size = BLADE_LETTER / 96.0
		label.modulate = neon
		label.outline_modulate = neon.darkened(0.4)
		label.outline_size = 8
		label.shaded = false
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		label.position = _at(x, y, z + 0.09)
		add_child(label)
		y += BLADE_STEP
	_glow = OmniLight3D.new()
	_glow.name = "BladeGlow"
	_glow.light_color = neon
	_glow.light_energy = BLADE_ENERGY
	_glow.omni_range = BLADE_RANGE
	_glow.omni_attenuation = 0.8
	_glow.shadow_enabled = false
	# Ниже середины щита и ближе к мостовой: отсвет ложится на маркизы, цоколь и
	# тротуар — фасад выше без освещения и отсвета не взял бы.
	_glow.position = _at(x, bottom + 0.6, z + 1.4)
	_glow.visible = false
	add_child(_glow)
	if Weather.is_raining(_weather):
		add_child(
			RainLook.halo(
				_at(x, bottom - height * 0.5, face + 0.3), neon, 0.22, Vector2(3.2, height + 2.0)
			)
		)


## Пожарная лестница: площадки у окон каждого этажа, перила и марши между
## ними — железо на фасаде, как в любом нуаре.
func _build_escape(block: CityPlan.Block, span: Vector2, face: float) -> void:
	var step := CityPlan.WINDOW_STEP
	var window := CityLook.WINDOW_SIZES[block.kind]
	var x := (span.x + span.y) * 0.5
	var iron := GreyboxLook.metal(IRON)
	var upper := block.height - SHOP_STOREY
	var levels: Array[float] = []
	var level := 0
	while step.y * float(level + 1) + window.y * 0.5 < upper - 1.4:
		levels.append(_street - SHOP_STOREY - step.y * float(level + 1) + window.y * 0.5 + 0.05)
		level += 1
	for index in levels.size():
		var deck := levels[index]
		_box(
			Vector3(ESCAPE_WIDTH, 0.05, ESCAPE_REACH),
			iron,
			_at(x, deck + 0.025, face + ESCAPE_REACH * 0.5 + 0.02),
			false
		)
		for rail: float in [ESCAPE_RAIL, ESCAPE_RAIL * 0.5]:
			_box(
				Vector3(ESCAPE_WIDTH, 0.035, 0.035),
				iron,
				_at(x, deck - rail, face + ESCAPE_REACH),
				false
			)
		for post in 5:
			var post_x := x - ESCAPE_WIDTH * 0.5 + ESCAPE_WIDTH * float(post) / 4.0
			_box(
				Vector3(0.03, ESCAPE_RAIL, 0.03),
				iron,
				_at(post_x, deck - ESCAPE_RAIL * 0.5, face + ESCAPE_REACH - 0.01),
				false
			)
		if index + 1 < levels.size():
			_flight(x, deck, levels[index + 1], face, iron, index % 2 == 0)


## Марш пожарной лестницы между площадками [param from] и [param to]: две
## тетивы наискосок.
func _flight(
	x: float, from: float, to: float, face: float, iron: StandardMaterial3D, rightwards: bool
) -> void:
	var run := ESCAPE_WIDTH * 0.8
	var rise := from - to
	var length := Vector2(run, rise).length()
	var side := 1.0 if rightwards else -1.0
	for offset: float in [0.25, 0.65]:
		var stringer := _box(
			Vector3(length, 0.05, 0.04), iron, _at(x, (from + to) * 0.5, face + offset), false
		)
		stringer.rotation.z = side * atan2(rise, run)


## Фонарь через дорогу: столб у бордюра, консоль над мостовой, светильник и
## пятно света под ним — без источника.
func _build_lamp(x: float) -> void:
	var metal := GreyboxLook.metal(POLE)
	var z := FAR_KERB_Z - 0.45
	var base := _street - KERB.y
	_box(Vector3(0.12, LAMP_HEIGHT, 0.12), metal, _at(x, base - LAMP_HEIGHT * 0.5, z))
	_box(
		Vector3(0.08, 0.08, LAMP_ARM), metal, _at(x, base - LAMP_HEIGHT, z + LAMP_ARM * 0.5), false
	)
	var head := _at(x, base - LAMP_HEIGHT + 0.08, z + LAMP_ARM)
	_box(Vector3(0.34, 0.1, 0.5), metal, head + Vector3(0.0, 0.08, 0.0), false)
	_box(Vector3(0.28, 0.04, 0.42), GreyboxLook.light(SODIUM), head, false)
	var pool := _pool(Vector2(4.2, 4.2), SODIUM, POOL_ENERGY)
	pool.position = _at(x, _street - 0.012, z + LAMP_ARM - 0.4)
	add_child(pool)
	if Weather.is_raining(_weather):
		add_child(RainLook.halo(head + Vector3(0.0, 0.0, -1.2), SODIUM, 0.2, Vector2(5.0, 4.5)))


## Чужая машина у бордюра через дорогу, носом влево, с погашенными фарами:
## улица живая, а мостовая не пустая полоса. Модель и краска — жребий улицы.
func _park_a_car(x: float) -> void:
	var choice := CarModel.Choice.new()
	choice.model = _rng.randi_range(0, CarModel.MODELS.size() - 1)
	# Без чёрной краски — последней: в темноте у бордюра машина пропадала.
	choice.paint = _rng.randi_range(1, CarModel.PAINTS.size() - 2)
	var model := CarModel.build(choice)
	model.name = "ParkedCar"
	model.scale = Vector3(1.0, 1.0, Garage.CAR_WIDTH / Garage.depth_of(model))
	model.rotation.y = PI
	model.position = _at(x, _street, FAR_KERB_Z + Garage.CAR_WIDTH * 0.5 + 0.25)
	Garage.switch_lights_off(model)
	add_child(model)


## Свет витрины на тротуаре: тёплое пятно перед стеклом.
func _spill(shop: Vector2, face: float, tone: Color) -> void:
	var depth := FAR_KERB_Z - KERB.x - face
	var pool := _pool(Vector2(shop.y * 1.3, absf(depth) * 1.6), tone, SPILL_ENERGY)
	pool.position = _at(shop.x, _street - KERB.y - 0.004, face)
	add_child(pool)


## Стекло с жизнью за ним — окно шейдером города ([CityLook]), своим мешем.
func _add_glass(centre: Vector2, size: Vector2, face: float, tone: Color, inside: int) -> void:
	var place := Transform3D(
		Basis.from_scale(
			Vector3(size.x / CityBackdrop.WINDOW_SIZE.x, size.y / CityBackdrop.WINDOW_SIZE.y, 1.0)
		),
		_at(centre.x, centre.y, face + 0.02)
	)
	var custom := Color(_rng.randf(), float(inside), 1.0, 1.0)
	(_windows[1] as Array).append([place, Color(tone.r, tone.g, tone.b), custom])


## Фасады и окна одним махом: мультимешем, как у города на заднике.
func _flush_multimeshes() -> void:
	var box := BoxMesh.new()
	var look := CityLook.facade()
	look.set_shader_parameter("glow_strength", FACADE_GLOW)
	box.material = look
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_colors = true
	many.use_custom_data = true
	many.mesh = box
	many.instance_count = _facades.size()
	for index in _facades.size():
		many.set_instance_transform(index, _facades[index])
		many.set_instance_color(index, _facade_tones[index])
		many.set_instance_custom_data(index, _facade_kinds[index])
	var facades := MultiMeshInstance3D.new()
	facades.name = "Facades"
	facades.multimesh = many
	facades.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(facades)
	for lit in 2:
		var places: Array[Transform3D] = []
		var colours: Array[Color] = []
		var customs: Array[Color] = []
		for window: Array in _windows[lit]:
			places.append(window[0] as Transform3D)
			colours.append(window[1] as Color)
			customs.append(window[2] as Color)
		var quads := CityBackdrop.window_quads(
			"LitWindows" if lit == 1 else "DarkWindows", places, colours, customs, lit == 1
		)
		quads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(quads)


## Дождь над улицей: струи перед домами и круги на мостовой.
func _build_rain() -> void:
	var from := _left - FROM
	var height := 16.0
	# Только над мостовой и тротуаром: ниже улицы капли уходят за асфальт и
	# грунт, а не в тоннель и не в разрез у камеры.
	var front := NEAR_Z
	var back := FACADE_Z + 0.6
	var drops := RainLook.streaks(
		DROPS,
		(height + 1.0) / RoofRain.SPEED.x,
		Vector3((_left - from) * 0.5, 0.3, (front - back) * 0.5),
		RoofRain.SPEED,
		RoofRain.SLANT,
		RoofRain.DROP,
		RainLook.drop_look(RoofRain.DROP_LOOK)
	)
	drops.name = "Drops"
	drops.position = _at((from + _left) * 0.5, _street - height, (front + back) * 0.5)
	drops.visibility_aabb = AABB(
		Vector3(-(_left - from), -height - 1.0, -8.0),
		Vector3((_left - from) * 2.0, height + 2.0, 16.0)
	)
	add_child(drops)
	_rain.append(drops)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3((_left - from) * 0.5, 0.0, (NEAR_Z - FAR_KERB_Z) * 0.5)
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.0
	process.scale_min = 0.8
	process.scale_max = 1.8
	var quad := QuadMesh.new()
	quad.size = Vector2(RoofRain.RIPPLE, RoofRain.RIPPLE)
	quad.orientation = PlaneMesh.FACE_Y
	var look := ShaderMaterial.new()
	look.shader = RainLook.RIPPLE_SHADER
	quad.material = look
	var ripples := GPUParticles3D.new()
	ripples.name = "Ripples"
	ripples.amount = RIPPLES
	ripples.set_meta(RainLook.FULL, RIPPLES)
	ripples.lifetime = RoofRain.RIPPLE_LIFE
	ripples.preprocess = RoofRain.RIPPLE_LIFE
	ripples.local_coords = false
	ripples.process_material = process
	ripples.draw_pass_1 = quad
	ripples.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ripples.position = _at((from + _left) * 0.5, _street - 0.006, (NEAR_Z + FAR_KERB_Z) * 0.5)
	ripples.visibility_aabb = AABB(
		Vector3(-(_left - from), -0.5, -4.0), Vector3((_left - from) * 2.0, 1.0, 8.0)
	)
	add_child(ripples)
	_rain.append(ripples)


## Пятно света: плоскость с круглым градиентом цвета [param tone], складывается
## с тем, на чём лежит. Не источник — картинка света.
static func _pool(size: Vector2, tone: Color, energy: float) -> MeshInstance3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(tone, energy))
	gradient.set_color(1, Color(tone, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 64
	texture.height = 64
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_texture = texture
	material.disable_receive_shadows = true
	var mesh := PlaneMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.name = "Pool"
	part.mesh = mesh
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return part


func _at(x: float, y: float, z: float) -> Vector3:
	return Garage.scene_point(x, y, z)


## Коробка улицы. Теней улица не кладёт: её источники — без теней, а тени
## ламп здания сюда не достают.
func _box(
	size: Vector3, material: StandardMaterial3D, centre: Vector3, shadow: bool = false
) -> MeshInstance3D:
	return Garage.put_box(self, size, material, centre, shadow)
