class_name ExitStreet
extends Node3D

## The street beyond the garage exit (M24b): roadway, sidewalk and a row of houses across the road —
## shop windows, awnings, neon, a fire escape, a street lamp.
##
## Otto's car drives out of the tunnel onto this street, and the view follows it ([ExitBoarding]):
## the street is the last shot of the building. Before, flat orange rectangles and turquoise strokes
## stood beyond the ramp, and above them glowed the haze of the city on the backdrop — a pink band
## that read as a bug. Now the houses across the road are built with the same look as the city on
## the backdrop ([CityLook]): belts, piers, windows with life behind the glass — and they are taller
## than any exit shot, so the backdrop above the street is not visible at all.
##
## The ground floor of the houses is its own, three-dimensional: shop windows are lit, closed ones
## have roller shutters and dead neon, above the windows are awnings and signs in the game's font.
## Light is emission and pools on the sidewalk; there is one real light source — the glow of the
## vertical sign, and it is on only while the exit is in the frame. In rain the roadway is wet and
## catches the lights, streaks fall over the street, rings spread on the puddles.
##
## Look only, no bodies: Otto does not come out here, the car — a look without a body — drives
## through.
##
## Since M24k (ADR-0052, decision 3) the houses across the road are the pack's baked facade, as with
## the city on the backdrop ([method CityLook.building]), at any time of day: by day they are lit by
## the building's sun ([Outdoors]), at night — by the street lamp, neon and lit windows. The street
## lights — lamp, neon, pools of light — burn at a share of [method TimeOfDay.street_lights], and by
## day in clear weather are off.

## How far the row of houses extends to the left of the building's end wall, m: to the edge of the
## widest exit shot, when the view has followed the car to the street.
const FROM: float = 36.0
## Roadway: from the sidewalk at the exit ([constant NEAR_Z]) to the curb across the road; asphalt
## thickness, m.
const NEAR_Z: float = -2.2
const FAR_KERB_Z: float = -8.0
const ASPHALT: float = 0.1
## Curb across the road: width and height above the roadway, m; the sidewalk is level with it, but a
## centimetre lower, so the faces do not lie in one plane.
const KERB := Vector2(0.18, 0.16)
## Front of the houses across the road — how far behind the play plane, m, and how much a house may
## step back from the line.
const FACADE_Z: float = -10.0
const SETBACK: float = 0.45
## Houses: width and height above the street, m. None is lower: the top of the exit shot at the
## house fronts is over 14 m above the street.
const WIDTHS := Vector2(6.5, 10.5)
const HEIGHTS := Vector2(16.0, 21.0)
## Ground floor with shop windows and the cornice above it, m; thickness of the facade box.
const SHOP_STOREY: float = 4.2
const CORNICE: float = 0.22
const FACADE_DEPTH: float = 1.2
## Shop window brightness: the glass is unlit, and at full strength it burned out to white.
const SHOP_GLOW: float = 0.17
## Shop window: the plinth under it, glass height, door width, m.
const RISER: float = 0.55
const GLASS_HEIGHT: float = 2.1
const DOOR_WIDTH: float = 0.95
const DOOR_HEIGHT: float = 2.35
const FRAME: float = 0.06
## Sign above the shop window: bottom, height of the board and letters, m.
const SIGN_BOTTOM: float = 2.95
const SIGN_HEIGHT: float = 0.62
const LETTERS: float = 0.4
## Awning: bottom of the valance, projection and valance height, stripe pitch, m.
const AWNING_LOW: float = 2.5
const AWNING_REACH: float = 1.1
const VALANCE: float = 0.26
const STRIPE: float = 0.32
## Roller shutter of a closed shop: height to the box, slat pitch, m.
const SHUTTER_HEIGHT: float = 2.6
const SLAT: float = 0.13
## Vertical sign on brackets: letter pitch and size, offset from the facade, m; glow — brightness
## and radius.
const BLADE_STEP: float = 0.78
const BLADE_LETTER: float = 0.62
const BLADE_REACH: float = 0.95
const BLADE_ENERGY: float = 3.5
const BLADE_RANGE: float = 6.5
## Fire escape: landing projection, width, railing height, m.
const ESCAPE_REACH: float = 0.95
const ESCAPE_WIDTH: float = 2.6
const ESCAPE_RAIL: float = 0.9
## Street lamp across the road: height, arm reach, m. It gives no light — only the fixture and a
## pool on the sidewalk.
const LAMP_HEIGHT: float = 4.6
const LAMP_ARM: float = 1.2
## Street lamp light: energy, range, m, cone angle and tilt toward the houses, degrees and radians —
## it shines on the sidewalk and shop windows across the road.
const LAMP_ENERGY: float = 5.0
const LAMP_RANGE: float = 9.0
const LAMP_ANGLE: float = 55.0
const LAMP_LEAN: float = -0.35
## Pools of light on the sidewalk: in front of a shop window and under the street lamp.
const SPILL_ENERGY: float = 0.32
const POOL_ENERGY: float = 0.4
## Rain over the street: how many streaks on "high" and rings on the puddles.
const DROPS: int = 1300
const RIPPLES: int = 90

