class_name Graphics
extends RefCounted

## Уровень качества графики и то, что он включает (ADR-0030, решение 5;
## «Ультра», сглаживание и выбор по замеру — ADR-0034).
##
## Одна таблица на весь проект: воздух, лампы, окно и город спрашивают здесь,
## что им можно, а не держат каждый свой порог. Правил игры уровень не касается —
## темнота живёт в [FloorLighting], а не в картинке, и агент в темноте видит
## Otto одинаково на любом уровне.
##
## Уровень меняется настройками прямо посреди партии: узлы, которым он важен,
## стоят в группе [constant GROUP] и перестраиваются по [method broadcast].

enum Quality { LOW, MEDIUM, HIGH, ULTRA }

## Группа узлов, которые перестраиваются при смене уровня. Каждый из них
## обязан уметь [code]apply_graphics()[/code].
const GROUP := &"graphics"

## Доля разрешения окна, в которой рисуется город, по уровню. Он в дымке и
## размыт по замыслу, а второй кадр в полном разрешении стоил бы вдвое.
const CITY_SHARE: Array[float] = [0.34, 0.5, 0.5, 0.67]

## Доля капель дождя по уровню.
const RAIN_SHARE: Array[float] = [0.25, 0.5, 1.0, 1.0]

## Сглаживание по уровню (ADR-0034, решение 2): MSAA на окне, FXAA — только
## низкому. TAA нет ни на одном: он размывал обводку актёров, на которой держится
## читаемость на погашенном этаже.
const MSAA: Array[Viewport.MSAA] = [
	Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_2X, Viewport.MSAA_4X
]

## Атлас теней ламп, пикселей по стороне: на «Ультра» вдвое крупнее, и тень
## мебели и людей чётче.
const SHADOW_ATLAS: Array[int] = [2048, 4096, 4096, 8192]

## Сколько света ламп уходит в объёмный туман: на «Ультра» у ламп ореол в
## воздухе коридора (ADR-0034, решение 1), ниже — туман лишь чуть светлеет у
## ламп, как было с M17. Больше — и дымка ложится поверх актёров.
const LIGHT_IN_FOG: Array[float] = [0.0, 1.0, 1.0, 3.0]

## Сетка объёмного тумана по уровню: ширина и глубина. Мельче сетка — и конус
## лампы в воздухе ступенчатый.
const FOG_GRID: Array[Vector2i] = [
	Vector2i(64, 64), Vector2i(64, 64), Vector2i(64, 64), Vector2i(128, 128)
]

## Текущий уровень. Статический: его читают узлы, которые заводятся и
## пересоздаются с каждым зданием, а настройки живут дольше любого из них.
static var quality: Quality = Quality.HIGH


## Отражения в полу — экранные, самые дорогие из высокого.
static func reflections() -> bool:
	return quality >= Quality.HIGH


## Контактные тени по углам.
static func contact_shadows() -> bool:
	return quality >= Quality.MEDIUM


## Объёмный туман.
static func volumetric_fog() -> bool:
	return quality >= Quality.MEDIUM


## Отражённый свет: лампа отскакивает от пола и стен.
static func indirect_light() -> bool:
	return quality == Quality.ULTRA


## Тень от конуса лампы.
static func spot_shadows() -> bool:
	return quality >= Quality.MEDIUM


## Тень от заливки лампы — вторая тень на каждую лампу.
static func fill_shadows() -> bool:
	return quality >= Quality.HIGH


## Сколько света источника уходит в объёмный туман.
static func light_in_fog() -> float:
	return LIGHT_IN_FOG[quality]


static func city_share() -> float:
	return CITY_SHARE[quality]


static func rain_share() -> float:
	return RAIN_SHARE[quality]


## Включает и выключает в воздухе то, что зависит от уровня.
static func apply_to(environment: Environment) -> void:
	environment.ssr_enabled = reflections()
	environment.ssao_enabled = contact_shadows()
	environment.volumetric_fog_enabled = volumetric_fog()
	environment.ssil_enabled = indirect_light()


## Сглаживание и тени — свойства окна, а не воздуха: ставятся на корневое окно.
static func apply_to_viewport(viewport: Viewport) -> void:
	viewport.msaa_3d = MSAA[quality]
	viewport.screen_space_aa = (
		Viewport.SCREEN_SPACE_AA_FXAA
		if quality == Quality.LOW
		else Viewport.SCREEN_SPACE_AA_DISABLED
	)
	viewport.use_taa = false
	viewport.positional_shadow_atlas_size = SHADOW_ATLAS[quality]
	RenderingServer.positional_soft_shadow_filter_set_quality(
		(
			RenderingServer.SHADOW_QUALITY_SOFT_ULTRA
			if quality == Quality.ULTRA
			else RenderingServer.SHADOW_QUALITY_SOFT_LOW
		)
	)
	var grid := FOG_GRID[quality]
	RenderingServer.environment_set_volumetric_fog_volume_size(grid.x, grid.y)


## Ставит уровень и перестраивает всех, кому он важен.
static func broadcast(level: Quality) -> void:
	quality = level
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		apply_to_viewport(tree.root)
		tree.call_group(GROUP, &"apply_graphics")
