class_name Atmosphere
extends RefCounted

## Воздух здания: общий тон, отражения, туман, свечение и тонмаппинг.
##
## Числа — из пробы `tools/look3d.gd`, подобранные на нашей же геометрии
## (ADR-0023, решение 7), и меняются только по замеру `tools/light_bench.gd`.
## Собирается здесь, а не в уровне: уровню довольно одной строки, а бенчу и
## пробам нужен тот же воздух без всего здания.

## Небо за зданием и общий тон. Тон низкий и нужен только затем, чтобы
## погашенная зона была темна, а не черна: агенты в темноте продолжают
## стрелять, и игрок обязан видеть, во что стрелять в ответ (ADR-0010, п. 3).
const SKY := Color(0.03, 0.04, 0.07)
const AMBIENT_ENERGY: float = 0.55

## Отражения в полу: экранные, им нужен наклон камеры (решение 1).
const SSR_STEPS: int = 96
const SSR_FADE_IN: float = 0.2

## Контактные тени по углам: под актёрами, у плинтуса, в проёмах.
const SSAO_INTENSITY: float = 2.0
const SSAO_RADIUS: float = 0.6

## Туман — намёк, а не молоко: на 0.015 конусы ламп съедали весь кадр. Множитель
## плотности и свечение воздуха — по типу здания ([constant BuildingAir.FOG_GAIN]).
const FOG_DENSITY: float = 0.0035

## Свечение только с того, что ярче кадра: иначе блум растит каждую лампу в
## белый столб и съедает деталь, ради которой всё и затевалось.
const GLOW_INTENSITY: float = 0.6
const GLOW_THRESHOLD: float = 1.0

const EXPOSURE: float = 1.15

## Тон кадра — ночной нуар по референсу (ADR-0030, решение 1): кривые по каналам
## от холодных теней к тёплому свету, чуть больше контраста, чуть меньше цвета.
## Игровые знаки светятся эмиссией поверх тона и яркими остаются.
##
## Подобран в M22 по кадрам из трёх наборов (`layout_shot --tone=N`): холод в
## тенях и тепло в свете разведены сильнее, чем в M20, — мрамор и обои больше
## не выбеливались лампой, а двери и лампы стали теплее на синей стене.
##
## С M24n контраст и ночной тон кадра задаёт тип здания ([BuildingAir]): нуар
## здесь — ночной тон суток в [TimeOfDay], и ночью тип перекрывает его целиком.
const NOIR_SHADOW := Color(0.0, 0.03, 0.08)
const NOIR_MIDDLE := Color(0.27, 0.33, 0.4)
const NOIR_LIGHT := Color(1.0, 0.93, 0.8)
const NOIR_MIDDLE_AT: float = 0.35
const SATURATION: float = 0.9


## Воздух здания с общим тоном [param ambient] — цветом палитры раунда — во
## время суток [param time] (ADR-0051): днём здание светлее и без ламп, тон
## кадра — свой на каждое время. С M24n тон, насыщенность и туман — ещё и по
## типу здания [param kind] ([BuildingAir], ADR-0056).
static func environment(
	ambient: Color,
	time: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT,
	kind: BuildingIdentity.Kind = BuildingIdentity.Kind.HOTEL
) -> Environment:
	var air := Environment.new()
	air.background_mode = Environment.BG_COLOR
	air.background_color = SKY
	air.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	air.ambient_light_color = TimeOfDay.ambient(time, ambient)
	air.ambient_light_energy = AMBIENT_ENERGY * TimeOfDay.ambient_gain(time)

	air.ssr_enabled = true
	air.ssr_max_steps = SSR_STEPS
	air.ssr_fade_in = SSR_FADE_IN
	air.ssao_enabled = true
	air.ssao_intensity = SSAO_INTENSITY
	air.ssao_radius = SSAO_RADIUS

	air.volumetric_fog_enabled = true
	air.volumetric_fog_density = FOG_DENSITY * BuildingAir.FOG_GAIN[kind]
	air.volumetric_fog_emission = BuildingAir.FOG_GLOW[kind].lerp(
		TimeOfDay.HORIZON[time] * 0.08, TimeOfDay.daylight(time)
	)

	air.glow_enabled = true
	air.glow_intensity = GLOW_INTENSITY
	air.glow_bloom = 0.0
	air.glow_hdr_threshold = GLOW_THRESHOLD
	air.tonemap_mode = Environment.TONE_MAPPER_ACES
	air.tonemap_exposure = EXPOSURE

	air.adjustment_enabled = true
	air.adjustment_contrast = BuildingAir.CONTRAST[kind]
	air.adjustment_saturation = BuildingAir.saturation(kind, time)
	air.adjustment_color_correction = grade_curve(time, kind)
	Graphics.apply_to(air)
	return air


## Кривые тона: градиент, по которому каждый канал переводится из своего
## значения в своё. Ночью — нуар: чёрный уходит в холодный синий, белый — в
## тёплый; в другое время — свой тон ([constant TimeOfDay.GRADE_SHADOW] и
## соседи), подкрашенный тоном типа здания [param kind] ([BuildingAir]).
static func grade_curve(
	time: TimeOfDay.Kind, kind: BuildingIdentity.Kind = BuildingIdentity.Kind.HOTEL
) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, NOIR_MIDDLE_AT, 1.0])
	gradient.colors = BuildingAir.grade(kind, time)
	var curve := GradientTexture1D.new()
	curve.gradient = gradient
	return curve