## Asphalt: colour in sRGB. Before M24g it was 0.055 — 0.004 in linear units, an almost black body:
## headlight light did not scatter on it at all, and when wet, almost a mirror, it reflected the
## slanting beam forward, past the camera (ADR-0043, decision 5). Real asphalt is about 0.2; wet is
## darker and shines, but takes light.
const ASPHALT_DRY := Color(0.21, 0.21, 0.22)
const ASPHALT_WET := Color(0.13, 0.13, 0.145)
const ASPHALT_DRY_ROUGHNESS: float = 0.78
const ASPHALT_WET_ROUGHNESS: float = 0.3
const KERB_TONE := Color(0.42, 0.42, 0.4)
const PAVEMENT := Color(0.2, 0.2, 0.21)
const LANE_PAINT := Color(0.55, 0.52, 0.42)
const FRAME_TONE := Color(0.04, 0.04, 0.05)
const PANEL := Color(0.06, 0.06, 0.07)
const SHUTTER_TONE := Color(0.3, 0.31, 0.33)
const IRON := Color(0.07, 0.07, 0.08)
const POLE := Color(0.16, 0.17, 0.19)
## Ground-floor plinth by house kind ([enum CityPlan.Kind]).
const BASE_TONES: Array[Color] = [
	Color(0.3, 0.3, 0.31), Color(0.34, 0.3, 0.27), Color(0.22, 0.25, 0.3), Color(0.3, 0.17, 0.14)
]
## House kinds in the row: residential and brick more often than offices, no glass towers — a glass
## tower has no shop windows.
const KINDS: Array[int] = [
	CityPlan.Kind.HOMES, CityPlan.Kind.BRICK, CityPlan.Kind.OFFICE, CityPlan.Kind.HOMES
]
## Awnings: deep night tones.
const AWNINGS: Array[Color] = [
	Color(0.36, 0.06, 0.08), Color(0.06, 0.22, 0.16), Color(0.1, 0.12, 0.3), Color(0.3, 0.2, 0.06)
]
## Sign neon. Not the colours of the game's indicator lights (ADR-0023, decision 6): no exit green
## and no red door.
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
## No HOTEL: across the road from a hotel it would compete with the building's sign.
const BLADES: Array[String] = ["BAR", "JAZZ", "CLUB", "LOUNGE", "DANCE", "GRILL"]
## Sodium light of the street lamp and warm light from the shop windows.
const SODIUM := Color(1.0, 0.62, 0.28)
const WARM := Color(1.0, 0.78, 0.45)
const COLD := Color(0.62, 0.78, 1.0)

const SALT: int = 0x57_4EE7

## From what street-light strength neon and the lamp are on: in the morning — yes (0.35), by day in
## clear weather — no (ADR-0052, decision 3).
const LIGHTS_ON: float = 0.3
## Shop window by day: the glass is in daylight, the room light behind it is dimmer.
const SHOP_GLOW_BY_DAY: float = 0.55
## The pack facade is set back behind the shop window line by this much, m: the plinth with shop
## windows is in front of it, and the faces do not lie in one plane.
const PACK_BEHIND: float = 0.05

