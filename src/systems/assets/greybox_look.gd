class_name GreyboxLook
extends RefCounted

## Материалы греев-бокса: чем покрашены коробки, пока нет моделей и текстур.
##
## Вид вехи M15 — серые коробки, и это нормально ([ADR-0021](../../../docs/adr/0021-3d-greybox.md)).
## Но «серые» не значит «одинаковые»: без разницы тонов кадр читается сплошной
## заливкой, и по нему не понять, где пол, где стена, а где шахта.
##
## Второе, что здесь решается, важнее цвета. [ADR-0019](../../../docs/adr/0019-3d-pivot.md),
## решение 5: игровой объект не зависит от освещения сцены. На пробе с погашенными
## лампами дверь исчезла полностью — а дверь это цель игры. Поэтому всё, с чем
## игрок взаимодействует, красится [method marker]: такой материал светится сам
## и виден на погашенном этаже. Всё остальное — [method surface], обычный
## шершавый бетон, которому свет нужен.

## Тона окружения. Подобраны так, чтобы соседние плоскости различались на глаз
## и в освещённом кадре, и в погашенном.
const SLAB := Color(0.38, 0.39, 0.42)
const WALL := Color(0.28, 0.29, 0.32)
const BACK_WALL := Color(0.19, 0.20, 0.23)
## Дальняя стена комнаты: темнее задней, чтобы проём читался глубиной.
const SKY_WALL := Color(0.11, 0.12, 0.16)
const SHAFT := Color(0.24, 0.27, 0.34)
const ESCALATOR := Color(0.33, 0.31, 0.29)

## Тона игровых объектов. Светятся сами.
const OTTO := Color(0.85, 0.87, 0.90)
const AGENT := Color(0.24, 0.26, 0.34)
const DOOR := Color(0.78, 0.66, 0.30)
const DOOR_RED := Color(0.76, 0.24, 0.22)
const LAMP := Color(1.0, 0.93, 0.72)
const BULLET := Color(1.0, 0.88, 0.60)
const CAR := Color(0.70, 0.22, 0.20)

## Насколько ярко светятся игровые объекты. Не «фонарь», а ровно столько, чтобы
## силуэт читался на погашенном этаже: выше — и кадр превращается в гирлянду.
const MARKER_GLOW: float = 0.55

## Шероховатость бетона. Гладкий бокс под светом читается размытым пятном —
## это находка пробы, и до появления настоящих материалов в M17 её держит
## хотя бы шероховатость.
const SURFACE_ROUGHNESS: float = 0.9

static var _cache: Dictionary = {}


## Материал окружения: ему нужен свет, и в темноте он темнеет.
static func surface(color: Color) -> StandardMaterial3D:
	return _made("s%s" % color, color, false)


## Материал игрового объекта: светится сам, поэтому виден и на погашенном этаже.
static func marker(color: Color) -> StandardMaterial3D:
	return _made("m%s" % color, color, true)


## Материалов на здание — единицы, а коробок тысячи: без кэша каждый меш тащил
## бы собственную копию одного и того же материала, и ни один batch не сложился бы.
static func _made(key: String, color: Color, glowing: bool) -> StandardMaterial3D:
	var found: Variant = _cache.get(key)
	if found != null:
		return found as StandardMaterial3D

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = SURFACE_ROUGHNESS
	material.metallic = 0.0
	if glowing:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = MARKER_GLOW
	_cache[key] = material
	return material


## Сбрасывает кэш. Нужен тестам: материалы живут в статике, а она переживает
## смену сцены, и накопленное из одного теста утекало бы в следующий.
static func forget() -> void:
	_cache.clear()
