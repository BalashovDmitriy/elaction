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

## Туман — намёк, а не молоко: на 0.015 конусы ламп съедали весь кадр.
const FOG_DENSITY: float = 0.0035
const FOG_EMISSION := Color(0.03, 0.04, 0.06)

## Свечение только с того, что ярче кадра: иначе блум растит каждую лампу в
## белый столб и съедает деталь, ради которой всё и затевалось.
const GLOW_INTENSITY: float = 0.45
const GLOW_THRESHOLD: float = 1.0

const EXPOSURE: float = 1.15

## Тон кадра — ночной нуар по референсу (ADR-0030, решение 1): кривые по каналам
## от холодных теней к тёплому свету, чуть больше контраста, чуть меньше цвета.
## Игровые знаки светятся эмиссией поверх тона и яркими остаются.
const NOIR_SHADOW := Color(0.0, 0.02, 0.05)
const NOIR_MIDDLE := Color(0.31, 0.35, 0.39)
const NOIR_LIGHT := Color(1.0, 0.96, 0.88)
const NOIR_MIDDLE_AT: float = 0.35
const CONTRAST: float = 1.08
const SATURATION: float = 0.88


## Воздух здания с общим тоном [param ambient] — цветом палитры раунда.
static func environment(ambient: Color) -> Environment:
	var air := Environment.new()
	air.background_mode = Environment.BG_COLOR
	air.background_color = SKY
	air.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	air.ambient_light_color = ambient
	air.ambient_light_energy = AMBIENT_ENERGY

	air.ssr_enabled = true
	air.ssr_max_steps = SSR_STEPS
	air.ssr_fade_in = SSR_FADE_IN
	air.ssao_enabled = true
	air.ssao_intensity = SSAO_INTENSITY
	air.ssao_radius = SSAO_RADIUS

	air.volumetric_fog_enabled = true
	air.volumetric_fog_density = FOG_DENSITY
	air.volumetric_fog_emission = FOG_EMISSION

	air.glow_enabled = true
	air.glow_intensity = GLOW_INTENSITY
	air.glow_bloom = 0.0
	air.glow_hdr_threshold = GLOW_THRESHOLD
	air.tonemap_mode = Environment.TONE_MAPPER_ACES
	air.tonemap_exposure = EXPOSURE

	air.adjustment_enabled = true
	air.adjustment_contrast = CONTRAST
	air.adjustment_saturation = SATURATION
	air.adjustment_color_correction = noir_curve()
	Graphics.apply_to(air)
	return air


## Кривые тона: градиент, по которому каждый канал переводится из своего
## значения в своё. Чёрный уходит в холодный синий, белый — в тёплый.
static func noir_curve() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, NOIR_MIDDLE_AT, 1.0])
	gradient.colors = PackedColorArray([NOIR_SHADOW, NOIR_MIDDLE, NOIR_LIGHT])
	var curve := GradientTexture1D.new()
	curve.gradient = gradient
	return curve
