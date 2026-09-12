class_name AreaLight
extends PointLight2D

## Прямоугольный мягкий источник: заливка этажа и столб света в шахте.
##
## Прямоугольных источников в 2D Godot нет вовсе, зато масштаб у узла свой по
## каждой оси. Поэтому берётся обычное пятно с плоской серединой
## ([LightTextures]) и растягивается по месту.
##
## Тени выключены намеренно: заливка изображает общий свет этажа, у которого нет
## одной точки-источника, и тени от неё ложились бы из середины комнаты.


## Источник, накрывающий прямоугольник целиком: заливка этажа.
static func covering(area: Rect2, tint: Color, strength: float) -> AreaLight:
	return _stretched(LightTextures.rectangle(), area, tint, strength)


## Столб света: спад только поперёк. Шахте нужен именно такой — вдоль неё
## тридцать этажей, и любой градиент такой длины идёт видимыми ступенями.
static func column(area: Rect2, tint: Color, strength: float) -> AreaLight:
	return _stretched(LightTextures.column(), area, tint, strength)


static func _stretched(profile: Texture2D, area: Rect2, tint: Color, strength: float) -> AreaLight:
	var light := AreaLight.new()
	light.texture = profile
	light.color = tint
	light.energy = strength
	light.shadow_enabled = false
	light.position = area.position + area.size * 0.5
	light.scale = area.size / float(LightTextures.SIZE)
	return light
