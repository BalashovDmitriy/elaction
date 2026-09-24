class_name BuildingFinish
extends RefCounted

## Отделка здания: материалы с фактурой (ADR-0033, решения 5, 6 и 8).
##
## До M21b стены были заливкой одного цвета и читались «квадратами». Теперь у
## стены рисунок: обои в отеле, штукатурка в офисе; нижняя панель — дерево или
## пластик, пилястры — мрамор или бетон; шахта — металлические листы и бетон,
## порог портала — рифлёная сталь, крыша — гравий. Фактуры собирает
## `tools/build_textures.py` в `assets/textures/`.
##
## Раскладка трипланарная, в координатах мира: у коробок стен своей развёртки
## нет, а плотность рисунка обязана быть одна на любой коробке. Тон раунда
## ([BuildingPalette]) ложится на фактуру множителем — там, где фактура серая,
## цвет даёт раунд, и раунды по-прежнему различаются на глаз (M20).

const DIR := "res://assets/textures"

## Через сколько метров повторяется рисунок.
const WALLPAPER_REPEAT: float = 1.0
const WOOD_REPEAT: float = 1.2
const STONE_REPEAT: float = 1.6
const PLATES_REPEAT: float = 1.2
const GRAVEL_REPEAT: float = 2.0

## Тон дерева и стали: у них свой цвет в фактуре, раунд их только чуть трогает.
const WOOD_TINT := Color(0.85, 0.8, 0.78)
const STEEL_TINT := Color(0.75, 0.78, 0.84)

## Материалы на здание — единицы, коробок тысячи: без кэша каждая тащила бы
## свою копию, и ни один batch не сложился бы.
static var _cache: Dictionary = {}


## Задняя стена коридора в тоне [param tone].
static func wall(identity: BuildingIdentity, tone: Color) -> StandardMaterial3D:
	var name := "hotel_wall" if identity.is_hotel() else "office_wall"
	return _textured(name, tone, WALLPAPER_REPEAT, 0.0)


## Нижняя панель стены.
static func wainscot(identity: BuildingIdentity, tone: Color) -> StandardMaterial3D:
	if identity.is_hotel():
		return _textured("hotel_wainscot", WOOD_TINT, WOOD_REPEAT, 0.0)
	return _textured(
		"office_wainscot", GreyboxLook.SKIRTING.lerp(tone, 0.25).lightened(0.2), WOOD_REPEAT, 0.0
	)


## Пилястры простенков.
static func pilaster(identity: BuildingIdentity, tone: Color) -> StandardMaterial3D:
	var name := "hotel_pilaster" if identity.is_hotel() else "office_pilaster"
	return _textured(name, tone.lightened(0.5), STONE_REPEAT, 0.0)


## Задняя стена шахты — металлические листы с болтами.
static func shaft_plates() -> StandardMaterial3D:
	return _textured("shaft_plates", STEEL_TINT, PLATES_REPEAT, 0.6)


## Бетон шахты: распорки, боковины, стены машинного отделения.
static func shaft_concrete(tone: Color) -> StandardMaterial3D:
	return _textured("shaft_concrete", tone, STONE_REPEAT, 0.0)


## Рифлёная сталь: порог портала.
static func tread_plate() -> StandardMaterial3D:
	return _textured("tread_plate", STEEL_TINT, 0.6, 0.8)


## Гравий настила крыши.
static func roof_gravel(tone: Color) -> StandardMaterial3D:
	return _textured("roof_gravel", tone, GRAVEL_REPEAT, 0.0)


## Забыть кэш: материалы держат цвет раунда, а тесты меняют раунды подряд.
static func forget() -> void:
	_cache.clear()


static func _textured(
	name: String, tint: Color, repeat: float, metallic: float
) -> StandardMaterial3D:
	var key := "%s/%s/%.2f" % [name, tint.to_html(), repeat]
	if _cache.has(key):
		return _cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("%s/%s/albedo.png" % [DIR, name]) as Texture2D
	material.albedo_color = tint
	material.normal_enabled = true
	material.normal_texture = load("%s/%s/normal.png" % [DIR, name]) as Texture2D
	material.roughness_texture = load("%s/%s/roughness.png" % [DIR, name]) as Texture2D
	material.roughness = 1.0
	material.metallic = metallic
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / repeat
	_cache[key] = material
	return material
