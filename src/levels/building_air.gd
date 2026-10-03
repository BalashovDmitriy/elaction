class_name BuildingAir
extends RefCounted

## Building kind air (ADR-0056, decisions 1–3): the hotel, office and residential building each
## have their own world inside the common noir.
##
## Before M24n the kind changed the finish, while frame colour, lamp light and the round palette
## were the same for all buildings — and the three kinds read as one frame. Here is what a
## kind shows at first glance: the tone curve, saturation, fog, colour and energy of
## lamps and the round palette set. Night takes the kind's tone entirely, in daytime the tone of
## the time of day stays the main one, and the kind only tints it ([constant DAY_SHARE]).
##
## Darkness is the same for all: the darkened zone tone ([member BuildingPalette.dark]) has
## the same brightness in the sets of all kinds, and the game rule reads the same way.
## No nodes: tables, read by [Atmosphere], [Lamp] and tests.

## Tone curve by kind ([enum BuildingIdentity.Kind]): shadows, midtones, highlights.
## Hotel — warm amber noir, office — cold white, residential building — sodium with
## green in the shadows.
const SHADOW: Array[Color] = [
	Color(0.03, 0.02, 0.06), Color(0.0, 0.04, 0.09), Color(0.02, 0.04, 0.03)
]
const MIDDLE: Array[Color] = [
	Color(0.32, 0.29, 0.31), Color(0.29, 0.35, 0.42), Color(0.3, 0.32, 0.26)
]
const LIGHT: Array[Color] = [Color(1.0, 0.86, 0.66), Color(0.92, 0.97, 1.0), Color(1.0, 0.84, 0.58)]
## Frame saturation and contrast: the office is more sterile, the hotel and residential denser.
const SATURATION: Array[float] = [0.95, 0.78, 0.86]
const CONTRAST: Array[float] = [1.14, 1.05, 1.12]
## Fog: density multiplier and air glow colour. In the hotel the air is thick
## and warm, in the office — clear, in the residential building — murky with green.
const FOG_GAIN: Array[float] = [1.5, 0.5, 1.3]
const FOG_GLOW: Array[Color] = [
	Color(0.06, 0.04, 0.03), Color(0.03, 0.045, 0.06), Color(0.035, 0.05, 0.035)
]
## In daytime the kind's tone is mixed into the time-of-day tone at this share: the sun beats lamps.
const DAY_SHARE: float = 0.35

## Lamp light: the hotel's incandescent lamp, the office's fluorescent lamp, the sodium yellow
## of the residential building; and the cone energy — the office is brighter, residential dimmer.
const LAMP_LIGHT: Array[Color] = [
	Color(1.0, 0.84, 0.6), Color(0.9, 0.96, 1.0), Color(1.0, 0.72, 0.42)
]
const LAMP_GAIN: Array[float] = [1.0, 1.15, 0.85]


## Frame tone by kind [param kind] at time of day [param time]: shadows, midtones,
## highlights.
static func grade(kind: BuildingIdentity.Kind, time: TimeOfDay.Kind) -> PackedColorArray:
	var share := 1.0 if time == TimeOfDay.Kind.NIGHT else DAY_SHARE
	return PackedColorArray(
		[
			TimeOfDay.GRADE_SHADOW[time].lerp(SHADOW[kind], share),
			TimeOfDay.GRADE_MIDDLE[time].lerp(MIDDLE[kind], share),
			TimeOfDay.GRADE_LIGHT[time].lerp(LIGHT[kind], share),
		]
	)


## Frame saturation by kind and time of day.
static func saturation(kind: BuildingIdentity.Kind, time: TimeOfDay.Kind) -> float:
	var share := 1.0 if time == TimeOfDay.Kind.NIGHT else DAY_SHARE
	return lerpf(TimeOfDay.SATURATION[time], SATURATION[kind], share)