var _left: float = 0.0
## The street and the top of the sidewalk across the road in the rules plane: houses stand on the
## sidewalk, not in it.
var _street: float = 0.0
var _floor: float = 0.0
var _weather: Weather.Kind = Weather.Kind.CLEAR
var _time: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT
## Street light strength, 0–1: at night 1, by day in clear weather — 0.
var _lights: float = 1.0
## Whether it is light outside — not night: dead neon is then in daylight, not in darkness.
var _sunlit: bool = false
## Houses and shop window glass — as multimeshes, as with the city on the backdrop.
var _blocks: Array[CityPlan.Block] = []
var _glass_places: Array[Transform3D] = []
var _glass_tones: Array[Color] = []
var _glass_customs: Array[Color] = []
var _rng := RandomNumberGenerator.new()
var _road: StandardMaterial3D = null
var _glow: OmniLight3D = null
var _lamp: SpotLight3D = null
var _rain: Array[GPUParticles3D] = []
var _snow: StreetSnow = null
var _people: StreetPeople = null
var _traffic: StreetTraffic = null
## Deck of signs: shops on one street do not repeat.
var _names: Array[String] = []


## Assembles the street at the building's left end wall: [param left] — the end wall, [param street]
## — the street level in the rules plane, [param time] — time of day.
func build(
	left: float,
	street: float,
	building_seed: int,
	weather: Weather.Kind,
	time: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT
) -> void:
	name = "Street"
	_left = left
	_street = street
	_floor = street - (KERB.y - 0.01)
	_weather = weather
	_time = time
	_lights = TimeOfDay.street_lights(time, weather)
	_sunlit = not TimeOfDay.is_night(time)
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
	_traffic = StreetTraffic.new()
	add_child(_traffic)
	_traffic.build(_left, _street, building_seed, time, _lights > 0.0, Weather.is_snowing(weather))
	_people = StreetPeople.new()
	add_child(_people)
	var walk_from := _at(_left - FROM, _floor, 0.0)
	var walk_to := _at(_left, _floor, 0.0)
	_people.build(walk_from.x, walk_to.x, walk_from.y, building_seed, time, weather)
	_flush_multimeshes()
	if Weather.is_raining(weather):
		_build_rain()
	elif Weather.is_snowing(weather):
		_build_snow()
	if Weather.is_raining(weather) or Weather.is_snowing(weather):
		_catch()
	add_to_group(Graphics.GROUP)
	apply_graphics()


## Roadway asphalt: in rain darker and shiny — it catches the lights.
static func road_material(weather: Weather.Kind) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	# In snow the same wet asphalt as in rain lies under the ruts (ADR-0054).
	if Weather.is_raining(weather) or Weather.is_snowing(weather):
		material.albedo_color = ASPHALT_WET
		material.roughness = ASPHALT_WET_ROUGHNESS
	else:
		material.albedo_color = ASPHALT_DRY
		material.roughness = ASPHALT_DRY_ROUGHNESS
	return material


## Roadway material — the exit also uses it to lay asphalt at the top of the ramp.
func road() -> StandardMaterial3D:
	return _road


## The real street light: on while the exit is in the frame. Traffic and pedestrians also move only
## then. By day in clear weather there are no sources at all ([method is_lit]).
func show_light(on: bool) -> void:
	if _glow != null:
		_glow.visible = on
	if _lamp != null:
		_lamp.visible = on
	if _traffic != null:
		_traffic.set_active(on)
	if _people != null:
		_people.set_active(on)


## Street traffic (ADR-0044, decision 1).
func traffic() -> StreetTraffic:
	return _traffic


## Whether the street lights are on: neon, lamp, sign glow. By day in clear weather — no.
func is_lit() -> bool:
	return _lights > LIGHTS_ON


## The street's real light sources — for budget tests.
func lights() -> Array[Light3D]:
	var found: Array[Light3D] = []
	if _glow != null:
		found.append(_glow)
	if _lamp != null:
		found.append(_lamp)
	return found


## Share of rain streaks by quality level.
func apply_graphics() -> void:
	for layer in _rain:
		RainLook.scale_amount(layer, Graphics.rain_share())
	if _glow != null:
		_glow.light_volumetric_fog_energy = Graphics.light_in_fog()
	if _lamp != null:
		_lamp.light_volumetric_fog_energy = Graphics.light_in_fog()


## Roadway with markings, curb and sidewalk across the road.
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
	# Dashed centre line: one dash per pitch, slightly above the asphalt. Since M24h — between the
	# traffic lanes, not in the middle of the roadway: a car stands at the far curb, and the far lane
	# needs room in front of it.
	var paint := GreyboxLook.surface(LANE_PAINT)
	var lane_z := (StreetTraffic.NEAR_LANE_Z + StreetTraffic.FAR_LANE_Z) * 0.5
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


