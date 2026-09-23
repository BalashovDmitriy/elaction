class_name Graphics
extends RefCounted

## Уровень качества графики и то, что он включает (ADR-0030, решение 5).
##
## Одна таблица на весь проект: воздух, лампы и город спрашивают здесь, что им
## можно, а не держат каждый свой порог. Правил игры уровень не касается —
## темнота живёт в [FloorLighting], а не в картинке, и агент в темноте видит
## Otto одинаково на любом уровне.
##
## Уровень меняется настройками прямо посреди партии: узлы, которым он важен,
## стоят в группе [constant GROUP] и перестраиваются по [method broadcast].

enum Quality { LOW, MEDIUM, HIGH }

## Группа узлов, которые перестраиваются при смене уровня. Каждый из них
## обязан уметь [code]apply_graphics()[/code].
const GROUP := &"graphics"

## Доля разрешения окна, в которой рисуется город, по уровню. Он в дымке и
## размыт по замыслу, а второй кадр в полном разрешении стоил бы вдвое.
const CITY_SHARE: Array[float] = [0.34, 0.5, 0.5]

## Доля капель дождя по уровню.
const RAIN_SHARE: Array[float] = [0.25, 0.5, 1.0]

## Текущий уровень. Статический: его читают узлы, которые заводятся и
## пересоздаются с каждым зданием, а настройки живут дольше любого из них.
static var quality: Quality = Quality.HIGH


## Отражения в полу — экранные, самые дорогие.
static func reflections() -> bool:
	return quality == Quality.HIGH


## Контактные тени по углам.
static func contact_shadows() -> bool:
	return quality >= Quality.MEDIUM


## Объёмный туман.
static func volumetric_fog() -> bool:
	return quality >= Quality.MEDIUM


## Тень от конуса лампы.
static func spot_shadows() -> bool:
	return quality >= Quality.MEDIUM


## Тень от заливки лампы — вторая тень на каждую лампу.
static func fill_shadows() -> bool:
	return quality == Quality.HIGH


static func city_share() -> float:
	return CITY_SHARE[quality]


static func rain_share() -> float:
	return RAIN_SHARE[quality]


## Включает и выключает в воздухе то, что зависит от уровня.
static func apply_to(environment: Environment) -> void:
	environment.ssr_enabled = reflections()
	environment.ssao_enabled = contact_shadows()
	environment.volumetric_fog_enabled = volumetric_fog()


## Ставит уровень и перестраивает всех, кому он важен.
static func broadcast(level: Quality) -> void:
	quality = level
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.call_group(GROUP, &"apply_graphics")
