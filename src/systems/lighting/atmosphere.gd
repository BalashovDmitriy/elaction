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


## Воздух здания с общим тоном [param ambient] — цветом палитры раунда.
static func environment(ambient: Color) -> Environment:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = ambient
	environment.ambient_light_energy = AMBIENT_ENERGY

	environment.ssr_enabled = true
	environment.ssr_max_steps = SSR_STEPS
	environment.ssr_fade_in = SSR_FADE_IN
	environment.ssao_enabled = true
	environment.ssao_intensity = SSAO_INTENSITY
	environment.ssao_radius = SSAO_RADIUS

	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = FOG_DENSITY
	environment.volumetric_fog_emission = FOG_EMISSION

	environment.glow_enabled = true
	environment.glow_intensity = GLOW_INTENSITY
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = GLOW_THRESHOLD
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = EXPOSURE
	return environment
