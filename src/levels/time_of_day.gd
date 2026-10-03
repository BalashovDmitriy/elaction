class_name TimeOfDay
extends RefCounted

## Building time of day: morning, day, evening or night (ADR-0051).
##
## One per building, chosen by its seed with its own draw — weather and the round
## palette do not depend on it — and frozen within the building: from the helicopter to the car
## (decisions 3 and 4). Night comes up twice as often as the others: night is the game's face.
##
## The class decides and hands out look numbers: sky, sun, lights, frame tone. Mechanics
## ask [BuildingRules] about time of day: darkness exists only at night
## (decision 5). The nodes are built by [BuildingScenery], [CityBackdrop] and the street.

enum Kind { MORNING, DAY, EVENING, NIGHT }

## Draw shares by [enum Kind]: night 40 %, the others 20 % each (decision 3).
const WEIGHTS: Array[float] = [0.2, 0.2, 0.2, 0.4]

## Mixed with the seed: the time draw coincides neither with weather
## ([constant Weather.SALT]) nor with the layout of the same seed.
const SALT: int = 0x71_3E0D

## Horizon in clear weather: the building air glows with its share by day.
const HORIZON: Array[Color] = [
	Color(0.98, 0.76, 0.6),
	Color(0.6, 0.75, 0.92),
	Color(0.98, 0.56, 0.34),
	Color(0.07, 0.08, 0.15),
]

## Where the sun shines from: height above the horizon, degrees, and side — minus
## left of the camera. In the morning low on the right, by day high, in the evening low on the left.
const SUN_ELEVATION: Array[float] = [6.0, 40.0, 5.0, 14.0]
const SUN_SIDE: Array[float] = [1.0, 0.5, -1.0, 0.6]
const SUN_COLOUR: Array[Color] = [
	Color(1.0, 0.86, 0.72),
	Color(1.0, 0.97, 0.9),
	Color(1.0, 0.72, 0.48),
	Color(0.0, 0.0, 0.0),
]
const SUN_ENERGY: Array[float] = [1.3, 1.8, 1.15, 0.0]

## How much day is in the frame, 0–1: the city, windows, building air follow it.
const DAYLIGHT: Array[float] = [0.7, 1.0, 0.55, 0.0]

## Share of lit city windows relative to night: by day — a handful.
const LIT_WINDOWS: Array[float] = [0.3, 0.06, 0.75, 1.0]

## Strength of street lights — lamps, neon, glow, beacons: morning and evening
## partial, off by day (decision 6).
const STREET_LIGHTS: Array[float] = [0.35, 0.0, 0.85, 1.0]

## Frame tone — per-channel curves from shadows to light ([Atmosphere]). Night is
## the M22 noir, [Atmosphere] holds its numbers; morning is cool with pink light,
## day almost neutral, evening — violet shadows and orange light.
const GRADE_SHADOW: Array[Color] = [
	Color(0.02, 0.03, 0.07),
	Color(0.02, 0.025, 0.04),
	Color(0.05, 0.02, 0.08),
	Atmosphere.NOIR_SHADOW,
]
const GRADE_MIDDLE: Array[Color] = [
	Color(0.33, 0.35, 0.39),
	Color(0.36, 0.36, 0.36),
	Color(0.38, 0.31, 0.33),
	Atmosphere.NOIR_MIDDLE,
]
const GRADE_LIGHT: Array[Color] = [
	Color(1.0, 0.94, 0.9),
	Color(1.0, 0.98, 0.94),
	Color(1.0, 0.86, 0.68),
	Atmosphere.NOIR_LIGHT,
]
const SATURATION: Array[float] = [0.95, 1.0, 1.05, Atmosphere.SATURATION]