## Row of houses across the road: from the building's end wall to the left, house after house.
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


## A house across the road: plinth with shop windows, cornice, facade with windows.
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
	# Pack facade over the full height of the house, behind the plinth with shop windows.
	block.depth = FACADE_DEPTH
	block.z = face - PACK_BEHIND - FACADE_DEPTH * 0.5
	_blocks.append(block)
	var shops := 2 if width >= 8.5 else 1
	var share := width / float(shops)
	for shop in shops:
		var shop_middle := span.x + share * (float(shop) + 0.5)
		var shop_width := minf(share - 0.9, 4.2)
		if _rng.randf() < 0.72:
			_build_open_shop(shop_middle, shop_width, face)
		else:
			_build_closed_shop(shop_middle, shop_width, face)


## The shop is open: a lit shop window in a frame, a glazed door, neon above it, sometimes an
## awning, and a pool of light on the sidewalk.
func _build_open_shop(middle: float, width: float, face: float) -> void:
	var glass_width := width - DOOR_WIDTH - FRAME * 3.0
	var glass_x := middle - width * 0.5 + FRAME + glass_width * 0.5
	var glass_y := _floor - RISER - GLASS_HEIGHT * 0.5
	var insides: Array[int] = [
		CityLook.Inside.BLINDS, CityLook.Inside.PERSON, CityLook.Inside.CURTAINS
	]
	var inside := insides[_rng.randi_range(0, insides.size() - 1)]
	var tone := (WARM if _rng.randf() < 0.75 else COLD) * SHOP_GLOW
	if not is_lit():
		tone *= SHOP_GLOW_BY_DAY
	_add_glass(Vector2(glass_x, glass_y), Vector2(glass_width, GLASS_HEIGHT), face, tone, inside)
	var frame := GreyboxLook.metal(FRAME_TONE)
	var front := face + 0.04
	# Shop window frame: bottom, top, sides and mullion.
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
	# Door: the leaf and the glass in it, slightly dimmer than the shop window.
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
	_hang_sign(middle, width, face, neon, is_lit())
	if _rng.randf() < 0.6:
		_build_awning(middle, width, face)
	_spill(Vector2(middle, width), face, tone)


## The shop is closed: a roller shutter with a box and dead neon.
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


## Sign above the shop window: a dark board and neon letters. At a closed shop the neon is off — the
## letters are barely visible.
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
	words.font = NeonStyle.scene_font(700)
	words.font_size = 96
	words.pixel_size = LETTERS / 96.0
	words.shaded = false
	words.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if lit:
		words.modulate = neon
		words.outline_modulate = neon.darkened(0.45)
		words.outline_size = 10
	elif _sunlit:
		# Dead neon by day — tubes in daylight, as with the building's sign.
		words.modulate = VerticalSign.unlit_tube(neon)
		words.outline_size = 0
		words.shaded = true
	else:
		words.modulate = neon.darkened(0.82)
		words.outline_size = 0
	words.position = Vector3(0.0, 0.0, 0.065)
	board.add_child(words)


## Awning: a canopy over the shop window and a striped valance.
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


## Vertical sign on brackets at the corner of the house: letters in a column and a glow — the
## street's only real light source.
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
	# The board faces the camera, as with the building's sign ([VerticalSign]): letters in a column.
	var y := bottom - height + 0.25 + BLADE_STEP * 0.5
	for letter in text:
		var label := Label3D.new()
		label.text = letter
		label.font = NeonStyle.scene_font(700)
		label.font_size = 96
		label.pixel_size = BLADE_LETTER / 96.0
		if is_lit():
			label.modulate = neon
			label.outline_modulate = neon.darkened(0.4)
		else:
			label.modulate = VerticalSign.unlit_tube(neon)
			label.outline_modulate = label.modulate.darkened(0.3)
		label.outline_size = 8
		label.shaded = not is_lit()
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		label.position = _at(x, y, z + 0.09)
		add_child(label)
		y += BLADE_STEP
	if not is_lit():
		# By day the glow is off: there is no source at all.
		return
	_glow = OmniLight3D.new()
	_glow.name = "BladeGlow"
	_glow.light_color = neon
	_glow.light_energy = BLADE_ENERGY
	_glow.omni_range = BLADE_RANGE
	_glow.omni_attenuation = 0.8
	_glow.shadow_enabled = false
	# Below the middle of the board and closer to the roadway: the glow falls on the awnings, plinth
	# and sidewalk — the facade above is unlit and would not take the glow anyway.
	_glow.position = _at(x, bottom + 0.6, z + 1.4)
	_glow.visible = false
	add_child(_glow)
	if Weather.is_raining(_weather):
		add_child(
			RainLook.halo(
				_at(x, bottom - height * 0.5, face + 0.3), neon, 0.22, Vector2(3.2, height + 2.0)
			)
		)


