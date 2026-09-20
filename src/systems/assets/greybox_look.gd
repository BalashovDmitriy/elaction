class_name GreyboxLook
extends RefCounted

## Материалы греев-бокса: чем покрашены коробки, пока нет моделей и текстур.
##
## Вид вехи M15 — серые коробки, и это нормально ([ADR-0021](../../../docs/adr/0021-3d-greybox.md)).
## Но «серые» не значит «одинаковые»: без разницы тонов кадр читается сплошной
## заливкой, и по нему не понять, где пол, где стена, а где шахта. С M17 к тону
## добавились шероховатость и металл ([ADR-0023](../../../docs/adr/0023-light-and-readability.md),
## решение 5): пол полированный ради отражений, стены — шершавый бетон, шахта и
## рёбра — металл. Текстур нет, они дело обстановки M19.
##
## Второе, что здесь решается, важнее цвета. [ADR-0019](../../../docs/adr/0019-3d-pivot.md),
## решение 5: игровой объект не зависит от освещения сцены. На пробе с погашенными
## лампами дверь исчезла полностью — а дверь это цель игры. С M17 читаемость
## держат не светящиеся целиком коробки, а **огоньки** — [method light]: табло над
## дверью, индикаторы кабины, вывеска выхода. Светильник лампы и пуля светятся
## сами — [method marker]; актёров держит [method outline].

## Тона окружения. Подобраны так, чтобы соседние плоскости различались на глаз
## и в освещённом кадре, и в погашенном.
const SLAB := Color(0.22, 0.22, 0.24)
const WALL := Color(0.28, 0.29, 0.32)
const BACK_WALL := Color(0.19, 0.20, 0.23)
## Дальняя стена комнаты: темнее задней, чтобы проём читался глубиной.
const SKY_WALL := Color(0.11, 0.12, 0.16)
const SHAFT := Color(0.24, 0.27, 0.34)
const ESCALATOR := Color(0.33, 0.31, 0.29)

## Рёбра (ADR-0023, решение 4): светлая рейка торцов и плинтуса, тёмный низ
## стены, пилястры чуть светлее самой стены.
const TRIM := Color(0.52, 0.50, 0.46)
const SKIRTING := Color(0.17, 0.17, 0.19)
const PILASTER := Color(0.40, 0.40, 0.42)

## Тона игровых объектов. Актёры и машина у выхода с M16 — модели со своими
## материалами; их читаемость держит [method outline].
const DOOR := Color(0.78, 0.66, 0.30)
const DOOR_RED := Color(0.76, 0.24, 0.22)
const LAMP := Color(1.0, 0.93, 0.72)
const BULLET := Color(1.0, 0.88, 0.60)
const CAR := Color(0.70, 0.22, 0.20)

## Огоньки (ADR-0023, решение 6): табло обычной и красной двери, вывеска выхода,
## индикаторы кабины.
const SIGN_WARM := Color(1.0, 0.72, 0.35)
const SIGN_RED := Color(1.0, 0.22, 0.16)
const SIGN_GREEN := Color(0.30, 1.0, 0.50)
const INDICATOR := Color(1.0, 0.25, 0.15)

## Обводка актёров: светлый кант и его толщина, м.
const OUTLINE := Color(0.92, 0.94, 1.0)
const OUTLINE_WIDTH: float = 0.018

## Насколько ярко светятся маркеры — светильник и пуля. Не «фонарь», а ровно
## столько, чтобы силуэт читался на погашенном этаже: выше — и кадр
## превращается в гирлянду.
const MARKER_GLOW: float = 0.55

## Насколько ярко горит огонёк. Ярче кадра — ровно настолько, чтобы свечение
## ([Environment] с порогом 1.0) дало ему ореол, как индикаторам на референсе.
const LIGHT_GLOW: float = 2.0

## Шероховатость и металл поверхностей. Гладкий бокс под светом читается
## размытым пятном — это находка пробы, поэтому бетон шершавый; пол, наоборот,
## гладкий и с каплей металла — в него ложатся отражения.
const SURFACE_ROUGHNESS: float = 0.85
const FLOOR_ROUGHNESS: float = 0.28
const FLOOR_METALLIC: float = 0.2
const METAL_ROUGHNESS: float = 0.45
const METAL_METALLIC: float = 0.35

static var _cache: Dictionary = {}


## Материал окружения — шершавый бетон: ему нужен свет, и в темноте он темнеет.
static func surface(color: Color) -> StandardMaterial3D:
	return _made("s%s" % color, color, SURFACE_ROUGHNESS, 0.0, 0.0)


## Полированный пол: тёмный и гладкий, ради отражений.
static func polished(color: Color) -> StandardMaterial3D:
	return _made("p%s" % color, color, FLOOR_ROUGHNESS, FLOOR_METALLIC, 0.0)


## Металл: шахта, рейки, кабина.
static func metal(color: Color) -> StandardMaterial3D:
	return _made("e%s" % color, color, METAL_ROUGHNESS, METAL_METALLIC, 0.0)


## Маркер: светится сам, неярко. Светильник лампы и пуля — то, что и в жизни
## есть источник.
static func marker(color: Color) -> StandardMaterial3D:
	return _made("m%s" % color, color, SURFACE_ROUGHNESS, 0.0, MARKER_GLOW)


## Огонёк: маленький собственный свет игрового объекта. Эмиссия, свету сцены не
## подчиняется, поэтому виден и на погашенном этаже.
static func light(color: Color) -> StandardMaterial3D:
	return _made("l%s" % color, color, SURFACE_ROUGHNESS, 0.0, LIGHT_GLOW)


## Материалов на здание — единицы, а коробок тысячи: без кэша каждый меш тащил
## бы собственную копию одного и того же материала, и ни один batch не сложился бы.
static func _made(
	key: String, color: Color, roughness: float, metallic: float, glow: float
) -> StandardMaterial3D:
	var found: Variant = _cache.get(key)
	if found != null:
		return found as StandardMaterial3D

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	_cache[key] = material
	return material


## Коробка без тела: меш нужного габарита с материалом, готовый встать в сцену.
##
## Собирается в одном месте. Уровень, одежда шахт и эскалатор клали её каждый
## своими пятью строками — семь копий одного и того же, и первая же правка
## (слой, тень, материал) разошлась бы между ними (авторевью M15).
static func box(size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	return part


## Обводка актёра: инвертированная оболочка вторым проходом.
##
## Лицевые грани отсечены, без затенения, чуть шире тела — рисуется задняя
## сторона раздутого меша, и по контуру фигуры остаётся кант. Свету он не
## подчиняется, поэтому виден и на погашенном этаже (ADR-0022, решение 4).
## Rim-свет для этого не годится: он слагаемое освещения и гаснет вместе с ним.
static func outline() -> StandardMaterial3D:
	var found: Variant = _cache.get("outline")
	if found != null:
		return found as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_FRONT
	material.grow = true
	material.grow_amount = OUTLINE_WIDTH
	material.albedo_color = OUTLINE
	_cache["outline"] = material
	return material


## Сбрасывает кэш. Нужен тестам: материалы живут в статике, а она переживает
## смену сцены, и накопленное из одного теста утекало бы в следующий.
static func forget() -> void:
	_cache.clear()