## Building ambient light: a multiplier to the night one and where its colour drifts. By day
## the building is bright even without lamps — a shot lamp does not darken a zone even visually.
const AMBIENT_GAIN: Array[float] = [1.45, 1.6, 1.3, 1.0]
const AMBIENT_TINT: Array[Color] = [
	Color(0.85, 0.82, 0.86),
	Color(0.9, 0.92, 0.95),
	Color(0.9, 0.72, 0.62),
	Color(0.0, 0.0, 0.0),
]
## How far the ambient light colour drifts toward [constant AMBIENT_TINT].
const AMBIENT_TINT_SHARE: Array[float] = [0.35, 0.45, 0.35, 0.0]


## Building time of day by its seed.
static func of_seed(building_seed: int) -> Kind:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, SALT])
	var roll := rng.randf()
	var total := 0.0
	for kind: int in WEIGHTS.size():
		total += WEIGHTS[kind]
		if roll < total:
			return kind as Kind
	return Kind.NIGHT


## Whether it is night: only at night is there darkness and dark floors (decision 5).
static func is_night(kind: Kind) -> bool:
	return kind == Kind.NIGHT


## Whether there can be a thunderstorm: only in the evening and at night (decision 7).
static func has_thunder(kind: Kind) -> bool:
	return kind == Kind.EVENING or kind == Kind.NIGHT


## Where sunlight comes from — the direction from the scene to the sun, scene world.
## The sun is behind the camera and to the side: what faces the player is lit by it.
## With the sun from behind, the faces of facades and the roof would be backlit — a silhouette.
static func sun_direction(kind: Kind) -> Vector3:
	var up := deg_to_rad(SUN_ELEVATION[kind])
	var side := SUN_SIDE[kind]
	var flat := Vector3(side, 0.0, 1.0).normalized() * cos(up)
	return Vector3(flat.x, sin(up), flat.z).normalized()


## Sun strength under the weather: in overcast there is almost none, at night none at all.
static func sun_energy(kind: Kind, weather: Weather.Kind) -> float:
	var energy := SUN_ENERGY[kind]
	if weather == Weather.Kind.FOG:
		return energy * 0.3
	if weather == Weather.Kind.RAIN:
		return energy * 0.2
	if weather == Weather.Kind.SNOW:
		return energy * 0.35
	return energy


static func sun_colour(kind: Kind) -> Color:
	return SUN_COLOUR[kind]


static func daylight(kind: Kind) -> float:
	return DAYLIGHT[kind]


static func lit_windows(kind: Kind) -> float:
	return LIT_WINDOWS[kind]


## A window onto the street from inside the building — in the office hall, onto the fire escape: at
## night dark glass [param night], at other times it glows with the horizon sky by the day share.
## Night glass by day read as a hole into darkness (M24n code review).
static func window_look(kind: Kind, night: Color) -> StandardMaterial3D:
	if is_night(kind):
		return GreyboxLook.polished(night)
	return GreyboxLook.marker(night.lerp(HORIZON[kind], daylight(kind)))


## Strength of street lights. In bad weather by day they are switched on — it is dark.
static func street_lights(kind: Kind, weather: Weather.Kind = Weather.Kind.CLEAR) -> float:
	var lights := STREET_LIGHTS[kind]
	if weather != Weather.Kind.CLEAR and kind != Kind.NIGHT:
		lights = maxf(lights, 0.4)
	return lights


## Whether it is light outside: morning and day. Then the sign neon is off, in the rooms behind
## doors the light is not on — the sun shines from the window (ADR-0052, decisions 4 and 5).
static func is_daytime(kind: Kind) -> bool:
	return kind == Kind.MORNING or kind == Kind.DAY


## Whether the building's sign neon is on: evening and night (ADR-0052, decision 4).
static func sign_lit(kind: Kind) -> bool:
	return not is_daytime(kind)


## Building ambient light from the night [param night]: colour and strength multiplier.
static func ambient(kind: Kind, night: Color) -> Color:
	return night.lerp(AMBIENT_TINT[kind], AMBIENT_TINT_SHARE[kind])


static func ambient_gain(kind: Kind) -> float:
	return AMBIENT_GAIN[kind]