## Fire escape: landings at the windows of every floor, railings and flights between them — iron on
## the facade, as in any noir.
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


## A fire escape flight between landings [param from] and [param to]: two stringers on the diagonal.
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


## Street lamp across the road: a pole at the curb, an arm over the roadway, a fixture and a pool of
## light under it — without a source.
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
	if not is_lit():
		# By day the street lamp is off: the fixture glass is dark, no pool.
		_box(Vector3(0.28, 0.04, 0.42), GreyboxLook.surface(SODIUM.darkened(0.6)), head, false)
		return
	_box(Vector3(0.28, 0.04, 0.42), GreyboxLook.light(SODIUM), head, false)
	# The street lamp shines for real: the pack facade without light is a dark wall, and the shop
	# windows, awnings and sidewalk under it take the sodium light (ADR-0052).
	_lamp = SpotLight3D.new()
	_lamp.name = "StreetLamp"
	_lamp.light_color = SODIUM
	_lamp.light_energy = LAMP_ENERGY * _lights
	_lamp.spot_range = LAMP_RANGE
	_lamp.spot_angle = LAMP_ANGLE
	_lamp.shadow_enabled = false
	_lamp.position = head + Vector3(0.0, -0.1, 0.0)
	_lamp.rotation = Vector3(-PI * 0.5 + LAMP_LEAN, 0.0, 0.0)
	_lamp.visible = false
	add_child(_lamp)
	var pool := _pool(Vector2(4.2, 4.2), SODIUM, POOL_ENERGY * _lights)
	pool.position = _at(x, _street - 0.012, z + LAMP_ARM - 0.4)
	add_child(pool)
	if Weather.is_raining(_weather):
		add_child(RainLook.halo(head + Vector3(0.0, 0.0, -1.2), SODIUM, 0.2, Vector2(5.0, 4.5)))


## Someone else's car at the curb across the road, nose to the left, headlights off: the street is
## alive, and the roadway is not an empty strip. Model and paint are the street's draw.
func _park_a_car(x: float) -> void:
	var choice := CarModel.Choice.new()
	choice.model = _rng.randi_range(0, CarModel.MODELS.size() - 1)
	# Without black paint — the last one: in the dark at the curb the car disappeared.
	choice.paint = _rng.randi_range(1, CarModel.PAINTS.size() - 2)
	var model := CarModel.build(choice)
	model.name = "ParkedCar"
	model.scale = Vector3(1.0, 1.0, Garage.CAR_WIDTH / Garage.depth_of(model))
	model.rotation.y = PI
	model.position = _at(x, _street, FAR_KERB_Z + Garage.CAR_WIDTH * 0.5 + 0.25)
	Garage.switch_lights_off(model)
	add_child(model)


## Shop window light on the sidewalk: a warm pool in front of the glass.
func _spill(shop: Vector2, face: float, tone: Color) -> void:
	var depth := FAR_KERB_Z - KERB.x - face
	if not is_lit():
		# By day shop window light on the sidewalk is not visible.
		return
	var pool := _pool(Vector2(shop.y * 1.3, absf(depth) * 1.6), tone, SPILL_ENERGY * _lights)
	pool.position = _at(shop.x, _street - KERB.y - 0.004, face)
	add_child(pool)


## Glass with life behind it — a window with the city shader ([CityLook]), as its own mesh.
func _add_glass(centre: Vector2, size: Vector2, face: float, tone: Color, inside: int) -> void:
	var place := Transform3D(
		Basis.from_scale(
			Vector3(size.x / CityBackdrop.WINDOW_SIZE.x, size.y / CityBackdrop.WINDOW_SIZE.y, 1.0)
		),
		_at(centre.x, centre.y, face + 0.02)
	)
	_glass_places.append(place)
	_glass_tones.append(Color(tone.r, tone.g, tone.b))
	_glass_customs.append(Color(_rng.randf(), float(inside), 1.0, 1.0))


