class_name BuildingAir
extends RefCounted

## Воздух типа здания (ADR-0056, решения 1–3): свой мир у отеля, офиса и жилого
## дома внутри общего нуара.
##
## До M24n тип менял отделку, а цвет кадра, свет ламп и палитра раунда были
## одни на все здания — и три типа читались одним кадром. Здесь — то, что у
## типа видно с первого взгляда: кривая тона, насыщенность, туман, цвет и сила
## ламп и набор палитр раунда. Ночь берёт тон типа целиком, днём тон суток
## остаётся главным, а тип только подкрашивает его ([constant DAY_SHARE]).
##
## Темнота у всех одна: тон погашенной зоны ([member BuildingPalette.dark]) в
## наборах всех типов одной яркости, и правило игры читается одинаково.
## Без узлов: таблицы, их читает [Atmosphere], [Lamp] и тесты.

## Кривая тона по типу ([enum BuildingIdentity.Kind]): тени, середина, свет.
## Отель — тёплый янтарный нуар, офис — холодный белый, жилой дом — натрий с
## зеленью в тенях.
const SHADOW: Array[Color] = [
	Color(0.03, 0.02, 0.06), Color(0.0, 0.04, 0.09), Color(0.02, 0.04, 0.03)
]
const MIDDLE: Array[Color] = [
	Color(0.32, 0.29, 0.31), Color(0.29, 0.35, 0.42), Color(0.3, 0.32, 0.26)
]
const LIGHT: Array[Color] = [Color(1.0, 0.86, 0.66), Color(0.92, 0.97, 1.0), Color(1.0, 0.84, 0.58)]
## Насыщенность и контраст кадра: офис стерильнее, отель и жилой дом гуще.
const SATURATION: Array[float] = [0.95, 0.78, 0.86]
const CONTRAST: Array[float] = [1.14, 1.05, 1.12]
## Туман: множитель плотности и цвет свечения воздуха. В отеле воздух густой
## и тёплый, в офисе — прозрачный, в жилом доме — мутный с зеленью.
const FOG_GAIN: Array[float] = [1.5, 0.5, 1.3]
const FOG_GLOW: Array[Color] = [
	Color(0.06, 0.04, 0.03), Color(0.03, 0.045, 0.06), Color(0.035, 0.05, 0.035)
]
## Днём тон типа подмешан к тону суток на эту долю: солнце главнее ламп.
const DAY_SHARE: float = 0.35

## Свет ламп: лампа накаливания отеля, дневная лампа офиса, натриевая желтизна
## жилого дома; и сила конуса — офис светлее, жилой дом тусклее.
const LAMP_LIGHT: Array[Color] = [
	Color(1.0, 0.84, 0.6), Color(0.9, 0.96, 1.0), Color(1.0, 0.72, 0.42)
]
const LAMP_GAIN: Array[float] = [1.0, 1.15, 0.85]


## Тон кадра по типу [param kind] во время суток [param time]: тени, середина,
## свет.
static func grade(kind: BuildingIdentity.Kind, time: TimeOfDay.Kind) -> PackedColorArray:
	var share := 1.0 if time == TimeOfDay.Kind.NIGHT else DAY_SHARE
	return PackedColorArray(
		[
			TimeOfDay.GRADE_SHADOW[time].lerp(SHADOW[kind], share),
			TimeOfDay.GRADE_MIDDLE[time].lerp(MIDDLE[kind], share),
			TimeOfDay.GRADE_LIGHT[time].lerp(LIGHT[kind], share),
		]
	)


## Насыщенность кадра по типу и времени суток.
static func saturation(kind: BuildingIdentity.Kind, time: TimeOfDay.Kind) -> float:
	var share := 1.0 if time == TimeOfDay.Kind.NIGHT else DAY_SHARE
	return lerpf(TimeOfDay.SATURATION[time], SATURATION[kind], share)
