class_name LightTextures
extends RefCounted

## Текстуры источников света.
##
## Считаются кодом, а не берутся из ассетов: ассетов до M7 нет, а свет нужен
## сейчас (ADR-0010, пункт 2). В M7 их заменят нарисованные, и это будет замена
## одной функции.
##
## Текстура маленькая, а растягивает её сам источник: [PointLight2D] — это
## [Node2D], и масштаб у него по каждой оси свой. Поэтому одна картинка 128×128
## годится и на узкое пятно лампы, и на заливку во всю ширину этажа.
##
## Профиль [method falloff] — чистая функция, и проверяется она без сцены:
## именно он решает, ровно ли освещён этаж и не течёт ли свет на соседний.

## Сторона готовой текстуры, px.
##
## Большая нарочно: заливку растягивают на всю ширину этажа, и на 128 точках
## спад шёл видимыми ступенями — на один тексель приходилось десять пикселей
## мира. Фильтрация источника здесь не спасает: свет берёт текстуру своим
## сэмплером, и [member CanvasItem.texture_filter] ему не указ.
const SIZE: int = 512

## На какой сетке профиль считается. Полмиллиона точек в GDScript — это
## заметная пауза на входе в здание, а увеличить готовую картинку движок
## умеет сам и делает это на C++.
const GRID: int = 128

## Какого вида профиль считается: прямоугольник, столб или круг.
const KIND_RECTANGLE: int = 0
const KIND_COLUMN: int = 1
const KIND_RADIAL: int = 2

## Какая доля столба света освещена ровно. Шахта узкая, и мягкого края
## ей нужно немного — иначе свет расползается на этаж по обе стороны.
const COLUMN_PLATEAU: float = 0.45

## Какая доля заливки освещена ровно, без спада. Остальное уходит на края.
##
## Доля большая нарочно: этаж шире кадра втрое, и при коротком плато свет
## заметно менялся по ходу Otto — этаж выглядел неровно освещённым, хотя
## лампа на нём одна и та же.
const FLOOR_PLATEAU: float = 0.80

static var _cache: Dictionary = {}


## Яркость по доле расстояния от середины: 0 — середина, 1 — край и дальше.
##
## [param plateau] — доля, освещённая полностью, без спада. При нуле получается
## обычное круглое пятно, при 0.55 — заливка этажа.
##
## Плато нужно именно заливке: без него она была бы эллипсом, и у стен
## на горящем этаже стояла бы темнота — этаж переставал бы читаться как горящий.
## На краю функция даёт ровно ноль, и поэтому свет не течёт на соседний этаж:
## заливку кладут точно по высоте пролёта.
static func profile(from_center: float, plateau: float) -> float:
	var edge := clampf(1.0 - clampf(plateau, 0.0, 1.0), 0.001, 1.0)
	var flat := 1.0 - edge
	var reach := clampf(from_center, 0.0, 1.0)
	if reach <= flat:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, (reach - flat) / edge)


## То же, но для точки на отрезке [code][0, size][/code]: середина отрезка —
## середина света. По этой функции заполняются строки и столбцы текстуры.
static func falloff(position: float, size: float, plateau: float) -> float:
	if size <= 0.0:
		return 0.0
	return profile(absf(position / size * 2.0 - 1.0), plateau)


## Прямоугольный источник: заливка этажа. Растягивается по месту.
static func rectangle(plateau: float = FLOOR_PLATEAU) -> Texture2D:
	return _made("rect:%.3f" % plateau, plateau, KIND_RECTANGLE)


## Круглое пятно: свет самой лампы, вспышка выстрела.
static func spot() -> Texture2D:
	return _made("spot", 0.0, KIND_RADIAL)


## Столб: спад только поперёк, вдоль — ровно.
##
## Нужен шахте. У неё длина в тридцать этажей, и любой градиент вдоль неё,
## как его ни считай, пойдёт ступенями: текселей на такую длину не хватит
## никогда. Ровному свету ступать негде.
static func column(plateau: float = COLUMN_PLATEAU) -> Texture2D:
	return _made("column:%.3f" % plateau, plateau, KIND_COLUMN)


## Готовая текстура из кэша или свежая. Кэш общий на процесс: текстуры зависят
## только от профиля, а здания в партии сменяют друг друга десятками.
static func _made(key: String, plateau: float, kind: int) -> Texture2D:
	if _cache.has(key):
		return _cache[key]

	var image := Image.create_empty(GRID, GRID, false, Image.FORMAT_RGBA8)
	for y: int in GRID:
		for x: int in GRID:
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, _alpha(x, y, plateau, kind)))
	image.resize(SIZE, SIZE, Image.INTERPOLATE_CUBIC)

	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


## Профиль берётся в середине текселя, а не в его углу: иначе левый край
## текстуры попадал бы ровно на ноль, а правый — на [code]1 - 1/GRID[/code], то есть
## оставался бы светить. Заливка от этого текла на этаж ниже, а сам свет
## съезжал на полтекселя вбок. Радиальная ветка так считала с самого начала.
static func _alpha(x: int, y: int, plateau: float, kind: int) -> float:
	var side := float(GRID)
	var centre_x := float(x) + 0.5
	var centre_y := float(y) + 0.5
	var across := falloff(centre_x, side, plateau)
	if kind == KIND_COLUMN:
		return across
	if kind == KIND_RECTANGLE:
		return across * falloff(centre_y, side, plateau)

	# Круглое пятно считается по расстоянию от середины, иначе вышел бы
	# скруглённый квадрат: произведение двух спадов в углах ещё не ноль.
	var centre := Vector2(side, side) * 0.5
	var reach := Vector2(centre_x, centre_y).distance_to(centre) / (side * 0.5)
	return profile(reach, plateau)