## Houses and shop windows in one go, as multimeshes, as with the city on the backdrop: the pack
## facade on a full-height box, its windows — lit at a share depending on time of day, — and shop
## glass with life behind it.
func _flush_multimeshes() -> void:
	var box := BoxMesh.new()
	var look := CityLook.building()
	look.set_shader_parameter("lit_share", CityPlan.LIT_SHARE * TimeOfDay.lit_windows(_time))
	look.set_shader_parameter("window_glow", CityBackdrop.WINDOW_GLOW[_time])
	box.material = look
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_colors = true
	many.use_custom_data = true
	many.mesh = box
	many.instance_count = _blocks.size()
	for index in _blocks.size():
		var block := _blocks[index]
		var centre := _at(block.x + block.width * 0.5, _street - block.height * 0.5, block.z)
		var basis := Basis.from_scale(Vector3(block.width, block.height, block.depth))
		many.set_instance_transform(index, Transform3D(basis, centre))
		many.set_instance_color(index, CityLook.wall_tint(block))
		many.set_instance_custom_data(index, CityLook.building_custom(block))
	var houses := MultiMeshInstance3D.new()
	houses.name = "PackFacades"
	houses.multimesh = many
	# The sun is behind the camera: the houses' shadow would fall behind them, where it is not visible,
	# and would load the shadow map with twenty-metre boxes.
	houses.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(houses)
	var glass := CityBackdrop.window_quads(
		"LitWindows", _glass_places, _glass_tones, _glass_customs, true
	)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass)


## Rain over the street: streaks in front of the houses and rings on the roadway.
func _build_rain() -> void:
	var from := _left - FROM
	var height := 16.0
	# Only over the roadway and sidewalk: below the street the drops go under the asphalt and ground,
	# not into the tunnel or into the cutaway at the camera.
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
	# They die on the awnings, cars and roadway, not by a timer ([method _catch]). The particle step is
	# as on the roof ([constant RoofRain.TICKS]): at thirty per second a drop travels up to 60 cm per
	# step and died already under the awning and inside the car, not on them (M24l code review).
	(drops.process_material as ParticleProcessMaterial).collision_mode = (
		ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	)
	drops.collision_base_size = 0.02
	drops.fixed_fps = RoofRain.TICKS
	drops.interpolate = true
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


## Drops and flakes die on the awnings, the car at the curb, the sidewalk and the roadway — by a
## height map taken from the street layer, as on the roof ([RoofCatch]). Traffic cars are not in the
## map: their own catcher kills particles on them ([Shelter]).
func _catch() -> void:
	var moving: Array[Node] = [_traffic, _people]
	StreetSnow.mark(self, moving)
	var from := _at(_left - FROM, _street, 0.0)
	var to := _at(_left, _street, 0.0)
	var over := AABB(
		Vector3(from.x, from.y - 0.5, FACADE_Z - SETBACK),
		Vector3(to.x - from.x, StreetSnow.HEIGHT + 1.5, NEAR_Z - FACADE_Z + SETBACK)
	)
	add_child(RoofCatch.catcher(over, "StreetCatcher", StreetSnow.LAYER))


## Snow over the street and the cover with ruts ([StreetSnow]). The cover lies on everything
## stationary in the street — including the car at the curb, it stands still — but not on the
## traffic: on a moving car the decal would slide in patches.
func _build_snow() -> void:
	_snow = StreetSnow.new()
	add_child(_snow)
	var from := _at(_left - FROM, _street, 0.0)
	var to := _at(_left, _street, 0.0)
	_snow.build(from.x, to.x, from.y, NEAR_Z, FACADE_Z - SETBACK, _time)


## Pedestrians on the sidewalk — for tests.
func people() -> StreetPeople:
	return _people


## Snow over the street — for tests; null if there is no snow.
func snow() -> StreetSnow:
	return _snow


## Pool of light: a plane with a round gradient of colour [param tone], added to what it lies on.
## Not a light source — a picture of light.
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


## The street box. The street casts no shadows: its sources are shadowless, and the building's lamp
## shadows do not reach here.
func _box(
	size: Vector3, material: StandardMaterial3D, centre: Vector3, shadow: bool = false
) -> MeshInstance3D:
	return Garage.put_box(self, size, material, centre, shadow)
